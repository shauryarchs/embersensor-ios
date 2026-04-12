import Foundation

nonisolated struct FireStatus: Codable, Sendable {
    let weatherTemperature: Double
    let sensorTemperature: Double?
    let smoke: Double?
    let flame: Int?
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
    let calfireNearby: Bool?
    let calfireCount: Int?
    let calfireFires: [CalFireIncident]?
    let scoreBreakdown: ScoreBreakdown?
    let generatedAt: String?
}

nonisolated struct ScoreBreakdown: Codable, Sendable {
    let sensorScore: Int
    let fireScore: Int
    let weatherScore: Int
    let windScore: Int
}

nonisolated struct CalFireIncident: Codable, Sendable {
    let name: String
    let distanceMiles: Double?
    let acresBurned: Int?
    let percentContained: Int?
    let state: String?
}
