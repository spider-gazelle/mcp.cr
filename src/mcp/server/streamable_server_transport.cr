require "uri"
require "uuid"
require "http/server"

module MCP::Server
  class StreamableHttpServerTransport < Shared::AbstractTransport
    Log            = ::Log.for(self)
    STANDALONE     = "standalone"
    MCP_SESSION_ID = "Mcp-Session-Id"

    @stateful : Bool
    @enable_json_response : Bool
    @stream_mapping = {} of String => ServerSSESession
    @request_to_stream_mapping = {} of MCP::Protocol::RequestId => String
    @request_response_mapping = {} of MCP::Protocol::RequestId => MCP::Protocol::JSONRPCMessage
    @call_mapping = {} of String => HTTP::Server::Context
    @started : Atomic(Bool)
    @initialized : Atomic(Bool)
    property session_id : String? = nil

    def initialize(@stateful = false, @enable_json_response = false)
      super()
      @initialized = Atomic(Bool).new(false)
      @started = Atomic(Bool).new(false)
    end

    def start
      _, _ = @initialized.compare_and_set(false, true)
      # raise "StreamableHttpServerTransport already started! If using Server class, note that connect() calls start() automatically." unless success
    end

    # ameba:disable Metrics/CyclomaticComplexity
    def send(message : MCP::Protocol::JSONRPCMessage)
      request_id = case message
                   when MCP::Protocol::JSONRPCResponse then message.id
                   when MCP::Protocol::JSONRPCError    then message.id
                   else
                     nil
                   end

      if request_id.nil?
        # Send to standalone stream
        standalone_session = @stream_mapping[STANDALONE]?
        return unless standalone_session

        standalone_session.send(
          event: "message",
          data: message.to_json
        )
        return
      end

      stream_id = @request_to_stream_mapping[request_id]? || return
      # raise "No connection established for request id #{request_id}"

      call = @call_mapping[stream_id]? || return
      # raise "No connection established for request id #{request_id}"

      @request_response_mapping[request_id] = message

      unless @enable_json_response
        session = @stream_mapping[stream_id]? ||
                  raise "No connection established for request id #{request_id}"
        session.send(
          event: "message",
          data: message.to_json
        )
      end

      # Find all request IDs for this stream
      related_ids = [] of MCP::Protocol::RequestId
      @request_to_stream_mapping.each do |req_id, sid|
        related_ids << req_id if sid == stream_id
      end

      # Check if all responses are ready
      all_responses_ready = related_ids.all? { |id| @request_response_mapping.has_key?(id) }
      return unless all_responses_ready

      if @enable_json_response
        call.response.headers["Content-Type"] = "application/json"
        call.response.status_code = HTTP::Status::OK.code
        if session_id = @session_id
          call.response.headers[MCP_SESSION_ID] = session_id
        end

        responses = related_ids.map { |id| @request_response_mapping[id] }
        if responses.size == 1
          call.response.puts responses.first.to_json
        else
          call.response.puts responses.to_json
        end
        @call_mapping.delete(stream_id)
      else
        # session.close
        @stream_mapping.delete(stream_id)
      end

      related_ids.each do |id|
        @request_to_stream_mapping.delete(id)
        @request_response_mapping.delete(id)
      end
    end

    def close
      @stream_mapping.values.each(&.close)
      @stream_mapping.clear
      @request_to_stream_mapping.clear
      @request_response_mapping.clear
      _on_close.call
    end

    # ameba:disable Metrics/CyclomaticComplexity
    def handle_post_request(call : HTTP::Server::Context) # , session : ServerSSESession)
      Log.info { "Received POST request: #{call.request.path}" }
      return unless validate_headers(call)
      begin
        messages = parse_body(call)
        return if messages.empty?

        has_initialization_request = messages.any?(MCP::Protocol::InitializeRequest)

        if has_initialization_request
          if @initialized.get && @session_id
            respond_error(
              call,
              HTTP::Status::BAD_REQUEST,
              MCP::Protocol::ErrorCode::InvalidRequest,
              "Invalid Request: Server already initialized"
            )
            return
          end

          if messages.size > 1
            respond_error(
              call,
              HTTP::Status::BAD_REQUEST,
              MCP::Protocol::ErrorCode::InvalidRequest,
              "Invalid Request: Only one initialization request is allowed"
            )
            return
          end

          @session_id = UUID.random.to_s if @stateful
          @initialized.set(true)
        end

        return unless validate_session(call)

        has_requests = messages.any?(JSONRPCRequest)
        stream_id = UUID.random.to_s

        if !has_requests
          call.response.status_code = HTTP::Status::ACCEPTED.code
        else
          unless @enable_json_response
            call.response.headers["Content-Type"] = "text/event-stream"
            if session_id = @session_id
              call.response.headers[MCP_SESSION_ID] = session_id
            end
          end

          messages.each do |msg|
            if msg.is_a?(JSONRPCRequest)
              # @stream_mapping[stream_id] = session
              @call_mapping[stream_id] = call
              # ameba:disable Lint/NotNil
              @request_to_stream_mapping[msg.id.not_nil!] = stream_id
            end
          end
        end

        messages.each { |msg| _on_message.call(msg) }
      rescue e : Exception
        respond_error(
          call,
          HTTP::Status::BAD_REQUEST,
          MCP::Protocol::ErrorCode::ParseError,
          e.message || "Parse error"
        )
        _on_error.call(e)
      end
    end

    def handle_get_request(call : HTTP::Server::Context, session : ServerSSESession)
      Log.info { "Received GET (SSE) request: #{call.request.path}" }
      accept_header = call.request.headers["Accept"]?.try(&.split(',').map(&.strip)) || [] of String
      accepts_event_stream = accept_header.any? { |header| header == "text/event-stream" || header.starts_with?("text/event-stream;") }

      unless accepts_event_stream
        respond_error(
          call,
          HTTP::Status::NOT_ACCEPTABLE,
          MCP::Protocol::ErrorCode::InvalidRequest,
          "Not Acceptable: Client must accept text/event-stream"
        )
        return
      end

      return unless validate_session(call)

      if session_id = @session_id
        call.response.headers[MCP_SESSION_ID] = session_id
      end

      if @stream_mapping[STANDALONE]?
        respond_error(
          call,
          HTTP::Status::CONFLICT,
          MCP::Protocol::ErrorCode::InvalidRequest,
          "Conflict: Only one SSE stream is allowed per session"
        )
        session.close
        return
      end

      @stream_mapping[STANDALONE] = session
    end

    def handle_delete_request(call : HTTP::Server::Context)
      Log.info { "Received delete session request: #{call.request.path}" }
      return unless validate_session(call)

      close
      call.response.status_code = HTTP::Status::OK.code
    end

    private def validate_session(call : HTTP::Server::Context) : Bool
      return true unless @session_id

      unless @initialized.get
        respond_error(
          call,
          HTTP::Status::BAD_REQUEST,
          MCP::Protocol::ErrorCode::InvalidRequest,
          "Bad Request: Server not initialized"
        )
        return false
      end

      true
    end

    private def validate_headers(call : HTTP::Server::Context) : Bool
      accept_header = call.request.headers["Accept"]?.try(&.split(',').map(&.strip)) || [] of String
      accepts_event_stream = accept_header.any? { |header| header == "text/event-stream" || header.starts_with?("text/event-stream;") }
      accepts_json = accept_header.any? { |header| header == "application/json" || header.starts_with?("application/json;") }

      unless accepts_event_stream && accepts_json
        respond_error(
          call,
          HTTP::Status::NOT_ACCEPTABLE,
          MCP::Protocol::ErrorCode::InvalidRequest,
          "Not Acceptable: Client must accept both application/json and text/event-stream"
        )
        return false
      end

      content_type = call.request.headers["Content-Type"]?
      unless content_type == "application/json"
        respond_error(
          call,
          HTTP::Status::UNSUPPORTED_MEDIA_TYPE,
          MCP::Protocol::ErrorCode::InvalidRequest,
          "Unsupported Media Type: Content-Type must be application/json"
        )
        return false
      end

      true
    end

    private def parse_body(call : HTTP::Server::Context) : Array(MCP::Protocol::JSONRPCMessage)
      body = call.request.body
      return [] of MCP::Protocol::JSONRPCMessage unless body

      data = body.gets_to_end
      return [] of MCP::Protocol::JSONRPCMessage if data.empty?

      begin
        json = JSON.parse(data)
        case json
        when JSON::Any
          [MCP::Protocol::JSONRPCMessage.from_json(data)]
        when Array
          json_arr = json.as_a
          json_arr.map { |value| MCP::Protocol::JSONRPCMessage.from_json(value.to_json) }
        else
          respond_error(
            call,
            HTTP::Status::BAD_REQUEST,
            MCP::Protocol::ErrorCode::InvalidRequest,
            "Body must be a JSON object or array"
          )
          [] of MCP::Protocol::JSONRPCMessage
        end
      rescue e : JSON::ParseException
        respond_error(
          call,
          HTTP::Status::BAD_REQUEST,
          MCP::Protocol::ErrorCode::ParseError,
          "Invalid JSON format"
        )
        [] of MCP::Protocol::JSONRPCMessage
      end
    end

    private def respond_error(call : HTTP::Server::Context, status : HTTP::Status, code : MCP::Protocol::ErrorCode, message : String)
      call.response.status_code = status.code
      response = MCP::Protocol::JSONRPCError.new(id: nil, code: code, message: message)
      call.response.puts response.to_json
    end
  end
end
