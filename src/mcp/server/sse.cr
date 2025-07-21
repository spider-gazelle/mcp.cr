require "http"
require "http/server/handler"

module MCP
  module SSE
    class Connection
      @mutex = Mutex.new
      @closed = false
      @closed_channel = Channel(Nil).new(1)
      property on_close : Proc(Nil) = -> { }

      def initialize(@io : IO)
        spawn_reader
      end

      private def spawn_reader
        spawn do
          begin
            buffer = Bytes.new(128)
            while @io.read(buffer) > 0
            end
          rescue IO::EOFError | IO::Error
          ensure
            close
          end
        end
      end

      def close
        return if @closed
        @closed = true
        @on_close.call
        @io.close rescue nil
        @closed_channel.send(nil) rescue nil
      end

      def closed?
        @closed
      end

      def wait
        @closed_channel.receive unless closed?
      end

      def send(data : String, id : String? = nil, event : String? = nil, retry : Int32? = nil)
        @mutex.synchronize do
          return if closed?
          build_message(event, data, id, retry)
          @io.flush
        end
      rescue ex : IO::Error
        close
      end

      private def build_message(event, data, id, retry)
        @io << "id: #{id.gsub(/\R/, " ")}\n" if id
        @io << "retry: #{retry}\n" if retry
        @io << "event: #{event.gsub(/\R/, " ")}\n" if event

        data.each_line do |line|
          @io << "data: #{line.chomp("\r")}\n"
        end

        @io << '\n'
      end
    end

    class SSEChannel
      @connections = [] of Connection
      @mutex = Mutex.new

      def add(connection)
        @mutex.synchronize do
          @connections << connection
          connection.on_close = -> { remove(connection) }
        end
      end

      def remove(connection)
        @mutex.synchronize do
          @connections.delete(connection)
        end
      end

      def broadcast(data : String, id = nil, event = nil, retry = nil)
        @mutex.synchronize do
          @connections.reject! do |conn|
            if conn.closed?
              true
            else
              conn.send(event, data, id, retry) rescue true
              false
            end
          end
        end
      end

      def size
        @mutex.synchronize { @connections.size }
      end
    end

    def self.upgrade_response(response : HTTP::Server::Response, &block : Connection ->)
      response.headers["Content-Type"] = "text/event-stream"
      response.headers["Cache-Control"] = "no-cache"
      response.headers["Connection"] = "keep-alive"
      response.status = HTTP::Status::OK

      response.upgrade do |io|
        conn = Connection.new(io)
        block.call(conn)
        conn.wait
      end
    end
  end
end
