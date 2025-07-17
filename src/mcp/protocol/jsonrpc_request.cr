require "./request_params"

module MCP::Protocol
  abstract class JSONRPCRequest < JSONRPCMessageWithId
    getter method : String

    def initialize(@method, @id = REQUEST_MESSAGE_ID.increment_and_get)
      super(@id)
    end

    protected def with_id(id : RequestId)
      new(method, id, params)
    end

    Protocol.use_custom_json_discriminator "method", {"ping": PingRequest, "initialize": InitializeRequest, "completion/complete": CompleteRequest, "logging/setLevel": SetLevelRequest, "prompts/get": GetPromptRequest, "prompts/list": ListPromptsRequest, "resources/list": ListResourcesRequest, "resources/templates/list": ListResourceTemplatesRequest, "resources/read": ReadResourceRequest, "resources/subscribe": SubscribeRequest, "resources/unsubscribe": UnsubscribeRequest, "tools/call": CallToolRequest, "tools/list": ListToolsRequest, "sampling/createMessage": CreateMessageRequest, "roots/list": ListRootsRequest}
  end

  class PingRequest < JSONRPCRequest
    def initialize
      super(method: Ping)
    end
  end

  class InitializeRequest < JSONRPCRequest
    getter params : InitializeRequestParams

    def initialize(@params)
      super(method: Initialize)
    end

    def self.new(protocol_version : String, capabilities : ClientCapabilities, client_info : Implementation, meta : Hash(String, JSON::Any)? = nil)
      params = InitializeRequestParams.new(protocol_version, capabilities, client_info, meta)
      InitializeRequest.new(params)
    end

    def self.new(
      protocol_version : String,
      client_name : String,
      client_version : String,
      client_title : String? = nil,
      experimental : Hash(String, JSON::Any)? = nil,
      sampling : Hash(String, JSON::Any)? = nil,
      elicitation : Hash(String, JSON::Any)? = nil,
      roots_list_changed : Bool? = nil,
      meta : Hash(String, JSON::Any)? = nil,
    )
      client_info = Implementation.new(client_name, client_version, client_title)
      capabilities = ClientCapabilities.new(
        experimental: experimental,
        sampling: sampling,
        elicitation: elicitation,
        roots: RootsCapability.new(roots_list_changed)
      )
      new(protocol_version, capabilities, client_info, meta)
    end
  end

  class CompleteRequest < JSONRPCRequest
    getter params : CompleteRequestParams

    def initialize(@params)
      super(method: CompletionComplete)
    end

    def self.new(
      ref : MCPReference,
      arg_name : String,
      arg_value : String,
      context_args : Hash(String, String)? = nil,
      meta : Hash(String, JSON::Any)? = nil,
    )
      argument = Argument.new(name: arg_name, value: arg_value)
      context = context_args ? CompleteContext.new(context_args) : nil
      params = CompleteRequestParams.new(ref, argument, context, meta)
      CompleteRequest.new(params)
    end
  end

  class SetLevelRequest < JSONRPCRequest
    getter params : SetLevelRequestParams

    def initialize(@params)
      super(method: LoggingSetLevel)
    end

    def self.new(level : LoggingLevel, meta : Hash(String, JSON::Any)? = nil)
      SetLevelRequest.new(SetLevelRequestParams.new(level, meta))
    end
  end

  class GetPromptRequest < JSONRPCRequest
    getter params : GetPromptRequestParams

    def initialize(@params)
      super(method: PromptsGet)
    end

    def self.new(name : String, arguments : Hash(String, JSON::Any)? = nil, meta : Hash(String, JSON::Any)? = nil)
      GetPromptRequest.new(GetPromptRequestParams.new(name, arguments, meta))
    end
  end

  class ListPromptsRequest < JSONRPCRequest
    getter params : ListPromptsRequestParams

    def initialize(@params)
      super(method: PromptsList)
    end

    def self.new(meta : Hash(String, JSON::Any)? = nil)
      ListPromptsRequest.new(ListPromptsRequestParams.new(meta))
    end
  end

  class ListResourcesRequest < JSONRPCRequest
    getter params : ListResourcesRequestParams

    def initialize(@params)
      super(method: ResourcesList)
    end

    def self.new(meta : Hash(String, JSON::Any)? = nil)
      ListResourcesRequest.new(ListResourcesRequestParams.new(meta))
    end
  end

  class ListResourceTemplatesRequest < JSONRPCRequest
    getter params : ListResourceTemplatesRequestParams

    def initialize(@params)
      super(method: ResourcesTemplatesList)
    end

    def self.new(meta : Hash(String, JSON::Any)? = nil)
      ListResourceTemplatesRequest.new(ListResourceTemplatesRequestParams.new(meta))
    end
  end

  class ReadResourceRequest < JSONRPCRequest
    getter params : ReadResourceRequestParams

    def initialize(@params)
      super(method: ResourcesRead)
    end

    def self.new(uri : String, meta : Hash(String, JSON::Any)? = nil)
      ReadResourceRequest.new(ReadResourceRequestParams.new(uri, meta))
    end
  end

  class SubscribeRequest < JSONRPCRequest
    getter params : SubscribeRequestParams

    def initialize(@params)
      super(method: ResourcesSubscribe)
    end

    def self.new(uri : String, meta : Hash(String, JSON::Any)? = nil)
      SubscribeRequest.new(SubscribeRequestParams.new(uri, meta))
    end
  end

  class UnsubscribeRequest < JSONRPCRequest
    getter params : UnsubscribeRequestParams

    def initialize(@params)
      super(method: ResourcesUnsubscribe)
    end

    def self.new(uri : String, meta : Hash(String, JSON::Any)? = nil)
      UnsubscribeRequest.new(UnsubscribeRequestParams.new(uri, meta))
    end
  end

  class CallToolRequest < JSONRPCRequest
    getter params : CallToolRequestParams

    def initialize(@params)
      super(method: ToolsCall)
    end

    def self.new(name : String, arguments : Hash(String, JSON::Any)? = nil, meta : Hash(String, JSON::Any)? = nil)
      CallToolRequest.new(CallToolRequestParams.new(name, arguments, meta))
    end
  end

  class ListToolsRequest < JSONRPCRequest
    getter params : ListToolsRequestParams

    def initialize(@params)
      super(method: ToolsList)
    end

    def self.new(meta : Hash(String, JSON::Any)? = nil)
      ListToolsRequest.new(ListToolsRequestParams.new(meta))
    end
  end

  class CreateMessageRequest < JSONRPCRequest
    getter params : CreateMessageRequestParams

    def initialize(@params)
      super(method: SamplingCreateMessage)
    end

    def self.new(
      messages : Array(Tuple(Role, ContentBlock)),
      max_tokens : Int32,
      system_prompt : String? = nil,
      include_context : ContextInclusion? = nil,
      temperature : Float64? = nil,
      stop_sequences : Array(String)? = nil,
      metadata : Hash(String, JSON::Any)? = nil,
      model_preferences : NamedTuple(
        hints: Array(String)?,
        cost_priority: Float64?,
        speed_priority: Float64?,
        intelligence_priority: Float64?)? = nil,
      meta : Hash(String, JSON::Any)? = nil,
    )
      sampling_messages = messages.map do |msg|
        SamplingMessage.new(msg[0], msg[1])
      end

      prefs = if model_preferences
                ModelPreferences.new(
                  hints: model_preferences[:hints].try { |hint| hint.map { |name| ModelHint.new(name) } },
                  cost_priority: model_preferences[:cost_priority]?,
                  speed_priority: model_preferences[:speed_priority]?,
                  intelligence_priority: model_preferences[:intelligence_priority]?
                )
              end

      params = CreateMessageRequestParams.new(
        messages: sampling_messages,
        max_tokens: max_tokens,
        system_prompt: system_prompt,
        include_context: include_context,
        temperature: temperature,
        stop_sequences: stop_sequences,
        metadata: metadata ? JSON::Any.new(metadata) : nil,
        model_preferences: prefs,
        meta: meta
      )

      CreateMessageRequest.new(params)
    end
  end

  class ListRootsRequest < JSONRPCRequest
    getter params : ListRootsRequestParams

    def initialize(@params)
      super(method: RootsList)
    end

    def self.new(meta : Hash(String, JSON::Any)? = nil)
      ListRootsRequest.new(ListRootsRequestParams.new(meta))
    end
  end
end
