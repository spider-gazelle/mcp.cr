module MCP
  class SseServerRunner
    @@sessions = {} of String => MCP::Server::Server
    @@mutex = Mutex.new

    getter server : MCP::Server::Server
    getter endpoint : String

    def initialize(@server, @endpoint = "/sse")
      @endpoint = "/#{endpoint}" unless @endpoint.starts_with?("/")
    end

    def run(port = 8080)
      server = HTTP::Server.new do |context|
        handle_request(context)
      end

      puts "SSE server listening on http://localhost:#{port}"
      puts "Use inspector to connect to the http://localhost:#{port}#{endpoint}"
      server.listen(port)
    end

    private def handle_request(context : HTTP::Server::Context)
      case {context.request.method, context.request.path}
      when {"GET", endpoint}
        handle_sse_connection(context)
      when {"POST", "/message"}
        handle_post_message(context)
      else
        context.response.status_code = HTTP::Status::NOT_FOUND.code
        context.response.puts "Not Found"
      end
    end

    private def handle_sse_connection(context : HTTP::Server::Context)
      MCP::SSE.upgrade_response(context.response) do |conn|
        session = MCP::Server::ServerSSESession.new(conn)
        transport = MCP::Server::SseServerTransport.new("/message", session)
        # Store session
        @@mutex.synchronize { @@sessions[transport.session_id] = server }

        puts "New connection: #{transport.session_id}"

        server.on_close do
          puts "Closing session: #{transport.session_id}"
          @@mutex.synchronize { @@sessions.delete(transport.session_id) }
        end

        server.connect(transport)
      end
    end

    private def handle_post_message(context : HTTP::Server::Context)
      session_id = context.request.query_params["sessionId"]?

      unless session_id
        context.response.status_code = HTTP::Status::BAD_REQUEST.code
        context.response.puts "Missing session ID"
        return
      end

      @@mutex.synchronize do
        if transport = @@sessions[session_id]?.try &.transport.as?(MCP::Server::SseServerTransport)
          # Delegate message handling to the transport
          transport.handle_post_message(context)
        else
          context.response.status_code = HTTP::Status::NOT_FOUND.code
          context.response.puts "Session not found"
        end
      end
    end
  end
end
