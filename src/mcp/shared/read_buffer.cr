module MCP::Shared
  class ReadBuffer
    @buffer : IO::Memory = IO::Memory.new(1024)

    def append(chunk : String)
      append(chunk.to_slice)
    end

    def append(chunk : Bytes)
      current_pos = @buffer.pos
      @buffer.seek(0, IO::Seek::End)
      @buffer.write(chunk)
      @buffer.seek(current_pos)
    end

    # Attempts to read a complete JSON-RPC message
    def read_message : JSONRPCMessage?
      return nil if @buffer.empty?
      slice = @buffer.to_slice
      index = slice.index('\n'.ord.to_u8)
      return nil if index.nil?
      message = @buffer.gets

      return nil if message.nil? || message.blank?

      JSONRPCMessage.from_json(message)
    end

    def clear
      @buffer.clear
    end
  end
end
