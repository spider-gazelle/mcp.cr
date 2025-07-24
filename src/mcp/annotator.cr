require "./runner"

module MCP
  # Annotation for Params
  annotation Param
  end

  # Annotation for marking methods as MCP tools
  annotation Tool
  end

  # Annotation for marking methods as MCP prompts
  annotation Prompt
  end

  # Annotation for marking methods as MCP resources
  annotation Resource
  end

  # Annotation for server configuration
  annotation MCPServer
  end

  # Annotation for Transport
  annotation Transport
  end

  module Annotator
    macro included
        getter! server : MCP::Server::Server

        def initialize(@server)
        end

        def self.run
        server = {{@type}}.create_mcp_server
        obj = {{@type}}.new(server)
        obj._register_features(obj.server)
        {% if tran_ann = @type.annotation(MCP::Transport) %}
            {% transport = tran_ann[:type].stringify %}
            {% endpoint = tran_ann[:endpoint] %}
            {% port = tran_ann[:port] %}
            {% if transport == "sse" %}
                {% uri = endpoint.nil? ? "/sse" : endpoint %}
                {% listen = port.nil? ? 8080 : port %}
                MCP::SseServerRunner.new(server, {{uri}}).run({{listen}})
            {% elsif transport == "streamable" %}
                {% uri = endpoint.nil? ? "/mcp" : endpoint %}
                {% listen = port.nil? ? 8080 : port %}
                MCP::StreamableRunner.new(server, {{uri}}).run({{listen}})
            {% elsif transport == "stdio" %}
                MCP::StdioRunner.new(server).run
            {% else %}
                {% raise "@[MCP::Transport] type should be any of stdio,sse,streamable" %}
            {% end %}
        {% else %}
            MCP::StdioRunner.new(server).run
        {% end %}
        end

       def self.create_mcp_server
        {% if server_ann = @type.annotation(MCP::MCPServer) %}
         {% name = server_ann[:name] || @type.name.stringify.underscore %}
          {% version = server_ann[:version] || "1.0.0" %}

          capabilities = MCP::Protocol::ServerCapabilities.new

          {% if server_ann[:tools] != nil %}
            capabilities = capabilities.with_tools({{server_ann[:tools]}})
          {% end %}

          {% if server_ann[:resources] != nil %}
            capabilities = capabilities.with_resources({{server_ann[:resources]}})
          {% end %}
          {% if server_ann[:prompts] != nil %}
            capabilities = capabilities.with_prompts({{server_ann[:prompts]}})
          {% end %}
          {% if server_ann[:logging] != nil %}
            capabilities = capabilities.with_logging({{server_ann[:logging]}})
          {% end %}

          MCP::Server::Server.new(
            MCP::Protocol::Implementation.new(
              name: "{{name.id}}",
              version: "{{version.id}}"
            ),
            MCP::Server::ServerOptions.new(capabilities: capabilities)
          )
        {% else %}
            raise "No @MCP::MCPServer annotation found. Please add @[MCP::MCPServer(name: \"your_server\", version: \"1.0.0\")] to your class."
        {% end %}
        end

        protected def self._map_crystal_type_to_json_schema(crystal_type : String) : Hash(String, JSON::Any)
            case crystal_type
            # Numeric types
            when "Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32", "UInt64"
                {"type" => JSON::Any.new("integer")}
            when "Float32", "Float64"
                {"type" => JSON::Any.new("number")}
                # String types
            when "String", "Char"
                {"type" => JSON::Any.new("string")}
                # Boolean
            when "Bool"
                {"type" => JSON::Any.new("boolean")}
                # Time types
            when "Time"
                {
                "type"   => JSON::Any.new("string"),
                "format" => JSON::Any.new("date-time"),
                }
                # UUID
            when "UUID"
                {
                "type"   => JSON::Any.new("string"),
                "format" => JSON::Any.new("uuid"),
                }
                # Path types
            when "Path"
                {
                "type"   => JSON::Any.new("string"),
                "format" => JSON::Any.new("path"),
                }
                # JSON types
            when "JSON::Any"
                {"type" => JSON::Any.new(["object", "array", "string", "number", "boolean", "null"].map { |t| JSON::Any.new(t) })}
                # Hash types
            when .starts_with?("Hash")
                {"type" => JSON::Any.new("object")}
                # Array types
            when .starts_with?("Array")
                inner_match = crystal_type.match(/Array\((.+)\)/)
                if inner_match && (inner_type = inner_match[1]?)
                inner_schema = {{@type}}._map_crystal_type_to_json_schema(inner_type)
                {
                    "type"  => JSON::Any.new("array"),
                    "items" => JSON::Any.new(inner_schema),
                }
                else
                {"type" => JSON::Any.new("array")}
                end
                # Set types
            when .starts_with?("Set")
                inner_match = crystal_type.match(/Set\((.+)\)/)
                if inner_match && (inner_type = inner_match[1]?)
                inner_schema = {{@type}}._map_crystal_type_to_json_schema(inner_type)
                {
                    "type"        => JSON::Any.new("array"),
                    "items"       => JSON::Any.new(inner_schema),
                    "uniqueItems" => JSON::Any.new(true),
                }
                else
                {
                    "type"        => JSON::Any.new("array"),
                    "uniqueItems" => JSON::Any.new(true),
                }
                end
                # Tuple types
            when .starts_with?("Tuple")
                {"type" => JSON::Any.new("array")}
                # Named tuple types
            when .starts_with?("NamedTuple")
                {"type" => JSON::Any.new("object")}
                # Union types
            when .includes?("|")
                union_types = crystal_type.split("|").map(&.strip)
                schemas = union_types.map { |t| JSON::Any.new({{@type}}._map_crystal_type_to_json_schema(t)) }
                {"anyOf" => JSON::Any.new(schemas)}
                # Nilable types
            when .ends_with?("?")
                base_type = crystal_type.rchop("?")
                base_schema = {{@type}}._map_crystal_type_to_json_schema(base_type)
                {
                "anyOf" => JSON::Any.new([
                    JSON::Any.new(base_schema),
                    JSON::Any.new({"type" => JSON::Any.new("null")}),
                ]),
                }
                # Enum types
            when .ends_with?("Enum")
                {"type" => JSON::Any.new("string")}
                # Default fallback
            else
                {
                "type"        => JSON::Any.new("string"),
                "description" => JSON::Any.new("Custom type: #{crystal_type}"),
                }
            end
        end
    end

    def _register_features(server)
      register_mcp_tools(server)
      register_mcp_prompts(server)
      register_mcp_resources(server)
    end

    def register_mcp_tools(server)
      {% for method in @type.methods %}
        {% if ann = method.annotation(MCP::Tool) %}
            {% tool_name = ann[:name] || method.name.stringify %}
            {% description = ann[:description] || "No description provided" %}
            properties = {} of String => Hash(String, JSON::Any)
            required = [] of String

            {% for arg in method.args %}
              {% if arg.restriction %}
                {% crystal_type = arg.restriction %}
                {% is_optional = crystal_type.resolve.nilable? %}
                {% base_type = is_optional ? crystal_type.types.find { |type| type != Nil.class } : crystal_type %}
                {% crystal_type_name = base_type.resolve.name.stringify %}

                schema = {{@type}}._map_crystal_type_to_json_schema({{crystal_type_name}})

                {% if param_ann = arg.annotation(MCP::Param) %}
                    {% if param_ann[:description] %}
                    schema["description"] = JSON::Any.new({{param_ann[:description]}})
                    {% end %}
                    {% for key, value in param_ann.named_args %}
                    {% unless key == :description %}
                        schema["{{key.id}}"] = JSON::Any.new({{value}})
                    {% end %}
                    {% end %}
                {% end %}

                {% if ann[arg.name.symbolize] %}
                  {% arg_ann = ann[arg.name.symbolize] %}
                  {% if arg_ann.is_a?(HashLiteral) %}
                    {% for key, value in arg_ann %}
                      schema["{{key.id}}"] = JSON::Any.new({{value}})
                    {% end %}
                  {% else %}
                    schema["description"] = JSON::Any.new("{{arg_ann.id}}")
                  {% end %}
                {% end %}

                {% if ann["#{arg.name}_description".id] %}
                  schema["description"] = JSON::Any.new("{{ann["#{arg.name}_description".id].id}}")
                {% end %}

                properties["{{arg.name.id}}"] = schema.transform_values { |v| JSON.parse(v.to_json) }

                {% unless arg.default_value || is_optional %}
                  required << {{arg.name.stringify}}
                {% end %}
              {% end %}
            {% end %}

            input_schema = MCP::Protocol::Tool::Input.new(
              properties: properties.transform_values { |v| JSON::Any.new(v) },
              required: required
            )

            server.add_tool(
              name: "{{tool_name.id}}",
              description: "{{description.id}}",
              input_schema: input_schema
            ) do |request|
            {% for arg in method.args %}
                {% arg_name = arg.name.stringify %}
                {% if arg.restriction %}
                {% crystal_type = arg.restriction %}
                {% is_optional = crystal_type.resolve.nilable? %}
                {% base_type = is_optional ? crystal_type.types.find { |type| type != Nil.class } : crystal_type %}
                {% type_name = base_type.resolve.name.stringify %}

                {% if type_name.starts_with?("Float") %}
                    {{arg.name.id}} = request.arguments.try(&.[{{arg_name}}]?).try(&.as_f?)
                    {% if type_name == "Float32" %}
                    {{arg.name.id}} = {{arg.name.id}}.try(&.to_f32)
                    {% end %}

                {% elsif type_name.starts_with?("Int") || type_name.starts_with?("UInt") %}
                    {{arg.name.id}} = request.arguments.try(&.[{{arg_name}}]?).try({% if type_name == "Int64" %}&.asi64{% else %}&.as_i?{% end %})

                {% elsif type_name == "String" %}
                    {{arg.name.id}} = request.arguments.try(&.[{{arg_name}}]?).try(&.as_s?)

                {% elsif type_name == "Bool" %}
                    {{arg.name.id}} = request.arguments.try(&.[{{arg_name}}]?).try(&.as_bool?)

                {% elsif type_name == "Time" %}
                    json_val = request.arguments.try(&.[{{arg_name}}]?)
                    {{arg.name.id}} = if json_val
                                        if str = json_val.as_s?
                                        Time.parse(str, Time::Format::ISO_8601_DATE_TIME) rescue nil
                                        elsif num = json_val.as_i?
                                        Time.unix(num)
                                        elsif num = json_val.as_f?
                                        Time.unix(num.to_i)
                                        end
                                    end

                {% elsif type_name == "UUID" %}
                    {{arg.name.id}} = request.arguments.try(&.[{{arg_name}}]?).try(&.as_s?).try { |s| UUID.new(s) rescue nil }

                {% elsif type_name.starts_with?("Array") %}
                    {{arg.name.id}} = request.arguments.try(&.[{{arg_name}}]?).try(&.as_a?)

                {% elsif type_name.starts_with?("Hash") %}
                    {{arg.name.id}} = request.arguments.try(&.[{{arg_name}}]?).try(&.as_h?)

                {% else %}
                    {{arg.name.id}} = request.arguments.try(&.[{{arg_name}}]?).try(&.as_s?)
                {% end %}

                {% unless arg.default_value || arg.restriction.resolve.nilable? %}
                    if {{arg.name.id}}.nil?
                    res = [MCP::Protocol::TextContentBlock.new("The '{{arg.name.id}}' parameter is required and must be a valid {{crystal_type.id}}.")] of MCP::Protocol::ContentBlock
                    next MCP::Protocol::CallToolResult.new(content: res)
                    end
                {% end %}
                {% end %}
            {% end %}

             begin
                result = {{method.name.id}}(
                  {% for arg, index in method.args %}
                  {% last_arg = index == method.args.size - 1 %}
                    {% if arg.restriction %}
                    {% crystal_type = arg.restriction %}
                    {% is_optional = crystal_type.resolve.nilable? %}
                    {{arg.name.id}}{% unless is_optional %}.not_nil! {% end %}{% unless last_arg %},{% end %}
                    {% end %}
                  {% end %}
                )
                case result
                when MCP::Protocol::CallToolResult
                    result
                when Int32, Int64, Float32, Float64, String, Bool, Nil
                    content = [MCP::Protocol::TextContentBlock.new(result.to_s)] of MCP::Protocol::ContentBlock
                    MCP::Protocol::CallToolResult.new(content: content)
                when Array
                    if result.all? { |item| item.is_a?(Int32) || item.is_a?(Int64) || item.is_a?(Float32) || item.is_a?(Float64) || item.is_a?(String) || item.is_a?(Bool) || item.nil? }
                        content = result.map { |item| (MCP::Protocol::TextContentBlock.new(item.to_s)).as(MCP::Protocol::ContentBlock) }
                        MCP::Protocol::CallToolResult.new(content: content)
                    else
                        json_str = result.to_json
                        content = [MCP::Protocol::TextContentBlock.new(json_str)] of MCP::Protocol::ContentBlock
                        structured = Hash(String, JSON::Any).from_json(json_str)
                        MCP::Protocol::CallToolResult.new(content: content,structured_content: structured)
                    end
                else
                    json_str = result.to_json
                    content = [MCP::Protocol::TextContentBlock.new(json_str)] of MCP::Protocol::ContentBlock
                    structured = Hash(String, JSON::Any).from_json(json_str)
                    MCP::Protocol::CallToolResult.new(content: content,structured_content: structured)
                end
                rescue ex
                    content = [MCP::Protocol::TextContentBlock.new("Error executing tool '{{tool_name.id}}': #{ex.message}")] of MCP::Protocol::ContentBlock
                    MCP::Protocol::CallToolResult.new(content: content, is_error: true)
                end
            end
        {% end %}
      {% end %}
    end

    def register_mcp_prompts(server)
      {% for method in @type.methods %}
        {% if ann = method.annotation(MCP::Prompt) %}
            {% prompt_name = ann[:name] || method.name.stringify %}
            {% description = ann[:description] || "No description provided" %}

            prompt_arguments = [] of MCP::Protocol::PromptArgument
            {% for arg in method.args %}
                {% if arg.restriction %}
                    {% crystal_type = arg.restriction %}
                    {% is_optional = crystal_type.resolve.nilable? %}
                    {% base_type = is_optional ? crystal_type.types.find { |type| type != Nil.class } : crystal_type %}
                    {% crystal_type_name = base_type.resolve.name.stringify %}

                arg_schema = {{@type}}._map_crystal_type_to_json_schema({{crystal_type_name}})
                arg_name = {{arg.name.stringify}}
                arg_title = nil
                arg_description = nil
                arg_required = {% if is_optional || arg.default_value %}false{% else %}true{% end %}

                {% if param_ann = arg.annotation(MCP::Param) %}
                    {% if param_ann[:description] %}
                    arg_description = {{param_ann[:description]}}
                    {% end %}
                    {% if param_ann[:title] %}
                    arg_title = {{param_ann[:title]}}
                    {% end %}
                {% end %}

                {% if ann[arg.name.symbolize] %}
                    {% arg_ann = ann[arg.name.symbolize] %}
                    {% if arg_ann.is_a?(HashLiteral) %}
                    {% for key, value in arg_ann %}
                        {% if key.stringify == "description" %}
                        arg_description = {{value}}
                        {% elsif key.stringify == "title" %}
                        arg_title = {{value}}
                        {% end %}
                    {% end %}
                    {% else %}
                    arg_description = {{arg_ann.stringify}}
                    {% end %}
                {% end %}
                if !arg_description
                    arg_description = "Parameter of type {{base_type.resolve.name}}{% if is_optional %} (optional){% end %}"
                end

                prompt_arguments << MCP::Protocol::PromptArgument.new(
                    name: arg_name,
                    description: arg_description,
                    title: arg_title,
                    required: arg_required
                )
                {% end %}
            {% end %}

            prompt = MCP::Protocol::Prompt.new({{prompt_name}}, {{description}}, prompt_arguments)
            server.add_prompt(prompt) do |params|
                {% if method.args.size > 0 %}
                {% for arg in method.args %}
                    {% arg_name = arg.name %}
                    {% crystal_type = arg.restriction %}
                    {% is_optional = crystal_type.resolve.nilable? %}
                    {% base_type = is_optional ? crystal_type.types.find { |type| type != Nil.class } : crystal_type %}
                    {% crystal_type_name = base_type.resolve.name.stringify %}

                    {{ arg_name }} = if params.arguments && params.arguments.not_nil!.has_key?({{ arg.name.stringify }})
                    arg_value = params.arguments.not_nil![{{ arg.name.stringify }}]
                    {% if crystal_type_name == "String" %}
                        case arg_value
                        when JSON::Any
                        arg_value.as_s
                        else
                        arg_value.to_s
                        end
                    {% elsif crystal_type_name == "Int32" %}
                        case arg_value
                        when JSON::Any
                        if arg_value.as_i?
                            arg_value.as_i.to_i32
                        else
                            arg_value.as_s.to_i32
                        end
                        else
                        arg_value.to_s.to_i32
                        end
                    {% elsif crystal_type_name == "Int64" %}
                        case arg_value
                        when JSON::Any
                        if arg_value.as_i64?
                            arg_value.as_i64
                        else
                            arg_value.as_s.to_i64
                        end
                        else
                        arg_value.to_s.to_i64
                        end
                    {% elsif crystal_type_name == "Float64" %}
                        case arg_value
                        when JSON::Any
                        if arg_value.as_f?
                            arg_value.as_f
                        else
                            arg_value.as_s.to_f64
                        end
                        else
                        arg_value.to_s.to_f64
                        end
                    {% elsif crystal_type_name == "Bool" %}
                        case arg_value
                        when JSON::Any
                        if arg_value.as_bool?
                            arg_value.as_bool
                        else
                            arg_value.as_s.downcase == "true"
                        end
                        else
                        arg_value.to_s.downcase == "true"
                        end
                    {% else %}
                        case arg_value
                        when JSON::Any
                        arg_value.as_s
                        else
                        arg_value.to_s
                        end
                    {% end %}
                    {% if is_optional %}
                    else
                    {{ arg.default_value }}
                    {% else %}
                    else
                    raise "Required parameter {{ arg_name }} not provided"
                    {% end %}
                    end
                {% end %}
                result = {{ method.name }}({{ method.args.map(&.name).splat }})
                {% else %}
                result = {{ method.name }}
                {% end %}
                messages = case result
                when String
                [MCP::Protocol::PromptMessage.new(MCP::Protocol::Role::User, MCP::Protocol::TextContentBlock.new(result))]
                when Array(MCP::Protocol::PromptMessage)
                result
                when MCP::Protocol::PromptMessage
                [result]
                when MCP::Protocol::GetPromptResult
                next result
                else
                [MCP::Protocol::PromptMessage.new(MCP::Protocol::Role::User, MCP::Protocol::TextContentBlock.new(result.to_s))]
                end
                MCP::Protocol::GetPromptResult.new(messages: messages,description: {{description}})
            end
        {% end %}
      {% end %}
    end

    def register_mcp_resources(server)
      {% for method in @type.methods %}
        {% if ann = method.annotation(MCP::Resource) %}
            {%
              method_name = method.name.stringify
              resource_name = ann[:name] || method_name
              resource_uri = ann[:uri]
              resource_description = ann[:description]
              resource_mime_type = ann[:mime_type] || "text/plain"
            %}

            server.add_resource(
            uri: {{resource_uri}},
            name: {{resource_name}},
            description: {{resource_description}},
            mime_type: {{resource_mime_type}}
            ) do |params|
            begin
                user_result = {{method.name}}(params.uri)
                contents = case user_result
                when String
                [MCP::Protocol::TextResourceContents.new(
                    uri: params.uri,
                    text: user_result,
                    mime_type: {{resource_mime_type}}
                )] of MCP::Protocol::ResourceContents
                when Bytes
                [MCP::Protocol::BlobResourceContents.new(
                    uri: params.uri,
                    blob: Base64.encode(user_result),
                    mime_type: {{resource_mime_type}}
                )] of MCP::Protocol::ResourceContents
                when Array(MCP::Protocol::ResourceContents)
                user_result
                when MCP::Protocol::ResourceContents
                [user_result]
                else
                [MCP::Protocol::TextResourceContents.new(
                    uri: params.uri,
                    text: user_result.to_s,
                    mime_type: {{resource_mime_type}}
                )] of MCP::Protocol::ResourceContents
                end

                MCP::Protocol::ReadResourceResult.new(contents: contents)
            rescue ex : Exception
                error_content = MCP::Protocol::TextResourceContents.new(
                uri: params.uri,
                text: "Error reading resource: #{ex.message}",
                mime_type: "text/plain"
                )
                MCP::Protocol::ReadResourceResult.new(contents: [error_content] of MCP::Protocol::ResourceContents)
            end
            end
        {% end %}
      {% end %}
    end
  end
end
