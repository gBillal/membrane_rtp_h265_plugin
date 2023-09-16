defmodule Membrane.RTP.H265.Depayloader do
  @moduledoc """
  Depayloads H265 RTP payloads into H265 NAL Units.

  Based on [RFC 7798](https://tools.ietf.org/html/rfc7798).

  Supported types: Single NALU, Fragmentation Unit, Aggegration Packets.
  """
  use Membrane.Filter

  require Membrane.Logger

  alias Membrane.Buffer
  alias Membrane.Event.Discontinuity
  alias Membrane.H265
  alias Membrane.RTP
  alias Membrane.RTP.H265.{AP, FU, NAL}

  @frame_prefix <<1::32>>

  def_input_pad :input, accepted_format: RTP, demand_mode: :auto

  def_output_pad :output,
    accepted_format: %H265{alignment: :nalu, stream_structure: :annexb},
    demand_mode: :auto

  def_options sprop_max_don_diff: [
                spec: 0..32_767,
                default: 0,
                description: """
                Specify the maximum absolute difference between the decoding order number (i.e. AbsDon)
                values of any two NAL units naluA and naluB, where naluA follows naluB in decoding order
                and precedes naluB in transmission order.

                If this value is greater than 0, then two additional fields `DONL` and `DOND` will
                be included in the RTP payload. A `decoding_order_number` field will be added to the
                buffer metadata.
                """
              ]

  defmodule State do
    @moduledoc false
    defstruct parser_acc: nil, sprop_max_don_diff: 0
  end

  @impl true
  def handle_init(_ctx, opts) do
    {[], %State{sprop_max_don_diff: opts.sprop_max_don_diff}}
  end

  @impl true
  def handle_stream_format(:input, _stream_format, _context, state) do
    {[stream_format: {:output, %H265{alignment: :nalu}}], state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: ""}, _ctx, state) do
    Membrane.Logger.debug("Received empty RTP packet. Ignoring")
    {[], state}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, state) do
    with {:ok, {header, _payload} = nal} <- NAL.Header.parse_unit_header(buffer.payload),
         unit_type = NAL.Header.decode_type(header),
         {:ok, {actions, state}} <- handle_unit_type(unit_type, nal, buffer, state) do
      {actions, state}
    else
      {:error, reason} ->
        log_malformed_buffer(buffer, reason)
        {[], %State{state | parser_acc: nil}}
    end
  end

  @impl true
  def handle_event(:input, %Discontinuity{} = event, _ctx, %State{parser_acc: %FU{}} = state),
    do: {[forward: event], %State{state | parser_acc: nil}}

  @impl true
  def handle_event(pad, event, context, state), do: super(pad, event, context, state)

  defp handle_unit_type(:single_nalu, _nalu, buffer, state) do
    {don, buffer} =
      if state.sprop_max_don_diff > 0 do
        <<don::16, payload::binary>> = buffer.payload
        {don, %Buffer{buffer | payload: payload}}
      else
        {nil, buffer}
      end

    result = buffer_output(buffer.payload, buffer, don, state)
    {:ok, result}
  end

  defp handle_unit_type(:fu, {header, data}, buffer, state) do
    %Buffer{metadata: %{rtp: %{sequence_number: seq_num}}} = buffer

    case FU.parse(data, seq_num, map_state_to_fu(state)) do
      {:ok, {data, type, don}} ->
        data =
          NAL.Header.add_header(data, 0, type, header.nuh_layer_id, header.nuh_temporal_id_plus1)

        result = buffer_output(data, buffer, don, %State{state | parser_acc: nil})
        {:ok, result}

      {:incomplete, fu} ->
        result = {[], %State{state | parser_acc: fu}}
        {:ok, result}

      {:error, _reason} = error ->
        error
    end
  end

  defp handle_unit_type(:ap, {_header, data}, buffer, state) do
    with {:ok, nalus} <- AP.parse(data, state.sprop_max_don_diff > 0) do
      buffers =
        Enum.map(nalus, fn {nalu, don} ->
          metadata = put_if(not is_nil(don), buffer.metadata, :decoding_order_number, don)
          %Buffer{buffer | payload: add_prefix(nalu), metadata: metadata}
        end)

      result = {[buffer: {:output, buffers}], state}
      {:ok, result}
    end
  end

  defp buffer_output(data, buffer, don, state) do
    {action_from_data(data, buffer, don), state}
  end

  defp action_from_data(data, buffer, nil) do
    [buffer: {:output, %Buffer{buffer | payload: add_prefix(data)}}]
  end

  defp action_from_data(data, buffer, don) do
    metadata = Map.put(buffer.metadata, :decoding_order_number, don)
    [buffer: {:output, %Buffer{buffer | payload: add_prefix(data), metadata: metadata}}]
  end

  defp add_prefix(data), do: @frame_prefix <> data

  defp map_state_to_fu(%State{parser_acc: %FU{} = fu}), do: fu
  defp map_state_to_fu(state), do: %FU{donl?: state.sprop_max_don_diff > 0}

  defp log_malformed_buffer(packet, reason) do
    Membrane.Logger.warning("""
    An error occurred while parsing H265 RTP payload.
    Reason: #{reason}
    Packet: #{inspect(packet, limit: :infinity)}
    """)
  end

  defp put_if(true, map, key, value), do: Map.put(map, key, value)
  defp put_if(false, map, _key, _value), do: map
end
