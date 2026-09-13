//
//  MisconceptionMappingModels.swift
//  VerbaDoc4
//
//  Core data model for the Misconception Mapping feature.
//  Architecture: the AI is the classifier, this schema + the mastery
//  algorithm are the learning system.
//

import Foundation
import SwiftData

// MARK: - Concept

@Model
final class Concept {
    @Attribute(.unique) var id: UUID
    var name: String
    var subject: String
    var conceptDescription: String

    // Store prerequisite/related concepts as arrays of IDs rather than
    // direct model references — avoids relationship-cycle headaches in
    // SwiftData and keeps the graph easy to reason about.
    var prerequisiteIDs: [UUID]
    var relatedConceptIDs: [UUID]

    @Relationship(deleteRule: .cascade, inverse: \Question.concept)
    var questions: [Question] = []

    @Relationship(deleteRule: .cascade, inverse: \StudentConcept.concept)
    var studentProgress: [StudentConcept] = []

    init(
        id: UUID = UUID(),
        name: String,
        subject: String,
        conceptDescription: String,
        prerequisiteIDs: [UUID] = [],
        relatedConceptIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.subject = subject
        self.conceptDescription = conceptDescription
        self.prerequisiteIDs = prerequisiteIDs
        self.relatedConceptIDs = relatedConceptIDs
    }
}

// MARK: - Question

enum QuestionDifficulty: String, Codable, CaseIterable {
    case easy
    case medium
    case hard

    /// Weight used by the mastery algorithm — harder questions move
    /// the needle more, in both directions.
    var weight: Double {
        switch self {
        case .easy: return 1.0
        case .medium: return 1.5
        case .hard: return 2.0
        }
    }
}

@Model
final class Question {
    @Attribute(.unique) var id: UUID
    var prompt: String
    var difficulty: QuestionDifficulty

    var correctAnswer: String
    var distractors: [String]

    // Concepts this question actually tests / leans on as prerequisites.
    var prerequisiteConceptIDs: [UUID]

    // Structured misconception tags, keyed by distractor text, so that
    // when a student picks a specific wrong answer we already know
    // which misconception it's associated with, before the AI even
    // classifies anything. The AI confirms/refines; this is the prior.
    var misconceptionTagsByDistractor: [String: String]

    var concept: Concept?

    init(
        id: UUID = UUID(),
        prompt: String,
        difficulty: QuestionDifficulty,
        correctAnswer: String,
        distractors: [String],
        prerequisiteConceptIDs: [UUID] = [],
        misconceptionTagsByDistractor: [String: String] = [:],
        concept: Concept? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.difficulty = difficulty
        self.correctAnswer = correctAnswer
        self.distractors = distractors
        self.prerequisiteConceptIDs = prerequisiteConceptIDs
        self.misconceptionTagsByDistractor = misconceptionTagsByDistractor
        self.concept = concept
    }
}

// MARK: - StudentConcept
//
// One row per (student, concept) — tracks mastery over time.
// Single-user app for now, so there's no separate Student model;
// if multi-profile support is ever added, add a `studentID` field.

@Model
final class StudentConcept {
    @Attribute(.unique) var id: UUID

    var concept: Concept?

    /// 0–100 mastery score. See MasteryCalculator for the update formula.
    var masteryScore: Double

    /// 0–1 confidence in the current mastery estimate — starts low,
    /// climbs as more attempts accumulate, so a single lucky guess
    /// doesn't read as "mastered."
    var confidence: Double

    var attempts: Int
    var correctAttempts: Int

    /// Timestamps of recent incorrect attempts, most recent last.
    /// Used to detect "repeated errors matter more."
    var recentErrorDates: [Date]

    var lastReviewed: Date?

    init(
        id: UUID = UUID(),
        concept: Concept? = nil,
        masteryScore: Double = 0,
        confidence: Double = 0,
        attempts: Int = 0,
        correctAttempts: Int = 0,
        recentErrorDates: [Date] = [],
        lastReviewed: Date? = nil
    ) {
        self.id = id
        self.concept = concept
        self.masteryScore = masteryScore
        self.confidence = confidence
        self.attempts = attempts
        self.correctAttempts = correctAttempts
        self.recentErrorDates = recentErrorDates
        self.lastReviewed = lastReviewed
    }

    var accuracy: Double {
        attempts == 0 ? 0 : Double(correctAttempts) / Double(attempts)
    }
}

// MARK: - Misconception

enum MisconceptionType: String, Codable, CaseIterable {
    case termConfusion          // e.g. mixing up NADH vs FADH2
    case processOrderError      // steps in the right idea, wrong sequence
    case causalMisattribution   // right effect, wrong cause
    case overgeneralization     // applying a rule outside its scope
    case other
}

@Model
final class Misconception {
    @Attribute(.unique) var id: UUID

    var concept: Concept?
    var type: MisconceptionType

    /// 0–1, how confident the classifier is that this misconception
    /// is actually what's going on (vs. a random mistake).
    var confidence: Double

    /// The raw evidence that led to this classification: the question
    /// asked, the student's answer, the expected answer, and the
    /// distractor selected — kept together so the classifier's
    /// reasoning can be inspected/debugged later.
    var evidenceQuestionID: UUID?
    var evidenceStudentAnswer: String
    var evidenceExpectedAnswer: String

    var relatedConceptIDs: [UUID]

    var detectedAt: Date
    var resolved: Bool

    init(
        id: UUID = UUID(),
        concept: Concept? = nil,
        type: MisconceptionType,
        confidence: Double,
        evidenceQuestionID: UUID? = nil,
        evidenceStudentAnswer: String,
        evidenceExpectedAnswer: String,
        relatedConceptIDs: [UUID] = [],
        detectedAt: Date = .now,
        resolved: Bool = false
    ) {
        self.id = id
        self.concept = concept
        self.type = type
        self.confidence = confidence
        self.evidenceQuestionID = evidenceQuestionID
        self.evidenceStudentAnswer = evidenceStudentAnswer
        self.evidenceExpectedAnswer = evidenceExpectedAnswer
        self.relatedConceptIDs = relatedConceptIDs
        self.detectedAt = detectedAt
        self.resolved = resolved
    }
}
