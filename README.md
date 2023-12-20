# Membrane TCP plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_tcp_plugin.svg)](https://hex.pm/packages/membrane_tcp_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_tcp_plugin/)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_tcp_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_tcp_plugin)

This package provides TCP Source and Sink, that read and write to TCP sockets.

## Installation

Add the following line to your `deps` in `mix.exs`. Run `mix deps.get`.

```elixir
	{:membrane_tcp_plugin, "~> 0.1.0"}
```

## Usage example

The example below shows 2 pipelines. `TCPDemo.Send` downloads an example file over HTTP and
sends it over TCP socket via localhost:

```elixir
defmodule TCPDemo.Send do
  use Membrane.Pipeline

  alias Membrane.{Hackney, TCP}
  alias Membrane.Pipeline.Spec

  def handle_init(_) do
    children = [
      source: %Hackney.Source{
        location: "https://membraneframework.github.io/static/video-samples/test-video.h264"
      },
      tcp: %TCP.Sink{
        destination_address: {127, 0, 0, 1},
        destination_port_no: 5001,
        local_address: {127, 0, 0, 1}
      }
    ]

    links = %{
      {:source, :output} => {:tcp, :input}
    }

    spec = %Spec{children: children, links: links}
    {[spec: spec], %{}}
  end
end
```

The `TCPDemo.Receive` retrieves packets from TCP socket and
saves the data to the `/tmp/tcp-recv.h264` file.

Bear in mind that for other files/sending pipelines you may need do adjust
[`recv_buffer_size`](https://hexdocs.pm/membrane_tcp_plugin/Membrane.TCP.Source.html#module-element-options)
option in `Membrane.TCP.Source` that determines the maximum size of received packets.

```elixir
defmodule TCPDemo.Receive do
  use Membrane.Pipeline

  alias Membrane.Element.{File, TCP}
  alias Membrane.Pipeline.Spec

  def handle_init(_) do
    children = [
      tcp: %TCP.Source{
        local_address: {127, 0, 0, 1},
        local_port_no: 5001
      },
      sink: %File.Sink{
        location: "/tmp/tcp-recv.h264"
      }
    ]

    links = %{
      {:tcp, :output} => {:sink, :input}
    }

    spec = %Spec{children: children, links: links}
    {[spec: spec], %{}}
  end
end
```

The snippet below presents how to run these pipelines. For convenience, it uses `Membrane.Testing.Pipeline`
that wraps the pipeline modules above and allows to assert on state changes and end of stream events from the elements.
Thanks to that, we can make sure the data is sent only when the receiving end is ready and the pipelines are stopped
after everything has been sent.

```elixir
alias Membrane.Testing.Pipeline
import Membrane.Testing.Assertions

sender = Pipeline.start_link_supervised!(%Pipeline.Options{module: TCPDemo.Send})
receiver = Pipeline.start_link_supervised!(%Pipeline.Options{module: TCPDemo.Receive})

assert_end_of_stream(sender, :tcp, :input, 5000)

:ok = Pipeline.terminate(sender)
:ok = Pipeline.terminate(receiver)
```

The deps required to run the example:

```elixir
defp deps do
  [
    {:membrane_core, "~> 0.9.0"},
	  {:membrane_tcp_plugin, "~> 0.12.0"}
    {:membrane_hackney_plugin, "~> 0.6"},
    {:membrane_file_plugin, "~> 0.9"}
  ]
end
```

## Copyright and License

Copyright 2019, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

Licensed under the [Apache License, Version 2.0](LICENSE)
