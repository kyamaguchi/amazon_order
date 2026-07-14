require 'spec_helper'

RSpec.describe AmazonOrder::RacecourseWeatherMonitor do
  let(:daily_response) do
    {
      'daily' => {
        'time' => ['2026-07-14'],
        'weather_code' => [61],
        'temperature_2m_max' => [36.2],
        'temperature_2m_min' => [24.1],
        'precipitation_sum' => [8.4],
        'precipitation_probability_max' => [70],
        'wind_speed_10m_max' => [13.5]
      }
    }
  end

  before do
    response = double('response', body: JSON.dump(daily_response), code: '200', message: 'OK')
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(Net::HTTP).to receive(:get_response).and_return(response)
  end

  describe '#weather_for' do
    it 'returns weather details and threshold alerts for a racecourse' do
      weather = described_class.new.weather_for(:tokyo)

      expect(weather).to include(
        key: 'tokyo',
        name: '東京競馬場',
        forecast_date: '2026-07-14',
        weather_code: 61,
        precipitation_probability: 70,
        precipitation: 8.4,
        wind_speed: 13.5,
        temperature_max: 36.2,
        temperature_min: 24.1
      )
      expect(weather[:alerts]).to contain_exactly(
        :precipitation_probability,
        :precipitation,
        :wind_speed,
        :temperature_high
      )
    end

    it 'requests the Open-Meteo daily forecast for the racecourse coordinates' do
      described_class.new.weather_for('kyoto')

      expect(Net::HTTP).to have_received(:get_response) do |requested_uri|
        query = URI.decode_www_form(requested_uri.query).to_h
        expect(requested_uri.to_s).to start_with(described_class::DEFAULT_API_ENDPOINT)
        expect(query['latitude']).to eq('34.9069')
        expect(query['longitude']).to eq('135.7247')
        expect(query['timezone']).to eq('Asia/Tokyo')
        expect(query['forecast_days']).to eq('1')
      end
    end

    it 'raises a useful error for unknown racecourses' do
      expect { described_class.new.weather_for(:unknown) }
        .to raise_error(ArgumentError, 'unknown racecourse: unknown')
    end
  end

  describe '#alerts' do
    it 'filters monitored racecourses to entries that have alerts' do
      monitor = described_class.new(thresholds: { precipitation_probability: 80, precipitation: 10, wind_speed: 20, temperature_high: 40 })
      expect(monitor.alerts([:tokyo])).to be_empty

      monitor = described_class.new(thresholds: { precipitation_probability: 60 })
      expect(monitor.alerts([:tokyo]).map { |weather| weather[:key] }).to eq(['tokyo'])
    end
  end
end
