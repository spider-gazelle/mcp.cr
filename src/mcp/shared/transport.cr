require "../protocol/jsonrpc_message"

module MCP::Shared
  module Transport
    # Starts processing messages, including any connection steps
    abstract def start
    # Sends a JSON-RPC message
    abstract def send(message : JSONRPCMessage)
    # Closes the connection
    abstract def close

    # Callback for connection close events
    abstract def on_close(&block : -> Nil) : Nil
    # Callback for error events
    abstract def on_error(&block : Exception -> Nil) : Nil
    # Callback for incoming messages
    abstract def on_message(&block : JSONRPCMessage -> Nil) : Nil
  end

  abstract class AbstractTransport
    include Transport

    protected property _on_close : Proc(Nil) = -> { }
    protected property _on_error : Proc(Exception, Nil) = ->(e : Exception) { }
    protected property _on_message : Proc(JSONRPCMessage, Nil)

    def initialize
      @on_message_initialized = Channel(Nil).new(1)
      @_on_message = ->(_msg : JSONRPCMessage) { } # work-around to satisfy type system

      @_on_message = ->(msg : JSONRPCMessage) {
        @on_message_initialized.receive?
        @_on_message.call(msg)
      }
    end

    def on_close(&block : -> Nil) : Nil
      old = @_on_close
      @_on_close = -> {
        old.call
        block.call
      }
    end

    def on_error(&block : Exception -> Nil) : Nil
      old = @_on_error
      @_on_error = ->(e : Exception) {
        old.call(e)
        block.call(e)
      }
    end

    def on_message(&block : JSONRPCMessage -> Nil) : Nil
      old = @on_message_initialized.closed? ? @_on_message : ->(_msg : JSONRPCMessage) { }

      @_on_message = ->(message : JSONRPCMessage) {
        old.call(message)
        block.call(message)
      }

      unless @on_message_initialized.closed?
        @on_message_initialized.send(nil)
        @on_message_initialized.close
      end
    end
  end
end
