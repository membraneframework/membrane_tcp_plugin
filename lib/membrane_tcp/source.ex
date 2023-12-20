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
                default: 5000,
                description: """
                A TCP port number used when connecting to a listening socket or
                starting a listening socket.
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
  def handle_init(_context, %__MODULE__{} = opts) do
    socket = %Socket{
      ip_address: opts.local_address,
      port_no: opts.local_port_no,
      sock_opts: [recbuf: opts.recv_buffer_size]
    }

    server_socket =
      case opts do
        %__MODULE__{connection_side: :server} ->
          nil

        %__MODULE__{connection_side: :client, server_address: address, server_port_no: port_no} ->
          %Socket{
            ip_address: address,
            port_no: port_no
          }
      end

    {[], %{local_socket: socket, server_socket: server_socket}}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[stream_format: {:output, %RemoteStream{type: :packetized}}], state}
  end

  @impl true
  def handle_parent_notification(
        {:tcp, _socket_handle, _addr, _port_no, _payload} = meta,
        ctx,
        state
      ) do
    handle_info(meta, ctx, state)
  end

  @impl true
  def handle_info(
        {:tcp, _socket_handle, address, port_no, payload},
        %{playback: :playing},
        state
      ) do
    metadata =
      Map.new()
      |> Map.put(:tcp_source_address, address)
      |> Map.put(:tcp_source_port, port_no)
      |> Map.put(:arrival_ts, Membrane.Time.vm_time())

    actions = [buffer: {:output, %Buffer{payload: payload, metadata: metadata}}]

    {actions, state}
  end

  @impl true
  def handle_info(
        {:tcp, _socket_handle, _address, _port_no, _payload},
        _ctx,
        state
      ) do
    {[], state}
  end

  @impl true
  defdelegate handle_setup(context, state), to: CommonSocketBehaviour
end
