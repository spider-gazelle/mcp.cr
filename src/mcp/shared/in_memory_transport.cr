require "./transport"

module MCP::Shared
  class InMemoryTransport < AbstractTransport
    property other_transport : InMemoryTransport?
    @message_queue = [] of JSONRPCMessage

    # Creates a pair of linked in-memory transports that can communicate with each other.
    # One should be passed to a Client and one to a Server.
    def self.create_linked_pair : {InMemoryTransport, InMemoryTransport}
      client = InMemoryTransport.new
      server = InMemoryTransport.new
      client.other_transport = server
      server.other_transport = client
      {client, server}
    end

    def start
      # spawn do
      while message = @message_queue.shift?
        _on_message.call(message)
      end
      # end
    end

    def close
      other = other_transport
      self.other_transport = nil
      other.try(&.close)
      _on_close.call
    end

    def send(message : JSONRPCMessage)
      other = other_transport
      raise "Not connected" if other.nil?
      other._on_message.call(message)
    end
  end
end
