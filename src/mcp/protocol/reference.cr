module MCP::Protocol
  abstract struct MCPReference
    include JSON::Serializable

    getter type : String = ""

    def initialize(@type)
    end

    use_json_discriminator "type", {"ref/prompt": PromptReference, "ref/resource": ResourceTemplateReference}
  end

  struct PromptReference < MCPReference
    include JSON::Serializable

    getter name : String
    getter title : String?

    def initialize(@name, @title = nil)
      super("ref/prompt")
    end

    def to_s : String
      "#{type}: #{name}"
    end
  end

  struct ResourceTemplateReference < MCPReference
    getter uri : String

    def initialize(@uri)
      super("ref/resource")
    end

    def to_s : String
      "#{type}: #{uri}"
    end
  end

  struct UknownReference < MCPReference
    def initialize(@type)
      super
    end
  end
end
