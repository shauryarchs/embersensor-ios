import Foundation

nonisolated struct FireStatus: Codable, Sendable {
    let weatherTemperature: Double
    let sensorTemperature: Double
    let smoke: Double
    let flame: Int
    let humidity: Double
    let wind: Double
    let windDirection: Double
    let raining: Bool
    let condition: String
    let fireNearby: Bool
    let windTowardsHome: Bool
    let nearbyCount: Int
    let closestFireDistanceMiles: Double?
    let riskIndex: Int
}
