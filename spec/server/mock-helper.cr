# ameba:disable Lint/SpecFilename
# Mock SSE Connection
class MockConnection < MCP::SSE::Connection
  getter sent_messages = [] of Tuple(String?, String, String?, Int32?)
  getter? closed = false

  def initialize
    io = IO::Memory.new
    @closed_channel = Channel(Nil).new(1)
    @closed = false
    super(io)
  end

  def send(data : String, event : String? = nil, id : String? = nil, retry : Int32? = nil)
    @sent_messages << {event, data, id, retry}
  end

  def close
    @closed = true
    @closed_channel.send(nil) rescue nil
  end

  def closed?
    @closed
  end

  def simulate_disconnect
    close
  end
end

# Mock ServerSSESession
class MockSession < MCP::Server::ServerSSESession
  getter mock_connection : MockConnection
  getter? closed = false

  def initialize
    @mock_connection = MockConnection.new
    super(@mock_connection)
  end

  def send(event : String, data : String)
    @mock_connection.send(data, event: event)
  end

  def close
    @closed = true
    @mock_connection.close
  end

  def connection
    @mock_connection
  end
end

# Mock HTTP Context
def create_mock_context(body : String? = nil, content_type : String = "application/json")
  request = HTTP::Request.new(
    "POST",
    "/",
    body: body ? IO::Memory.new(body) : nil
  )
  request.headers["Content-Type"] = content_type if content_type

  response = HTTP::Server::Response.new(IO::Memory.new)
  HTTP::Server::Context.new(request, response)
end
