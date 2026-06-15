#!/bin/bash
# s3nd endpoint failover watchdog -- managed by puppet (s3nd::watchdog)
#
# Probes the receiver currently pinned in /etc/hosts for the watched endpoint
# hostname. After WATCHDOG_FAIL_THRESHOLD consecutive probe failures, re-pins
# the hostname to the first alternate receiver which passes
# WATCHDOG_RISE_COUNT consecutive probes, records the new pin as a puppet
# external fact (so puppet agrees with the change instead of reverting it),
# and restarts the s3nd units which target that endpoint so that pooled
# keep-alive connections are re-established. If no receiver is healthy, the
# current pin is kept and a CRIT message is logged.

set -o nounset -o pipefail

CONF=${S3ND_WATCHDOG_CONF:-/etc/sysconfig/s3nd-watchdog}
# shellcheck source=/dev/null
. "$CONF"

: "${WATCHDOG_HOSTNAME:?}"
: "${WATCHDOG_PORT:=443}"
: "${WATCHDOG_RECEIVERS:?}"        # space separated list of receiver IPs
: "${WATCHDOG_UNITS:=}"            # space separated list of systemd units
: "${WATCHDOG_PROBE_PATH:=/}"
: "${WATCHDOG_PROBE_TIMEOUT:=5}"   # seconds
: "${WATCHDOG_FAIL_THRESHOLD:=3}"  # consecutive failures before failover
: "${WATCHDOG_RISE_COUNT:=2}"      # consecutive successes to confirm a candidate
: "${WATCHDOG_COOLDOWN:=300}"      # min seconds between failovers
: "${WATCHDOG_STATE_DIR:=/run/s3nd-watchdog}"
: "${WATCHDOG_FACT_FILE:=/etc/puppetlabs/facter/facts.d/s3nd_watchdog.json}"
: "${WATCHDOG_HOSTS_FILE:=/etc/hosts}"

log() { # <level> <msg>...
  local level=$1
  shift
  logger -t s3nd-watchdog -p "daemon.${level}" -- "$@"
  echo "${level}: $*" >&2
}

# a receiver is healthy if it completes a TLS handshake for the endpoint
# hostname and answers with any http status < 500. 000 is curl-speak for no
# response at all (timeout, connection refused, tls failure).
probe() { # <ip>
  local ip=$1 code
  code=$(curl --silent --output /dev/null \
    --max-time "$WATCHDOG_PROBE_TIMEOUT" \
    --resolve "${WATCHDOG_HOSTNAME}:${WATCHDOG_PORT}:${ip}" \
    --write-out '%{http_code}' \
    "https://${WATCHDOG_HOSTNAME}:${WATCHDOG_PORT}${WATCHDOG_PROBE_PATH}" 2>/dev/null)
  [[ $code =~ ^[0-9]+$ ]] && ((code >= 100 && code < 500))
}

confirm_healthy() { # <ip>
  local ip=$1 i
  for ((i = 0; i < WATCHDOG_RISE_COUNT; i++)); do
    ((i > 0)) && sleep 2
    probe "$ip" || return 1
  done
}

current_ip() {
  awk -v host="$WATCHDOG_HOSTNAME" '
    $1 !~ /^#/ {
      for (i = 2; i <= NF; i++) {
        if ($i ~ /^#/) { break }
        if ($i == host) { print $1; exit }
      }
    }' "$WATCHDOG_HOSTS_FILE"
}

# rewrite the hosts entry by truncating in place, which preserves the inode,
# permissions, and selinux context of the hosts file
pin_ip() { # <ip>
  local ip=$1 tmp
  tmp=$(mktemp) || return 1
  awk -v host="$WATCHDOG_HOSTNAME" -v ip="$ip" '
    {
      matched = 0
      if ($1 !~ /^#/) {
        for (i = 2; i <= NF; i++) {
          if ($i ~ /^#/) { break }
          if ($i == host) { matched = 1; break }
        }
      }
      if (matched) {
        if (!done) { print ip "\t" host; done = 1 }
      } else {
        print
      }
    }
    END { if (!done) print ip "\t" host }
  ' "$WATCHDOG_HOSTS_FILE" >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  cat "$tmp" >"$WATCHDOG_HOSTS_FILE"
  local rc=$?
  rm -f "$tmp"
  return $rc
}

write_fact() { # <ip>
  local ip=$1 dir tmp
  dir=$(dirname "$WATCHDOG_FACT_FILE")
  mkdir -p "$dir" || return 1
  tmp=$(mktemp -p "$dir") || return 1
  printf '{"s3nd_watchdog": {"endpoint_ip": "%s"}}\n' "$ip" >"$tmp"
  chmod 0644 "$tmp"
  mv -f "$tmp" "$WATCHDOG_FACT_FILE"
}

restart_units() {
  local unit rc=0
  # shellcheck disable=SC2086 # intentional word splitting
  for unit in $WATCHDOG_UNITS; do
    if systemctl restart "$unit"; then
      log notice "restarted ${unit}"
    else
      log err "failed to restart ${unit}"
      rc=1
    fi
  done
  return $rc
}

mkdir -p "$WATCHDOG_STATE_DIR"
fail_file="${WATCHDOG_STATE_DIR}/consecutive_failures"
flip_file="${WATCHDOG_STATE_DIR}/last_flip"

cur=$(current_ip)
if [[ -z $cur ]]; then
  log err "no ${WATCHDOG_HOSTNAME} entry in ${WATCHDOG_HOSTS_FILE}; waiting for puppet to converge"
  exit 1
fi

if probe "$cur"; then
  echo 0 >"$fail_file"
  exit 0
fi

fails=$(($(cat "$fail_file" 2>/dev/null || echo 0) + 1))
echo "$fails" >"$fail_file"
log warning "probe of ${WATCHDOG_HOSTNAME} (${cur}) failed (${fails}/${WATCHDOG_FAIL_THRESHOLD})"

if ((fails < WATCHDOG_FAIL_THRESHOLD)); then
  exit 0
fi

now=$(date +%s)
last_flip=$(cat "$flip_file" 2>/dev/null || echo 0)
if ((now - last_flip < WATCHDOG_COOLDOWN)); then
  log err "failover suppressed: last flip $((now - last_flip))s ago (cooldown ${WATCHDOG_COOLDOWN}s)"
  exit 1
fi

# shellcheck disable=SC2086 # intentional word splitting
for candidate in $WATCHDOG_RECEIVERS; do
  [[ $candidate == "$cur" ]] && continue
  if confirm_healthy "$candidate"; then
    log notice "failing over ${WATCHDOG_HOSTNAME}: ${cur} -> ${candidate}"
    if ! pin_ip "$candidate"; then
      log err "failed to update ${WATCHDOG_HOSTS_FILE}; aborting failover"
      exit 1
    fi
    write_fact "$candidate" || log err "failed to write ${WATCHDOG_FACT_FILE}; puppet may revert the pin"
    echo "$now" >"$flip_file"
    echo 0 >"$fail_file"
    restart_units
    exit $?
  fi
  log warning "candidate receiver ${candidate} failed health confirmation"
done

log crit "all receivers for ${WATCHDOG_HOSTNAME} are unhealthy; staying pinned to ${cur}"
exit 1
