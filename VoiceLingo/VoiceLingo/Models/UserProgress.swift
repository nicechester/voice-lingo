import Foundation
import SwiftData

@Model
final class UserProgress {
    var languageCode: String
    var currentLevel: String
    var unlockedLevels: [String]
    var levelScores: [String: Double]
    @Relationship(deleteRule: .cascade, inverse: \PhraseProgress.userProgress)
    var phraseHistory: [PhraseProgress]
    var totalXP: Int

    init(
        languageCode: String,
        currentLevel: String = "A1",
        unlockedLevels: [String] = ["A1"],
        levelScores: [String: Double] = [:],
        phraseHistory: [PhraseProgress] = [],
        totalXP: Int = 0
    ) {
        self.languageCode = languageCode
        self.currentLevel = currentLevel
        self.unlockedLevels = unlockedLevels
        self.levelScores = levelScores
        self.phraseHistory = phraseHistory
        self.totalXP = totalXP
    }

    func updateLevelScore(_ levelId: String, score: Double) {
        levelScores[levelId] = score
        if score >= 0.8 && !unlockedLevels.contains(levelId) {
            unlockedLevels.append(levelId)
        }
    }

    func recordPhrase(_ phraseId: String, correct: Bool) {
        var progress = phraseHistory.first { $0.phraseId == phraseId }

        if progress == nil {
            progress = PhraseProgress(phraseId: phraseId, userProgress: self)
            phraseHistory.append(progress!)
        }

        if let progress = progress {
            if correct {
                progress.correctCount += 1
                progress.interval *= 2
                totalXP += 10
            } else {
                progress.incorrectCount += 1
                progress.interval = 1
            }
            progress.lastAttempt = Date()
        }
    }

    func phraseProgress(for phraseId: String) -> PhraseProgress? {
        phraseHistory.first { $0.phraseId == phraseId }
    }
}

@Model
final class PhraseProgress {
    var phraseId: String
    var correctCount: Int
    var incorrectCount: Int
    var interval: Int
    var lastAttempt: Date?
    var nextReviewDate: Date
    var userProgress: UserProgress?

    init(phraseId: String, userProgress: UserProgress? = nil) {
        self.phraseId = phraseId
        self.correctCount = 0
        self.incorrectCount = 0
        self.interval = 1
        self.lastAttempt = nil
        self.nextReviewDate = Date()
        self.userProgress = userProgress
    }

    var accuracy: Double {
        let total = correctCount + incorrectCount
        guard total > 0 else { return 0 }
        return Double(correctCount) / Double(total)
    }

    var isDue: Bool {
        Date() >= nextReviewDate
    }

    func updateInterval(correct: Bool) {
        if correct {
            interval *= 2
        } else {
            interval = 1
        }
        nextReviewDate = Calendar.current.date(byAdding: .day, value: interval, to: Date()) ?? Date()
    }
}
