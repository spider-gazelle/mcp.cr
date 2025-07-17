require "json"

module MCP::Protocol
  LATEST_PROTOCOL_VERSION     = "2025-06-18"
  SUPPORTED_PROTOCOL_VERSIONS = [
    LATEST_PROTOCOL_VERSION,
    "2025-03-26",
    "2024-11-05",
    "2024-10-07",
  ]

  JSONRPC_VERSION    = "2.0"
  REQUEST_MESSAGE_ID = Atomic(Int64).new(0_i64)

  alias RequestId = String | Int64
  alias ProgressToken = RequestId
  alias Cursor = String

  enum Role
    User
    Assistant
  end

  enum ActionType
    Accept
    Decline
    Cancel
  end

  enum ContextInclusion
    None
    ThisServer
    AllServers

    def to_json(json : JSON::Builder)
      json.string(to_s.camelcase(lower: true))
    end
  end

  enum ErrorCode
    ConnectionClosed = -32000
    RequestTimeout   = -32001
    ParseError       = -32700
    InvalidRequest   = -32600
    MethodNotFound   = -32601
    InvalidParams    = -32602
    InternalError    = -32603
  end

  class MCPError < Exception
    getter code : ErrorCode
    getter data : Hash(String, JSON::Any)?

    def initialize(@code, @message, @data = nil)
      super("MCP error #{code}: #{message}")
    end
  end

  macro use_custom_json_discriminator(field, mapping, else = nil)
      {% unless mapping.is_a?(HashLiteral) || mapping.is_a?(NamedTupleLiteral) %}
        {% mapping.raise "Mapping argument must be a HashLiteral or a NamedTupleLiteral, not #{mapping.class_name.id}" %}
      {% end %}

      def self.new(pull : ::JSON::PullParser)
        location = pull.location

        discriminator_value = nil

        # Try to find the discriminator while also getting the raw
        # string value of the parsed JSON, so then we can pass it
        # to the final type.
        json = ::String.build do |io|
          ::JSON.build(io) do |builder|
            builder.start_object
            pull.read_object do |key|
              if key == {{field.id.stringify}}
                value_kind = pull.kind
                case value_kind
                when .string?
                  discriminator_value = pull.string_value
                when .int?
                  discriminator_value = pull.int_value
                when .bool?
                  discriminator_value = pull.bool_value
                else
                  raise ::JSON::SerializableError.new("JSON discriminator field '{{field.id}}' has an invalid value type of #{value_kind.to_s}", to_s, nil, *location, nil)
                end
                builder.field(key, discriminator_value)
                pull.read_next
              else
                builder.field(key) { pull.read_raw(builder) }
              end
            end
            builder.end_object
          end
        end

        if discriminator_value.nil?
          raise ::JSON::SerializableError.new("Missing JSON discriminator field '{{field.id}}'", to_s, nil, *location, nil)
        end

        case discriminator_value
        {% for key, value in mapping %}
          {% if mapping.is_a?(NamedTupleLiteral) %}
            when {{key.id.stringify}}
          {% else %}
            {% if key.is_a?(StringLiteral) %}
              when {{key}}
            {% elsif key.is_a?(NumberLiteral) || key.is_a?(BoolLiteral) %}
              when {{key.id}}
            {% elsif key.is_a?(Path) %}
              when {{key.resolve}}
            {% else %}
              {% key.raise "Mapping keys must be one of StringLiteral, NumberLiteral, BoolLiteral, or Path, not #{key.class_name.id}" %}
            {% end %}
          {% end %}
          {{value.id}}.new(pull: JSON::PullParser.new(json))
        {% end %}
        else
          {% if else %}
            return {{else.id}}.new(pull: JSON::PullParser.new(json))
          {% else %}
            raise ::JSON::SerializableError.new("Unknown '{{field.id}}' discriminator value: #{discriminator_value.inspect}", to_s, nil, *location, nil)
          {% end %}
        end
      end
    end

  macro use_key_discriminator(field, mapping, else = nil)
  {% unless mapping.is_a?(HashLiteral) || mapping.is_a?(NamedTupleLiteral) %}
    {% mapping.raise "Mapping argument must be a HashLiteral or a NamedTupleLiteral, not #{mapping.class_name.id}" %}
  {% end %}

  def self.new(pull : ::JSON::PullParser)
    location = pull.location
      parsed = Hash(String, JSON::Any).new(pull)
      target_object = parsed[{{field.id.stringify}}]?
      json = target_object.to_json

      unless target_object
        raise ::JSON::SerializableError.new(
          "Missing required field '{{field.id}}'",
          self.class.name,
          nil,
          *location,
          nil
        )
      end

      id = parsed["id"].as_i64? || parsed["id"].as_s

      keys_found = target_object.as_h.keys.map(&.to_s)
      found = false
      {% for key, klass in mapping %}
        if keys_found.includes?({{key.id.stringify}})
           {{field.id}} = {{klass.id}}.from_json(json)
           found = true
        end
      {% end %}

      {% if else %}
        {{field.id}} = {{else.id}}.from_json(json) unless found
      {% else %}
        raise ::JSON::SerializableError.new(
          "None of the expected keys found: {{ mapping.keys.map(&.id.stringify).join(", ") }}. " +
          "Actual keys: #{keys_found.join(", ")}",
          self.class.name,
          nil,
          *location,
          nil
        )
      {% end %}
      new(id,{{field.id}}.not_nil!)
  end
end
end

require "./methods"
require "./jsonrpc_message"
