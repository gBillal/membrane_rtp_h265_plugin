defmodule Membrane.RTP.H265.FUTest do
  @moduledoc false

  use ExUnit.Case
  use Bunch

  alias Membrane.RTP.H265.{FU, NAL}
  alias Membrane.Support.Formatters.FUFactory

  @base_seq_num 4567
  @nal_header <<0::1, 1::6, 0::6, 1::3>>

  describe "Fragmentation Unit parser" do
    test "parses first packet" do
      packet = FUFactory.first()

      assert {:incomplete, fu} = FU.parse(packet, @base_seq_num, %FU{})
      assert %FU{last_seq_num: @base_seq_num} = fu
    end

    test "parses packet sequence" do
      fixtures = FUFactory.get_all_fixtures()

      result =
        fixtures
        |> Enum.zip(1..Enum.count(fixtures))
        |> Enum.reduce(%FU{}, fn {elem, seq_num}, acc ->
          FU.parse(elem, seq_num, acc)
          ~> ({_command, value} -> value)
        end)

      expected_result = FUFactory.glued_fixtures() ~> (<<_header::16, rest::binary>> -> rest)
      assert result == {expected_result, 19, nil}
    end

    test "parses packet with donl field" do
      don = :rand.uniform(10_000)

      [first_fixture | rest] = FUFactory.get_all_fixtures()
      fixtures = [FUFactory.add_donl_field(first_fixture, don) | rest]

      result =
        fixtures
        |> Enum.zip(1..Enum.count(fixtures))
        |> Enum.reduce(%FU{donl?: true}, fn {elem, seq_num}, acc ->
          FU.parse(elem, seq_num, acc)
          ~> ({_command, value} -> value)
        end)

      expected_result = FUFactory.glued_fixtures() ~> (<<_header::16, rest::binary>> -> rest)
      assert result == {expected_result, 19, don}
    end

    test "returns error when one of non edge packets dropped" do
      fixtures = FUFactory.get_all_fixtures()

      assert {:error, :missing_packet} ==
               fixtures
               |> Enum.zip([0, 1, 3, 4, 5])
               |> Enum.reduce(%FU{}, fn {elem, seq_num}, acc ->
                 FU.parse(elem, seq_num, acc)
                 ~>> ({command, fu} when command in [:incomplete, :ok] -> fu)
               end)
    end

    test "returns error when first packet is not starting packet" do
      invalid_first_packet = <<0::5, 3::3>>
      assert {:error, :invalid_first_packet} == FU.parse(invalid_first_packet, 2, %FU{})
    end

    test "returns error when header is not valid" do
      assert {:error, :packet_malformed} == FU.parse(<<0::2, 1::5>>, 0, %FU{})
    end
  end

  describe "serialize/2" do
    test "returns error when there isn't enough data left for a start and an end fragment" do
      assert FU.serialize(unit(0), 4) == {:error, :unit_too_small}
      assert FU.serialize(unit(1), 4) == {:error, :unit_too_small}
    end

    test "always produces a start and an end fragment, even for the smallest valid unit" do
      fragments = FU.serialize(unit(2), 4)

      assert [start_fragment, end_fragment] = fragments

      assert {_nal, %FU.Header{start_bit: true, end_bit: false}, _data} =
               decode_fragment(start_fragment)

      assert {_nal, %FU.Header{start_bit: false, end_bit: true}, _data} =
               decode_fragment(end_fragment)
    end

    test "keeps an end fragment when the payload exactly matches preferred_size" do
      fragments = FU.serialize(unit(4), 4)

      assert [start_fragment, end_fragment] = fragments

      assert {_nal, %FU.Header{start_bit: true, end_bit: false}, start_data} =
               decode_fragment(start_fragment)

      assert {_nal, %FU.Header{start_bit: false, end_bit: true}, end_data} =
               decode_fragment(end_fragment)

      assert byte_size(start_data) + byte_size(end_data) == 4
      assert byte_size(end_data) > 0
    end

    test "does not emit an empty trailing fragment when the payload is an exact multiple of preferred_size" do
      fragments = FU.serialize(unit(8), 4)

      assert [start_fragment, end_fragment] = fragments

      assert {_nal, %FU.Header{start_bit: true, end_bit: false}, start_data} =
               decode_fragment(start_fragment)

      assert {_nal, %FU.Header{start_bit: false, end_bit: true}, end_data} =
               decode_fragment(end_fragment)

      assert byte_size(start_data) == 4
      assert byte_size(end_data) == 4
    end

    test "splits a payload spanning more than two chunks into start, middle and end fragments" do
      fragments = FU.serialize(unit(9), 4)

      assert [start_fragment, middle_fragment, end_fragment] = fragments

      assert {_nal, %FU.Header{start_bit: true, end_bit: false}, _} =
               decode_fragment(start_fragment)

      assert {_nal, %FU.Header{start_bit: false, end_bit: false}, middle_data} =
               decode_fragment(middle_fragment)

      assert {_nal, %FU.Header{start_bit: false, end_bit: true}, end_data} =
               decode_fragment(end_fragment)

      assert byte_size(middle_data) == 4
      assert byte_size(end_data) == 1
    end

    test "reassembled fragment data equals the original payload" do
      original = :binary.copy(<<1, 2, 3, 4>>, 3)
      fragments = FU.serialize(@nal_header <> original, 4)

      reassembled =
        fragments
        |> Enum.map(fn fragment ->
          {_nal, _fu_header, data} = decode_fragment(fragment)
          data
        end)
        |> Enum.join()

      assert reassembled == original
    end
  end

  defp unit(rest_size), do: @nal_header <> :binary.copy(<<1>>, rest_size)

  defp decode_fragment(fragment) do
    {:ok, {nal_header, rest}} = NAL.Header.parse_unit_header(fragment)
    {:ok, {fu_header, data}} = FU.Header.parse(rest)
    {nal_header, fu_header, data}
  end
end
