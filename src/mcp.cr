require "json"
require "./ext/atomic"

module MCP
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
end

require "./mcp/protocol"
require "./mcp/shared/**"
require "./mcp/server/**"
require "./mcp/client/**"
require "./mcp/annotator"
