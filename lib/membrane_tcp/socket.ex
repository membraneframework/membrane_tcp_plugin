defmodule Membrane.TCP.Socket do
  @moduledoc """
  TCP Socket behavior
  """

  @enforce_keys [:connection_side, :port_no, :ip_address]
  defstruct [:port_no, :ip_address, :socket_handle, :state, :connection_side, sock_opts: []]

  @type t :: %__MODULE__{
          port_no: :inet.port_number(),
          ip_address: :inet.socket_address(),
          socket_handle: :gen_tcp.socket() | nil,
          state: :listening | :connected | nil,
          connection_side: :server | :client | nil,
          sock_opts: [:gen_tcp.option()]
        }

  @type socket_pair_config :: %{
          connection_side: :server | :client | {:client, :inet.ip_address(), :inet.port_number()},
          local_address: :inet.socket_address(),
          local_port_no: :inet.port_number(),
          local_socket: t() | nil
        }

  @spec create_socket_pair(socket_pair_config(), keyword()) ::
          {local_socket :: t(), remote_socket :: t() | nil}
  def create_socket_pair(
        %{connection_side: connection_side, local_socket: local_socket} = sockets_config,
        local_socket_options \\ []
      ) do
    local_socket =
      case local_socket do
        nil ->
          %__MODULE__{
            ip_address: sockets_config.local_address,
            port_no: sockets_config.local_port_no,
            sock_opts: local_socket_options,
            connection_side: connection_side
          }

        %__MODULE__{connection_side: ^connection_side, state: :connected} ->
          local_socket

        _not_matching_connection_side_socket ->
          raise "Connection side of provided socket not matching options"
      end

    remote_socket =
      case connection_side do
        :server ->
          nil

        :client ->
          {:ok, {server_address, server_port}} = :inet.peername(local_socket.socket_handle)

          %__MODULE__{ip_address: server_address, port_no: server_port, connection_side: :server}

        {:client, address, port_no} ->
          %__MODULE__{ip_address: address, port_no: port_no, connection_side: :server}
      end

    {local_socket, remote_socket}
  end

  @spec listen(socket :: t()) :: {:ok, listen_socket :: t()} | {:error, :inet.posix()}
  def listen(%__MODULE__{port_no: port_no, ip_address: ip, sock_opts: sock_opts} = local_socket) do
    listen_result =
      :gen_tcp.listen(port_no, [:binary, ip: ip, active: false, reuseaddr: true] ++ sock_opts)

    with {:ok, listen_socket_handle} <- listen_result,
         # Port may change if 0 is used, ip - when either `:any` or `:loopback` is passed
         {:ok, {real_ip_addr, real_port_no}} <- :inet.sockname(listen_socket_handle) do
      updated_socket = %__MODULE__{
        local_socket
        | socket_handle: listen_socket_handle,
          port_no: real_port_no,
          ip_address: real_ip_addr,
          state: :listening
      }

      {:ok, updated_socket}
    end
  end

  @spec accept(listening_socket :: t()) ::
          {:ok, connected_socket :: t()} | {:error, :inet.posix()}
  def accept(%__MODULE__{socket_handle: socket_handle, state: :listening} = socket) do
    accept_result = :gen_tcp.accept(socket_handle)

    with {:ok, connected_socket_handle} <- accept_result do
      :gen_tcp.close(socket_handle)

      updated_socket = %__MODULE__{
        socket
        | socket_handle: connected_socket_handle,
          state: :connected
      }

      {:ok, updated_socket}
    end
  end

  @spec connect(local :: t(), target :: t()) :: {:ok, t()} | {:error, :inet.posix()}
  def connect(
        %__MODULE__{port_no: local_port_no, ip_address: local_ip, sock_opts: sock_opts} =
          local_socket,
        %__MODULE__{port_no: target_port_no, ip_address: target_ip}
      ) do
    connect_result =
      :gen_tcp.connect(
        target_ip,
        target_port_no,
        [:binary, ip: local_ip, port: local_port_no, active: false, reuseaddr: true] ++ sock_opts
      )

    with {:ok, socket_handle} <- connect_result,
         # Port may change if 0 is used, ip - when either `:any` or `:loopback` is passed
         {:ok, {real_ip_addr, real_port_no}} <- :inet.sockname(socket_handle) do
      updated_socket = %__MODULE__{
        local_socket
        | socket_handle: socket_handle,
          port_no: real_port_no,
          ip_address: real_ip_addr,
          state: :connected
      }

      {:ok, updated_socket}
    end
  end

  @spec close(socket :: t()) :: t()
  def close(%__MODULE__{socket_handle: handle} = socket) when is_port(handle) do
    :ok = :gen_tcp.close(handle)
    %__MODULE__{socket | socket_handle: nil, state: nil}
  end

  @spec send(local_socket :: t(), payload :: Membrane.Payload.t()) ::
          :ok | {:error, :closed | :inet.posix()}
  def send(%__MODULE__{socket_handle: socket_handle}, payload) when is_port(socket_handle) do
    :gen_tcp.send(socket_handle, payload)
  end

  @spec recv(socket :: t()) ::
          {:ok, Membrane.Payload.t()} | {:error, :closed | :timeout | :inet.posix()}
  def recv(%__MODULE__{socket_handle: socket_handle}) do
    :gen_tcp.recv(socket_handle, 0, 0)
  end
end
