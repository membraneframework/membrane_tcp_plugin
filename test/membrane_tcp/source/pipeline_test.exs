defmodule Membrane.TCP.SourcePipelineTest do
  use ExUnit.Case, async: false

  import Membrane.ChildrenSpec

  alias Membrane.TCP.{Socket, Source, TestingSinkReceiver}
  alias Membrane.Testing.{Pipeline, Sink}

  @local_address {127, 0, 0, 1}
  @server_port_no 5052

  @payload_frames 100

  defp run_pipeline(pipeline, server_socket) do
    data = Enum.map(1..@payload_frames, &"(#{&1})") ++ ["."]

    Enum.each(data, fn elem ->
      Socket.send(server_socket, elem)
    end)

    received_data = TestingSinkReceiver.receive_data(pipeline)
    assert received_data == Enum.join(data)
    Pipeline.terminate(pipeline)
    Socket.close(server_socket)
  end

  describe "100 messages pass through pipeline" do
    test "created without socket" do
      {:ok, listening_server_socket} =
        %Socket{
          connection_side: :server,
          ip_address: @local_address,
          port_no: @server_port_no,
          sock_opts: [reuseaddr: true]
        }
        |> Socket.listen()

      assert pipeline =
               Pipeline.start_link_supervised!(
                 spec:
                   child(:tcp_source, %Source{
                     local_address: @local_address,
                     connection_side: {:client, @local_address, @server_port_no}
                   })
                   |> child(:sink, Sink),
                 test_process: self()
               )

      assert {:ok, server_socket} = Socket.accept(listening_server_socket)
      Socket.close(listening_server_socket)
      # time for a pipeline to enter playing playback
      Process.sleep(100)
      run_pipeline(pipeline, server_socket)
    end

    test "created with already connected client socket" do
      server_socket =
        %Socket{connection_side: :server, ip_address: @local_address, port_no: @server_port_no}

      client_socket =
        %Socket{connection_side: :client, ip_address: @local_address, port_no: 0}

      assert {:ok, listening_server_socket} = Socket.listen(server_socket)
      assert {:ok, client_socket} = Socket.connect(client_socket, server_socket)
      assert {:ok, server_socket} = Socket.accept(listening_server_socket)

      Socket.close(listening_server_socket)

      assert pipeline =
               Pipeline.start_link_supervised!(
                 spec:
                   child(:tcp_source, %Source{
                     connection_side: :client,
                     local_socket: client_socket
                   })
                   |> child(:sink, Sink),
                 test_process: self()
               )

      Process.sleep(100)
      run_pipeline(pipeline, server_socket)
    end
  end
end
