defmodule Membrane.RTP.H265.DepayloaderPipelineTest do
  @moduledoc false

  use ExUnit.Case

  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Support.DepayloaderTestingPipeline
  alias Membrane.Support.Formatters.{APFactory, FUFactory}
  alias Membrane.Testing.Source

  describe "Depayloader in a pipeline" do
    test "does not crash when parsing AP" do
      pid =
        APFactory.sample_data()
        |> Enum.chunk_every(2)
        |> Enum.map(&APFactory.into_ap_unit/1)
        |> Enum.map(&%Membrane.Buffer{payload: &1})
        |> Source.output_from_buffers()
        |> DepayloaderTestingPipeline.start_pipeline()

      APFactory.sample_data()
      |> Enum.each(fn elem ->
        assert_sink_buffer(pid, :sink, buffer)
        assert %Buffer{payload: payload} = buffer
        assert <<1::32, elem::binary>> == payload
      end)

      Membrane.Pipeline.terminate(pid)
    end

    test "does not crash when parsing fu" do
      glued_data = FUFactory.glued_fixtures()
      data_base = 1..10

      pid =
        data_base
        |> Enum.flat_map(fn _i -> FUFactory.get_all_fixtures() end)
        |> Enum.map(fn binary -> <<0::1, 49::6, 0::6, 1::3>> <> binary end)
        |> Enum.with_index()
        |> Enum.map(fn {data, seq_num} ->
          %Buffer{payload: data, metadata: %{rtp: %{sequence_number: seq_num}}}
        end)
        |> Source.output_from_buffers()
        |> DepayloaderTestingPipeline.start_pipeline()

      Enum.each(data_base, fn _i ->
        assert_sink_buffer(pid, :sink, %Buffer{payload: data})
        assert <<1::32, ^glued_data::binary>> = data
      end)

      Membrane.Pipeline.terminate(pid)
    end
  end
end
