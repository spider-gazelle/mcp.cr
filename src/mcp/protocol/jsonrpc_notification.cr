require "./notification_params"

module MCP::Protocol
  class JSONRPCNotification < JSONRPCMessage
    getter method : String

    def initialize(@method)
      super()
    end

    def params : Notification
      raise "Must be implemented by sub-classes"
    end

    Protocol.use_custom_json_discriminator "method", {"notifications/tools/list_changed": ToolListChangedNotification, "notifications/prompts/list_changed": PromptListChangedNotification, "notifications/resources/list_changed": ResourceListChangedNotification,
                                                      "notifications/resources/updated": ResourceUpdatedNotification, "notifications/roots/list_changed": RootsListChangedNotification,
                                                      "notifications/message": LoggingMessageNotification, "notifications/initialized": InitializedNotification, "notifications/progress": ProgressNotification, "notifications/cancelled": CancelledNotification}, else: UknownNotification
  end

  class CancelledNotification < JSONRPCNotification
    getter params : CancelledNotificationParams

    def initialize(@params)
      super(NotificationsCancelled)
    end

    def self.new(request_id : RequestId, reason : String? = nil)
      CancelledNotification.new(CancelledNotificationParams.new(request_id, reason))
    end
  end

  class ProgressNotification < JSONRPCNotification
    getter params : ProgressNotificationParams

    def initialize(@params)
      super(NotificationsProgress)
    end
  end

  class InitializedNotification < JSONRPCNotification
    getter params : InitializedNotificationParams

    def initialize(@params)
      super(NotificationsInitialized)
    end

    def self.new
      InitializedNotification.new(InitializedNotificationParams.new)
    end
  end

  class RootsListChangedNotification < JSONRPCNotification
    getter params : RootsListChangedNotificationParams

    def initialize(@params)
      super(NotificationsRootsListChanged)
    end

    def self.new
      new(RootsListChangedNotificationParams.new)
    end
  end

  class LoggingMessageNotification < JSONRPCNotification
    getter params : LoggingMessageNotificationParams

    def initialize(@params)
      super(NotificationsMessage)
    end
  end

  class ResourceUpdatedNotification < JSONRPCNotification
    getter params : ResourceUpdatedNotificationParams

    def initialize(@params)
      super(NotificationsResourcesUpdated)
    end
  end

  class ResourceListChangedNotification < JSONRPCNotification
    getter params : ResourceListChangedNotificationParams

    def initialize(@params)
      super(NotificationsResourcesListChanged)
    end

    def self.new
      ResourceListChangedNotification.new(ResourceListChangedNotificationParams.new)
    end
  end

  class ToolListChangedNotification < JSONRPCNotification
    getter params : ToolListChangedNotificationParams

    def initialize(@params)
      super(NotificationsToolsListChanged)
    end

    def self.new
      ToolListChangedNotification.new(ToolListChangedNotificationParams.new)
    end
  end

  class PromptListChangedNotification < JSONRPCNotification
    getter params : PromptListChangedNotificationParams

    def initialize(@params)
      super(NotificationsPromptsListChanged)
    end

    def self.new
      PromptListChangedNotification.new(PromptListChangedNotificationParams.new)
    end
  end

  class UknownNotification < JSONRPCNotification
    getter input : Hash(String, JSON::Any)?

    def initialize(@method, @input)
      super(@method)
    end
  end
end
