import Foundation

nonisolated struct FireStatus: Codable, Sendable {
    let temperature: Double
    let smoke: Double
    let flame: Int
    let humidity: Int
    let wind: Double
    let raining: Bool
    let condition: String
    let fireDetected: Bool
}
