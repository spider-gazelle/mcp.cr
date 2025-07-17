require "wait_group"
require "../spec_helper"

describe MCP::Client::Client do
  it "should initialize with matching protocol version" do
    client_transport = ClientTransport.new

    client = MCP::Client::Client.new(
      client_info: MCP::Protocol::Implementation.new("test client", "1.0"),
      client_options: MCP::Client::ClientOptions.new(
        capabilities: MCP::Protocol::ClientCapabilities.new(sampling: Hash(String, JSON::Any).new)
      )
    )

    client.connect(client_transport)

    client_transport.initialized?.should be_true
  end

  it "should initialize with supported older protocol version" do
    client_transport = ClientTransport.new(MCP::Protocol::SUPPORTED_PROTOCOL_VERSIONS[1])

    client = MCP::Client::Client.new(
      client_info: MCP::Protocol::Implementation.new("test client", "1.0"),
      client_options: MCP::Client::ClientOptions.new(
        capabilities: MCP::Protocol::ClientCapabilities.new(sampling: Hash(String, JSON::Any).new)
      )
    )

    client.connect(client_transport)

    client.server_version.to_json.should eq(MCP::Protocol::Implementation.new("test", "1.0").to_json)
  end

  it "should reject unsupported protocol version" do
    client_transport = ClientTransport.new("invalid-version")

    client = MCP::Client::Client.new(
      client_info: MCP::Protocol::Implementation.new("test client", "1.0"),
      client_options: MCP::Client::ClientOptions.new(
        capabilities: MCP::Protocol::ClientCapabilities.new(sampling: Hash(String, JSON::Any).new)
      )
    )

    expect_raises(Exception, "Server's protocol version is not supported: invalid-version") do
      client.connect(client_transport)
    end

    client_transport.closed?.should be_true
  end

  it "should respect server notification capabilities" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(logging: Hash(String, JSON::Any).new,
      resources: MCP::Protocol::ServerCapabilities::ResourcesCapability.new(list_changed: true, subscribe: nil)))

    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    client = MCP::Client::Client.new(
      client_info: MCP::Protocol::Implementation.new("test client", "1.0"),
      client_options: MCP::Client::ClientOptions.new(
        capabilities: MCP::Protocol::ClientCapabilities.new))

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair

    wg = WaitGroup.new

    wg.spawn {
      client.connect(client_transport)
      puts "\nClient connected"
    }

    wg.spawn {
      server.connect(server_transport)
      puts "\nServer connected"
    }

    wg.wait

    obj = JSON.parse({"name": "John", "age": 30, "isStudent": false}.to_json)

    server.send_logging_message(MCP::Protocol::LoggingMessageNotificationParams.new(level: MCP::Protocol::LoggingLevel::Info, data: obj))
    server.send_resource_list_changed

    expect_raises(Exception, "Server does not support notifying of tool list changes") do
      server.send_tool_list_changed
    end
  end

  it "JSONRPCRequest with ToolsList method and default params returns list of tools" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new.with_tools)

    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    server.request_handler(MCP::Protocol::Initialize) do |_request, _|
      MCP::Protocol::InitializeResult.new(
        protocol_version: MCP::Protocol::LATEST_PROTOCOL_VERSION,
        capabilities: MCP::Protocol::ServerCapabilities.new.with_tools.with_resources,
        server_info: MCP::Protocol::Implementation.new("test", "1.0")
      )
    end

    server.request_handler(MCP::Protocol::ToolsList) do |_request, _|
      MCP::Protocol::ListToolsResult.new(
        tools: [MCP::Protocol::Tool.new(name: "testTool", description: "testTool description", input_schema: MCP::Protocol::Tool::Input.new)],
        next_cursor: nil
      )
    end

    client = MCP::Client::Client.new(
      client_info: MCP::Protocol::Implementation.new("test client", "1.0"),
      client_options: MCP::Client::ClientOptions.new(
        capabilities: MCP::Protocol::ClientCapabilities.new(sampling: Hash(String, JSON::Any).new)))

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair

    received_message = nil
    client_transport.on_message { |msg| received_message = msg }

    wg = WaitGroup.new

    wg.spawn {
      client.connect(client_transport)
    }

    wg.spawn {
      server.connect(server_transport)
    }

    wg.wait

    server_capabilities = client.server_capabilities?
    server_capabilities.try &.tools.try &.list_changed.should be_nil

    request = MCP::Protocol::ListToolsRequest.new

    client_transport.send(request)

    received_message.is_a?(MCP::Protocol::JSONRPCResponse).should be_true
    resp = received_message.as(MCP::Protocol::JSONRPCResponse)
    request.id.should eq(resp.id)
    request.jsonrpc.should eq(resp.jsonrpc)
    resp.result.is_a?(MCP::Protocol::ListToolsResult)
  end

  it "list_roots should return a list of roots" do
    client = MCP::Client::Client.new(
      client_info: MCP::Protocol::Implementation.new("test client", "1.0"),
      client_options: MCP::Client::ClientOptions.new(
        capabilities: MCP::Protocol::ClientCapabilities.with_roots))

    client_roots = [MCP::Protocol::Root.new(uri: "file:///test-root", name: "testRoot")]

    client.add_roots(client_roots)
    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair

    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new)

    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    wg = WaitGroup.new

    wg.spawn {
      client.connect(client_transport)
    }

    wg.spawn {
      server.connect(server_transport)
    }

    wg.wait

    client_capabilities = server.client_capabilities
    client_capabilities.try &.roots.try &.list_changed.should be_nil

    list_roots_result = server.list_roots

    list_roots_result.roots.size.should eq(client_roots.size)
    list_roots_result.roots.first.to_json.should eq(client_roots.first.to_json)
  end

  it "remove_root should raise when roots capability is not supported" do
    client = MCP::Client::Client.new(
      client_info: MCP::Protocol::Implementation.new("test client", "1.0"),
      client_options: MCP::Client::ClientOptions.new(
        capabilities: MCP::Protocol::ClientCapabilities.new))

    expect_raises(Exception, "Client does not support roots capability") do
      client.remove_root("file:///test-uri")
    end
  end

  it "remove_root should remove a root" do
    client = MCP::Client::Client.new(
      client_info: MCP::Protocol::Implementation.new("test client", "1.0"),
      client_options: MCP::Client::ClientOptions.new(
        capabilities: MCP::Protocol::ClientCapabilities.with_roots))

    client_roots = [MCP::Protocol::Root.new(uri: "file:///test-root", name: "testRoot"), MCP::Protocol::Root.new(uri: "file:///test-root2", name: "testRoot2")]

    client.add_roots(client_roots)

    result = client.remove_root("file:///test-root2")
    result.should be_true
  end

  it "remote_roots should remove multiple roots" do
    client = MCP::Client::Client.new(
      client_info: MCP::Protocol::Implementation.new("test client", "1.0"),
      client_options: MCP::Client::ClientOptions.new(
        capabilities: MCP::Protocol::ClientCapabilities.with_roots))

    client_roots = [MCP::Protocol::Root.new(uri: "file:///test-root", name: "testRoot"), MCP::Protocol::Root.new(uri: "file:///test-root2", name: "testRoot2")]

    client.add_roots(client_roots)

    result = client.remove_roots(["file:///test-root2", "file:///test-root"])
    result.should eq(2)
  end

  it "send_roots_list_changed should notify server" do
    client = MCP::Client::Client.new(
      client_info: MCP::Protocol::Implementation.new("test client", "1.0"),
      client_options: MCP::Client::ClientOptions.new(
        capabilities: MCP::Protocol::ClientCapabilities.with_roots(true)))

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair

    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new)
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    root_list_changed_notification_received = false

    server.notification_handler(MCP::Protocol::NotificationsRootsListChanged) {
      root_list_changed_notification_received = true
      nil
    }

    wg = WaitGroup.new

    wg.spawn {
      client.connect(client_transport)
    }

    wg.spawn {
      server.connect(server_transport)
    }

    wg.wait

    client.send_root_list_changed

    root_list_changed_notification_received.should be_true
  end
end

class ClientTransport < MCP::Shared::AbstractTransport
  getter? initialized : Bool = false
  getter? closed : Bool = false

  def initialize(@version : String = MCP::Protocol::LATEST_PROTOCOL_VERSION)
    super()
  end

  def start
  end

  def send(message : MCP::Protocol::JSONRPCMessage)
    return unless message.is_a?(MCP::Protocol::JSONRPCRequest)
    @initialized = true

    result = MCP::Protocol::InitializeResult.new(
      protocol_version: @version,
      capabilities: MCP::Protocol::ServerCapabilities.new,
      server_info: MCP::Protocol::Implementation.new("test", "1.0")
    )

    resp = MCP::Protocol::JSONRPCResponse.new(message.id, result)
    _on_message.call(resp)
  end

  def close
    @closed = true
  end
end
