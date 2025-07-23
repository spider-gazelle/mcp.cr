require "../spec_helper"

describe MCP::Server::StreamableHttpServerTransport do
  it "should start and close cleanly" do
    transport = MCP::Server::StreamableHttpServerTransport.new(stateful: false)

    did_close = false

    transport.on_close { did_close = true }

    transport.start
    did_close.should be_false
    transport.close
    did_close.should be_true
  end

  it "should initialize with stateful mode" do
    transport = MCP::Server::StreamableHttpServerTransport.new(stateful: true)
    transport.start

    transport.session_id.should be_nil
    transport.close
  end

  it "should initialize with stateless mode" do
    transport = MCP::Server::StreamableHttpServerTransport.new(stateful: false)
    transport.start

    transport.session_id.should be_nil
    transport.close
  end

  it "should handle message callbacks" do
    transport = MCP::Server::StreamableHttpServerTransport.new
    received_msg = nil

    transport.on_message { |msg| received_msg = msg }

    transport.start

    # Test that message handler can be called
    received_msg.should be_nil
    transport.close
  end
end
