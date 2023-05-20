defmodule Membrane.Support.Formatters.APFactory do
  @moduledoc false
  @spec sample_data() :: [binary()]
  def sample_data do
    Enum.map(1..10, &<<&1>>)
  end

  @spec binaries_into_ap([binary()]) :: binary()
  def binaries_into_ap(binaries) do
    binaries
    |> into_aggregation_units()
    |> Enum.reduce(&(&2 <> &1))
  end

  @spec sample_ap_header() :: <<_::16>>
  def sample_ap_header, do: <<0::1, 48::6, 0::6, 1::3>>

  @spec into_ap_unit([binary()]) :: binary()
  def into_ap_unit(data), do: sample_ap_header() <> binaries_into_ap(data)

  # AP
  @spec into_aggregation_units([binary()]) :: [binary()]
  def into_aggregation_units(binaries), do: Enum.map(binaries, &<<byte_size(&1)::16, &1::binary>>)

  @spec example_nalu_hdr() :: <<_::16>>
  def example_nalu_hdr, do: <<0::1, 1::6, 0::6, 1::3>>
end
