defmodule Membrane.TCP.Source do
  @moduledoc """
  Element that reads packets from a TCP socket and sends their payloads through the output pad.
  """
  use Membrane.Source

  alias Membrane.{Buffer, RemoteStream}
  alias Membrane.TCP.{CommonSocketBehaviour, Socket}

  def_options connection_side: [
                spec: :client | :server,
                default: :client,
                description: """
                Determines whether this element will behave like a server or a client when
                establishing TCP connection.
                """
              ],
              server_address: [
                spec: :inet.ip_address() | nil,
                default: nil,
                description: """
                An IP Address of the server the packets will be sent from.
                (nil in case of `connection_side: :server`)
                """
              ],
              server_port_no: [
                spec: :inet.port_number() | nil,
                default: nil,
                description: """
                A TCP port number of the server the packets will be sent from.
                (nil in case of `connection_side: :server`)
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
              local_address: [
                spec: :inet.socket_address(),
                default: :any,
                description: """
                An IP Address from which the socket will connect or will listen on.
                It allows to choose which network interface to use if there's more than one.
                """
              ],
              socket: [
                spec: :gen_tcp.socket(),
                default: nil,
                description: """
                Already connected TCP socket, has to be in active mode.
                """
              ],
              recv_buffer_size: [
                spec: pos_integer(),
                default: 1024 * 1024,
                description: """
                Size of the receive buffer. Packages of size greater than this buffer will be truncated
                """
              ]

  def_output_pad :output, accepted_format: %RemoteStream{type: :packetized}, flow_control: :push

  @impl true
  def handle_init(_context, opts) do
    {local_socket, server_socket} =
      Socket.create_socket_pair(Map.from_struct(opts), recbuf: opts.recv_buffer_size)

    {[],
     %{
       connection_side: opts.connection_side,
       local_socket: local_socket,
       server_socket: server_socket
     }}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[stream_format: {:output, %RemoteStream{type: :packetized}}], state}
  end

  @impl true
  def handle_info({:tcp, socket_handle, payload}, %{playback: :playing}, state) do
    {:ok, {peer_address, peer_port_no}} = :inet.peername(socket_handle)

    metadata =
      Map.new()
      |> Map.put(:tcp_source_address, peer_address)
      |> Map.put(:tcp_source_port, peer_port_no)
      |> Map.put(:arrival_ts, Membrane.Time.vm_time())

    actions = [buffer: {:output, %Buffer{payload: payload, metadata: metadata}}]

    {actions, state}
  end

  @impl true
  def handle_info({:tcp, _socket_handle, _address, _port_no, _payload}, _ctx, state) do
    {[], state}
  end

  def handle_info({:tcp_closed, _local_socket_handle}, _ctx, state) do
    Socket.close(state.local_socket)
    {[], state}
  end

  @impl true
  defdelegate handle_setup(context, state), to: CommonSocketBehaviour

  @impl true
  def handle_terminate_request(_ctx, state) do
    Socket.close(state.local_socket)
    {[terminate: :normal], state}
  end
end
