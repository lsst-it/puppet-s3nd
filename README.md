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
    aws_access_key_id: access_key_id
    aws_secret_access_key: secret_access_key
    image: ghcr.io/lsst-dm/s3nd:main
    env:
      S3ND_ENDPOINT_URL: https://s3.foo.example.com
      S3ND_PORT: 15556
  bar:
    aws_access_key_id: access_key_id
    aws_secret_access_key: secret_access_key
    volumes:
      - "/home:/home"
      - "/opt:/opt"
    env:
      S3ND_ENDPOINT_URL: https://s3.bar.example.com
      S3ND_PORT: 15557
      AWS_DEFAULT_REGION: baz
```

## Reference

See [REFERENCE](REFERENCE.md)
