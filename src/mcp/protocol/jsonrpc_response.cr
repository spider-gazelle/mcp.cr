require "./annotations"
require "./content_blocks"
require "./resource_contents"

module MCP::Protocol
  class JSONRPCResponse < JSONRPCMessageWithId
    getter result : Result

    Protocol.use_key_discriminator "result", {"model": CreateMessageResult, "roots": ListRootsResult, "tools": ListToolsResult, "resources": ListResourcesResult, "resourceTemplates": ListResourceTemplatesResult, "prompts": ListPromptsResult, "capabilities": InitializeResult,
                                              "description": GetPromptResult, "completion": CompleteResult, "toolResult": CompatibilityCallToolResult, "contents": ReadResourceResult, "content": CallToolResult}, else: EmptyResult

    def initialize(@id, @result)
      super(@id)
    end
  end

  abstract class Result
    include JSON::Serializable

    @[JSON::Field(key: "_meta")]
    getter meta : Hash(String, JSON::Any)?

    def initialize(@meta = nil)
    end
  end

  abstract class PaginatedResult < Result
    @[JSON::Field(key: "NextCursor")]
    property next_cursor : String?

    def initialize(@next_cursor = nil, @meta = nil)
      super(@meta)
    end
  end

  class EmptyResult < Result
    def initialize
      super(nil)
    end
  end

  class CallToolResult < Result
    getter content : Array(ContentBlock)
    @[JSON::Field(key: "structuredContent")]
    getter structured_content : Hash(String, JSON::Any)?
    @[JSON::Field(key: "isError")]
    getter is_error : Bool?

    def initialize(@content = [] of ContentBlock, @structured_content = nil,
                   @is_error = false, @meta = nil)
    end
  end

  class CompatibilityCallToolResult < Result
    getter content : Array(ContentBlock)
    @[JSON::Field(key: "toolResult")]
    getter tool_result : Hash(String, JSON::Any)
    @[JSON::Field(key: "isError")]
    getter is_error : Bool?

    def initialize(@content = [] of ContentBlock, @tool_result = Hash(String, JSON::Any).new,
                   @is_error = false, @meta = nil)
    end
  end

  class CompleteResult < Result
    getter completion : Completion

    def initialize(@completion, @meta = nil)
      super(@meta)
    end

    struct Completion
      include JSON::Serializable

      getter values : Array(String)
      getter total : Int64?
      @[JSON::Field(key: "hasMore")]
      getter has_more : Bool?

      def initialize(@values = [] of String, @total = nil, @has_more = nil)
      end
    end
  end

  class CreateMessageResult < Result
    getter content : ContentBlock
    getter model : String
    @[JSON::Field(key: "stopReason")]
    getter stop_reason : String?
    getter role : Role

    def initialize(@content, @model, @role, @stop_reason = nil, @meta = nil)
      super(@meta)
    end
  end

  class ElicitResult < Result
    getter action : ActionType
    getter content : Hash(String, JSON::Any)?

    def initialize(@action = ActionType::Cancel, @content = nil, @meta = nil)
      super(@meta)
    end
  end

  struct PromptMessage
    include JSON::Serializable
    include JSON::Serializable::Unmapped
    getter role : Role
    getter content : ContentBlock

    def initialize(@role = Role::User, @content = TextContentBlock.new(""))
    end
  end

  class GetPromptResult < Result
    getter description : String?
    getter messages : Array(PromptMessage)

    def initialize(@messages, @description = nil, @meta = nil)
      super(@meta)
    end
  end

  class ServerCapabilities
    include JSON::Serializable
    include JSON::Serializable::Unmapped
    getter experimental : Hash(String, JSON::Any)?
    getter sampling : Hash(String, JSON::Any)?
    getter logging : Hash(String, JSON::Any)?
    getter completions : Hash(String, JSON::Any)?
    getter prompts : PromptsCapability?
    getter resources : ResourcesCapability?
    getter tools : ToolsCapability?

    def initialize(@experimental = nil, @sampling = nil, @logging = nil, @completions = nil,
                   @prompts = nil, @resources = nil, @tools = nil)
    end

    def with_experimental(**kw)
      return self if kw.empty?
      @experimental = JSON.parse(kw.to_json).as_h
      self
    end

    def with_logging(**kw)
      return self if kw.empty?
      @logging = JSON.parse(kw.to_json).as_h
      self
    end

    def with_completions(**kw)
      return self if kw.empty?
      @completions = JSON.parse(kw.to_json).as_h
      self
    end

    def with_resources(list_changed : Bool? = nil, subscribe : Bool? = nil)
      @resources = ResourcesCapability.new(list_changed, subscribe)
      self
    end

    def with_prompts(list_changed : Bool = false)
      @prompts = PromptsCapability.new(list_changed)
      self
    end

    def with_tools(list_changed : Bool? = nil)
      @tools = ToolsCapability.new(list_changed)
      self
    end

    struct PromptsCapability
      include JSON::Serializable

      @[JSON::Field(key: "listChanged")]
      getter list_changed : Bool?

      def initialize(@list_changed = nil)
      end
    end

    struct ToolsCapability
      include JSON::Serializable

      @[JSON::Field(key: "listChanged")]
      getter list_changed : Bool?

      def initialize(@list_changed = nil)
      end
    end

    struct ResourcesCapability
      include JSON::Serializable

      getter subscribe : Bool?
      @[JSON::Field(key: "listChanged")]
      getter list_changed : Bool?

      def initialize(@list_changed = nil, @subscribe = nil)
      end
    end
  end

  class InitializeResult < Result
    @[JSON::Field(key: "protocolVersion")]
    getter protocol_version : String
    getter capabilities : ServerCapabilities
    @[JSON::Field(key: "serverInfo")]
    getter server_info : Implementation
    getter instructions : String?

    def initialize(@protocol_version, @capabilities, @server_info, @instructions = nil, @meta = nil)
      super(@meta)
    end
  end

  struct PromptArgument
    include JSON::Serializable

    getter name : String
    getter title : String?

    getter description : String?
    getter required : Bool?

    def initialize(@name, @description = "", @title = nil, @required = nil)
    end
  end

  struct Prompt
    include JSON::Serializable

    getter name : String
    getter title : String?

    getter description : String?
    getter arguments : Array(PromptArgument)?
    @[JSON::Field(key: "_meta")]
    getter meta : Hash(String, JSON::Any)?

    def initialize(@name, @description = nil, @arguments = nil, @title = nil, @meta = nil)
    end
  end

  class ListPromptsResult < PaginatedResult
    getter prompts : Array(Prompt)

    def initialize(@prompts = [] of Prompt, @next_cursor = nil, @meta = nil)
      super(@next_cursor, @meta)
    end
  end

  struct Resource
    include JSON::Serializable

    getter name : String
    getter title : String?

    getter uri : String
    getter description : String?
    @[JSON::Field(key: "mimeType")]
    getter mime_type : String?
    getter annotations : Annotations?
    getter size : Int64?
    @[JSON::Field(key: "_meta")]
    getter meta : Hash(String, JSON::Any)?

    def initialize(@name, @uri, @description = nil, @mime_type = nil, @title = nil, @annotations = nil, @size = nil, @meta = nil)
    end
  end

  class ListResourcesResult < PaginatedResult
    getter resources : Array(Resource)

    def initialize(@resources = [] of Resource, @next_cursor = nil, @meta = nil)
      super(@next_cursor, @meta)
    end
  end

  struct ResourceTemplate
    include JSON::Serializable

    getter name : String
    getter title : String?

    @[JSON::Field(key: "uriTemplate")]
    getter uri_template : String
    getter description : String?
    @[JSON::Field(key: "mimeType")]
    getter mime_type : String?
    getter annotations : Annotations?
    @[JSON::Field(key: "_meta")]
    getter meta : Hash(String, JSON::Any)?

    def initialize(@name, @uri_template, @description = nil, @title = nil, @mime_type = nil, @annotations = nil, @meta = nil)
    end
  end

  class ListResourceTemplatesResult < PaginatedResult
    @[JSON::Field(key: "resourceTemplates")]
    getter resource_templates : Array(ResourceTemplate)

    def initialize(@resource_templates = [] of ResourceTemplate, @next_cursor = nil, @meta = nil)
      super(@next_cursor, @meta)
    end
  end

  struct Root
    include JSON::Serializable

    getter uri : String
    getter name : String?
    @[JSON::Field(key: "_meta")]
    getter meta : Hash(String, JSON::Any)?

    def initialize(@uri, @name = nil, @meta = nil)
      raise "uri params must starts with 'file://'" unless @uri.starts_with?("file://")
    end
  end

  class ListRootsResult < Result
    getter roots : Array(Root)

    def initialize(@roots, @meta = nil)
      super(@meta)
    end
  end

  struct Tool
    include JSON::Serializable

    getter name : String
    getter title : String?
    getter description : String?
    @[JSON::Field(key: "inputSchema")]
    getter input_schema : Input
    @[JSON::Field(key: "outputSchema")]
    getter output_schema : Input?
    getter annotations : ToolAnnotations?
    @[JSON::Field(key: "_meta")]
    getter meta : Hash(String, JSON::Any)?

    def initialize(@name, @input_schema, @description = nil, @title = nil,
                   @output_schema = nil, @annotations = nil, @meta = nil)
    end

    struct Input
      include JSON::Serializable

      getter properties : Hash(String, JSON::Any)
      getter required : Array(String)?
      @type : String

      def initialize(@properties = Hash(String, JSON::Any).new, @required = nil)
        @type = "object"
      end
    end
  end

  class ListToolsResult < PaginatedResult
    getter tools : Array(Tool)

    def initialize(@tools, @next_cursor = nil, @meta = nil)
      super(@meta)
    end
  end

  class ReadResourceResult < Result
    getter contents : Array(ResourceContents)

    def initialize(@contents, @meta = nil)
      super(@meta)
    end
  end
end
