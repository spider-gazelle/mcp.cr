require "../spec_helper"

describe MCP::Shared::InMemoryTransport do
  client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair

  it "should create a linked pair" do
    client_transport.should_not be_nil
    server_transport.should_not be_nil
  end

  it "should start without error" do
    client_transport.start
    client_transport.start
  end

  it "should send message from client to server" do
    message = MCP::Protocol::InitializedNotification.new
    received = nil
    server_transport.on_message { |msg| received = msg }

    client_transport.send(message)
    message.to_json.should eq(received.to_json)
  end

  it "should send message from server to client" do
    message = MCP::Protocol::InitializedNotification.new
    received = nil
    client_transport.on_message { |msg| received = msg }

    server_transport.send(message)
    message.to_json.should eq(received.to_json)
  end

  it "should handle close" do
    client_closed = false
    server_closed = false

    client_transport.on_close {
      client_closed = true
    }

    server_transport.on_close {
      server_closed = true
    }

    client_transport.close

    client_closed.should be_true
    server_closed.should be_true
  end

  it "should raise error when sending after close" do
    client_transport.close

    expect_raises(Exception, "Not connected") do
      client_transport.send(MCP::Protocol::InitializedNotification.new)
    end
  end
end
