//
//  WeatherService.swift
//  Weather
//
//  Created by Pierluigi Galdi on 20/06/21.
//  Copyright © 2021 Pierluigi Galdi. All rights reserved.
//
//  Updated: replaced the defunct weather.navalia.app backend with the Open-Meteo API
//  (https://open-meteo.com): free, no API key required.
//

import Foundation
import CoreLocation
import AppKit

struct Weather: Codable {
    let name: String
    let temp: Double // always Fahrenheit; converted for display in `temperature`
    let icon: String
    let description: String
    var temperature: String {
        guard temp > -999 else {
            return "Unknown information"
        }
        let units: String = Preferences[.units]
        switch units {
        case "celsius":
            let converted = (temp - 32) * (5/9)
            return "\(Int(converted.rounded()))°"
        default:
            return "\(Int(temp.rounded()))°"
        }
    }
}

struct WeatherData: Codable {
    struct Metadata: Codable {
        let error: String?
        let code: Int
    }
    let metadata: Metadata
    let weather: Weather
    private enum CodingKeys: String, CodingKey {
        case weather = "data", metadata
    }
}

/// Open-Meteo `current` response (only the fields we use).
private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let is_day: Int
    }
    let current: Current
}

internal class WeatherService {
    
    /// Maps a WMO weather code to one of the bundled icon names (01d…50n) and a short description.
    private func condition(for code: Int, isDay: Bool) -> (icon: String, description: String) {
        let suffix = isDay ? "d" : "n"
        switch code {
        case 0:             return ("01\(suffix)", "Clear sky")
        case 1:             return ("02\(suffix)", "Mainly clear")
        case 2:             return ("03\(suffix)", "Partly cloudy")
        case 3:             return ("04\(suffix)", "Overcast")
        case 45, 48:        return ("50\(suffix)", "Fog")
        case 51, 53, 55:    return ("09\(suffix)", "Drizzle")
        case 56, 57:        return ("09\(suffix)", "Freezing drizzle")
        case 61:            return ("10\(suffix)", "Light rain")
        case 63:            return ("10\(suffix)", "Rain")
        case 65:            return ("10\(suffix)", "Heavy rain")
        case 66, 67:        return ("10\(suffix)", "Freezing rain")
        case 71:            return ("13\(suffix)", "Light snow")
        case 73:            return ("13\(suffix)", "Snow")
        case 75:            return ("13\(suffix)", "Heavy snow")
        case 77:            return ("13\(suffix)", "Snow grains")
        case 80, 81, 82:    return ("09\(suffix)", "Rain showers")
        case 85, 86:        return ("13\(suffix)", "Snow showers")
        case 95:            return ("11\(suffix)", "Thunderstorm")
        case 96, 99:        return ("11\(suffix)", "Thunderstorm with hail")
        default:            return (NSImage.touchBarSearchTemplateName, "Unknown conditions")
        }
    }
    
    private func fallback(code: Int, error: String?) -> WeatherData {
        let name: String = Preferences[.city_name]
        return WeatherData(
            metadata: .init(error: error, code: code),
            weather: Weather(
                name: name,
                temp: -999,
                icon: NSImage.touchBarSearchTemplateName,
                description: "Unknown information"
            )
        )
    }
    
    func currentConditions(for coordinate: CLLocationCoordinate2D, cityName: String, result: @escaping (WeatherData?) -> Void) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else {
            print("[WeatherService]: Invalid URL")
            result(nil)
            return
        }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -999
            print("[WeatherService]: \(status)")
            guard let self = self else { return }
            guard error == nil, status == 200, let data = data else {
                result(self.fallback(code: status, error: error?.localizedDescription))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
                let mapped = self.condition(for: decoded.current.weather_code, isDay: decoded.current.is_day == 1)
                let weather = Weather(
                    name: cityName,
                    temp: decoded.current.temperature_2m,
                    icon: mapped.icon,
                    description: mapped.description
                )
                result(WeatherData(metadata: .init(error: nil, code: status), weather: weather))
            } catch {
                print("[WeatherService]: Decoding failed: \(error)")
                result(self.fallback(code: status, error: error.localizedDescription))
            }
        }
        task.resume()
    }
    
}
