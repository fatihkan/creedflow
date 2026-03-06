import Foundation
import GRDB

/// Tracks computed performance scores for each CLI backend, updated periodically
/// by BackendScoringService based on cost, speed, reliability, and quality metrics.
package struct BackendScore: Codable, Identifiable, Equatable {
    package var id: UUID
    package var backendType: CLIBackendType
    package var costEfficiency: Double
    package var speed: Double
    package var reliability: Double
    package var quality: Double
    package var compositeScore: Double
    package var sampleSize: Int
    package var updatedAt: Date

    package init(
        id: UUID = UUID(),
        backendType: CLIBackendType,
        costEfficiency: Double = 0.5,
        speed: Double = 0.5,
        reliability: Double = 0.5,
        quality: Double = 0.5,
        compositeScore: Double = 0.5,
        sampleSize: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.backendType = backendType
        self.costEfficiency = costEfficiency
        self.speed = speed
        self.reliability = reliability
        self.quality = quality
        self.compositeScore = compositeScore
        self.sampleSize = sampleSize
        self.updatedAt = updatedAt
    }
}

// MARK: - Persistence

extension BackendScore: FetchableRecord, PersistableRecord {
    package static let databaseTableName = "backendScore"
}
