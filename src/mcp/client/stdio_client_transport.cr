require "wait_group"
require "../shared/read_buffer"

module MCP::Client
  class StdioClientTransport < Shared::AbstractTransport
    Log = ::Log.for(self)

    private getter input : IO
    private getter output : IO
    @initialized : Atomic(Bool)
    private getter send_channel : Channel(MCP::Protocol::JSONRPCMessage)

    def initialize(@input, @output)
      super()

      @read_buffer = Shared::ReadBuffer.new
      @initialized = Atomic.new(false)
      @send_channel = Channel(MCP::Protocol::JSONRPCMessage).new(50)
    end

    def start
      _, success = @initialized.compare_and_set(false, true)
      raise "StdioClientTransport already started" unless success

      Log.debug { "Starting StdioClientTransport..." }
      spawn {
        wg = WaitGroup.new

        wg.spawn do
          Log.debug { "Read fiber started" }
          buf = Bytes.new(8192)
          begin
            loop do
              break if input.closed?
              bytes_read = input.read(buf)
              break if bytes_read == 0
              @read_buffer.append(buf[...bytes_read])
              process_read_buffer
            end
          rescue ex
            Log.error(exception: ex) { "Error reading from stdin" }
            _on_error.call(ex)
          ensure
            close
          end
        end

        wg.spawn do
          Log.debug { "Write fiber started" }
          loop do
            begin
              break if send_channel.closed?
              select
              when message = send_channel.receive?
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

        wg.wait
        _on_close.call
      }
    end

    def send(message : MCP::Protocol::JSONRPCMessage)
      raise "Transport not started" unless @initialized.get
      send_channel.send(message)
    end

    def close
      _, success = @initialized.compare_and_set(true, false)
      return unless success

      begin
        send_channel.close
        begin
          input.close
        rescue e
          Log.warn(exception: e) { "Failed to close stdin" }
        end

        @read_buffer.clear
        output.close
        @_on_close.call
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
          Log.error(exception: e) { "Error processing message." }
        end
      end
    end
  end
end
