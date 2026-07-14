require 'json'
require 'net/http'
require 'uri'

module AmazonOrder
  # Monitors JRA racecourse weather using the Open-Meteo forecast API.
  class RacecourseWeatherMonitor
    DEFAULT_API_ENDPOINT = 'https://api.open-meteo.com/v1/forecast'.freeze

    RACECOURSES = {
      'sapporo' => { name: '札幌競馬場', latitude: 43.0740, longitude: 141.3269 },
      'hakodate' => { name: '函館競馬場', latitude: 41.7839, longitude: 140.7750 },
      'fukushima' => { name: '福島競馬場', latitude: 37.7656, longitude: 140.4808 },
      'niigata' => { name: '新潟競馬場', latitude: 37.9475, longitude: 139.1872 },
      'tokyo' => { name: '東京競馬場', latitude: 35.6650, longitude: 139.4850 },
      'nakayama' => { name: '中山競馬場', latitude: 35.7258, longitude: 139.9598 },
      'chukyo' => { name: '中京競馬場', latitude: 35.0703, longitude: 136.9856 },
      'kyoto' => { name: '京都競馬場', latitude: 34.9069, longitude: 135.7247 },
      'hanshin' => { name: '阪神競馬場', latitude: 34.7792, longitude: 135.3628 },
      'kokura' => { name: '小倉競馬場', latitude: 33.8428, longitude: 130.8750 }
    }.freeze

    DEFAULT_THRESHOLDS = {
      precipitation_probability: 60,
      precipitation: 5.0,
      wind_speed: 12.0,
      temperature_high: 35.0,
      temperature_low: 0.0
    }.freeze

    attr_reader :api_endpoint, :thresholds

    def initialize(api_endpoint: DEFAULT_API_ENDPOINT, thresholds: {})
      @api_endpoint = api_endpoint
      @thresholds = DEFAULT_THRESHOLDS.merge(thresholds)
    end

    def monitor(keys = RACECOURSES.keys)
      keys.map { |key| weather_for(key) }
    end

    def alerts(keys = RACECOURSES.keys)
      monitor(keys).select { |weather| weather[:alerts].any? }
    end

    def weather_for(key)
      racecourse = racecourse_for(key)
      daily = fetch_daily_forecast(racecourse)
      forecast = daily_forecast_for(daily, 0)

      racecourse.merge(
        key: key.to_s,
        forecast_date: forecast[:date],
        weather_code: forecast[:weather_code],
        precipitation_probability: forecast[:precipitation_probability],
        precipitation: forecast[:precipitation],
        wind_speed: forecast[:wind_speed],
        temperature_max: forecast[:temperature_max],
        temperature_min: forecast[:temperature_min],
        alerts: alerts_for(forecast)
      )
    end

    private

    def racecourse_for(key)
      RACECOURSES.fetch(key.to_s) do
        raise ArgumentError, "unknown racecourse: #{key}"
      end
    end

    def fetch_daily_forecast(racecourse)
      uri = URI(api_endpoint)
      params = {
        latitude: racecourse[:latitude],
        longitude: racecourse[:longitude],
        daily: 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,wind_speed_10m_max',
        timezone: 'Asia/Tokyo',
        forecast_days: 1
      }
      uri.query = URI.encode_www_form(params)

      response = Net::HTTP.get_response(uri)
      unless response.is_a?(Net::HTTPSuccess)
        raise "weather API request failed: #{response.code} #{response.message}"
      end

      JSON.parse(response.body).fetch('daily')
    end

    def daily_forecast_for(daily, index)
      {
        date: daily.fetch('time').fetch(index),
        weather_code: daily.fetch('weather_code').fetch(index),
        temperature_max: daily.fetch('temperature_2m_max').fetch(index),
        temperature_min: daily.fetch('temperature_2m_min').fetch(index),
        precipitation: daily.fetch('precipitation_sum').fetch(index),
        precipitation_probability: daily.fetch('precipitation_probability_max').fetch(index),
        wind_speed: daily.fetch('wind_speed_10m_max').fetch(index)
      }
    end

    def alerts_for(forecast)
      [].tap do |alerts|
        alerts << :precipitation_probability if forecast[:precipitation_probability].to_f >= thresholds[:precipitation_probability]
        alerts << :precipitation if forecast[:precipitation].to_f >= thresholds[:precipitation]
        alerts << :wind_speed if forecast[:wind_speed].to_f >= thresholds[:wind_speed]
        alerts << :temperature_high if forecast[:temperature_max].to_f >= thresholds[:temperature_high]
        alerts << :temperature_low if forecast[:temperature_min].to_f <= thresholds[:temperature_low]
      end
    end
  end
end
