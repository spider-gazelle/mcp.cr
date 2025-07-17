require "../shared/read_buffer"

module MCP::Server
  class StdioServerTransport < Shared::AbstractTransport
    Log = ::Log.for(self)

    private getter input : IO
    private getter output : IO
    private getter read_channel : Channel(Bytes)
    private getter write_channel : Channel(MCP::Protocol::JSONRPCMessage)
    @initialized : Atomic(Bool)

    def initialize(@input, @output)
      super()

      @read_buffer = Shared::ReadBuffer.new
      @initialized = Atomic.new(false)
      @read_channel = Channel(Bytes).new(50)
      @write_channel = Channel(MCP::Protocol::JSONRPCMessage).new(50)
    end

    def start
      _, success = @initialized.compare_and_set(false, true)
      raise "StdioServerTransport already started" unless success

      spawn do
        buf = Bytes.new(8192)
        begin
          loop do
            break if input.closed?
            bytes_read = input.read(buf)
            break if bytes_read == 0
            read_channel.send(buf[...bytes_read])
          end
        rescue ex
          Log.error(exception: ex) { "Error reading from stdin" }
          _on_error.call(ex)
        ensure
          close
        end
      end

      spawn do
        loop do
          begin
            select
            when chunk = read_channel.receive?
              break if chunk.nil?
              @read_buffer.append(chunk)
              process_read_buffer
            when timeout(1.seconds)
              sleep(100.milliseconds)
            end
          rescue e
            _on_error.call(e)
          end
        end
      end

      spawn do
        loop do
          begin
            select
            when message = write_channel.receive?
              break if message.nil?
              output.puts(message.to_json)
              output.flush
            when timeout(1.seconds)
              sleep(100.milliseconds)
            end
          rescue e
            Log.error(exception: e) { "Error writing to stdout" }
            _on_error.call(e)
          end
        end
      end
    end

    private def process_read_buffer
      loop do
        message = begin
          @read_buffer.read_message
        rescue e
          _on_error.call(e)
          nil
        end
        break if message.nil?
        begin
          _on_message.call(message)
        rescue e
          _on_error.call(e)
        end
      end
    end

    def close
      _, success = @initialized.compare_and_set(true, false)
      return unless success

      begin
        write_channel.close
        begin
          input.close
        rescue e
          Log.warn(exception: e) { "Failed to close stdin" }
        end

        read_channel.close
        @read_buffer.clear
        output.flush
        @_on_close.call
      end
    end

    def send(message : MCP::Protocol::JSONRPCMessage)
      write_channel.send(message)
    end
  end
end
