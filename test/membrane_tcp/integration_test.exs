defmodule Membrane.TCP.IntegrationTest do
  use ExUnit.Case, async: false

  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  alias Membrane.{Buffer, Testing}
  alias Membrane.Testing.Pipeline
  alias Membrane.TCP

  @target_port 5000
  @server_port 6789
  @localhostv4 {127, 0, 0, 1}

  @payload_frames 100

  test "send and receive using 2 pipelines" do
    data = 1..@payload_frames |> Enum.map(&"(#{&1})")

    sender =
      Pipeline.start_link_supervised!(
        spec: [
          child(:source, %Testing.Source{output: data})
          |> child(:sink, %TCP.Sink{
            local_address: @localhostv4,
            local_port_no: @server_port
          })
        ]
      )

    receiver =
      Pipeline.start_link_supervised!(
        spec: [
          child(:source, %TCP.Source{
            server_address: @localhostv4,
            server_port_no: @server_port,
            local_address: @localhostv4
          })
          |> child(:sink, %Testing.Sink{})
        ]
      )

    assert_pipeline_notified(sender, :sink, {:connection_info, @localhostv4, @server_port})
    assert_pipeline_notified(receiver, :source, {:connection_info, @localhostv4, _ephemeral_port})

    assert_end_of_stream(sender, :sink)

    received_data =
      Enum.reduce_while(data, "", fn _elem, acc ->
        assert_sink_buffer(
          receiver,
          :sink,
          %Membrane.Buffer{
            metadata: %{
              tcp_source_address: @localhostv4,
              tcp_source_port: @server_port
            },
            payload: payload
          }
        )
        IO.inspect(payload)
        if String.ends_with?(payload, "(#{@payload_frames})") do
          {:halt, acc <> payload}
        else
          {:cont, acc <> payload}
        end
      end)

    assert received_data == Enum.join(data)
    Pipeline.terminate(sender)
    Pipeline.terminate(receiver)
  end
end
