module MCP
  class StreamableRunner
    @@transports = {} of String => MCP::Server::StreamableHttpServerTransport
    @@mutex = Mutex.new
    getter server : MCP::Server::Server
    getter endpoint : String

    def initialize(@server, @endpoint = "/mcp")
      @endpoint = "/#{endpoint}" unless @endpoint.starts_with?("/")
    end

    def run(port = 8080)
      server = HTTP::Server.new do |context|
        handle_request(context)
      end

      puts "Streamable HTTP Server listening on http://localhost:#{port}#{endpoint}"
      server.listen(port)
    end

    private def handle_request(context : HTTP::Server::Context)
      path = context.request.path
      method = context.request.method

      case {method, path}
      when {"POST", endpoint}
        handle_post_rpc(context)
      when {"GET", endpoint}
        handle_sse_stream(context)
      when {"DELETE", endpoint}
        handle_delete_session(context)
      else
        context.response.status_code = HTTP::Status::NOT_FOUND.code
        context.response.puts "Not Found"
      end
    end

    private def handle_post_rpc(context)
      session_id = context.request.headers[MCP::Server::StreamableHttpServerTransport::MCP_SESSION_ID]?
      transport = if (sesid = session_id) && (existing_transport = @@mutex.synchronize { @@transports[sesid]? })
                    existing_transport
                  elsif session_id.nil?
                    MCP::Server::StreamableHttpServerTransport.new(true, true)
                  else
                    context.response.status_code = HTTP::Status::BAD_REQUEST.code
                    context.response.puts "Invalid request or session"
                    return
                  end

      transport.on_close {
        if sid = transport.session_id
          @@transports.delete(sid)
        end
      }

      server.connect(transport)
      transport.handle_post_request(context)
      if tsid = transport.session_id
        @@mutex.synchronize { @@transports[tsid] = transport }
      end
    end

    private def handle_sse_stream(context)
      session_id = context.request.headers[MCP::Server::StreamableHttpServerTransport::MCP_SESSION_ID]?
      transport = session_id ? @@mutex.synchronize { @@transports[session_id]? } : nil

      unless transport
        context.response.status_code = HTTP::Status::BAD_REQUEST.code
        context.response.puts "Invalid session"
        return
      end

      MCP::SSE.upgrade_response(context.response) do |conn|
        session = MCP::Server::ServerSSESession.new(conn)
        transport.handle_get_request(context, session)
      end
    end

    private def handle_delete_session(context)
      session_id = context.request.headers[MCP::Server::StreamableHttpServerTransport::MCP_SESSION_ID]?
      return unless session_id

      @@mutex.synchronize do
        if transport = @@transports.delete(session_id)
          transport.handle_delete_request(context)
        else
          context.response.status_code = HTTP::Status::NOT_FOUND.code
          context.response.puts "Session not found"
        end
      end
    end
  end
end
