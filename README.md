# Membrane RTP H265 plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtp_h265_plugin.svg)](https://hex.pm/packages/membrane_rtp_h265_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtp_h265_plugin/)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_rtp_h265_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_rtp_h265_plugin)

RTP payloader and depayloader for H265.

It is part of [Membrane Multimedia Framework](https://membraneframework.org).

## Supported packetization modes

This package currently does not support `PACI` carrying RTP packet and does support the other types of packetization (Single NALU, Fragmentation Unit and Aggregation Packets).

Also it does not support `DONL` and `DOND`, this extra data are added to the packets when the `sprop-max-don-diff` is present and greater than 0. `sprop-max-don-diff` is transmitted out of band such as in `SDP` description when using RTSP.  

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
