# Membrane RTP H265 plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtp_h265_plugin.svg)](https://hex.pm/packages/membrane_rtp_h265_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtp_h265_plugin/)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_rtp_h265_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_rtp_h265_plugin)

RTP payloader and depayloader for H265.

It is part of [Membrane Multimedia Framework](https://membraneframework.org).

## Supported packetization modes

This package does support the following (de)packetization modes:
  * Single NALu
  * Fragmentation Unit
  * Aggregation Packets

It does not support `PACI` packets.

Please refer to [RFC 7798](https://tools.ietf.org/html/rfc7798) for details.



## Installation

The package can be installed by adding `membrane_rtp_h265_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_rtp_h265_plugin, "~> 0.1.0"}
  ]
end
```
