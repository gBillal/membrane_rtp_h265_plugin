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
      ~> ({:ok, result} -> Enum.zip(result, test_data))
      |> Enum.each(fn {a, b} -> assert a == b end)
    end

    test "returns error when packet is malformed" do
      assert {:error, :packet_malformed} == AP.parse(<<35_402::16, 0, 0, 0, 0, 0, 0, 1, 1, 2>>)
    end
  end
end
