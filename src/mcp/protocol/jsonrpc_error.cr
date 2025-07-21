module MCP::Protocol
  class JSONRPCError < JSONRPCMessageWithId
    getter error : ErrorDetail

    def initialize(@id, @error)
      super(@id)
    end

    def self.with_auto_id(code : ErrorCode, message : String, data : Hash(String, JSON::Any)? = nil)
      id = REQUEST_MESSAGE_ID.increment_and_get
      new(id, code, message, data)
    end

    def self.new(id : RequestId?, code : ErrorCode, message : String, data : Hash(String, JSON::Any)? = nil)
      JSONRPCError.new(id, ErrorDetail.new(code, message, data))
    end

    def self.new(id : RequestId?, code : ErrorCode, message : String, **kw)
      data = kw.size > 0 ? JSON.parse(kw.to_json).as_h : nil
      new(id, code, message, data)
    end

    struct ErrorDetail
      include JSON::Serializable
      @[JSON::Field(converter: Enum::ValueConverter(MCP::Protocol::ErrorCode))]
      getter code : ErrorCode
      getter message : String
      getter data : Hash(String, JSON::Any)?

      def initialize(@code, @message, @data = nil)
      end
    end
  end
end
