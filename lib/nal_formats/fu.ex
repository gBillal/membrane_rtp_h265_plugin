defmodule Membrane.RTP.H265.FU do
  @moduledoc """
  Module responsible for parsing H265 Fragmentation Unit.
  """
  use Bunch
  alias __MODULE__
  alias Membrane.RTP.H265.NAL

  defstruct [:last_seq_num, data: [], type: nil, donl?: false, don: nil]

  @type don :: nil | non_neg_integer()

  @type t :: %__MODULE__{
          data: [binary()],
          last_seq_num: nil | non_neg_integer(),
          type: NAL.Header.type(),
          donl?: boolean(),
          don: don()
        }

  defguardp is_next(last_seq_num, next_seq_num) when rem(last_seq_num + 1, 65_536) == next_seq_num

  @doc """
  Parses H265 Fragmentation Unit

  If a packet that is being parsed is not considered last then a `{:incomplete, t()}`
  tuple  will be returned.
  In case of last packet `{:ok, {type, data, don}}` tuple will be returned, where data
  is `NAL Unit` created by concatenating subsequent Fragmentation Units and `don` is the
  decoding order number of the `NAL unit` in case `donl` field is present in the packet.
  """
  @spec parse(binary(), non_neg_integer(), t) ::
          {:ok, {binary(), NAL.Header.type(), don()}}
          | {:error, :packet_malformed | :invalid_first_packet}
          | {:incomplete, t()}
  def parse(data, seq_num, acc) do
    with {:ok, {header, value}} <- FU.Header.parse(data) do
      do_parse(header, value, seq_num, acc)
    end
  end

  @doc """
  Serialize H265 unit into list of FU payloads
  """
  @spec serialize(binary(), pos_integer()) :: list(binary()) | {:error, :unit_too_small}
  def serialize(<<header::2-binary, rest::binary>>, preferred_size) when byte_size(rest) >= 2 do
    <<r::1, type::6, layer_id::6, t_id::3>> = header

    # An FU must consist of at least a start and an end fragment. The first
    # chunk is capped at byte_size(rest) - 1 so a unit barely exceeding
    # preferred_size still leaves data for the end fragment (upstream matched
    # exactly preferred_size, so units of preferred_size + 3 bytes returned
    # {:error, :unit_too_small} and units of preferred_size + 4 bytes emitted
    # a start fragment with no end fragment).
    chunk_size = min(preferred_size, byte_size(rest) - 1)
    <<head::binary-size(chunk_size), rest::binary>> = rest

    payload =
      head
      |> FU.Header.add_header(1, 0, type)
      |> NAL.Header.add_header(r, NAL.Header.encode_type(:fu), layer_id, t_id)

    [payload | do_serialize(rest, r, type, layer_id, t_id, preferred_size)]
  end

  def serialize(_data, _preferred_size), do: {:error, :unit_too_small}

  defp do_serialize(data, r, type, layer_id, t_id, preferred_size)
       when byte_size(data) > preferred_size do
    <<head::binary-size(preferred_size), rest::binary>> = data

    payload =
      head
      |> FU.Header.add_header(0, 0, type)
      |> NAL.Header.add_header(r, NAL.Header.encode_type(:fu), layer_id, t_id)

    [payload | do_serialize(rest, r, type, layer_id, t_id, preferred_size)]
  end

  defp do_serialize(data, r, type, layer_id, t_id, _preferred_size) do
    [
      data
      |> FU.Header.add_header(0, 1, type)
      |> NAL.Header.add_header(r, NAL.Header.encode_type(:fu), layer_id, t_id)
    ]
  end

  defp do_parse(header, data, seq_num, acc)

  defp do_parse(%FU.Header{start_bit: true, type: type}, data, seq_num, %{donl?: false} = acc),
    do: {:incomplete, %__MODULE__{acc | data: [data], last_seq_num: seq_num, type: type}}

  defp do_parse(%FU.Header{start_bit: true, type: type}, <<don::16, data::binary>>, seq_num, acc) do
    {:incomplete, %__MODULE__{acc | data: [data], last_seq_num: seq_num, type: type, don: don}}
  end

  defp do_parse(%FU.Header{start_bit: false}, _data, _seq_num, %__MODULE__{last_seq_num: nil}),
    do: {:error, :invalid_first_packet}

  defp do_parse(%FU.Header{end_bit: true}, data, seq_num, %__MODULE__{
         data: acc,
         last_seq_num: last,
         type: type,
         don: don
       })
       when is_next(last, seq_num) do
    result =
      [data | acc]
      |> Enum.reverse()
      |> Enum.join()

    {:ok, {result, type, don}}
  end

  defp do_parse(_header, data, seq_num, %__MODULE__{data: acc, last_seq_num: last} = fu)
       when is_next(last, seq_num),
       do: {:incomplete, %__MODULE__{fu | data: [data | acc], last_seq_num: seq_num}}

  defp do_parse(_header, _data, _seq_num, _fu), do: {:error, :missing_packet}
end
