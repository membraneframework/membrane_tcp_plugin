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
                spec: :gen_tcp.socket() | nil,
                default: nil,
                description: """
                Already connected TCP socket, if provided will be used instead of creating
                and connecting a new one. It's REQUIRED to pass control of it to this element
                from the previous owner. It can be done by receiving a
                `{:request_socket_control, socket, pid}` message sent by this element to it's
                parent and calling `:gen_tcp.controlling_process(socket, pid)` (needs to be called by
                a process currently controlling the socket)
                """
              ],
              recv_buffer_size: [
                spec: pos_integer(),
                default: 1024 * 1024,
                description: """
                Size of the receive buffer. Packages of size greater than this buffer will be truncated
                """
              ]

  def_output_pad :output,
    accepted_format: %RemoteStream{type: :bytestream},
    flow_control: :manual,
    demand_unit: :buffers

  @typedoc """
  Notification sent when a local socket handle was provided via `local_socket` option.
  """
  @type request_socket_control() :: {:request_socket_control, :gen_tcp.socket(), pid()}

  @impl true
  def handle_init(_context, opts) do
    {local_socket, remote_socket} =
      CommonSocketBehaviour.create_socket_pair(Map.from_struct(opts),
        recbuf: opts.recv_buffer_size
      )

    connection_side =
      case opts.connection_side do
        :server -> :server
        :client -> :client
        {:client, _server_address, _server_port_no} -> :client
      end

    actions =
      case local_socket do
        %Socket{socket_handle: nil} ->
          []

        %Socket{socket_handle: handle} ->
          [notify_parent: {:request_socket_control, handle, self()}]
      end

    {actions,
     %{
       connection_side: connection_side,
       local_socket: local_socket,
       remote_socket: remote_socket,
       sent_info_about_first?: false
     }}
  end

  @impl true
  defdelegate handle_setup(context, state), to: CommonSocketBehaviour

  @impl true
  def handle_playing(_ctx, state) do
    {[stream_format: {:output, %RemoteStream{type: :bytestream}}], state}
  end

  @impl true
  def handle_demand(_pad, size, :buffers, _ctx, state) do
    :inet.setopts(state.local_socket.socket_handle, active: size)
    {[], state}
  end

  @impl true
  def handle_info({:tcp, _socket, payload}, _ctx, state) do
    if not state.sent_info_about_first? do
      require Logger
      Logger.warning("First buffer received123")
    end
    metadata =
      %{
        tcp_source_address: state.remote_socket.ip_address,
        tcp_source_port: state.remote_socket.port_no,
        arrival_ts: Membrane.Time.vm_time()
      }

    {
      [buffer: {:output, %Buffer{payload: payload, metadata: metadata}}],
      %{state | sent_info_about_first?: true}
    }
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, _ctx, state) do
    {[end_of_stream: :output], state}
  end

  @impl true
  def handle_info({:tcp_passive, _socket}, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_info({:tcp_error, _socket, reason}, _ctx, _state) do
    raise "TCP Socket receiving error, reason: #{inspect(reason)}"
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    Socket.close(state.local_socket)
    {[terminate: :normal], state}
  end
end
