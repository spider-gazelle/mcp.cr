module MCP::Protocol
  abstract class JSONRPCMessage
    include JSON::Serializable

    getter jsonrpc : String = JSONRPC_VERSION

    def initialize(@jsonrpc = JSONRPC_VERSION)
    end

    # ameba:disable Metrics/CyclomaticComplexity
    def self.from_json(json : String) : JSONRPCMessage
      has_id = false
      has_method = false
      has_error = false
      has_result = false

      parser = JSON::PullParser.new(json)
      parser.read_object do |key|
        case key
        when "jsonrpc"
          version = parser.read_string
          raise "Invalid or missing jsonrpc version" unless version == JSONRPC_VERSION
        when "id"
          has_id = true
          parser.skip
        when "method"
          has_method = true
          parser.skip
        when "error"
          has_error = true
          parser.skip
        when "result"
          has_result = true
          parser.skip
        else
          parser.skip
        end
      end

      case
      when has_id && !has_method
        if has_error
          JSONRPCError.new(pull: JSON::PullParser.new(json))
        elsif has_result
          JSONRPCResponse.new(pull: JSON::PullParser.new(json))
        else
          raise "Response must have either result or error"
        end
      when has_method && !has_id
        JSONRPCNotification.new(pull: JSON::PullParser.new(json))
      when has_method && has_id
        JSONRPCRequest.new(pull: JSON::PullParser.new(json))
      else
        raise "Invalid JSON-RPC message format"
      end
    end
  end

  abstract class JSONRPCMessageWithId < JSONRPCMessage
    protected def initialize(@id)
      super()
    end

    getter id : RequestId
  end
end

require "./jsonrpc_request"
require "./jsonrpc_notification"
require "./jsonrpc_response"
require "./jsonrpc_error"
