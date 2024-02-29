defmodule Membrane.TCP.Sink do
  @moduledoc """
  Element that sends buffers received on the input pad over a TCP socket.
  """
  use Membrane.Sink

  alias Membrane.Buffer
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
                and connecting a new one.
                """
              ]

  def_input_pad :input, accepted_format: _any

  @impl true
  def handle_init(_context, opts) do
    {local_socket, remote_socket} = Socket.create_socket_pair(Map.from_struct(opts))

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
       remote_socket: remote_socket
     }}
  end

  @impl true
  def handle_playing(_context, state) do
    {[], state}
  end

  @impl true
  def handle_buffer(:input, %Buffer{payload: payload}, _context, state) do
    %{local_socket: local_socket} = state

    case Socket.send(local_socket, payload) do
      :ok -> {[], state}
      {:error, cause} -> raise "Error sending TCP packet, reason: #{inspect(cause)}"
    end
  end

  @impl true
  defdelegate handle_setup(context, state), to: CommonSocketBehaviour
end
