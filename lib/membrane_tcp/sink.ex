defmodule Membrane.TCP.Sink do
  @moduledoc """
  Element that sends buffers received on the input pad over a TCP socket.
  """
  use Membrane.Sink

  alias Membrane.Buffer
  alias Membrane.TCP.{CommonSocketBehaviour, Socket}

  def_options connection_side: [
                spec: :client | :server,
                default: :server,
                description: """
                Determines whether this element will behave like a server or a client when
                establishing TCP connection.
                """
              ],
              server_address: [
                spec: :inet.ip_address() | nil,
                default: nil,
                description: """
                An IP Address of the server the packets will be sent to.
                (nil in case of `connection_side: :server`)
                """
              ],
              server_port_no: [
                spec: :inet.port_number() | nil,
                default: nil,
                description: """
                A TCP port number of the server the packets will be sent to.
                (nil in case of `connection_side: :server`)
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
              ]

  def_input_pad :input, accepted_format: _any

  @impl true
  def handle_init(_context, opts) do
    {local_socket, server_socket} = Socket.create_socket_pair(Map.from_struct(opts))

    {[],
     %{
       connection_side: opts.connection_side,
       local_socket: local_socket,
       server_socket: server_socket
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
