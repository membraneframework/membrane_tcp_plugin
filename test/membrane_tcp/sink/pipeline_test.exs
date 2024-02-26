defmodule Membrane.TCP.SinkPipelineTest do
  use ExUnit.Case, async: false

  import Membrane.ChildrenSpec

  alias Membrane.TCP.{Sink, Socket}
  alias Membrane.Testing.{Pipeline, Source}

  @localhost {127, 0, 0, 1}
  @server_port_no 5052

  @payload_frames 100
  @data Enum.map(1..@payload_frames, &"(#{&1})") ++ ["."]

  defp run_pipeline(pipeline, socket) do
    received_data = receive_data(socket)
    assert received_data == Enum.join(@data)
    Pipeline.terminate(pipeline)
    Socket.close(socket)
  end

  defp receive_data(socket, received_data \\ "", terminator \\ ".") do
    {:ok, payload} = Socket.recv(socket)

    if String.ends_with?(payload, terminator) do
      received_data <> payload
    else
      receive_data(socket, received_data <> payload)
    end
  end

  defp create_connected_socket_pair() do
    server_socket =
      %Socket{connection_side: :server, ip_address: @localhost, port_no: @server_port_no}

    client_socket =
      %Socket{connection_side: :client, ip_address: @localhost, port_no: 0}

    {:ok, listening_socket} = Socket.listen(server_socket)
    {:ok, client_socket} = Socket.connect(client_socket, server_socket)
    {:ok, server_socket} = Socket.accept(listening_socket)

    Socket.close(listening_socket)

    {client_socket, server_socket}
  end

  describe "100 messages pass through a" do
    test "client-side pipeline created without a socket" do
      assert {:ok, listening_socket} =
               %Socket{
                 connection_side: :server,
                 ip_address: @localhost,
                 port_no: @server_port_no,
                 sock_opts: [active: false]
               }
               |> Socket.listen()

      assert pipeline =
               Pipeline.start_link_supervised!(
                 spec:
                   child(:source, %Source{output: @data})
                   |> child(:sink, %Sink{
                     local_address: @localhost,
                     connection_side: {:client, @localhost, @server_port_no}
                   }),
                 test_process: self()
               )

      assert {:ok, socket} = Socket.accept(listening_socket)
      Socket.close(listening_socket)
      # time for a pipeline to enter playing playback
      Process.sleep(200)
      run_pipeline(pipeline, socket)
    end

    test "server-side pipeline created without a socket" do
      assert pipeline =
               Pipeline.start_link_supervised!(
                 spec:
                   child(:tcp_source, %Source{output: @data})
                   |> child(:sink, %Sink{
                     connection_side: :server,
                     local_address: @localhost,
                     local_port_no: @server_port_no
                   }),
                 test_process: self()
               )

      assert {:ok, connected_client_socket} =
               %Socket{
                 connection_side: {:client, @localhost, @server_port_no},
                 port_no: 0,
                 ip_address: @localhost,
                 sock_opts: [active: false]
               }
               |> Socket.connect(%Socket{
                 connection_side: :server,
                 ip_address: @localhost,
                 port_no: @server_port_no
               })

      # time for a pipeline to enter playing playback
      Process.sleep(200)
      run_pipeline(pipeline, connected_client_socket)
    end

    test "client-side pipeline created with an already connected socket" do
      {client_socket, server_socket} = create_connected_socket_pair()

      assert pipeline =
               Pipeline.start_link_supervised!(
                 spec:
                   child(:tcp_source, %Source{
                     output: @data
                   })
                   |> child(:sink, %Sink{
                     connection_side: :client,
                     local_socket: client_socket
                   }),
                 test_process: self()
               )

      Process.sleep(200)
      run_pipeline(pipeline, server_socket)
    end

    test "server-side pipeline created with an already connected socket" do
      {client_socket, server_socket} = create_connected_socket_pair()

      assert pipeline =
               Pipeline.start_link_supervised!(
                 spec:
                   child(:tcp_source, %Source{
                     output: @data
                   })
                   |> child(:sink, %Sink{
                     connection_side: :server,
                     local_socket: server_socket
                   }),
                 test_process: self()
               )

      Process.sleep(200)
      run_pipeline(pipeline, client_socket)
    end
  end
end
