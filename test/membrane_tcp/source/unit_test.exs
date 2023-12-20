defmodule Membrane.TCP.SourceTest do
  use ExUnit.Case

  alias Membrane.TCP.{Endpoint, Source}

  for module <- [Endpoint, Source] do
    test "parses tcp message #{inspect(module)} element" do
      example_binary_payload = "Hi there, I am binary"
      sender_port = 6666
      sender_address = {192, 168, 0, 1}
      state = :unchanged
      message = {:tcp, 5000, sender_address, sender_port, example_binary_payload}

      assert {actions, ^state} =
               unquote(module).handle_parent_notification(message, %{playback: :playing}, state)

      assert {:output, buffer} = Keyword.get(actions, :buffer)

      assert %Membrane.Buffer{
               payload: ^example_binary_payload,
               metadata: %{
                 tcp_source_address: ^sender_address,
                 tcp_source_port: ^sender_port,
                 arrival_ts: arrival_ts
               }
             } = buffer

      assert_in_delta(arrival_ts, Membrane.Time.vm_time(), 2 |> Membrane.Time.milliseconds())
    end
  end
end
