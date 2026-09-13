import Foundation

// MARK: - StudyGenPrompts
//
// Prompt construction for the five generation modes. Kept separate from
// the service so the exact wording is reviewable and unit-testable
// without a network call.
//
// Three deliberate changes from the first draft of this pipeline:
//
//  1. EVERY prompt now ends with an explicit "no prose, no markdown
//     fences" instruction. The decoder tolerates both
//     (`StudyGenJSON`), but tolerance is a safety net, not the plan —
//     fences and preambles burn tokens and occasionally confuse the
//     bracket extraction.
//
//  2. The multiple-choice schema carries a `misconception` tag on each
//     distractor. This is what connects generation to the Misconception
//     Mapping engine: without it, a wrong answer is only "wrong", and
//     `Misconception.swift` has nothing to record. This is the single
//     most important schema decision in this file.
//
//  3. Counts are clamped. `count: 0` or a negative from a caller
//     produces a confusing model reply, not an error.

enum StudyGenPrompts {

    /// Shared system prompt. Short, and it restates the only rule that
    /// matters — because a system prompt is followed far more reliably
    /// than a trailing instruction.
    static let system = """
    You generate study material as strict JSON for an iOS study app. \
    You reply with JSON only — no prose, no explanation, no markdown code \
    fences. Every field matches the requested schema exactly. If the \
    source notes don't support a requested item, return fewer items \
    rather than inventing content.
    """

    // MARK: Flashcards

    /// Flashcards: extract real terms, answers capped at 1–4 words.
    static func flashcards(noteText: String, count: Int = 10) -> String {
        let n = max(1, count)
        return """
        You are extracting flashcard material from a student's study notes below.

        Rules:
        - Pick \(n) of the most important TERMS, VOCAB WORDS, or NAMED CONCEPTS \
        that actually appear in the notes (things that are defined, bolded, capitalized, \
        or clearly a key concept) — do not invent terms that aren't in the notes.
        - The "answer" field must be 1 to 4 WORDS MAX. Never a sentence. Never an explanation. \
        If the true answer needs more than 4 words, pick a shorter, more specific term instead.
        - Do not make generic definition-style flashcards ("What is X? X is a thing that..."). \
        The term IS the front. The short answer/value/definition-in-a-few-words IS the back.
        - Return fewer than \(n) items if the notes don't contain \(n) real terms.

        Return ONLY valid JSON, an array of objects shaped like:
        [{"term": "...", "answer": "..."}]
        No prose. No markdown code fences. No explanation before or after the JSON.

        NOTES:
        \(noteText)
        """
    }

    // MARK: Multiple choice

    /// Multiple choice: real same-domain distractors, each tagged with
    /// the specific misconception it represents.
    static func multipleChoice(noteText: String, count: Int = 5) -> String {
        let n = max(1, count)
        return """
        Create \(n) multiple choice questions from the study notes below.

        Rules:
        - Each question must have exactly 4 options.
        - The 3 wrong options (distractors) MUST be other real terms/values/names that \
        appear elsewhere in these same notes — never made-up or unrelated wrong answers. \
        This is what makes it a real test of recognition instead of a guessing game.
        - Do not use "All of the above" or "None of the above."
        - Keep each option short — a word, name, or short phrase, matching the style of \
        the correct answer.
        - For each WRONG option, fill "misconception" with a SHORT phrase naming the exact \
        confusion a student would have if they chose it (for example: "confuses NADH with \
        FADH2", "thinks ATP is produced in the cytoplasm"). Set "misconception" to null for \
        the correct option. This is used to diagnose what the student misunderstands, so it \
        must describe a specific error, not "wrong answer".
        - Return fewer than \(n) questions if the notes don't support them.

        Return ONLY valid JSON, an array shaped like:
        [{"question": "...", "options": [{"text": "...", "misconception": "..."}, \
        {"text": "...", "misconception": "..."}, {"text": "...", "misconception": null}, \
        {"text": "...", "misconception": null}], "correctIndex": 0}]
        No prose. No markdown code fences. No explanation before or after the JSON.

        NOTES:
        \(noteText)
        """
    }

    // MARK: Free response

