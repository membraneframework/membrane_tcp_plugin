defmodule Membrane.TCP.SocketTest do
  use ExUnit.Case, async: false

  alias Membrane.TCP.Socket

  describe "listen" do
    test "with explicit port and address" do
      sock = %Socket{port_no: 50_666, ip_address: {127, 0, 0, 1}}
      assert {:ok, new_sock} = Socket.listen(sock)
      assert new_sock.ip_address == sock.ip_address
      assert new_sock.port_no == sock.port_no

      assert :inet.sockname(new_sock.socket_handle) ==
               {:ok, {new_sock.ip_address, new_sock.port_no}}
    end

    test "with port 0 and `:any` IPv6 address" do
      sock = %Socket{port_no: 0, ip_address: :any, sock_opts: [:inet6]}
      assert {:ok, new_sock} = Socket.listen(sock)
      assert new_sock.ip_address == {0, 0, 0, 0, 0, 0, 0, 0}
      assert new_sock.port_no != 0

      assert :inet.sockname(new_sock.socket_handle) ==
               {:ok, {new_sock.ip_address, new_sock.port_no}}
    end

    test "with port 0 and `:loopback` IPv4 address" do
      sock = %Socket{port_no: 0, ip_address: :loopback, sock_opts: [:inet]}
      assert {:ok, new_sock} = Socket.listen(sock)
      assert new_sock.ip_address == {127, 0, 0, 1}
      assert new_sock.port_no != 0

      assert :inet.sockname(new_sock.socket_handle) ==
               {:ok, {new_sock.ip_address, new_sock.port_no}}
    end
  end

  describe "socket pair" do
    test "completes the handshake successfully" do
      client_socket = %Socket{port_no: 50_667, ip_address: :loopback}
      server_socket = %Socket{port_no: 50_666, ip_address: {127, 0, 0, 1}}

      assert {:ok, listening_server_socket} = Socket.listen(server_socket)
      assert {:ok, client_socket} = Socket.connect(client_socket, server_socket)
      assert {:ok, server_socket} = Socket.accept(listening_server_socket)

      assert {:ok, {server_socket.ip_address, server_socket.port_no}} ==
               :inet.peername(client_socket.socket_handle)

      assert {:ok, {client_socket.ip_address, client_socket.port_no}} ==
               :inet.peername(server_socket.socket_handle)

      Socket.close(server_socket)
      Socket.close(listening_server_socket)
      Socket.close(client_socket)

      assert :undefined == :erlang.port_info(client_socket.socket_handle)
      assert :undefined == :erlang.port_info(server_socket.socket_handle)
    end
  end
end
