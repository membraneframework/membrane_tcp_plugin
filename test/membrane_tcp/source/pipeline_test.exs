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

  def run_pipeline(pipeline, server_socket) do
    data = 1..@payload_frames |> Enum.map(&"(#{&1})")

    Enum.map(data, fn elem ->
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
    Socket.close(server_socket)
  end

  describe "100 messages pass through pipeline" do
    test "created without socket" do
      {:ok, listening_server_socket} =
        %Socket{
          ip_address: @local_address,
          port_no: @server_port_no,
          sock_opts: [reuseaddr: true]
        }
        |> Socket.listen()

      assert pipeline =
               Pipeline.start_link_supervised!(
                 spec: [
                   child(:tcp_source, %Source{
                     local_address: @local_address,
                     server_address: @local_address,
                     server_port_no: @server_port_no
                   })
                   |> child(:sink, Sink)
                 ],
                 test_process: self()
               )

      assert {:ok, server_socket} = Socket.accept(listening_server_socket)
      Socket.close(listening_server_socket)
      # time for a pipeline to enter playing playback
      Process.sleep(100)
      run_pipeline(pipeline, server_socket)
    end

    test "created with already connected socket" do
      server_socket = %Socket{connection_side: :server, ip_address: @local_address, port_no: @server_port_no}
      client_socket = %Socket{connection_side: :client, ip_address: @local_address, port_no: 0}

      assert {:ok, listening_server_socket} = Socket.listen(server_socket)
      assert {:ok, client_socket} = Socket.connect(client_socket, server_socket)
      assert {:ok, server_socket} = Socket.accept(listening_server_socket)

      Socket.close(listening_server_socket)

      assert pipeline =
               Pipeline.start_link_supervised!(
                 spec: [
                   child(:tcp_source, %Source{
                     local_socket: client_socket
                   })
                   |> child(:sink, Sink)
                 ],
                 test_process: self()
               )

      Process.sleep(100)
      run_pipeline(pipeline, server_socket)
    end
  end
end
