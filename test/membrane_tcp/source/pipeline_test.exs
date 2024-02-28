defmodule Membrane.TCP.SourcePipelineTest do
  use ExUnit.Case, async: false

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.TCP.{Socket, Source, TestingSinkReceiver}
  alias Membrane.Testing.{Pipeline, Sink}

  @localhost {127, 0, 0, 1}
  @server_port_no 5052

  @payload_frames 100
  @data Enum.map(1..@payload_frames, &"(#{&1})") ++ ["."]

  defp run_pipeline(pipeline, socket) do
    Enum.each(@data, fn elem ->
      Socket.send(socket, elem)
    end)

    received_data = TestingSinkReceiver.receive_data(pipeline)
    assert received_data == Enum.join(@data)
    Pipeline.terminate(pipeline)
    Socket.close(socket)
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
                 port_no: @server_port_no
               }
               |> Socket.listen()

      pipeline =
        Pipeline.start_link_supervised!(
          spec:
            child(:tcp_source, %Source{
              local_address: @localhost,
              connection_side: {:client, @localhost, @server_port_no}
            })
            |> child(:sink, Sink),
          test_process: self()
        )

      assert {:ok, socket} = Socket.accept(listening_socket)

      Socket.close(listening_socket)

      assert_sink_playing(pipeline, :sink)

      run_pipeline(pipeline, socket)
    end

    test "server-side pipeline created without a socket" do
      pipeline =
        Pipeline.start_link_supervised!(
          spec:
            child(:tcp_source, %Source{
              connection_side: :server,
              local_address: @localhost,
              local_port_no: @server_port_no
            })
            |> child(:sink, Sink),
          test_process: self()
        )

      assert {:ok, connected_client_socket} =
               %Socket{
                 connection_side: {:client, @localhost, @server_port_no},
                 port_no: 0,
                 ip_address: @localhost
               }
               |> Socket.connect(%Socket{
                 connection_side: :server,
                 ip_address: @localhost,
                 port_no: @server_port_no
               })

      assert_sink_playing(pipeline, :sink)

      run_pipeline(pipeline, connected_client_socket)
    end

    test "client-side pipeline created with an already connected socket" do
      {client_socket, server_socket} = create_connected_socket_pair()

      pipeline =
        Pipeline.start_link_supervised!(
          spec:
            child(:tcp_source, %Source{
              connection_side: :client,
              local_socket: client_socket
            })
            |> child(:sink, Sink),
          test_process: self()
        )

      assert_sink_playing(pipeline, :sink)

      run_pipeline(pipeline, server_socket)
    end

    test "server-side pipeline created with an already connected socket" do
      {client_socket, server_socket} = create_connected_socket_pair()

      pipeline =
        Pipeline.start_link_supervised!(
          spec:
            child(:tcp_source, %Source{
              connection_side: :server,
              local_socket: server_socket
            })
            |> child(:sink, Sink),
          test_process: self()
        )

      assert_sink_playing(pipeline, :sink)

      run_pipeline(pipeline, client_socket)
    end
  end
end
