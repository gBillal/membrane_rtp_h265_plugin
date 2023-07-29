defmodule Membrane.RTP.H265.APTest do
  @moduledoc false

  use ExUnit.Case
  use Bunch

  alias Membrane.RTP.H265.AP
  alias Membrane.Support.Formatters.APFactory

  describe "Agregation Packets parser" do
    test "properly decodes nal aggregate" do
      test_data = APFactory.sample_data()

      test_data
      |> APFactory.binaries_into_ap()
      |> AP.parse()
      ~> ({:ok, result} -> result |> Enum.map(&elem(&1, 0)) |> Enum.zip(test_data))
      |> Enum.each(fn {a, b} -> assert a == b end)
    end

    test "properly decodes nal aggregate with donl and dond fields" do
      test_data = APFactory.sample_data()
      don = :rand.uniform(10_000)

      test_data
      |> APFactory.binaries_into_ap_with_don(don)
      |> AP.parse(true)
      ~> ({:ok, result} ->
            result
            |> Enum.with_index(fn {data, don}, index -> {index, data, don} end)
            |> Enum.zip(test_data))
      |> Enum.each(fn {{idx, parsed_data, expected_don}, expected_data} ->
        assert don + idx == expected_don
        assert parsed_data == expected_data
      end)
    end

    test "returns error when packet is malformed" do
      assert {:error, :packet_malformed} == AP.parse(<<35_402::16, 0, 0, 0, 0, 0, 0, 1, 1, 2>>)
    end
  end
end
