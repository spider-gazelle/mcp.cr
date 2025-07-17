module MCP::Protocol
  struct Annotations
    include JSON::Serializable

    getter audience : Array(Role)?
    getter priority : Float64?
    @[JSON::Field(key: "lastModified")]
    getter last_modified : Time?

    def initialize(@audience = nil, @priority = nil, @last_modified = nil)
    end
  end

  struct Argument
    include JSON::Serializable

    getter name : String
    getter value : String

    def initialize(@name = "", @value = "")
    end
  end

  struct ToolAnnotations
    include JSON::Serializable

    getter title : String?
    @[JSON::Field(key: "readOnlyHint")]
    getter read_only_hint : Bool?
    @[JSON::Field(key: "destructiveHint")]
    getter destructive_hint : Bool?
    @[JSON::Field(key: "idempotentHint")]
    getter idempotent_hint : Bool?
    @[JSON::Field(key: "openWorldHint")]
    getter open_world_hint : Bool?

    def initialize(@title = nil, @read_only_hint = nil, @destructive_hint = nil,
                   @idempotent_hint = nil, @open_world_hint = nil)
    end
  end
end
