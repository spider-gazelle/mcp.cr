module MCP
  class StdioRunner
    getter server : MCP::Server::Server

    def initialize(@server)
    end

    def run
      wg = WaitGroup.new(1)
      terminate = Proc(Signal, Nil).new do |signal|
        wg.done
        signal.ignore
      end

      Signal::INT.trap &terminate
      transport = MCP::Server::StdioServerTransport.new(STDIN, STDOUT)
      server.on_close { wg.done }

      wg.spawn do
        server.connect(transport)
      end

      wg.wait
    end
  end
end
