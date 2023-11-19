defmodule Membrane.Support.PayloaderTestingPipeline do
  @moduledoc false

  import Membrane.ChildrenSpec

  alias Membrane.H265
  alias Membrane.RTP.H265.Payloader
  alias Membrane.Testing
  alias Testing.Pipeline

  @spec start_pipeline(any()) :: pid()
  def start_pipeline(data) do
    spec = [
      child(:source, %Testing.Source{
        output: data,
        stream_format: %H265{
          width: nil,
          height: nil,
          framerate: nil,
          alignment: :nalu,
          nalu_in_metadata?: nil,
          profile: nil
        }
      })
      |> child(:payloader, Payloader)
      |> child(:sink, Testing.Sink)
    ]

    Pipeline.start_link_supervised!(spec: spec)
  end
end
