defmodule Membrane.TCP.SourcePipelineTest do
  use ExUnit.Case, async: false

  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  alias Membrane.TCP.{Socket, Source}
  alias Membrane.Testing.{Pipeline, Sink}

  @local_address {127, 0, 0, 1}
  @server_port_no 5052
  @timeout 2_000

  @payload_frames 100

  test "100 messages passes through pipeline" do
    data = 1..@payload_frames |> Enum.map(&"(#{&1})")

    {:ok, listening_server_socket} =
      %Socket{ip_address: @local_address, port_no: @server_port_no, sock_opts: [reuseaddr: true]}
      |> Socket.listen()

    assert pipeline =
             Pipeline.start_link_supervised!(
               spec: [
                 child(:tcp_source, %Source{
                   local_address: @local_address,
                   server_address: @local_address,
                   server_port_no: @server_port_no
                 })
                 |> child(:sink, %Sink{})
               ],
               test_process: self()
             )

    {:ok, server_socket} = Socket.accept(listening_server_socket)
    # time for a pipeline to enter playing playback
    Process.sleep(100)

    Enum.map(data, fn elem ->
      # Pipeline.message_child(pipeline, :tcp_source, tcp_like_message)
      Socket.send(server_socket, elem)
    end)

    received_data =
      Enum.reduce_while(data, "", fn _elem, acc ->
        assert_sink_buffer(
          pipeline,
          :sink,
          %Membrane.Buffer{
            metadata: %{
              tcp_source_address: @local_address,
              tcp_source_port: @server_port_no
            },
            payload: payload
          },
          @timeout
        )
        if String.ends_with?(payload, "(#{@payload_frames})") do
          {:halt, acc <> payload}
        else
          {:cont, acc <> payload}
        end
      end)

    assert received_data == Enum.join(data)
    Pipeline.terminate(pipeline)
    Socket.close(listening_server_socket)
    Socket.close(server_socket)
  end
end
