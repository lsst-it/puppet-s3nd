# s3nd

## Table of Contents

1. [Overview](#overview)
1. [Description](#description)
1. [Usage - Configuration options and additional functionality](#usage)
1. [Reference - An under-the-hood peek at what the module is doing and how](#reference)

## Overview

[s3nd](https://github.com/lsst-dm/s3nd/) S3 Nexus Deliverator

## Description

The server is intended to be able to maintain long-lived TCP connections, avoiding both authentication delays and TCP slow start on long bandwidth-delay product network segments.
Enabling multiple simultaneous parallel transfers also is intended to maximize usage of the network.

The client is intended to allow "fire-and-forget" submissions of transfer requests by file-writing code.

## Usage

Example role defined via hiera.

```yaml
---
lookup_options:
  s3nd::instances:
    merge:
      strategy: deep
classes:
  - s3nd
s3nd::image: ghcr.io/lsst-dm/s3nd:sha-e9bfaa0
s3nd::env:
  AWS_CA_BUNDLE: /path/to/cacert.pem
s3nd::instances:
  foo:
    port: 15556
    aws_access_key_id: access_key_id
    aws_secret_access_key: secret_access_key
    image: ghcr.io/lsst-dm/s3nd:main
    env:
      S3ND_ENDPOINT_URL: https://s3.foo.example.com
  bar:
    port: 15557
    aws_access_key_id: access_key_id
    aws_secret_access_key: secret_access_key
    volumes:
      - "/home:/home"
      - "/opt:/opt"
    env:
      S3ND_ENDPOINT_URL: https://s3.bar.example.com
      AWS_DEFAULT_REGION: baz
```

### Endpoint failover watchdog

When the endpoint hostname is not resolvable from the client network and has
to be pinned in `/etc/hosts` (e.g. an embargo store reachable only by IP over
a dedicated link), the module can deploy a watchdog which health checks the
pinned receiver and automatically re-pins the hostname to a healthy alternate
receiver, restarting the s3nd instances which target that endpoint:

```yaml
s3nd::watchdog:
  endpoint_hostname: sdfembs3.sdf.slac.stanford.edu
  receivers:
    - "172.24.7.249"
    - "172.24.7.250"
    - "172.24.7.251"
```

The affected instances are derived automatically from the effective
`S3ND_ENDPOINT_URL` of each instance. The watchdog records its choice in the
`s3nd_watchdog.endpoint_ip` external fact, which this module uses to declare
the `host` resource -- puppet therefore converges on the watchdog's pin
instead of reverting it. A pre-existing `hosts::entries` (or similar)
declaration of the same hostname must be removed when enabling the watchdog,
or catalog compilation will fail with a duplicate `Host` resource.

Failover requires a service restart by design: s3nd never expires idle
pooled connections, and podman only copies `/etc/hosts` into the container
at startup. See `REFERENCE.md` for the flap protection knobs
(`fail_threshold`, `rise_count`, `cooldown`).

## Reference

See [REFERENCE](REFERENCE.md)
