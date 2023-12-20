defmodule Membrane.TCP.Socket do
  @moduledoc false

  @enforce_keys [:port_no, :ip_address]
  defstruct [:port_no, :ip_address, :socket_handle, sock_opts: []]

  @type t :: %__MODULE__{
          port_no: :inet.port_number(),
          ip_address: :inet.socket_address(),
          socket_handle: :gen_tcp.socket() | nil,
          sock_opts: [:gen_tcp.option()] | nil
        }

  @spec connect(socket :: t()) :: {:ok, t()} | {:error, :inet.posix()}
  def connect(%__MODULE__{port_no: port_no, ip_address: ip, sock_opts: sock_opts} = socket) do
    connect_result = :gen_tcp.connect(port_no, [:binary, ip: ip, active: true] ++ sock_opts)

    with {:ok, socket_handle} <- connect_result,
         # Port may change if 0 is used, ip - when either `:any` or `:loopback` is passed
         {:ok, {real_ip_addr, real_port_no}} <- :inet.sockname(socket_handle) do
      updated_socket = %__MODULE__{
        socket
        | socket_handle: socket_handle,
          port_no: real_port_no,
          ip_address: real_ip_addr
      }

      {:ok, updated_socket}
    end
  end

  @spec close(socket :: t()) :: t()
  def close(%__MODULE__{socket_handle: handle} = socket) when is_port(handle) do
    :gen_tcp.close(handle)
    %__MODULE__{socket | socket_handle: nil}
  end

  @spec send(target :: t(), source :: t(), payload :: Membrane.Payload.t()) ::
          :ok | {:error, :not_owner | :inet.posix()}
  def send(
        %__MODULE__{port_no: target_port_no, ip_address: target_ip},
        %__MODULE__{socket_handle: socket_handle},
        payload
      )
      when is_port(socket_handle) do
    :gen_tcp.send(socket_handle, payload)
  end
end
