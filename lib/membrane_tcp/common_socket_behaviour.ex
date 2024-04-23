defmodule Membrane.TCP.CommonSocketBehaviour do
  @moduledoc false

  alias Membrane.Element
  alias Membrane.Element.Base
  alias Membrane.Element.CallbackContext
  alias Membrane.TCP.Socket

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
