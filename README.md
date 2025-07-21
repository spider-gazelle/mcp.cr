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
