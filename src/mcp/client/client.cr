require "log"
require "../shared"

module MCP::Client
  Log = ::Log.for(self)

  alias ServerCapabilities = MCP::Protocol::ServerCapabilities
  alias ClientCapabilities = MCP::Protocol::ClientCapabilities
  alias Implementation = MCP::Protocol::Implementation
  alias ProtocolOptions = MCP::Shared::ProtocolOptions
  alias JSONRPCMessage = MCP::Protocol::JSONRPCMessage
  alias JSONRPCRequest = MCP::Protocol::JSONRPCRequest
  alias JSONRPCResponse = MCP::Protocol::JSONRPCResponse
  alias JSONRPCNotification = MCP::Protocol::JSONRPCNotification

  class ClientOptions < ProtocolOptions
    property capabilities : ClientCapabilities
    property? enforce_strict_capabilities : Bool = true

    def initialize(@capabilities = ClientCapabilities.new, @enforce_strict_capabilities = true)
      super(@enforce_strict_capabilities)
    end
  end

  class Client < MCP::Shared::Protocol
    getter client_info : Implementation
    getter client_options : ClientOptions

    getter! server_capabilities : ServerCapabilities
    getter! server_version : Implementation

    getter(capabilities : ClientCapabilities) { client_options.capabilities }
    private getter roots : Hash(String, MCP::Protocol::Root)

    def initialize(@client_info, @client_options = ClientOptions.new)
      super(@client_options)
      @roots = Hash(String, MCP::Protocol::Root).new
      Log.debug { "Initializing MCP client with capabilities: #{capabilities.to_json}" }

      if capabilities.roots
        request_handler(MCP::Protocol::RootsList) { |_, _| handle_list_roots }
      end
    end

    protected def assert_capability(capability : String, method : String)
      caps = server_capabilities?
      has_capability = case capability
                       when "logging"   then caps.try &.logging != nil
                       when "prompts"   then caps.try &.prompts != nil
                       when "resources" then caps.try &.resources != nil
                       when "tools"     then caps.try &.tools != nil
                       else
                         true
                       end

      raise "Server does not support #{capability} (required for #{method})" unless has_capability
    end

    def connect(transport : MCP::Shared::Transport)
      super

      begin
        message = MCP::Protocol::InitializeRequest.new(
          protocol_version: MCP::Protocol::LATEST_PROTOCOL_VERSION,
          capabilities: self.capabilities,
          client_info: self.client_info
        )

        result = request(message).as(MCP::Protocol::InitializeResult)
        unless MCP::Protocol::SUPPORTED_PROTOCOL_VERSIONS.includes?(result.protocol_version)
          raise "Server's protocol version is not supported: #{result.protocol_version}"
        end

        @server_capabilities = result.capabilities
        @server_version = result.server_info

        notification(MCP::Protocol::InitializedNotification.new)
      rescue ex
        close
        raise "Error connecting to transport: #{ex.message}"
      end
    end

    def assert_capability_for_method(method : String)
      case method
      when MCP::Protocol::LoggingSetLevel
        raise "Server does not support logging (required for #{method})" unless server_capabilities?.try &.logging
      when MCP::Protocol::PromptsGet, MCP::Protocol::PromptsList, MCP::Protocol::CompletionComplete
        raise "Server does not support prompts (required for #{method})" unless server_capabilities?.try &.prompts
      when MCP::Protocol::ResourcesList, MCP::Protocol::ResourcesTemplatesList, MCP::Protocol::ResourcesRead, MCP::Protocol::ResourcesSubscribe, MCP::Protocol::ResourcesUnsubscribe
        raise "Server does not support resources (required for #{method})" unless server_capabilities?.try &.resources
      when MCP::Protocol::ToolsCall, MCP::Protocol::ToolsList
        raise "Server does not support tools (required for #{method})" unless server_capabilities?.try &.tools
      when MCP::Protocol::Initialize, MCP::Protocol::Ping
        # No specific capability required
      else
        # For uknown or future methods, no assertion by default
      end
    end

    def assert_notification_capability(method : String)
      Log.debug { "Asserting notification capability for method: #{method}" }
      case method
      when MCP::Protocol::NotificationsRootsListChanged
        raise "Client does not support roots list changed notifications (required for #{method})" unless capabilities.roots.try &.list_changed == true
      when MCP::Protocol::NotificationsInitialized, MCP::Protocol::NotificationsCancelled, MCP::Protocol::NotificationsProgress
        # Always allowed
      else
        # For notifications not specifically listed, no assertion by default
      end
    end

    def assert_request_handler_capability(method : String)
      case method
      when MCP::Protocol::SamplingCreateMessage
        raise "Client does not support sampling capability (required for #{method})" unless capabilities.sampling
      when MCP::Protocol::RootsList
        raise "Client does not support roots capability (required for #{method})" unless capabilities.roots
      when MCP::Protocol::Ping
        # No capability required
      else
        #
      end
    end

    def ping(options : MCP::Shared::RequestOptions? = nil) : MCP::Protocol::EmptyResult
      request(MCP::Protocol::PingRequest.new, options)
    end

    def complete(params : MCP::Protocol::CompleteRequestParams, options : MCP::Shared::RequestOptions? = nil) : MCP::Protocol::CompleteResult
      request(MCP::Protocol::CompleteRequest.new(params), options)
    end

    def logging_level(level : MCP::Protocol::LoggingLevel, options : MCP::Shared::RequestOptions? = nil) : EmptyResult
      request(MCP::Protocol::SetLevelRequest.new(level), options)
    end

    def get_prompt(req : MCP::Protocol::GetPromptRequest, options : MCP::Shared::RequestOptions? = nil) : MCP::Protocol::GetPromptResult?
      request(req, options)
    end

    def list_prompts(req : MCP::Protocol::ListPromptsRequest = MCP::Protocol::ListPromptsRequest.new, options : MCP::Shared::RequestOptions? = nil) : MCP::Protocol::ListPromptsResult?
      request(req, options)
    end

    def list_resources(req : MCP::Protocol::ListResourcesRequest = MCP::Protocol::ListResourcesRequest.new, options : MCP::Shared::RequestOptions? = nil) : MCP::Protocol::ListResourcesResult?
      request(req, options)
    end

    def list_resource_templates(req : MCP::Protocol::ListResourceTemplatesRequest = MCP::Protocol::ListResourceTemplatesRequest.new, options : MCP::Shared::RequestOptions? = nil) : MCP::Protocol::ListResourceTemplatesResult?
      request(req, options)
    end

    def read_resource(req : MCP::Protocol::ReadResourceRequest, options : MCP::Shared::RequestOptions? = nil) : MCP::Protocol::ReadResourceResult?
      request(req, options)
    end

    def subscribe_resource(req : MCP::Protocol::SubscribeRequest, options : MCP::Shared::RequestOptions? = nil) : EmptyRequestResult
      request(req, options)
    end

    def unsubscribe_resource(req : MCP::Protocol::UnsubscribeRequest, options : MCP::Shared::RequestOptions? = nil) : EmptyRequestResult
      request(req, options)
    end

    def call_tool(name : String, arguments : Hash(String, JSON::Any), compatibility : Bool = false, options : MCP::Shared::RequestOptions? = nil) : MCP::Protocol::CallToolResult | MCP::Protocol::CompatibilityCallToolResult
      obj = MCP::Protocol::CallToolRequest.new(name, arguments)

      request(obj, options)
    end

    def list_tools(req : MCP::Protocol::ListToolsRequest = MCP::Protocol::ListToolsRequest.new, options : MCP::Shared::RequestOptions? = nil) : MCP::Protocol::ListToolsResult?
      request(req, options)
    end

    def add_root(uri : String, name : String?)
      if capabilities.roots.nil?
        Log.error { "Failed to add root '#{uri}': Client does not support roots capability" }
        raise "Client does not support roots capability"
      end

      Log.info { "Adding root: #{name} #{uri}" }
      roots[uri] = MCP::Protocol::Root.new(uri: uri, name: name)
    end

    def add_roots(root_list : Array(MCP::Protocol::Root))
      if capabilities.roots.nil?
        Log.error { "Failed to add roots': Client does not support roots capability" }
        raise "Client does not support roots capability"
      end
      Log.info { "Adding #{root_list.size} roots" }
      root_list.each { |root| add_root(root.uri, root.name) }
    end

    def remove_root(uri : String) : Bool
      if capabilities.roots.nil?
        Log.error { "Failed to add root '#{uri}': Client does not support roots capability" }
        raise "Client does not support roots capability"
      end

      Log.info { "Removing root #{uri}" }
      removed = roots.delete(uri) != nil
      Log.debug { removed ? " Root removed: #{uri}" : "Root not found: #{uri}" }
      removed
    end

    def remove_roots(root_uris : Array(String)) : Int32
      if capabilities.roots.nil?
        Log.error { "Failed to add roots: Client does not support roots capability" }
        raise "Client does not support roots capability"
      end

      Log.info { "Removing #{root_uris.size} roots" }
      res = root_uris.map { |uri| remove_root(uri) }
      removed = res.count(&.== true)
      Log.info { removed > 0 ? "Removed #{removed} roots" : "No roots were removed" }
      removed
    end

    def send_root_list_changed
      notification(MCP::Protocol::RootsListChangedNotification.new)
    end

    private def handle_list_roots : MCP::Protocol::ListRootsResult
      MCP::Protocol::ListRootsResult.new(roots.values)
    end
  end
end
