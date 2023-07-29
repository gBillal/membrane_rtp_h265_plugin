defmodule Membrane.Support.Formatters.APFactory do
  @moduledoc false
  @spec sample_data() :: [binary()]
  def sample_data do
    Enum.map(3..10, &<<&1>>)
  end

  @spec binaries_into_ap([binary()]) :: binary()
  def binaries_into_ap(binaries) do
    binaries
    |> into_aggregation_units()
    |> Enum.reduce(&(&2 <> &1))
  end

  @spec binaries_into_ap_with_don([binary()], non_neg_integer()) :: binary()
  def binaries_into_ap_with_don(binaries, don) do
    binaries
    |> into_aggregation_units_with_don(don)
    |> Enum.reduce(&(&2 <> &1))
  end

  @spec sample_ap_header() :: <<_::16>>
  def sample_ap_header, do: <<0::1, 48::6, 0::6, 1::3>>

  @spec into_ap_unit([binary()]) :: binary()
  def into_ap_unit(data), do: sample_ap_header() <> binaries_into_ap(data)

  @spec into_ap_unit_with_don([binary()], non_neg_integer()) :: binary()
  def into_ap_unit_with_don(data, don),
    do: sample_ap_header() <> binaries_into_ap_with_don(data, don)

  # AP
  @spec into_aggregation_units([binary()]) :: [binary()]
  def into_aggregation_units(binaries), do: Enum.map(binaries, &<<byte_size(&1)::16, &1::binary>>)

  @spec into_aggregation_units_with_don([binary()], non_neg_integer()) :: [binary()]
  def into_aggregation_units_with_don(binaries, don) do
    Enum.with_index(binaries, 1)
    |> Enum.map(fn
      {data, 1} -> <<don::16, byte_size(data)::16, data::binary>>
      {data, _} -> <<0::8, byte_size(data)::16, data::binary>>
    end)
  end

  @spec example_nalu_hdr() :: <<_::16>>
  def example_nalu_hdr, do: <<0::1, 1::6, 0::6, 1::3>>
end
