import Foundation

public struct WeatherPlace: Codable, Equatable, Sendable {
    public var name: String
    public var admin: String?
    public var country: String?
    public var latitude: Double
    public var longitude: Double

    public init(name: String, admin: String? = nil, country: String? = nil, latitude: Double, longitude: Double) {
        self.name = name
        self.admin = admin
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
    }

    /// "Hanoi, Hanoi, Vietnam" without repeating a name.
    public var displayName: String {
        var parts = [name]
        if let admin, admin != name { parts.append(admin) }
        if let country { parts.append(country) }
        return parts.joined(separator: ", ")
    }
}

public struct DailyForecast: Equatable, Sendable {
    public var date: Date
    public var code: Int
    public var high: Double
    public var low: Double
    public var rainChance: Int?

    public init(date: Date, code: Int, high: Double, low: Double, rainChance: Int?) {
        self.date = date
        self.code = code
        self.high = high
        self.low = low
        self.rainChance = rainChance
    }
}

public struct WeatherReport: Equatable, Sendable {
    public var place: WeatherPlace
    public var temperature: Double
    public var feelsLike: Double
    public var humidity: Int
    public var windKph: Double
    public var code: Int
    public var isDay: Bool
    public var sunrise: String?   // "06:01", local time of the place
    public var sunset: String?
    public var daily: [DailyForecast]
    public var fetched: Date

    public init(place: WeatherPlace, temperature: Double, feelsLike: Double, humidity: Int, windKph: Double, code: Int,
                isDay: Bool, sunrise: String?, sunset: String?, daily: [DailyForecast], fetched: Date) {
        self.place = place
        self.temperature = temperature
        self.feelsLike = feelsLike
        self.humidity = humidity
        self.windKph = windKph
        self.code = code
        self.isDay = isDay
        self.sunrise = sunrise
        self.sunset = sunset
        self.daily = daily
        self.fetched = fetched
    }
}

public enum WeatherError: Error, LocalizedError {
    case badResponse
    case noResults

    public var errorDescription: String? {
        switch self {
        case .badResponse: "The weather service returned something unexpected"
        case .noResults: "No place found"
        }
    }
}

/// Weather from Open-Meteo (free, no API key). Needs internet on the Mac.
public enum WeatherService {
    public static func search(_ query: String) async throws -> [WeatherPlace] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: query), URLQueryItem(name: "count", value: "6"),
            URLQueryItem(name: "language", value: "en"), URLQueryItem(name: "format", value: "json"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return parseSearch(data)
    }

    public static func forecast(for place: WeatherPlace, fahrenheit: Bool) async throws -> WeatherReport {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try parseForecast(data, place: place)
    }

    // MARK: Parsing (pure, so it can be checked offline)

    public static func parseSearch(_ data: Data) -> [WeatherPlace] {
        struct Response: Decodable {
            struct Result: Decodable { let name: String; let latitude: Double; let longitude: Double; let country: String?; let admin1: String? }
            let results: [Result]?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return (response.results ?? []).map {
            WeatherPlace(name: $0.name, admin: $0.admin1, country: $0.country, latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    public static func parseForecast(_ data: Data, place: WeatherPlace, now: Date = Date()) throws -> WeatherReport {
        struct Response: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double; let relative_humidity_2m: Double; let apparent_temperature: Double
                let is_day: Int; let weather_code: Int; let wind_speed_10m: Double
            }
            struct Daily: Decodable {
                let time: [String]; let weather_code: [Int?]
                let temperature_2m_max: [Double?]; let temperature_2m_min: [Double?]
                let precipitation_probability_max: [Int?]?
                let sunrise: [String?]?; let sunset: [String?]?
            }
            let utc_offset_seconds: Int?
            let current: Current
            let daily: Daily
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw WeatherError.badResponse }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: response.utc_offset_seconds ?? 0)
        func clock(_ iso: String?) -> String? { iso.flatMap { $0.split(separator: "T").last.map(String.init) } }

        var days: [DailyForecast] = []
        for (index, day) in response.daily.time.enumerated() {
            guard let date = formatter.date(from: day),
                  index < response.daily.weather_code.count, let code = response.daily.weather_code[index],
                  let high = response.daily.temperature_2m_max[index], let low = response.daily.temperature_2m_min[index] else { continue }
            days.append(DailyForecast(date: date, code: code, high: high, low: low,
                                      rainChance: response.daily.precipitation_probability_max.flatMap { index < $0.count ? $0[index] : nil }))
        }
        return WeatherReport(
            place: place, temperature: response.current.temperature_2m, feelsLike: response.current.apparent_temperature,
            humidity: Int(response.current.relative_humidity_2m.rounded()), windKph: response.current.wind_speed_10m,
            code: response.current.weather_code, isDay: response.current.is_day == 1,
            sunrise: clock(response.daily.sunrise?.first ?? nil), sunset: clock(response.daily.sunset?.first ?? nil),
            daily: days, fetched: now)
    }

    /// WMO weather code to a short description and an SF Symbol name.
    public static func describe(code: Int, isDay: Bool = true) -> (text: String, symbol: String) {
        switch code {
        case 0: return isDay ? ("Clear", "sun.max") : ("Clear", "moon.stars")
        case 1: return ("Mostly clear", isDay ? "cloud.sun" : "cloud.moon")
        case 2: return ("Partly cloudy", isDay ? "cloud.sun" : "cloud.moon")
        case 3: return ("Overcast", "cloud")
        case 45, 48: return ("Fog", "cloud.fog")
        case 51, 53, 55: return ("Drizzle", "cloud.drizzle")
        case 56, 57: return ("Freezing drizzle", "cloud.sleet")
        case 61, 63: return ("Rain", "cloud.rain")
        case 65: return ("Heavy rain", "cloud.heavyrain")
        case 66, 67: return ("Freezing rain", "cloud.sleet")
        case 71, 73, 75, 77: return ("Snow", "cloud.snow")
        case 80: return ("Showers", "cloud.rain")
        case 81, 82: return ("Heavy showers", "cloud.heavyrain")
        case 85, 86: return ("Snow showers", "cloud.snow")
        case 95: return ("Thunderstorm", "cloud.bolt.rain")
        case 96, 99: return ("Thunderstorm, hail", "cloud.bolt.rain")
        default: return ("Unknown", "questionmark")
        }
    }

    /// A starting city from the Mac's time zone ("Asia/Ho_Chi_Minh" -> "Ho Chi Minh"), so the widget works before setup.
    public static func guessPlace() async -> WeatherPlace? {
        guard let city = TimeZone.current.identifier.split(separator: "/").last else { return nil }
        let query = city.replacingOccurrences(of: "_", with: " ")
        return try? await search(query).first
    }
}
