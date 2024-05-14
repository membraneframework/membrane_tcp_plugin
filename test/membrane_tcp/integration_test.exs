defmodule Membrane.TCP.IntegrationTest do
  use ExUnit.Case, async: false

  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  alias Membrane.TCP
  alias Membrane.Testing
  alias Membrane.Testing.Pipeline

  @server_port 6789
  @localhost {127, 0, 0, 1}

  @payload_frames 1000
  @data Enum.map(1..@payload_frames, &"(#{&1})") ++ ["."]

  test "send from server-side pipeline and receive on client-side pipeline" do
    sender =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, %Testing.Source{output: @data})
          |> child(:sink, %TCP.Sink{
            connection_side: :server,
            local_address: @localhost,
            local_port_no: @server_port
          })
      )

    receiver =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, %TCP.Source{
            connection_side: {:client, @localhost, @server_port},
            local_address: @localhost
          })
          |> child(:sink, %Testing.Sink{})
      )

    assert_pipeline_notified(sender, :sink, {:connection_info, @localhost, @server_port})

    assert_pipeline_notified(receiver, :source, {:connection_info, @localhost, _port})

    assert_end_of_stream(sender, :sink)

    received_data = TCP.TestingSinkReceiver.receive_data(receiver)

    assert received_data == Enum.join(@data)
    Pipeline.terminate(sender)
    Pipeline.terminate(receiver)
  end

  test "send from client-side pipeline and receive on server-side pipeline" do
    receiver =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, %TCP.Source{
            connection_side: :server,
            local_address: @localhost,
            local_port_no: @server_port
          })
          |> child(:sink, %Testing.Sink{})
      )

    sender =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, %Testing.Source{output: @data})
          |> child(:sink, %TCP.Sink{
            connection_side: {:client, @localhost, @server_port},
            local_address: @localhost
          })
      )

    assert_pipeline_notified(sender, :sink, {:connection_info, @localhost, _port})

    assert_pipeline_notified(receiver, :source, {:connection_info, @localhost, @server_port})

    assert_end_of_stream(sender, :sink)

    received_data = TCP.TestingSinkReceiver.receive_data(receiver)

    assert received_data == Enum.join(@data)
    Pipeline.terminate(sender)
    Pipeline.terminate(receiver)
  end
end
