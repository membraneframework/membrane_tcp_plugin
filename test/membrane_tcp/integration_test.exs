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

  test "send and receive using 2 pipelines" do
    data = Enum.map(1..@payload_frames, &"(#{&1})") ++ ["."]

    sender =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, %Testing.Source{output: data})
          |> child(:sink, %TCP.Sink{
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
      {:connection_info, @local_address, _ephemeral_port}
    )

    assert_end_of_stream(sender, :sink)

    received_data = TCP.TestingSinkReceiver.receive_data(receiver)

    assert received_data == Enum.join(data)
    Pipeline.terminate(sender)
    Pipeline.terminate(receiver)
  end
end
