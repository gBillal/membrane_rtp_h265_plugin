defmodule Membrane.RTP.H265.FU.HeaderTest do
  @moduledoc false

  use ExUnit.Case
  alias Membrane.RTP.H265.FU.Header

  describe "Fragmentation Unit Header parser" do
    test "returns error when invalid data is being parsed" do
      invalid_data = <<1::1, 1::1, 0::1, 1::5>>
      assert {:error, :packet_malformed} == Header.parse(invalid_data)
    end

    test "returns parsed data for valid packets" do
      # First packet, middle packet, last packet
      combinations = [{1, 0}, {0, 0}, {0, 1}]

      combinations
      |> Enum.map(fn {starting, ending} ->
        <<starting::1, ending::1, 1::6, 4343::128>>
      end)
      |> Enum.map(&Header.parse/1)
      |> Enum.zip(combinations)
      |> Enum.each(fn {result, {starting, ending}} ->
        assert {:ok, {%Header{start_bit: r_starting, end_bit: r_ending}, _}} = result
        assert starting == 1 == r_starting
        assert ending == 1 == r_ending
      end)
    end

    test "does not allow 1 in start bit and end bit" do
      assert {:error, :packet_malformed} == Header.parse(<<1::1, 1::1, 1::6>>)
    end
  end
end
