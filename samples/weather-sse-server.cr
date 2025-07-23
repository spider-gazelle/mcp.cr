require "http/client"
require "http/server"
require "uuid"
require "../src/mcp"

class WeatherApi
  getter client : HTTP::Client

  def initialize
    @client = HTTP::Client.new(URI.parse("https://api.weather.gov"))
    headers = HTTP::Headers{
      "Accept"       => "application/geo+json",
      "Content-Type" => "application/json",
      "User-Agent"   => "WeatherApiClient/1.0",
    }
    @client.before_request do |request|
      request.headers.merge!(headers)
    end
  end

  def get_alerts(state : String) : Array(String)
    uri = "/alerts/active/area/#{state}"
    resp = client.get(uri)
    raise "Unable to get alerts: #{resp.body}" unless resp.success?
    alerts = Alert.from_json(resp.body)

    alerts.features.map do |feature|
      String.build do |str|
        str << "Event: #{feature.properties.event}\n"
        str << "Area: #{feature.properties.area_desc}\n"
        str << "Severity: #{feature.properties.severity}\n"
        str << "Description: #{feature.properties.description}\n"
        str << "Instructions: #{feature.properties.instructions}\n"
      end
    end
  end

  def get_forecast(latitude : Float64, longitude : Float64) : Array(String)
    uri = "/points/#{latitude},#{longitude}"

    resp = client.get(uri)
    raise "Unable to get points: #{resp.body}" unless resp.success?
    points = Points.from_json(resp.body)

    resp = client.get(points.properties.forecast)
    raise "Unable to get forecast: #{resp.body}" unless resp.success?
    forecast = Forecast.from_json(resp.body)

    forecast.properties.periods.map do |period|
      String.build do |str|
        str << "#{period.name}:\n"
        str << "Temperature: #{period.temperature} #{period.temperature_unit}\n"
        str << "Wind: #{period.wind_speed} #{period.wind_direction}\n"
        str << "Forecast: #{period.detailed_forecast}\n"
      end
    end
  end

  record Alert, features : Array(Feature) do
    include JSON::Serializable

    record Feature, properties : Properties do
      include JSON::Serializable
    end

    record Properties, event : String, area_desc : String, severity : String, description : String, instructions : String? do
      include JSON::Serializable
      @[JSON::Field(key: "areaDesc")]
      getter area_desc : String
    end
  end

  record Points, properties : Properties do
    include JSON::Serializable

    record Properties, forecast : String do
      include JSON::Serializable
    end
  end

  record Forecast, properties : Properties do
    include JSON::Serializable

    record Properties, periods : Array(Period) do
      include JSON::Serializable
    end
  end

  record Period, number : Int32, name : String, start_time : String, end_time : String,
    is_day_time : Bool, temperature : Int32, temperature_unit : String, temperature_trend : String,
    probability_description : JSON::Any, wind_speed : String, wind_direction : String, short_forecast : String, detailed_forecast : String do
    include JSON::Serializable

    @[JSON::Field(key: "startTime")]
    getter start_time : String

    @[JSON::Field(key: "endTime")]
    getter end_time : String

    @[JSON::Field(key: "isDaytime")]
    getter is_day_time : Bool

    @[JSON::Field(key: "temperatureUnit")]
    getter temperature_unit : String

    @[JSON::Field(key: "temperatureTrend")]
    getter temperature_trend : String

    @[JSON::Field(key: "probabilityOfPrecipitation")]
    getter probability_description : JSON::Any

    @[JSON::Field(key: "windSpeed")]
    getter wind_speed : String

    @[JSON::Field(key: "windDirection")]
    getter wind_direction : String

    @[JSON::Field(key: "shortForecast")]
    getter short_forecast : String

    @[JSON::Field(key: "detailedForecast")]
    getter detailed_forecast : String
  end
end

