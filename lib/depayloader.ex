defmodule Membrane.RTP.H265.Depayloader do
  @moduledoc """
  Depayloads H265 RTP payloads into H265 NAL Units.

  Based on [RFC 7798](https://tools.ietf.org/html/rfc7798).

  Supported types: Single NALU, Fragementation Unit, Aggegration Packets.
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
    accepted_format: %H265.RemoteStream{alignment: :nalu},
    demand_mode: :auto

  defmodule State do
    @moduledoc false
    defstruct parser_acc: nil
  end

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %State{}}
  end

  @impl true
  def handle_stream_format(:input, _stream_format, _context, state) do
    stream_format = %H265.RemoteStream{alignment: :nalu}
    {[stream_format: {:output, stream_format}], state}
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
    result = buffer_output(buffer.payload, buffer, state)
    {:ok, result}
  end

  defp handle_unit_type(:fu, {header, data}, buffer, state) do
    %Buffer{metadata: %{rtp: %{sequence_number: seq_num}}} = buffer

    case FU.parse(data, seq_num, map_state_to_fu(state)) do
      {:ok, {data, type}} ->
        data =
          NAL.Header.add_header(data, 0, type, header.nuh_layer_id, header.nuh_temporal_id_plus1)

        result = buffer_output(data, buffer, %State{state | parser_acc: nil})
        {:ok, result}

      {:incomplete, fu} ->
        result = {[], %State{state | parser_acc: fu}}
        {:ok, result}

      {:error, _reason} = error ->
        error
    end
  end

  defp handle_unit_type(:ap, {_header, data}, buffer, state) do
    with {:ok, result} <- AP.parse(data) do
      buffers = Enum.map(result, &%Buffer{buffer | payload: add_prefix(&1)})
      result = {[buffer: {:output, buffers}], state}
      {:ok, result}
    end
  end

  defp buffer_output(data, buffer, state) do
    {action_from_data(data, buffer), state}
  end

  defp action_from_data(data, buffer) do
    [buffer: {:output, %Buffer{buffer | payload: add_prefix(data)}}]
  end

  defp add_prefix(data), do: @frame_prefix <> data

  defp map_state_to_fu(%State{parser_acc: %FU{} = fu}), do: fu
  defp map_state_to_fu(_state), do: %FU{}

  defp log_malformed_buffer(packet, reason) do
    Membrane.Logger.warn("""
    An error occurred while parsing H265 RTP payload.
    Reason: #{reason}
    Packet: #{inspect(packet, limit: :infinity)}
    """)
  end
end
