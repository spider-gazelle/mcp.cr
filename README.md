# Crystal MCP: Unofficial Crystal Implementation of the Model Context Protocol

This is an unofficial Crystal language implementation of the [Model Context Protocol (MCP)](https://modelcontextprotocol.io), offering both client and server functionality to enable seamless integration with LLM interfaces across a variety of platforms.

## Overview

The Model Context Protocol (MCP) standardizes how applications provide contextual information to large language models (LLMs), decoupling context management from the LLM runtime itself.

This Crystal shard brings full MCP compatibility to your applications, allowing you to:

* Develop MCP clients that can connect to any MCP-compliant server
* Implement MCP servers that expose **resources**, **prompts**, and **tools**
* Use standard transports such as **STDIO**, **SSE**, **HTTP Streamable**
* Manage the full MCP message flow and lifecycle events effortlessly


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

#### Easy way (Annotate and enjoy)

```crystal
require "mcp"

@[MCP::MCPServer(name: "weather_service", version: "2.1.0", tools: false, prompts: false, resources: false)]
@[MCP::Transport(type: streamable, endpoint: "/mymcp")]
class WeatherMCPServer
  include MCP::Annotator

  getter(weather_client : WeatherApi) { WeatherApi.new }

  @[MCP::Tool(
    name: "weather_alerts",
    description: "Get weather alerts for a US state. Input is Two-letter US state code (e.g. CA, NY)"
  )]
  def get_alerts(@[MCP::Param(description: "Two-letter US state code (e.g. CA, NY)")] state : String,
                 @[MCP::Param(description: "size of result")] limit : Int32?) : Array(String)
    weather_client.get_alerts(state)
  end

  @[MCP::Tool(description: "Get weather forecast for a specific latitude/longitude")]
  def get_forecast(@[MCP::Param(description: "Latitude coordinate", minimum: -90, maximum: 90)] latitude : Float64,
                   @[MCP::Param(description: "Longitude coordinate", minimum: -180, maximum: 107)] longitude : Float64) : Array(String)
    weather_client.get_forecast(latitude, longitude)
  end

  @[MCP::Prompt(
    name: "simple",
    description: "A simple prompt that can take optional context and topic"
  )]
  def simple_prompt(@[MCP::Param(description: "Additional context to consider")] context : String?,
                    @[MCP::Param(description: "A Specific topic to focus on")] topic : String?) : String
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

WeatherMCPServer.run
```

#### Why the Unusual Name `MCP::MCPServer`?

The annotation is named `MCPServer` instead of the more intuitive `Server` to avoid a naming conflict with the existing `MCP::Server` module.

#### `MCP::MCPServer` Annotation

The `MCP::MCPServer` annotation is used to configure an MCP Server instance. Here's how its fields work:

* **`name` and `version`**: These populate the `serverInfo` field during the `initialize` lifecycle event.
* **`tools`, `prompts`, `resources`** *(optional)*: These flags indicate if your server supports updates or notifications for these elements.

If you set any of `tools`, `prompts`, or `resources` to `true`, you're responsible for notifying the MCP client when those lists change. For example:

If `resources: true` is set, and the resource list changes, you must call:

```crystal
server.send_resource_list_changed
```

This informs the client that the resource list has been updated.

#### `MCP::Transport` Annotation

This annotation defines the supported transport types for the MCP Server. It supports three modes:

* `stdio`: Standard input/output
* `sse`: Server-Sent Events
* `streamable`: Streamable HTTP


#### Hard way (Low-level API calls)
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