def configure_server
  weather_client = WeatherApi.new
  server = MCP::Server::Server.new(
    MCP::Protocol::Implementation.new(name: "weather", version: "1.0.0"),
    MCP::Server::ServerOptions.new(
      capabilities: MCP::Protocol::ServerCapabilities.new.with_tools(true)
    )
  )

  server.add_tool(
    name: "get_alerts",
    description: "Get weather alerts for a US state. Input is Two-letter US state code (e.g. CA, NY)",
    input_schema: MCP::Protocol::Tool::Input.new(properties: {"state" => JSON::Any.new({"type" => JSON::Any.new("string"),
                                                                                        "description" => JSON::Any.new("Two-letter US state code (e.g. CA, NY)")})},
      required: ["state"])
  ) do |request|
    if (state = request.arguments.try &.["state"]?.try &.as_s?) && !state.blank?
      alerts = weather_client.get_alerts(state)
      res = [] of MCP::Protocol::ContentBlock
      alerts.each { |alert| res << MCP::Protocol::TextContentBlock.new(alert) }
      MCP::Protocol::CallToolResult.new(content: res)
    else
      res = [] of MCP::Protocol::ContentBlock
      res << MCP::Protocol::TextContentBlock.new("The 'state' parameter is required")
      MCP::Protocol::CallToolResult.new(content: res)
    end
  end

  props = {"latitude" => {"type" => "number"}, "longitude" => {"type" => "number"}}
  server.add_tool(
    name: "get_forecast",
    description: "Get weather forecast for a specific latitude/longitude",
    input_schema: MCP::Protocol::Tool::Input.new(properties: JSON.parse(props.to_json).as_h,
      required: ["latitude", "longitude"])
  ) do |request|
    latitude = request.arguments.try &.["latitude"].try &.as_f
    longitude = request.arguments.try &.["longitude"].try &.as_f

    if (latitude.nil? || latitude == 0) || (longitude.nil? || longitude == 0)
      res = [MCP::Protocol::TextContentBlock.new("The 'latitude' and 'longitude' parameters are required.")] of MCP::Protocol::ContentBlock
      next MCP::Protocol::CallToolResult.new(content: res)
    end
    forecast = weather_client.get_forecast(latitude, longitude)
    res = [] of MCP::Protocol::ContentBlock
    forecast.each { |fcast| res << MCP::Protocol::TextContentBlock.new(fcast) }
    MCP::Protocol::CallToolResult.new(content: res)
  end

  server
end

class SseServer
  @@sessions = {} of String => MCP::Server::Server
  @@mutex = Mutex.new

  def self.run(port = 8080)
    server = HTTP::Server.new do |context|
      handle_request(context)
    end

    puts "SSE server listening on http://localhost:#{port}"
    puts "Use inspector to connect to the http://localhost:#{port}/sse"
    server.listen(port)
  end

  private def self.handle_request(context : HTTP::Server::Context)
    case {context.request.method, context.request.path}
    when {"GET", "/sse"}
      handle_sse_connection(context)
    when {"POST", "/message"}
      handle_post_message(context)
    else
      context.response.status_code = HTTP::Status::NOT_FOUND.code
      context.response.puts "Not Found"
    end
  end

  private def self.handle_sse_connection(context : HTTP::Server::Context)
    MCP::SSE.upgrade_response(context.response) do |conn|
      session = MCP::Server::ServerSSESession.new(conn)
      transport = MCP::Server::SseServerTransport.new("/message", session)
      server = configure_server
      # Store session
      @@mutex.synchronize { @@sessions[transport.session_id] = server }

      puts "New connection: #{transport.session_id}"

      server.on_close do
        puts "Closing session: #{transport.session_id}"
        @@mutex.synchronize { @@sessions.delete(transport.session_id) }
      end

      server.connect(transport)
    end
  end

  private def self.handle_post_message(context : HTTP::Server::Context)
    session_id = context.request.query_params["sessionId"]?

    unless session_id
      context.response.status_code = HTTP::Status::BAD_REQUEST.code
      context.response.puts "Missing session ID"
      return
    end

    @@mutex.synchronize do
      if transport = @@sessions[session_id]?.try &.transport.as?(MCP::Server::SseServerTransport)
        # Delegate message handling to the transport
        transport.handle_post_message(context)
      else
        context.response.status_code = HTTP::Status::NOT_FOUND.code
        context.response.puts "Session not found"
      end
    end
  end
end

SseServer.run
