require "../spec_helper"
require "./mock-helper"

describe MCP::Server::SseServerTransport do
  endpoint = "/sse_endpoint"

  describe "#start" do
    it "sends endpoint event on first start" do
      session = MockSession.new
      transport = MCP::Server::SseServerTransport.new(endpoint, session)
      transport.start

      session.connection.sent_messages.should contain(
        {"endpoint", "#{URI.encode_path(endpoint)}?sessionId=#{transport.session_id}", nil, nil}
      )
    end

    it "raises error when started twice" do
      session = MockSession.new
      transport = MCP::Server::SseServerTransport.new(endpoint, session)
      transport.start

      expect_raises(Exception, "SSEServerTransport already started!") do
        transport.start
      end
    end

    it "triggers on_close when connection closes" do
      session = MockSession.new
      transport = MCP::Server::SseServerTransport.new(endpoint, session)
      closed = false
      transport.on_close { closed = true }

      transport.start
      transport.close

      closed.should be_true
    end
  end

  describe "#handle_post_message" do
    it "rejects when transport not initialized" do
      session = MockSession.new
      transport = MCP::Server::SseServerTransport.new(endpoint, session)
      context = create_mock_context(MCP::Protocol::PingRequest.new.to_json)

      transport.handle_post_message(context)

      context.response.status_code.should eq(500)
    end

    it "rejects non-JSON content" do
      session = MockSession.new
      transport = MCP::Server::SseServerTransport.new(endpoint, session)
      transport.start
      context = create_mock_context("invalid", "text/plain")

      transport.handle_post_message(context)

      context.response.status_code.should eq(400)
    end

    it "processes valid JSON messages" do
      session = MockSession.new
      transport = MCP::Server::SseServerTransport.new(endpoint, session)
      transport.start
      message = MCP::Protocol::PingRequest.new
      context = create_mock_context(message.to_json)

      received = false
      transport.on_message { |_msg| received = true }

      transport.handle_post_message(context)

      context.response.status_code.should eq(202)
      received.should be_true
    end

    it "handles JSON parsing errors" do
      session = MockSession.new
      transport = MCP::Server::SseServerTransport.new(endpoint, session)
      transport.start
      context = create_mock_context("invalid json")
      error_triggered = false
      transport.on_error { error_triggered = true }

      transport.handle_post_message(context)

      context.response.status_code.should eq(400)
      error_triggered.should be_true
    end
  end

  describe "#send" do
    it "sends messages through session" do
      session = MockSession.new
      transport = MCP::Server::SseServerTransport.new(endpoint, session)
      transport.start
      message = MCP::Protocol::PingRequest.new

      transport.send(message)

      session.connection.sent_messages.should contain(
        {"message", message.to_json, nil, nil}
      )
    end

    it "raises when sending without connection" do
      session = MockSession.new
      transport = MCP::Server::SseServerTransport.new(endpoint, session)
      message = MCP::Protocol::PingRequest.new

      expect_raises(Exception, "Not connected") do
        transport.send(message)
      end
    end
  end

  describe "#close" do
    it "closes session and triggers on_close" do
      session = MockSession.new
      transport = MCP::Server::SseServerTransport.new(endpoint, session)
      transport.start
      closed = false
      transport.on_close { closed = true }

      transport.close

      session.closed?.should be_true
      closed.should be_true
    end
  end

  describe "integration" do
    it "maintains full message flow" do
      session = MockSession.new
      transport = MCP::Server::SseServerTransport.new(endpoint, session)

      transport.start
      session.connection.sent_messages.size.should eq(1)

      client_message = MCP::Protocol::PingRequest.new
      context = create_mock_context(client_message.to_json)

      received = false
      transport.on_message { |_msg| received = true }
      transport.handle_post_message(context)

      received.should be_true
      context.response.status_code.should eq(202)

      server_message = MCP::Protocol::PingRequest.new
      transport.send(server_message)

      session.connection.sent_messages.should contain(
        {"message", server_message.to_json, nil, nil}
      )

      transport.close
      session.closed?.should be_true
    end
  end
end
