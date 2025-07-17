require "json"
require "./ext/atomic"

module MCP
  VERSION = "0.1.0"
end

require "./mcp/protocol"
require "./mcp/shared/**"
require "./mcp/server/**"
require "./mcp/client/**"

# req = MCP::Protocol::PingRequest.new
# puts req.to_json

# pp MCP::Protocol::JSONRPCMessage.from_json(%({"jsonrpc":"2.0","id":1,"method":"ping"}))

# json = <<-JSON
# {
#   "jsonrpc": "2.0",
#   "method": "notifications/cancelled",
#   "params": {
#     "requestId": "123",
#     "reason": "User requested cancellation"
#   }
# }
# JSON

# notif = MCP::Protocol::JSONRPCMessage.from_json(json)
# puts notif.to_pretty_json

# json = <<-JSON
# {
#   "jsonrpc": "2.0",
#   "id": 1,
#   "result": {
#     "protocolVersion": "2024-11-05",
#     "capabilities": {
#       "logging": {},
#       "prompts": {
#         "listChanged": true
#       },
#       "resources": {
#         "subscribe": true,
#         "listChanged": true
#       },
#       "tools": {
#         "listChanged": true
#       }
#     },
#     "serverInfo": {
#       "name": "ExampleServer",
#       "title": "Example Server Display Name",
#       "version": "1.0.0"
#     },
#     "instructions": "Optional instructions for the client"
#   }
# }
# JSON

# res = MCP::Protocol::JSONRPCMessage.from_json(json)
# pp res
# puts res.to_pretty_json

# json = <<-JSON
# {
#   "jsonrpc": "2.0",
#   "id": 1,
#   "error": {
#     "code": -32602,
#     "message": "Unsupported protocol version",
#     "data": {
#       "supported": ["2024-11-05"],
#       "requested": "1.0.0"
#     }
#   }
# }
# JSON

# res = MCP::Protocol::JSONRPCMessage.from_json(json)
# puts res.to_pretty_json

# json = <<-JSON
# {
#   "jsonrpc": "2.0",
#   "id": 1,
#   "method": "initialize",
#   "params": {
#     "protocolVersion": "2024-11-05",
#     "capabilities": {
#       "roots": {
#         "listChanged": true
#       },
#       "sampling": {},
#       "elicitation": {}
#     },
#     "clientInfo": {
#       "name": "ExampleClient",
#       "title": "Example Client Display Name",
#       "version": "1.0.0"
#     }
#   }
# }
# JSON

# res = MCP::Protocol::JSONRPCMessage.from_json(json)
# pp res
# # puts res.to_pretty_json

# req = MCP::Protocol::InitializeRequest.new("2024-11-05", "ExampleClient", "1.0.0", "Example Client Display Name", nil, Hash(String, JSON::Any).new, Hash(String, JSON::Any).new, true, nil)
# pp req

# client = MCP::Client::Client.new(
#   client_info: MCP::Protocol::Implementation.new("test-client", "1.0"),
#   client_options: MCP::Client::ClientOptions.new(
#     capabilities: MCP::Protocol::ClientCapabilities.new(sampling: Hash(String, JSON::Any).new)
#   )
# )

# pp client
