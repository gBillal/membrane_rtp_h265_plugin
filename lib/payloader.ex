defmodule Membrane.RTP.H265.Payloader do
  @moduledoc """
  Payloads H265 NAL units into RTP packets.

  Based on [RFC 7798](https://tools.ietf.org/html/rfc7798).
  """

  use Bunch
  use Membrane.Filter

  alias Membrane.{Buffer, H265, RTP}
  alias Membrane.RTP.H265.{AP, FU}

  def_options max_payload_size: [
                spec: non_neg_integer(),
                default: 1400,
                description: """
                Maximal size of outputted payloads in bytes. Doesn't work in
                the `single_nalu` mode. The resulting RTP packet will also contain
                RTP header (12B) and potentially RTP extensions. For most
                applications, everything should fit in standard MTU size (1500B)
                after adding L3 and L2 protocols' overhead.
                """
              ],
              mode: [
                spec: :single_nalu | :non_interleaved,
                default: :non_interleaved,
                description: """
                In `:single_nalu` mode, payloader puts exactly one NAL unit
                into each payload, altering only RTP metadata. `:non_interleaved`
                mode handles also FU and AP packetization. See
                [RFC 7798](https://tools.ietf.org/html/rfc7798) for details.
                """
              ]

  def_input_pad :input,
    flow_control: :auto,
    accepted_format: %H265{alignment: :nalu, stream_structure: :annexb}

  def_output_pad :output,
    flow_control: :auto,
    accepted_format: %RTP{payload_format: H265}

  defmodule State do
    @moduledoc false
    defstruct [
      :max_payload_size,
      :mode,
      ap_acc: %{
        payloads: [],
        byte_size: 2,
        pts: 0,
        dts: 0,
        metadata: nil,
        layer_id: 0,
        tid: 1,
        reserved: 0
      }
    ]
  end

  @impl true
  def handle_init(_ctx, opts) do
    {[], Map.merge(%State{}, opts)}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[stream_format: {:output, %RTP{payload_format: H265}}], state}
  end

  @impl true
  def handle_stream_format(:input, _stream_format, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_buffer(:input, %Buffer{} = buffer, _ctx, state) do
    buffer = Map.update!(buffer, :payload, &delete_prefix/1)

    {buffers, state} =
      withl mode: :non_interleaved <- state.mode,
            ap: {:deny, ap_buffers, state} <- try_ap(buffer, state),
            single_nalu: :deny <- try_single_nalu(buffer, state) do
        {ap_buffers ++ use_fu(buffer, state), state}
      else
        mode: :single_nalu -> use_single_nalu(buffer)
        ap: {:accept, buffers, state} -> {buffers, state}
        single_nalu: {:accept, buffer} -> {ap_buffers ++ [buffer], state}
      end

    {[buffer: {:output, buffers}], state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    {ap_buffers, state} = flush_stap_acc(state)
    {[buffer: {:output, ap_buffers}, end_of_stream: :output], state}
  end

  defp delete_prefix(<<0, 0, 0, 1, nal::binary>>), do: nal
  defp delete_prefix(<<0, 0, 1, nal::binary>>), do: nal

  defp try_ap(buffer, state) do
    with {:deny, acc_buffers, state} <- do_try_ap(buffer, state) do
      {result, [], state} = do_try_ap(buffer, state)
      {result, acc_buffers, state}
    end
  end

  defp do_try_ap(buffer, state) do
    %{ap_acc: ap_acc} = state
    size = ap_acc.byte_size + AP.aggregation_unit_size(buffer.payload)
    metadata_match? = !ap_acc.metadata || ap_acc.pts == buffer.pts

    if metadata_match? and size <= state.max_payload_size do
      <<r::1, _type::6, layer_id::6, tid::3, _rest::binary>> = buffer.payload

      ap_acc = %{
        ap_acc
        | payloads: [buffer.payload | ap_acc.payloads],
          byte_size: size,
          metadata: ap_acc.metadata || buffer.metadata,
          pts: buffer.pts,
          dts: buffer.dts,
          reserved: max(ap_acc.reserved, r),
          layer_id: min(ap_acc.layer_id, layer_id),
          tid: min(ap_acc.tid, tid)
      }

      {:accept, [], %{state | ap_acc: ap_acc}}
    else
      {buffers, state} = flush_stap_acc(state)
      {:deny, buffers, state}
    end
  end

  defp flush_stap_acc(%{ap_acc: ap_acc} = state) do
    buffers =
      case ap_acc.payloads do
        [] ->
          []

        [payload] ->
          # use single nalu
          [
            %Buffer{
              payload: payload,
              metadata: ap_acc.metadata,
              pts: ap_acc.pts,
              dts: ap_acc.dts
            }
            |> set_marker()
          ]

        payloads ->
          payload = AP.serialize(payloads, ap_acc.reserved, ap_acc.layer_id, ap_acc.tid)

          [
            %Buffer{
              payload: payload,
              metadata: ap_acc.metadata,
              pts: ap_acc.pts,
              dts: ap_acc.dts
            }
            |> set_marker()
          ]
      end

    {buffers, %{state | ap_acc: %State{}.ap_acc}}
  end

  defp try_single_nalu(buffer, state) do
    if byte_size(buffer.payload) <= state.max_payload_size do
      {:accept, use_single_nalu(buffer)}
    else
      :deny
    end
  end

  defp use_fu(buffer, state) do
    buffer.payload
    |> FU.serialize(state.max_payload_size)
    |> Enum.map(&%Buffer{buffer | payload: &1})
    |> Enum.map(&clear_marker/1)
    |> List.update_at(-1, &set_marker/1)
  end

  defp use_single_nalu(buffer), do: set_marker(buffer)

  defp set_marker(buffer) do
    marker = Map.get(buffer.metadata.h265, :end_access_unit, false)
    Bunch.Struct.put_in(buffer, [:metadata, :rtp], %{marker: marker})
  end

  defp clear_marker(buffer) do
    Bunch.Struct.put_in(buffer, [:metadata, :rtp], %{marker: false})
  end
end
