import Foundation
import CoreLocation

struct FirePoint: Codable, Identifiable, Sendable {
    let latitude: Double
    let longitude: Double
    let brightness: Double?
    let confidence: String?
    let satellite: String?
    let acquiredDate: String?
    let acquiredTime: String?

    var id: String {
        "\(latitude)-\(longitude)-\(acquiredDate ?? "")-\(acquiredTime ?? "")"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case brightness
        case confidence
        case satellite
        case acquiredDate
        case acquiredTime
    }
}

struct FiresResponse: Codable, Sendable {
    let count: Int
    let fires: [FirePoint]
    let firmsSource: String?
    let generatedAt: String?
}