    /// Free response: a question plus the short rubric used to grade it.
    static func freeResponse(noteText: String, count: Int = 3) -> String {
        let n = max(1, count)
        return """
        Create \(n) short-answer free response questions from the study notes below.

        Rules:
        - Each question should require a 1-3 sentence answer from the student, not a single word.
        - For each question, also provide 2-4 short "keyPoints" — the specific facts or ideas \
        a correct answer needs to include. These will be used to grade the student's answer, \
        so keep each keyPoint concrete and checkable (a fact, not a vague theme).
        - A keyPoint must be a single short phrase (under ~12 words). "It relates to energy" \
        is not checkable; "produces 2 ATP per glucose" is.

        Return ONLY valid JSON, an array shaped like:
        [{"question": "...", "keyPoints": ["...", "..."]}]
        No prose. No markdown code fences. No explanation before or after the JSON.

        NOTES:
        \(noteText)
        """
    }

    // MARK: Grading

    /// Grades a student's answer against the rubric.
    ///
    /// Returns hit/miss lists only — no score field, because the score is
    /// computed in code from these lists (`FreeResponseGrade.score`) so
    /// partial credit can't disagree with the model's own rubric.
    static func grade(question: String, keyPoints: [String], studentAnswer: String) -> String {
        """
        Grade this student's short answer against the rubric below.

        QUESTION: \(question)
        RUBRIC (key points a good answer should hit): \(keyPoints.joined(separator: "; "))
        STUDENT'S ANSWER: \(studentAnswer)

        Rules:
        - Put each rubric point the answer genuinely addresses in "pointsHit" — \
        quote the rubric point, don't paraphrase it, and don't invent new points.
        - Put every remaining rubric point in "pointsMissed".
        - Do not award a point for something the student didn't say, even if it's implied.
        - "feedback" is one or two short, encouraging sentences naming exactly what to add. \
        Never generic ("needs more detail") — say which point is missing.

        Return ONLY valid JSON shaped like:
        {"pointsHit": ["..."], "pointsMissed": ["..."], "feedback": "..."}
        No prose. No markdown code fences. No explanation before or after the JSON.
        """
    }

    // MARK: Notes outline

    /// Notes view: organize the raw text instead of dumping it, with a
    /// glossary of extracted terms.
    static func outline(noteText: String) -> String {
        """
        Organize the raw extracted text below into a clean study outline.

        Rules:
        - Group content under short, specific headings (not "Section 1", "Introduction").
        - Bullets under each heading should be concise — facts, not restated paragraphs.
        - Separately, build a glossary of the 5-10 most important terms, each with a \
        1-4 word answer/definition (same short format as flashcards).
        - Use only content present in the text. Don't add outside knowledge.

        Return ONLY valid JSON shaped like:
        {"sections": [{"heading": "...", "bullets": ["...", "..."]}], \
        "glossary": [{"term": "...", "answer": "..."}]}
        No prose. No markdown code fences. No explanation before or after the JSON.

        RAW TEXT:
        \(noteText)
        """
    }

    // NOTE: there is deliberately no `quiz(...)` prompt-bundling helper
    // here. The first draft of this pipeline had a `build(...)` that
    // returned three prompt STRINGS while presenting itself as building
    // a `QuizSession` — a lie the compiler couldn't catch, and one that
    // would have shipped a session with no items in it.
    //
    // Quiz assembly lives in `StudyGenService.quiz(from:)`, which sends
    // the three prompts and returns an actual, populated session.
}

// MARK: - Context sampling
//
// Generation needs COVERAGE; retrieval needs RELEVANCE. Feeding a
// generator the top-3 query matches would produce ten flashcards about
// one paragraph. This samples across the whole document instead, within
// a character budget the model can actually accept.

enum StudyGenContext {

    /// Evenly-spaced sample of `chunks` bounded by `maxCharacters`.
    ///
    /// Pure and deterministic, so it's unit-testable without a network
    /// call or a store.
    static func sample(from chunks: [String], maxCharacters: Int = 6_000) -> String {
        let usable = chunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !usable.isEmpty, maxCharacters > 0 else { return "" }

        let totalCharacters = usable.reduce(0) { $0 + $1.count }
        let average = max(1, totalCharacters / usable.count)
        // How many chunks fit, then walk that many evenly across the doc.
        let wanted = max(1, min(usable.count, maxCharacters / average))
        let step = max(1, usable.count / wanted)

        var picked: [String] = []
        var used = 0
        var index = 0
        while index < usable.count {
            let chunk = usable[index]
            guard used + chunk.count <= maxCharacters else { break }
            picked.append(chunk)
            used += chunk.count
            index += step
        }
        if picked.isEmpty {
            // A single chunk larger than the budget: truncate rather than
            // return nothing, so generation still has material.
            return String(usable[0].prefix(maxCharacters))
        }
        return picked.joined(separator: "\n\n")
    }
}
