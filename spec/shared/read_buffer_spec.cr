require "../spec_helper"

describe MCP::Shared::ReadBuffer do
  it "should have no messages after initialization" do
    buffer = MCP::Shared::ReadBuffer.new
    buffer.read_message.should be_nil
  end

  it "should only yield a message after a newline" do
    buffer = MCP::Shared::ReadBuffer.new
    msg = MCP::Protocol::JSONRPCNotification.new("foobar")
    buffer.append(msg.to_json)
    buffer.read_message.should be_nil
    buffer.append("\n")
    result = buffer.read_message
    result.should_not be_nil
    result.to_json.should eq(msg.to_json)
    buffer.read_message.should be_nil
  end

  it "should skip empty lines" do
    buffer = MCP::Shared::ReadBuffer.new
    buffer.append("\n")
    buffer.read_message.should be_nil
  end

  it "should be reusable after clearning" do
    buffer = MCP::Shared::ReadBuffer.new
    msg = MCP::Protocol::JSONRPCNotification.new("foobar")
    buffer.append(msg.to_json)
    buffer.clear
    buffer.read_message.should be_nil
    buffer.append(msg.to_json)
    buffer.append("\n")
    result = buffer.read_message
    result.should_not be_nil
    result.to_json.should eq(msg.to_json)
    buffer.read_message.should be_nil
  end
end
