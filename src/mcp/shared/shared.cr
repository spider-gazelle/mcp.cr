module MCP::Shared
  alias ProgressCallback = Proc(MCP::Protocol::Progress, Nil)

  DEFAULT_REQUEST_TIMEOUT = 60_000.milliseconds

  alias JSONRPCMessage = MCP::Protocol::JSONRPCMessage
  alias JSONRPCRequest = MCP::Protocol::JSONRPCRequest
  alias JSONRPCResponse = MCP::Protocol::JSONRPCResponse
  alias JSONRPCNotification = MCP::Protocol::JSONRPCNotification
  alias JSONRPCError = MCP::Protocol::JSONRPCError
  alias Result = MCP::Protocol::Result
  alias EmptyResult = MCP::Protocol::EmptyResult
  alias RequestId = MCP::Protocol::RequestId
  alias RequestParams = MCP::Protocol::RequestParams
  alias Notification = MCP::Protocol::Notification
end

require "./transport"
require "./protocol"
require "./read_buffer"
