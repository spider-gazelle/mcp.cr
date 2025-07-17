module MCP::Protocol
  abstract class Notification
    include JSON::Serializable

    @[JSON::Field(key: "_meta")]
    property meta : Hash(String, JSON::Any)?

    def initialize(@meta = nil)
    end
  end

  class CancelledNotificationParams < Notification
    @[JSON::Field(key: "requestId")]
    getter request_id : RequestId
    getter reason : String?

    def initialize(@request_id, @reason = nil, @meta = nil)
      super(@meta)
    end
  end

  class InitializedNotificationParams < Notification
    def initialize(@meta = nil)
      super
    end
  end

  class LoggingMessageNotificationParams < Notification
    getter level : LoggingLevel
    getter logger : String?
    getter data : JSON::Any?

    def initialize(@level, @logger = nil, @data = nil, @meta = nil)
      super(@meta)
    end
  end

  class Progress
    include JSON::Serializable

    getter progress : Int64
    getter total : Float64?
    getter message : String?

    def initialize(@progress, @total, @message)
    end
  end

  class ProgressNotificationParams < Notification
    @[JSON::Field(key: "progressToken")]
    getter progress_token : ProgressToken
    getter progress : Int64
    getter total : Float64?
    getter message : String?

    def initialize(@progress_token, @progress, @total, @message, @meta = nil)
      super(@meta)
    end
  end

  class PromptListChangedNotificationParams < Notification
    def initialize(@meta = nil)
      super
    end
  end

  class ResourceListChangedNotificationParams < Notification
    def initialize(@meta = nil)
      super
    end
  end

  class ResourceUpdatedNotificationParams < Notification
    getter uri : String?

    def initialize(@uri = nil, @meta = nil)
      super(@meta)
    end
  end

  class RootsListChangedNotificationParams < Notification
    def initialize(@meta = nil)
      super
    end
  end

  class ToolListChangedNotificationParams < Notification
    def initialize(@meta = nil)
      super
    end
  end

  class UknownParams < Notification
    def initialize(@meta = nil)
      super
    end
  end
end
