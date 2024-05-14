defmodule Membrane.TCP.CommonSocketBehaviour do
  @moduledoc false

  alias Membrane.Element
  alias Membrane.Element.Base
  alias Membrane.Element.CallbackContext
  alias Membrane.TCP.Socket

  @type socket_pair_config :: %{
          connection_side: :server | :client | {:client, :inet.ip_address(), :inet.port_number()},
          local_address: :inet.socket_address(),
          local_port_no: :inet.port_number(),
          local_socket: :gen_tcp.socket() | nil
        }

  @spec create_socket_pair(socket_pair_config(), keyword()) ::
          {local_socket :: Socket.t(), remote_socket :: Socket.t() | nil}
  def create_socket_pair(sockets_config, local_socket_options \\ []) do
    local_socket = create_local_socket(sockets_config, local_socket_options)

    remote_socket = create_remote_socket(sockets_config, local_socket)

    {local_socket, remote_socket}
  end

  @spec handle_setup(context :: CallbackContext.t(), state :: Element.state()) ::
          Base.callback_return()
  def handle_setup(
        ctx,
        %{connection_side: :client, local_socket: local_socket, remote_socket: server_socket} =
          state
      ) do
    local_socket_connection_result =
      if local_socket.state == :connected do
        {:ok, local_socket}
      else
        Socket.connect(local_socket, server_socket)
      end

    handle_local_socket_connection_result(local_socket_connection_result, ctx, state)
  end

  def handle_setup(ctx, %{connection_side: :server, local_socket: local_socket} = state) do
    local_socket_connection_result =
      if local_socket.state == :connected do
        {:ok, local_socket}
      else
        with {:ok, listening_socket} <- Socket.listen(local_socket),
             do: Socket.accept(listening_socket)
      end

    handle_local_socket_connection_result(local_socket_connection_result, ctx, state)
  end

  @spec create_local_socket(socket_pair_config(), [:gen_tcp.option()]) :: Socket.t()
  defp create_local_socket(%{local_socket: nil} = sockets_config, local_socket_options) do
    %Socket{
      ip_address: sockets_config.local_address,
      port_no: sockets_config.local_port_no,
      sock_opts: local_socket_options,
      connection_side: sockets_config.connection_side
    }
  end

  defp create_local_socket(%{local_socket: socket_handle} = sockets_config, local_socket_options) do
    {:ok, {socket_address, socket_port}} = :inet.sockname(socket_handle)

    cond do
      sockets_config.local_address not in [socket_address, :any] ->
        raise "Local address passed in options not matching the one of the passed socket."

      sockets_config.local_port_no not in [socket_port, 0] ->
        raise "Local port passed in options not matching the one of the passed socket."

      not match?({:ok, _peername}, :inet.peername(socket_handle)) ->
        raise "Local socket not connected."

      true ->
        :ok
    end

    :inet.setopts(socket_handle, active: false)

    %Socket{
      ip_address: sockets_config.local_address,
      port_no: sockets_config.local_port_no,
      socket_handle: socket_handle,
      state: :connected,
      connection_side: sockets_config.connection_side,
      sock_opts: local_socket_options
    }
  end

  @spec create_remote_socket(socket_pair_config(), Socket.t()) :: Socket.t()
  defp create_remote_socket(sockets_config, local_socket) do
    case sockets_config.connection_side do
      :server ->
        nil

      :client ->
        {:ok, {server_address, server_port}} = :inet.peername(local_socket.socket_handle)

        %Socket{ip_address: server_address, port_no: server_port, connection_side: :server}

      {:client, address, port_no} ->
        %Socket{ip_address: address, port_no: port_no, connection_side: :server}
    end
  end

  @spec handle_local_socket_connection_result(
          {:ok, Socket.t()} | {:error, term()},
          Membrane.Element.CallbackContext.t(),
          Membrane.Element.state()
        ) :: Membrane.Element.Base.callback_return() | no_return()
  defp handle_local_socket_connection_result({:ok, connected_socket}, ctx, state) do
    notification = {:connection_info, connected_socket.ip_address, connected_socket.port_no}

    Membrane.ResourceGuard.register(
      ctx.resource_guard,
      fn -> close_socket(connected_socket) end,
      tag: :tcp_guard
    )

    remote_socket =
      if state.remote_socket != nil do
        state.remote_socket
      else
        {:ok, {remote_address, remote_port}} = :inet.peername(connected_socket.socket_handle)

        remote_connection_side =
          case connected_socket.connection_side do
            :client -> :server
            :server -> :client
          end

        %Socket{
          connection_side: remote_connection_side,
          ip_address: remote_address,
          port_no: remote_port,
          state: :connected
        }
      end

    {[notify_parent: notification],
     %{state | local_socket: connected_socket, remote_socket: remote_socket}}
  end

  defp handle_local_socket_connection_result({:error, reason}, _ctx, _state) do
    raise "Error connecting TCP socket, reason: #{inspect(reason)}"
  end

  defp close_socket(%Socket{} = local_socket) do
    Socket.close(local_socket)
  end
end
