require "./sse_server_session"

module MCP::Server
  class SseServerTransport < Shared::AbstractTransport
    SESSION_ID_PARAM = "sessionId"

    @endpoint : String
    @session : ServerSSESession
    @initialized : Atomic(Bool)
    getter session_id : String

    def initialize(@endpoint : String, @session : ServerSSESession)
      super()
      @session_id = UUID.random.to_s
      @initialized = Atomic.new(false)
    end

    def start
      _, success = @initialized.compare_and_set(false, true)
      raise "SSEServerTransport already started!" unless success

      @session.start
      # Send endpoint event
      @session.send(
        "endpoint",
        "#{URI.encode_path(@endpoint)}?#{SESSION_ID_PARAM}=#{@session_id}"
      )

      spawn do
        begin
          @session.done.receive?
        ensure
          _on_close.call
        end
      end
    end

    def handle_post_message(context : HTTP::Server::Context)
      unless @initialized.get
        message = "SSE connection not established"
        context.response.status_code = HTTP::Status::INTERNAL_SERVER_ERROR.code
        context.response.puts message
        _on_error.call(Exception.new(message))
        return
      end

      body = begin
        content_type = context.request.headers["Content-Type"]?
        if content_type.nil? || !content_type.starts_with?("application/json")
          raise "Unsupported content-type: #{content_type}"
        end
        context.request.body.try &.gets_to_end
      rescue e
        context.response.status_code = HTTP::Status::BAD_REQUEST.code
        context.response.puts "Invalid message: #{e.message}"
        _on_error.call(e)
        return
      end

      begin
        raise "No body received" unless body
        handle_message(body)
      rescue e
        context.response.status_code = HTTP::Status::BAD_REQUEST.code
        context.response.puts "Error handling message: #{e.message}"
        return
      end

      context.response.status_code = HTTP::Status::ACCEPTED.code
      context.response.puts "Accepted"
    end

    def handle_message(message : String)
      parsed_message = MCP::Protocol::JSONRPCMessage.from_json(message)
      _on_message.call(parsed_message)
    rescue e
      _on_error.call(e)
      raise e
    end

    def close
      _, success = @initialized.compare_and_set(true, false)
      return unless success

      @session.close
      _on_close.call
    end

    def send(message : MCP::Protocol::JSONRPCMessage)
      raise "Not connected" unless @initialized.get
      @session.send("message", message.to_json)
    end
  end
end
