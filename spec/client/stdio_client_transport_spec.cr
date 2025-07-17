require "../spec_helper"

describe MCP::Client::StdioClientTransport do
  it "should start and close cleanly" do
    process = Process.new(
      "/usr/bin/tee",
      input: :pipe,
      output: :pipe
    )

    input = process.output
    output = process.input

    client = MCP::Client::StdioClientTransport.new(
      input: input,
      output: output
    )

    client.on_error do |error|
      fail("Unexpected error: #{error}")
    end

    did_close = false
    client.on_close { did_close = true }

    client.start
    did_close.should be_false
    client.close
    did_close.should be_true
    process.close
  end

  it "should read messages" do
    process = Process.new(
      "/usr/bin/tee",
      input: :pipe,
      output: :pipe
    )

    input = process.output
    output = process.input

    client = MCP::Client::StdioClientTransport.new(
      input: input,
      output: output
    )

    messages = [MCP::Protocol::PingRequest.new, MCP::Protocol::InitializedNotification.new] of MCP::Protocol::JSONRPCMessage

    read_messages = [] of MCP::Protocol::JSONRPCMessage
    finished = Channel(Nil).new(1)

    client.on_message do |message|
      read_messages << message
      finished.send(nil) if message.is_a?(MCP::Protocol::JSONRPCNotification)
    end

    client.start

    messages.each { |message| client.send(message) }

    finished.receive?

    read_messages.size.should eq(messages.size)
    read_messages.first.to_json.should eq(messages.first.to_json)
    read_messages.last.to_json.should eq(messages.last.to_json)
    client.close
    process.wait
  end
end
