defmodule Membrane.TCP.TestingSinkReceiver do
  @moduledoc false
  import Membrane.Testing.Assertions

  @spec receive_data(pid(), String.t(), String.t()) :: String.t()
  def receive_data(pipeline, received_data \\ "", terminator \\ ".") do
    assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: payload})

    if String.ends_with?(payload, terminator) do
      received_data <> payload
    else
      receive_data(pipeline, received_data <> payload, terminator)
    end
  end
end
