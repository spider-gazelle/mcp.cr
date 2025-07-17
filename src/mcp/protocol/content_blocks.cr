module MCP::Protocol
  abstract struct ContentBlock
    include JSON::Serializable

    use_json_discriminator "type", {"text": TextContentBlock, "image": ImageContentBlock, "audio": AudioContentBlock, "resource": EmbeddedResourceBlock,
                                    "resource_link": ResourceLinkBlock}
    property type : String
    getter annotations : Annotations?
    @[JSON::Field(key: "_meta")]
    getter meta : Hash(String, JSON::Any)?
  end

  struct TextContentBlock < ContentBlock
    getter text : String

    def initialize(@text, @meta = nil, @type = "text")
    end
  end

  struct ImageContentBlock < ContentBlock
    getter data : String
    @[JSON::Field(key: "mimeType")]
    getter mime_type : String

    def initialize(@data, @mime_type, @meta = nil, @type = "image")
    end
  end

  struct AudioContentBlock < ContentBlock
    getter data : String
    @[JSON::Field(key: "mimeType")]
    getter mime_type : String

    def initialize(@data, @mime_type, @meta = nil, @type = "audio")
    end
  end

  struct EmbeddedResourceBlock < ContentBlock
    getter resource : ResourceContents

    def initialize(@resource, @meta = nil, @type = "resource")
    end
  end

  struct ResourceLinkBlock < ContentBlock
    getter name : String
    getter uri : String
    getter description : String?
    getter title : String?
    @[JSON::Field(key: "mimeType")]
    getter mime_type : String?

    def initialize(@name, @uri, @description = nil, @title = nil, @mime_type = nil, @meta = nil, @type = "resource_link")
    end
  end
end
