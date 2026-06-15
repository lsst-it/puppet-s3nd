# @summary
#   Automatic endpoint failover for s3nd instances.
#
# Deploys a systemd timer driven watchdog which health checks the receiver
# behind an /etc/hosts pinned endpoint hostname. After a number of
# consecutive probe failures the watchdog re-pins the hostname to a confirmed
# healthy receiver and restarts the s3nd instances which target that
# endpoint, so that pooled keep-alive connections are re-established (s3nd
# never closes idle connections and podman only copies /etc/hosts into the
# container at startup, so a restart is mandatory for a pin change to take
# effect).
#
# The watchdog records the current pin in the `s3nd_watchdog.endpoint_ip`
# external fact and this class uses that fact to declare the `host` resource,
# so puppet converges on whatever pin the watchdog has chosen instead of
# fighting it. A fact value which is not in $receivers is ignored and the
# first receiver is used instead.
#
# This class is not intended to be assigned to a node directly; declare it
# via the `s3nd::watchdog` class parameter.
#
# @param endpoint_hostname
#   The endpoint hostname to manage in /etc/hosts and to health check. Mind
#   that any `hosts::entries` (or other) declaration of the same hostname
#   must be removed to avoid a duplicate resource error.
#
# @param receivers
#   IP addresses of the interchangeable receivers behind the endpoint
#   hostname. The first receiver is the initial pin. A single element list is
#   allowed; the watchdog then only reports health (it has nowhere to fail
#   over to).
#
# @param ensure
#   Set to `absent` to remove the watchdog, its configuration, and its fact.
#   The /etc/hosts entry is no longer managed (and will be purged if the
#   `hosts` class purges unmanaged entries) unless it is re-declared
#   elsewhere.
#
# @param endpoint_port
#   The TCP port used by both the health probe and the receivers.
#
# @param probe_path
#   URL path requested by the health probe. Any HTTP response with a status
#   below 500 counts as healthy.
#
# @param probe_timeout
#   Per-probe timeout in seconds.
#
# @param fail_threshold
#   Number of consecutive probe failures of the pinned receiver before a
#   failover is attempted.
#
# @param rise_count
#   Number of consecutive successful probes required to confirm a candidate
#   receiver as healthy before failing over to it.
#
# @param cooldown
#   Minimum number of seconds between failovers (flap protection).
#
# @param interval
#   Probe interval, as a systemd timespan (timer `OnUnitActiveSec`).
#
# @param units
#   Systemd units to restart after a failover. Defaults to the units of the
#   `s3nd::instance` resources whose effective `S3ND_ENDPOINT_URL` targets
#   $endpoint_hostname.
#
class s3nd::watchdog (
  Stdlib::Fqdn $endpoint_hostname,
  Array[Stdlib::IP::Address::Nosubnet, 1] $receivers,
  Enum['present', 'absent'] $ensure = 'present',
  Stdlib::Port $endpoint_port = 443,
  String[1] $probe_path = '/',
  Integer[1] $probe_timeout = 5,
  Integer[1] $fail_threshold = 3,
  Integer[1] $rise_count = 2,
  Integer[0] $cooldown = 300,
  String[1] $interval = '30s',
  Optional[Array[String[1]]] $units = undef,
) {
  assert_private()

  if $units =~ NotUndef {
    $_units = $units
  } else {
    # derive the units of the instances whose effective env targets the
    # watched endpoint
    $_hostname_re = regsubst($endpoint_hostname, '\.', '\\.', 'G')
    $_units = sort(pick($s3nd::instances, {}).filter |$_instance, $_params| {
      $_env = $s3nd::env + pick_default($_params['env'], {})
      String(pick_default($_env['S3ND_ENDPOINT_URL'], '')) =~ Regexp("(?i)^https?://${_hostname_re}(:[0-9]+)?(/|\$)")
    }.keys.map |$_instance| { "s3nd-${_instance}.service" })
  }

  $_file_ensure = $ensure ? {
    'present' => 'file',
    default   => 'absent',
  }

  $_config = {
    'WATCHDOG_HOSTNAME'       => $endpoint_hostname,
    'WATCHDOG_PORT'           => $endpoint_port,
    'WATCHDOG_RECEIVERS'      => join($receivers, ' '),
    'WATCHDOG_UNITS'          => join($_units, ' '),
    'WATCHDOG_PROBE_PATH'     => $probe_path,
    'WATCHDOG_PROBE_TIMEOUT'  => $probe_timeout,
    'WATCHDOG_FAIL_THRESHOLD' => $fail_threshold,
    'WATCHDOG_RISE_COUNT'     => $rise_count,
    'WATCHDOG_COOLDOWN'       => $cooldown,
  }

  file { '/etc/sysconfig/s3nd-watchdog':
    ensure  => $_file_ensure,
    mode    => '0644',
    # lint:ignore:strict_indent
    content => inline_epp(@(TMPL), { config => $_config }),
      <%- | Hash $config | -%>
      # managed by puppet (s3nd::watchdog)
      <% $config.each | $k, $v | { -%>
      <%= $k %>="<%= $v %>"
      <% } -%>
      | TMPL
    # lint:endignore
  }

  file { '/usr/local/sbin/s3nd-watchdog':
    ensure => $_file_ensure,
    mode   => '0755',
    source => 'puppet:///modules/s3nd/s3nd-watchdog.sh',
  }

  $_active = $ensure == 'present'
  systemd::timer { 's3nd-watchdog.timer':
    ensure          => $ensure,
    active          => $_active,
    enable          => $_active,
    # lint:ignore:strict_indent
    timer_content   => inline_epp(@(TMPL), { interval => $interval }),
      <%- | String[1] $interval | -%>
      # managed by puppet (s3nd::watchdog)
      [Unit]
      Description=periodically run the s3nd endpoint failover watchdog

      [Timer]
      OnBootSec=2min
      OnUnitActiveSec=<%= $interval %>
      RandomizedDelaySec=5s

      [Install]
      WantedBy=timers.target
      | TMPL
    # lint:endignore
    service_content => file('s3nd/s3nd-watchdog.service'),
    require         => [
      File['/etc/sysconfig/s3nd-watchdog'],
      File['/usr/local/sbin/s3nd-watchdog'],
    ],
  }

  if $ensure == 'present' {
    # the watchdog owns failover; puppet converges on the watchdog's choice
    # via the external fact it maintains. no notify of the s3nd units here:
    # the watchdog restarts them itself, exactly when a pin changes.
    $_fact_ip = fact('s3nd_watchdog.endpoint_ip')
    if $_fact_ip =~ NotUndef and $_fact_ip in $receivers {
      $_endpoint_ip = $_fact_ip
    } else {
      $_endpoint_ip = $receivers[0]
    }

    host { $endpoint_hostname:
      ensure => present,
      ip     => $_endpoint_ip,
    }
  } else {
    file { '/etc/puppetlabs/facter/facts.d/s3nd_watchdog.json':
      ensure => absent,
    }
  }
}
