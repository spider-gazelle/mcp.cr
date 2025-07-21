require "./sse"

module MCP::Server
  class ServerSSESession
    SESSION_ID_PARAM = "sessionId"

    @connection : SSE::Connection
    getter done : Channel(Bool)

    def initialize(@connection : SSE::Connection)
      @done = Channel(Bool).new(1)
    end

    def start
      spawn do
        @connection.wait
        done.send(true)
      end
    end

    def send(event : String, data : String)
      @connection.send(data, event: event)
    end

    def close
      @connection.close
    end
  end
end
