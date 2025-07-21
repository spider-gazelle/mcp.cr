require "../spec_helper"

describe MCP::SSE::Connection do
  it "formats SSE messages correctly" do
    io = IO::Memory.new
    conn = MCP::SSE::Connection.new(io)

    conn.send("test data", event: "message", id: "123")
    io.to_s.should eq("id: 123\nevent: message\ndata: test data\n\n")
  end

  it "sends heartbeats" do
    io = IO::Memory.new
    conn = MCP::SSE::Connection.new(io)

    sleep 15.milliseconds
    conn.close

    io.to_s.should eq("")
  end

  it "detects client disconnects" do
    io = IO::Memory.new
    conn = MCP::SSE::Connection.new(io)
    closed = false
    conn.on_close = -> { closed = true }

    io.close
    sleep 1.milliseconds

    closed.should be_true
  end
end
