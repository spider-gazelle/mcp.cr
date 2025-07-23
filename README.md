# MCP Crystal SDK

The un-official Crystal-lang implementation of [Model Context Protocol](https://modelcontextprotocol.io) (MCP) providing both client and server capabilities for integrating with LLM surfaces across various platforms.

## Overview

The Model Context Protocol allows applications to provide context for LLMs in a standardized way, separating the concerns of providing context from the actual LLM interaction.
This shard implements the MCP specification for Crystal, enabling you to build applications that can communicate using MCP.

- Build MCP clients that can connect to any MCP server
- Create MCP servers that expose resources, prompts and tools
- Use standard transports like STDIO
- Handle all MCP protocol messages and lifecycle events

### TODO 

Implement 

- [X] SSE Transport
- [X] Streamable HTTP Transport 
- [ ] WebSocket transports (optional)

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     mcp:
       github: spider-gazelle/mcp.cr
   ```

2. Run `shards install`

## Usage

```crystal
require "mcp"
```
### Quick Start

### Creating a Server

#### Easy way

```crystal
@[MCP::MCPServer(name: "weather_service", version: "2.1.0", tools: false, prompts: false, resources: false)]
@[MCP::Transport(type: streamable, endpoint: "/mymcp")]
class WeatherMCPServer
  include MCP::Annotator

  getter(weather_client : WeatherApi) { WeatherApi.new }

  @[MCP::Tool(
    name: "weather_alerts",
    description: "Get weather alerts for a US state. Input is Two-letter US state code (e.g. CA, NY)",
    state: {description => "Two-letter US state code (e.g. CA, NY)"},
    limit: {description => "size of result"}
  )]
  def get_alerts(state : String, limit : Int32?) : Array(String)
    weather_client.get_alerts(state)
  end

  @[MCP::Tool(
    # name: "get_forecast",
    description: "Get weather forecast for a specific latitude/longitude",
    latitude: {"minimum" => -90, "maximum" => 90, "description" => "Latitude coordinate"},
    longitude: {"minimum" => -180, "maximum" => 180, "default" => 107, "description" => "Longitude coordinate"},
  )]
  def get_forecast(latitude : Float64, longitude : Float64) : Array(String)
    weather_client.get_forecast(latitude, longitude)
  end

  @[MCP::Prompt(
    name: "simple",
    description: "A simple prompt that can take optional context and topic ",
    context: {description => "Additional context to consider"},
    topic: {description => "Specific topic to focus on"}
  )]
  def simple_prompt(context : String?, topic : String?) : String
    String.build do |str|
      str << "Here is some relevant context: #{context}" if context
      str << "Please help with "
      str << (topic ? "the following topic: #{topic}" : "whatever questions I may have")
    end
  end

  @[MCP::Resource(name: "greeting", uri: "file:///greeting.txt", description: "Sample text resource", mime_type: "text/plain")]
  def read_text_resource(uri : String) : String
    raise "Invalid resource uri '#{uri}' or resource does not exist" unless uri == "file:///greeting.txt"
    "Hello! This is a sample text resource."
  end
end
```

`MCP::Transport` annotation supports 3 type of transports
* `stdio` : STDIO Transport
* `sse`: Server Sent Events 
* `streamable`: Streamable HTTP

#### Hard way
```crystal
require "mcp"

    server = MCP::Server::Server.new(
      MCP::Protocol::Implementation.new(name: "test server", version: "1.0"), 
      MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(
        MCP::Server::ServerCapabilities.new
        .with_tools
        .with_resources))
    )

    server.add_tool("test-tool", "Test Tool", MCP::Protocol::Tool::Input.new) { |_request|
      contents = [] of MCP::Protocol::ContentBlock
      contents << MCP::Protocol::TextContentBlock.new("Test result")
      MCP::Protocol::CallToolResult.new(contents)
    }

    transport = MCP::Server::StdioServerTransport(...)
    server.connect(transport)
```

### Creating a Client

```crystal
require "mcp"

  client = MCP::Client::Client.new(
    client_info: MCP::Protocol::Implementation.new("test client", "1.0"),
    client_options: MCP::Client::ClientOptions.new(
      capabilities: MCP::Protocol::ClientCapabilities.new))

    process = Process.new(
      "path-to-some-mcp-server .....",
      input: :pipe,
      output: :pipe
    )

    transport = MCP::Client::StdioClientTransport.new(
      input: process.input,
      output: process.output
    )

    # Connect to Server
    client.connect(transport)

    # List available resources
    resources = client.list_resources

    # Read a specific resource
    resource = MCP::Protocol::ReadResourceRequest.new(uri: "file:///example.txt")
    content = client.read_resource(resource)
```

Refer to [samples](samples) folder for samples

## Development

To run all tests:

```
crystal spec
```

## Contributing

1. Fork it (<https://github.com/spider-gazelle/mcp.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Ali Naqvi](https://github.com/naqvis) - creator and maintainer
