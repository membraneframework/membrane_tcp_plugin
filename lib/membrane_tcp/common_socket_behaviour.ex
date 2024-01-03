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
        %{connection_side: :client, local_socket: local_socket, server_socket: server_socket} =
          state
      ) do
    case Socket.connect(local_socket, server_socket) do
      {:ok, socket} ->
        notification = {:connection_info, socket.ip_address, socket.port_no}

        Membrane.ResourceGuard.register(
          ctx.resource_guard,
          fn -> close_socket(socket) end,
          tag: :tcp_guard
        )

        {[notify_parent: notification], %{state | local_socket: socket}}

      {:error, reason} ->
        raise "Error connecting TCP socket, reason: #{inspect(reason)}"
    end
  end

  def handle_setup(ctx, %{connection_side: :server, local_socket: local_socket} = state) do
    with {:ok, listening_socket} <- Socket.listen(local_socket),
         {:ok, connected_socket} <- Socket.accept(listening_socket) do
      notification = {:connection_info, connected_socket.ip_address, connected_socket.port_no}

      Membrane.ResourceGuard.register(
        ctx.resource_guard,
        fn -> close_socket(connected_socket) end,
        tag: :tcp_guard
      )

      {[notify_parent: notification], %{state | local_socket: connected_socket}}
    else
      {:error, reason} ->
        raise "Error connecting TCP socket, reason: #{inspect(reason)}"
    end
  end

  defp close_socket(%Socket{} = local_socket) do
    Socket.close(local_socket)
  end
end
