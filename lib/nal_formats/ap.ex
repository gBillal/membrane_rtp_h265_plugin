defmodule Membrane.RTP.H265.AP do
  @moduledoc """
  Module responsible for parsing Aggregation Packets.

  Documented in [RFC7798](https://tools.ietf.org/html/rfc7798#page-28)

  ```
    0                   1                   2                   3
    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                         RTP Header                            |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |    PayloadHdr (Type=48)     |        NALU 1 Size              |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |        NALU 1 HDR           |                                 |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+      NALU 1 Data              |
    |                  . . .                                        |
    |                                                               |
    +               +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    | . . .         | NALU 2 Size                   | NALU 2 HDR    |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    | NALU 2 HDR    |                                               |
    +-+-+-+-+-+-+-+-+             NALU 2 Data                       |
    |                   . . .                                       |
    |                               +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                               :...OPTIONAL RTP padding        |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  ```
  """
  use Bunch

  alias Membrane.RTP.H265.NAL

  @spec parse(binary()) :: {:ok, [binary()]} | {:error, :packet_malformed}
  def parse(data) do
    do_parse(data, [])
  end

  defp do_parse(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp do_parse(<<size::16, nalu::binary-size(size), rest::binary>>, acc) do
    do_parse(rest, [nalu | acc])
  end

  defp do_parse(_data, _acc), do: {:error, :packet_malformed}

  @spec aggregation_unit_size(binary()) :: pos_integer()
  def aggregation_unit_size(nalu), do: byte_size(nalu) + 2

  @spec serialize([binary], 0..1, NAL.Header.nuh_layer_id(), NAL.Header.nuh_temporal_id_plus1()) ::
          binary
  def serialize(payloads, reserved, layer_id, t_id) do
    payloads
    |> Enum.reverse()
    |> Enum.map(&<<byte_size(&1)::16, &1::binary>>)
    |> IO.iodata_to_binary()
    |> NAL.Header.add_header(reserved, NAL.Header.encode_type(:ap), layer_id, t_id)
  end
end
