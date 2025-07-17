require "../spec_helper"

describe MCP::Server::Server do
  it "remove_tool should remove a tool" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools.tools))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    server.add_tool("test-tool", "Test Tool", MCP::Protocol::Tool::Input.new) { |_request|
      contents = [] of MCP::Protocol::ContentBlock
      contents << MCP::Protocol::TextContentBlock.new("Test result")
      MCP::Protocol::CallToolResult.new(contents)
    }

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    client = MCP::Client::Client.new(client_info: MCP::Protocol::Implementation.new("test-client", "1.0"))

    spawn { client.connect(client_transport) }
    spawn { server.connect(server_transport) }

    result = server.remove_tool("test-tool")
    result.should be_true
  end

  it "remove_tool should return false when tool does not exists" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools.tools))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    client = MCP::Client::Client.new(client_info: MCP::Protocol::Implementation.new("test-client", "1.0"))

    list_changed_notification = false

    client.notification_handler(MCP::Protocol::NotificationsToolsListChanged) {
      list_changed_notification = true
      nil
    }

    spawn { client.connect(client_transport) }
    spawn { server.connect(server_transport) }

    result = server.remove_tool("non-existent-tool")
    result.should be_false
    list_changed_notification.should be_false
  end

  it "remove_tool should raise when tools capabaility is not supported" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new)
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    expect_raises(Exception, "Server does not support tools capability") do
      server.remove_tool("non-existent-tool")
    end
  end

  it "remove_prompt should remove a prompt" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(prompts: MCP::Server::ServerCapabilities.new.with_prompts.prompts))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    prompt = MCP::Protocol::Prompt.new("test-prompt", " Test Prompt")
    server.add_prompt(prompt) { |_request|
      MCP::Protocol::GetPromptResult.new(description: "Test Prompt description", messages: [] of MCP::Protocol::PromptMessage)
    }

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    client = MCP::Client::Client.new(client_info: MCP::Protocol::Implementation.new("test-client", "1.0"))

    spawn { client.connect(client_transport) }
    spawn { server.connect(server_transport) }

    result = server.remove_prompt(prompt.name)
    result.should be_true
  end

  it "remove_prompt should remove multiple prompts and send notification" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(prompts: MCP::Server::ServerCapabilities.new.with_prompts.prompts))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    prompt1 = MCP::Protocol::Prompt.new("test-prompt-1", " Test Prompt 1")
    prompt2 = MCP::Protocol::Prompt.new("test-prompt-2", " Test Prompt 2")

    server.add_prompt(prompt1) { |_request|
      MCP::Protocol::GetPromptResult.new(description: "Test Prompt description 1", messages: [] of MCP::Protocol::PromptMessage)
    }

    server.add_prompt(prompt2) { |_request|
      MCP::Protocol::GetPromptResult.new(description: "Test Prompt description 2", messages: [] of MCP::Protocol::PromptMessage)
    }

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    client = MCP::Client::Client.new(client_info: MCP::Protocol::Implementation.new("test-client", "1.0"))

    spawn { client.connect(client_transport) }
    spawn { server.connect(server_transport) }

    result = server.remove_prompts([prompt1.name, prompt2.name])
    result.should eq(2)
  end

  it "remove_resource should remove a resource and send notification" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(resources: MCP::Server::ServerCapabilities.new.with_resources.resources))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    test_resource_uri = "test://resource"
    server.add_resource(uri: test_resource_uri, name: "Test Resource", description: "A test resource", mime_type: "text/plain") { |_request|
      MCP::Protocol::ReadResourceResult.new(contents: [MCP::Protocol::TextResourceContents.new(text: "Test resource content", uri: test_resource_uri, mime_type: "text/plain")] of MCP::Protocol::ResourceContents)
    }

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    client = MCP::Client::Client.new(client_info: MCP::Protocol::Implementation.new("test-client", "1.0"))

    spawn { client.connect(client_transport) }
    spawn { server.connect(server_transport) }

    result = server.remove_resource(test_resource_uri)
    result.should be_true
  end

  it "remove_resource should remove multiple resources and send notification" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(resources: MCP::Server::ServerCapabilities.new.with_resources.resources))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    test_resource_uri1 = "test://resource1"
    test_resource_uri2 = "test://resource2"

    server.add_resource(uri: test_resource_uri1, name: "Test Resource 1", description: "A test resource 1", mime_type: "text/plain") { |_request|
      MCP::Protocol::ReadResourceResult.new(contents: [MCP::Protocol::TextResourceContents.new(text: "Test resource content 1", uri: test_resource_uri1, mime_type: "text/plain")] of MCP::Protocol::ResourceContents)
    }

    server.add_resource(uri: test_resource_uri2, name: "Test Resource 2", description: "A test resource 2", mime_type: "text/plain") { |_request|
      MCP::Protocol::ReadResourceResult.new(contents: [MCP::Protocol::TextResourceContents.new(text: "Test resource content 2", uri: test_resource_uri2, mime_type: "text/plain")] of MCP::Protocol::ResourceContents)
    }

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    client = MCP::Client::Client.new(client_info: MCP::Protocol::Implementation.new("test-client", "1.0"))

    spawn { client.connect(client_transport) }
    spawn { server.connect(server_transport) }

    result = server.remove_resources([test_resource_uri1, test_resource_uri2])
    result.should eq(2)
  end

  it "remove_prompt should raise when prompts capability is not supported" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new)
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    expect_raises(Exception, "Server does not support prompts capability") do
      server.remove_prompt("test-prompt")
    end
  end
end
