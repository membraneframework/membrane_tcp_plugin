defmodule Membrane.TCP.IntegrationTest do
  use ExUnit.Case, async: false

  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  alias Membrane.TCP
  alias Membrane.Testing
  alias Membrane.Testing.Pipeline

  @server_port 6789
  @local_address {127, 0, 0, 1}

  @payload_frames 100

  test "send from server pipeline and receive on client pipeline" do
    data = Enum.map(1..@payload_frames, &"(#{&1})") ++ ["."]

    sender =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, %Testing.Source{output: data})
          |> child(:sink, %TCP.Sink{
            connection_side: :server,
            local_address: @local_address,
            local_port_no: @server_port
          })
      )

    receiver =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, %TCP.Source{
            connection_side: {:client, @local_address, @server_port},
            local_address: @local_address
          })
          |> child(:sink, %Testing.Sink{})
      )

    assert_pipeline_notified(sender, :sink, {:connection_info, @local_address, @server_port})

    assert_pipeline_notified(
      receiver,
      :source,
      {:connection_info, @local_address, _port}
    )

    assert_end_of_stream(sender, :sink)

    received_data = TCP.TestingSinkReceiver.receive_data(receiver)

    assert received_data == Enum.join(data)
    Pipeline.terminate(sender)
    Pipeline.terminate(receiver)
  end

  test "send from client pipeline and receive on server pipeline" do
    data = Enum.map(1..@payload_frames, &"(#{&1})") ++ ["."]

    receiver =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, %TCP.Source{
            connection_side: :server,
            local_address: @local_address,
            local_port_no: @server_port
          })
          |> child(:sink, %Testing.Sink{})
      )

    sender =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, %Testing.Source{output: data})
          |> child(:sink, %TCP.Sink{
            connection_side: {:client, @local_address, @server_port},
            local_address: @local_address
          })
      )

    assert_pipeline_notified(sender, :sink, {:connection_info, @local_address, _port})

    assert_pipeline_notified(receiver, :source, {:connection_info, @local_address, @server_port})

    assert_end_of_stream(sender, :sink)

    received_data = TCP.TestingSinkReceiver.receive_data(receiver)

    assert received_data == Enum.join(data)
    Pipeline.terminate(sender)
    Pipeline.terminate(receiver)
  end
end
