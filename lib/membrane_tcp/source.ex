defmodule Membrane.TCP.Source do
  @moduledoc """
  Element that reads packets from a TCP socket and sends their payloads through the output pad.
  """
  use Membrane.Source

  alias Membrane.{Buffer, RemoteStream}
  alias Membrane.TCP.{CommonSocketBehaviour, Socket}

  def_options connection_side: [
                spec:
                  :server
                  | :client
                  | {:client, server_address :: :inet.ip_address(),
                     server_port_no :: :inet.port_number()},
                description: """
                Determines whether this element will operate like a server or a client when
                establishing TCP connection. In case of client-side connection server address
                and port number are required, unless `local_socket` is provided.
                """
              ],
              local_address: [
                spec: :inet.socket_address(),
                default: :any,
                description: """
                An IP Address from which the socket will connect or will listen on.
                It allows to choose which network interface to use if there's more than one.
                """
              ],
              local_port_no: [
                spec: :inet.port_number(),
                default: 0,
                description: """
                A TCP port number used when connecting to a listening socket or
                starting a listening socket. If not specified any free port is chosen.
                """
              ],
              local_socket: [
                spec: Socket.t(),
                default: nil,
                description: """
                Already connected TCP socket with connection side mathing the one passed
                as an option, has to be connected.
                """
              ],
              recv_buffer_size: [
                spec: pos_integer(),
                default: 1024 * 1024,
                description: """
                Size of the receive buffer. Packages of size greater than this buffer will be truncated
                """
              ]

  def_output_pad :output, accepted_format: %RemoteStream{type: :bytestream}, flow_control: :manual

  @impl true
  def handle_init(_context, opts) do
    {local_socket, server_socket} =
      Socket.create_socket_pair(Map.from_struct(opts), recbuf: opts.recv_buffer_size)

    connection_side =
      case opts.connection_side do
        :server -> :server
        :client -> :client
        {:client, _server_address, _server_port_no} -> :client
      end

    {[],
     %{
       connection_side: connection_side,
       local_socket: local_socket,
       server_socket: server_socket
     }}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[stream_format: {:output, %RemoteStream{type: :bytestream}}], state}
  end

  @impl true
  def handle_demand(_pad, _size, _unit, _ctx, state) do
    case Socket.recv(state.local_socket) do
      {:ok, payload} ->
        {:ok, {peer_address, peer_port_no}} = :inet.peername(state.local_socket.socket_handle)

        metadata =
          Map.new()
          |> Map.put(:tcp_source_address, peer_address)
          |> Map.put(:tcp_source_port, peer_port_no)
          |> Map.put(:arrival_ts, Membrane.Time.vm_time())

        {
          [buffer: {:output, %Buffer{payload: payload, metadata: metadata}}, redemand: :output],
          state
        }

      {:error, :timeout} ->
        {[redemand: :output], state}

      {:error, :closed} ->
        {[end_of_stream: :output], state}

      {:error, reason} ->
        raise "TCP Socket receiving error, reason: #{inspect(reason)}"
    end
  end

  @impl true
  defdelegate handle_setup(context, state), to: CommonSocketBehaviour

  @impl true
  def handle_terminate_request(_ctx, state) do
    Socket.close(state.local_socket)
    {[terminate: :normal], state}
  end
end
