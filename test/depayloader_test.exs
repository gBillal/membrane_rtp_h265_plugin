defmodule Membrane.RTP.H265.DepayloaderTest do
  @moduledoc false

  use ExUnit.Case
  use Bunch

  alias Membrane.Buffer
  alias Membrane.RTP.H265.{Depayloader, FU}
  alias Membrane.Support.Formatters.{APFactory, FUFactory, RBSPNaluFactory}

  @empty_state %Depayloader.State{}
  @don_state %Depayloader.State{sprop_max_don_diff: 1}

  describe "Depayloader when processing data" do
    test "passes through packets with type 0..47 (RBSP types)" do
      data = RBSPNaluFactory.sample_nalu()
      buffer = %Buffer{payload: data}

      assert {actions, @empty_state} =
               Depayloader.handle_buffer(:input, buffer, nil, @empty_state)

      assert {:output, result} = Keyword.fetch!(actions, :buffer)
      assert %Buffer{payload: <<1::32, processed_data::binary>>} = result
      assert processed_data == data
    end

    test "parses FU packets" do
      assert {actions, @empty_state} =
               FUFactory.get_all_fixtures()
               |> Enum.map(&FUFactory.precede_with_fu_nal_header/1)
               ~> (enum -> Enum.zip(enum, 1..Enum.count(enum)))
               |> Enum.map(fn {elem, seq_num} ->
                 %Buffer{payload: elem, metadata: %{rtp: %{sequence_number: seq_num}}}
               end)
               |> Enum.reduce(@empty_state, fn buffer, prev_state ->
                 Depayloader.handle_buffer(:input, buffer, nil, prev_state)
                 ~> (
                   {[], %Depayloader.State{} = state} -> state
                   {actions, state} -> {actions, state}
                 )
               end)

      assert {:output, %Buffer{payload: data}} = Keyword.fetch!(actions, :buffer)
      assert data == <<1::32, FUFactory.glued_fixtures()::binary>>
    end

    test "parses FU packets with donl" do
      assert {actions, @don_state} =
               FUFactory.get_all_fixtures()
               |> then(&[FUFactory.add_donl_field(hd(&1), 1_000) | tl(&1)])
               |> Enum.map(&FUFactory.precede_with_fu_nal_header/1)
               ~> (enum -> Enum.zip(enum, 1..Enum.count(enum)))
               |> Enum.map(fn {elem, seq_num} ->
                 %Buffer{payload: elem, metadata: %{rtp: %{sequence_number: seq_num}}}
               end)
               |> Enum.reduce(@don_state, fn buffer, prev_state ->
                 Depayloader.handle_buffer(:input, buffer, nil, prev_state)
                 ~> (
                   {[], %Depayloader.State{} = state} -> state
                   {actions, state} -> {actions, state}
                 )
               end)

      assert {:output, %Buffer{payload: data, metadata: metadata}} =
               Keyword.fetch!(actions, :buffer)

      assert data == <<1::32, FUFactory.glued_fixtures()::binary>>
      assert metadata.decoding_order_number == 1_000
    end

    test "parses AP packets" do
      data = APFactory.sample_data()

      buffer = %Buffer{payload: APFactory.into_ap_unit(data)}

      assert {actions, _state} = Depayloader.handle_buffer(:input, buffer, nil, @empty_state)

      assert [buffer: {:output, buffers}] = actions

      buffers
      |> Enum.zip(data)
      |> Enum.each(fn {result, original_data} ->
        assert %Buffer{payload: result_data} = result
        assert <<1::32, ^original_data::binary>> = result_data
      end)
    end

    test "parses AP packets with donl and dond" do
      data = APFactory.sample_data()
      don = :rand.uniform(10_000)

      buffer = %Buffer{payload: APFactory.into_ap_unit_with_don(data, don)}

      assert {actions, _state} = Depayloader.handle_buffer(:input, buffer, nil, @don_state)

      assert [buffer: {:output, buffers}] = actions

      buffers
      |> Enum.zip(data)
      |> Enum.with_index(0)
      |> Enum.each(fn {{result, original_data}, index} ->
        assert %Buffer{payload: result_data, metadata: metadata} = result
        assert <<1::32, ^original_data::binary>> = result_data
        assert metadata.decoding_order_number == don + index
      end)
    end
  end

  describe "Depayloader when handling events" do
    alias Membrane.Event.Discontinuity

    test "drops current accumulator in case of discontinuity" do
      state = %Depayloader.State{parser_acc: %FU{}}

      {actions, @empty_state} = Depayloader.handle_event(:input, %Discontinuity{}, nil, state)

      assert actions == [forward: %Discontinuity{}]
    end

    test "passes through rest of events" do
      assert {actions, @empty_state} =
               Depayloader.handle_event(:input, %Discontinuity{}, nil, @empty_state)

      assert actions == [forward: %Discontinuity{}]
    end
  end

  describe "Depayloader resets internal state in case of error and redemands" do
    test "when parsing Fragmentation Unit" do
      assert {[], @empty_state} ==
               %Buffer{
                 metadata: %{rtp: %{sequence_number: 2}},
                 payload:
                   <<98, 1, 192, 184, 105, 243, 121, 62, 233, 29, 109, 103, 237, 76, 39, 197, 20,
                     67, 149, 169, 61, 178, 147, 249, 138, 15, 81, 60, 59, 234, 117, 32, 55, 245,
                     115, 49, 165, 19, 87, 99, 15, 255, 51, 62, 243, 41, 9>>
               }
               ~> Depayloader.handle_buffer(:input, &1, nil, %Depayloader.State{
                 parser_acc: %FU{}
               })
    end

    test "when parsing Agregation Unit" do
      assert {[], @empty_state} ==
               %Buffer{
                 metadata: %{rtp: %{sequence_number: 2}},
                 payload: <<96, 1>> <> <<35_402::16, 0, 0, 0, 0, 0, 0, 1, 1, 2>>
               }
               ~> Depayloader.handle_buffer(:input, &1, nil, @empty_state)
    end

    test "when parsing not valid nalu" do
      assert {[], @empty_state} ==
               %Buffer{
                 metadata: %{rtp: %{sequence_number: 2}},
                 payload: <<128::8>>
               }
               ~> Depayloader.handle_buffer(:input, &1, nil, @empty_state)
    end
  end
end
