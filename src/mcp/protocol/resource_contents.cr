require "json"

module MCP::Protocol
  abstract struct ResourceContents
    include JSON::Serializable
    include JSON::Serializable::Unmapped

    getter uri : String
    @[JSON::Field(key: "mimeType")]
    getter mime_type : String?
    @[JSON::Field(key: "_meta")]
    getter meta : Hash(String, JSON::Any)?

    def initialize(@uri, @mime_type = nil, @meta = nil)
    end

    def self.new(pull : ::JSON::PullParser)
      uri = ""
      mime_type = nil
      blob = nil
      text = nil
      meta = nil

      pull.read_object do |key|
        case key
        when "uri"
          uri = pull.read_string
        when "mimeType"
          mime_type = pull.read_string
        when "blob"
          blob = pull.read_string
        when "text"
          text = pull.read_string
        when "_meta"
          meta = JSON::Any.new(pull.read_raw).as_h?
        else
          pull.skip
        end
      end
      if blob
        BlobResourceContents.new(uri, blob, mime_type, meta)
      else
        if value = text
          TextResourceContents.new(uri, value, mime_type, meta)
        else
          raise "Invalid Text value. Expected text but got nil"
        end
      end
    end
  end

  struct TextResourceContents < ResourceContents
    getter text : String

    def initialize(@uri, @text, @mime_type = nil, @meta = nil)
      super(@uri, @mime_type, @meta)
    end
  end

  struct BlobResourceContents < ResourceContents
    getter blob : String

    def initialize(@uri, @blob, @mime_type = nil, @meta = nil)
      super(@uri, @mime_type, @meta)
    end
  end
end
