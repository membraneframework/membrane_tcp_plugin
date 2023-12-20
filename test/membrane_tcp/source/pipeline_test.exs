defmodule Membrane.TCP.SourcePipelineTest do
  use ExUnit.Case, async: false

  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  alias Membrane.TCP.Source
  alias Membrane.Testing.{Pipeline, Sink}

  @local_address {127, 0, 0, 1}
  @local_port_no 5052
  @destination_port_no 5053
  @values 1..100
  @timeout 2_000

  test "100 messages passes through pipeline" do
    data = @values |> Enum.map(&to_string(&1))

    assert pipeline =
             Pipeline.start_link_supervised!(
               spec: [
                 child(:tcp_source, %Source{
                   local_address: @local_address,
                   local_port_no: @destination_port_no
                 })
                 |> child(:sink, %Sink{})
               ],
               test_process: self()
             )

    # time for a pipeline to enter playing playback
    Process.sleep(100)

    Enum.map(data, fn elem ->
      tcp_like_message = {:tcp, nil, @local_address, @local_port_no, elem}
      Pipeline.message_child(pipeline, :tcp_source, tcp_like_message)
    end)

    Enum.each(data, fn elem ->
      expected_value = to_string(elem)

      assert_sink_buffer(
        pipeline,
        :sink,
        %Membrane.Buffer{
          metadata: %{
            tcp_source_address: @local_address,
            tcp_source_port: @local_port_no
          },
          payload: ^expected_value
        },
        @timeout
      )
    end)

    Pipeline.terminate(pipeline)
  end
end
