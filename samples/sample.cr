require "http/client"
require "../src/mcp"

@[MCP::MCPServer(name: "weather_service", version: "2.1.0", tools: false, prompts: false, resources: false)]
@[MCP::Transport(type: streamable, endpoint: "/mymcp")]
class WeatherMCPServer
  include MCP::Annotator

  getter(weather_client : WeatherApi) { WeatherApi.new }

  @[MCP::Tool(
    name: "weather_alerts",
    description: "Get weather alerts for a US state. Input is Two-letter US state code (e.g. CA, NY)"
  )]
  def get_alerts(@[MCP::Param(description: "Two-letter US state code (e.g. CA, NY)")] state : String,
                 @[MCP::Param(description: "size of result")] limit : Int32?) : Array(String)
    weather_client.get_alerts(state)
  end

  @[MCP::Tool(description: "Get weather forecast for a specific latitude/longitude")]
  def get_forecast(@[MCP::Param(description: "Latitude coordinate", minimum: -90, maximum: 90)] latitude : Float64,
                   @[MCP::Param(description: "Longitude coordinate", minimum: -180, maximum: 107)] longitude : Float64) : Array(String)
    weather_client.get_forecast(latitude, longitude)
  end

  @[MCP::Prompt(
    name: "simple",
    description: "A simple prompt that can take optional context and topic"
  )]
  def simple_prompt(@[MCP::Param(description: "Additional context to consider")] context : String?,
                    @[MCP::Param(description: "A Specific topic to focus on")] topic : String?) : String
    String.build do |str|
      str << "Here is some relevant context: #{context}" if context
      str << "Please help with "
      str << (topic ? "the following topic: #{topic}" : "whatever questions I may have")
    end
  end

  @[MCP::Resource(name: "greeting", uri: "file:///greeting.txt", description: "Sample text resource", mime_type: "text/plain")]
  def read_text_resource(uri : String) : String
    raise "Invalid resource uri '#{uri}' or resource does not exist" unless uri == "file:///greeting.txt"
    "Hello! This is a sample text resource."
  end
end

WeatherMCPServer.run

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
