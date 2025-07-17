require "../spec_helper"

describe MCP::Server::StdioServerTransport do
  it "should start then close cleanly" do
    input, _output_writer = IO.pipe
    output_buffer = MCP::Shared::ReadBuffer.new
    output = OutputCapture.new(output_buffer)

    server = MCP::Server::StdioServerTransport.new(input, output)
    server.on_error { |error| raise error }
    did_close = false
    server.on_close { did_close = true }

    server.start
    did_close.should be_false
    server.close
    did_close.should be_true
  end

  it "should not read until started" do
    input, output_writer = IO.pipe
    output_buffer = MCP::Shared::ReadBuffer.new
    output = OutputCapture.new(output_buffer)

    server = MCP::Server::StdioServerTransport.new(input, output)
    server.on_error { |error| raise error }

    did_read = false
    read_chan = Channel(MCP::Protocol::JSONRPCMessage).new

    server.on_message { |message|
      did_read = true
      read_chan.send(message)
    }

    message = MCP::Protocol::PingRequest.new
    output_writer.puts(message.to_json)

    did_read.should be_false

    server.start
    select
    when received = read_chan.receive
      message.to_json.should eq(received.to_json)
    when timeout 5.seconds
      fail "timeout after 5 seconds, expected object"
    end
  end

  it "should read multiple messages" do
    input, output_writer = IO.pipe
    output_buffer = MCP::Shared::ReadBuffer.new
    output = OutputCapture.new(output_buffer)

    server = MCP::Server::StdioServerTransport.new(input, output)
    server.on_error { |error| raise error }

    messages = [MCP::Protocol::PingRequest.new, MCP::Protocol::InitializedNotification.new] of MCP::Protocol::JSONRPCMessage
    read_messages = [] of MCP::Protocol::JSONRPCMessage
    finished = Channel(Nil).new

    server.on_message { |message|
      read_messages << message
      finished.send(nil) if message.to_json == messages.last.to_json
    }

    messages.each { |message| output_writer.puts(message.to_json) }

    server.start
    select
    when _received = finished.receive
      messages.size.should eq(read_messages.size)
      read_messages.first.is_a?(MCP::Protocol::PingRequest).should be_true
      read_messages.last.is_a?(MCP::Protocol::InitializedNotification).should be_true
    when timeout 5.seconds
      fail "timeout after 5 seconds, expected object"
    end
  end
end

class OutputCapture < IO
  def initialize(@buffer : MCP::Shared::ReadBuffer)
    @memory = IO::Memory.new
  end

  def write(slice : Bytes) : Nil
    @memory.write(slice)
    @buffer.append(slice)
  end

  def read(slice : Bytes) : Int32
    raise "Not implemented for reading"
  end

  def flush
    @memory.flush
  end

  def close
    @memory.close
  end

  def closed? : Bool
    @memory.closed?
  end
end
