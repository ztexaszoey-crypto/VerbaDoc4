import Foundation

// MARK: - TeacherBlueprint (Phase 17 overhaul)
//
// The VerbaDoc AI generation pipeline. The previous version shipped
// four single-product directives that roughly demanded "do not copy".
// This version enforces a real 4-stage pipeline that the model MUST
// walk through internally before emitting anything:
//
//   STAGE 1 — ANALYZE  : identify concepts, relationships, definitions,
//                        processes, chronology, cause/effect, comparisons,
//                        examples, and rank importance by exam-yield.
//   STAGE 2 — REPRESENT: build an internal knowledge representation in
//                        the model's own wording. FORGET the source
//                        phrasing. Remember only the knowledge.
//   STAGE 3 — GENERATE : write ORIGINAL artefacts. Nothing is a copy,
//                        nothing is a paraphrase, nothing is fill-in-
//                        the-blank, nothing references the document.
//   STAGE 4 — EVALUATE : self-grade every artefact. Reject anything
//                        that copies, paraphrases, contains cloze,
//                        trivial detail, or weak reasoning. Regenerate.
//
// The model is told that the artefact bundle returned to the user is
// the ONLY output the user will ever see; everything in STAGES 1-4
// stays in private reasoning.
//
// Two layered defences
// ────────────────────
// The model is supposed to honour these rules. Sometimes it slips.
// A second-line client-side `QualityValidator` (see
// `Services/QualityValidator.swift`) catches the residue after JSON
// parse. The two systems together drive the verbatim score down to
// ~0% and zero out cloze emissions.

enum TeacherBlueprint {

    // MARK: - Difficulty
    //
    // Six difficulty levels. Each rewrites the model's vocabulary
    // register, example-types, and conceptual depth, so a history of
    // the Roman Republic for Elementary reads very differently from
    // the same content for Graduate. The default is `.highSchool`
    // because that's the median examinee; SettingsView can offer
    // the user a one-tap coarse-to-fine switch.

    public enum Difficulty: String, Codable, CaseIterable {
        case elementary  = "elementary"
        case middle      = "middle"
        case highSchool  = "high_school"
        case ap          = "ap"
        case college     = "college"
        case graduate    = "graduate"

        public var promptFragment: String {
            switch self {
            case .elementary:
                return """
                DIFFICULTY: ELEMENTARY.

                Vocabulary register: short, concrete, everyday English.
                Example types: family scenes, schoolyard, kitchen, animals,
                weather, playtime.
                Question register: simple present tense, no jargon,
                short sentences. Avoid abstract reasoning; favour
                concrete cause→observable-effect chains.
                """
            case .middle:
                return """
                DIFFICULTY: MIDDLE SCHOOL.

                Vocabulary register: plain language; technical words are
                allowed but must be defined inline ("…a hypothesis, a
                tentative explanation…").
                Example types: classroom, friendships, sports, family,
                local community.
                Question register: multi-clause questions, one inferential
                step required per question.
                """
            case .highSchool:
                return """
                DIFFICULTY: HIGH SCHOOL.

                Vocabulary register: standard academic, technical terms
                used without re-definition.
                Example types: history, science, literature, civics.
                Question register: 8th-12th grade exam style. Mix of
                recall, application, and analysis.
                """
            case .ap:
                return """
                DIFFICULTY: AP / ADVANCED PLACEMENT.

                Vocabulary register: college-prep academic, discipline-
                specific terminology expected.
                Example types: AP exam items (US History, Biology,
                Literature, Psychology, etc.).
                Question register: AP-style stems with realistic
                distractors that mirror common student misconceptions.
                """
            case .college:
                return """
                DIFFICULTY: COLLEGE INTRODUCTORY.

                Vocabulary register: introductory college, tightly
                technical where necessary, no hand-holding.
                Example types: textbook scenarios, brief case studies,
                primary-source quotations.
                Question register: college-exam style (midterm/final);
                integrate multiple sources of information; require
                2-3 reasoning steps per question.
                """
            case .graduate:
                return """
                DIFFICULTY: GRADUATE / PROFESSIONAL.

                Vocabulary register: discipline-fluent; assume the reader
                knows the field.
                Example types: journal-article abstracts, case law,
                primary-source extended quotations.
                Question register: synthesise across the entire source;
                require multi-source integration and critical evaluation.
                """
            }
        }

        public var displayTitle: String {
            switch self {
            case .elementary: return "Elementary"
            case .middle:     return "Middle school"
            case .highSchool: return "High school"
            case .ap:         return "AP"
            case .college:    return "College"
            case .graduate:   return "Graduate"
            }
        }
    }

    // MARK: - Universal 4-stage pipeline
    //
    // Prepended to every product-specific directive. Forces the model
    // to walk through internal reasoning BEFORE generating anything.
    // The wrapper is short enough to fit comfortably in the Edge
    // Function's prompt-cost budget; the per-product directives
    // underneath plug into this same skeleton.

    public static let contentQualityPreamble: String = """
    [HIDDEN INTERNAL REASONING — DO NOT OUTPUT IN FINAL ANSWER]

    Before producing any artefact in the schema below, internally
    walk through the following four stages. DO NOT include any
    reasoning text in the JSON output — only the final artefacts.

    STAGE 1 — ANALYZE.

      Read the entire source text. Identify:

        A. Main topics and subtopics.
        B. Important concepts (definitions, theorems, formulas).
        C. Relationships (cause→effect, A→B, X vs Y, sequence steps).
        D. Timelines (dates and events, if historical).
        E. People / places / terms that recur and matter.
        F. Frequently-tested ideas: definitions, named people,
           formulas, dates, citation specifics, exceptions,
           counter-intuitive facts.
        G. Concepts that require UNDERSTANDING rather than recall.
        H. Connections the learner must make across paragraphs.

      Rank every concept by EXAM YIELD. Skip trivia, filler,
      "nice to know" content. Skip textbook introductions and
      recap sections.

    STAGE 2 — REPRESENT.

      Build an INTERNAL knowledge representation in YOUR OWN
      WORDS. Forget the source text's phrasing. Remember only
      THE KNOWLEDGE. Imagine explaining every concept to another
      teacher without ever looking back at the document.

    STAGE 3 — GENERATE.

      Produce ORIGINAL artefacts. NEVER copy a sentence from the
      source. NEVER paraphrase. NEVER replace a word with a blank.
      NEVER begin a question with "According to the document…",
      "The passage states…", "Based on the text…". Every artefact
      MUST feel like a teacher wrote it; a learner who never read
      the source should still be able to learn from the artefacts.

    STAGE 4 — EVALUATE.

      Before returning each artefact, self-grade:

        · Did I copy ANY phrase from the source? → REJECT and rewrite.
        · Did I paraphrase closely? → REJECT and rewrite.
        · Is there a fill-in-the-blank? → REJECT and rewrite.
        · Does this artefact require UNDERSTANDING, not just
          recognition? → Keep only if yes.
        · Would a teacher be proud to put this on an exam? → Keep
          only if yes.

      Repeat until every artefact passes. Quantity is NOT the
      goal — quality is. 20 excellent artefacts always beat 200
      mediocre ones.

    OUTPUT RULES:
      · Return ONLY the JSON in the schema provided below.
      · DO NOT include any reasoning text, headers, or analysis.
      · DO NOT include markdown code fences. The schema is JSON only.
      · DO NOT include commentary AFTER the JSON.
    """

    // MARK: - Flashcards (Phase 17)
    //
    // Card subtypes the user asked for: definition, detail,
    // relationship, process, formula, application. We additionally
    // force a token cause-effect card subtype because the user
    // explicitly mentioned "compare / cause and effect / contrast"
    // in the spec.

    public static let flashcardsDirective: String = """
    PRODUCT: FLASHCARDS.

    PURPOSE: Active recall and concept understanding. Cards are NOT
    copied textbook sentences. Cards are NOT fill-in-the-blank
    cloze deletions. Every card is a complete Q&A pair produced
    from YOUR UNDERSTANDING of the source — not from its wording.

    Produce cards from the following subtypes ONLY. Vary across
    subtypes; do not stack the same subtype:

      1. DEFINITION / CONCEPT.
          Front: phrased as "What is … ?", "What does … mean?",
                 "Define … in your own words."
          Back:  plain-language explanation in YOUR OWN WORDS.

      2. IMPORTANT DETAIL.
          Front: "What is significant about [date|event|person]?",
                 "Why is [fact] important?"
          Back:  the fact + WHY it matters (one or two sentences).

      3. RELATIONSHIP / CAUSE-EFFECT.
          Front: "How does [A] lead to [B]?",
                 "What is the relationship between [X] and [Y]?"
          Back:  the connection stated in YOUR OWN WORDS.

      4. PROCESS / STEPS.
          Front: "What are the steps of [process]?",
                 "Outline the sequence in which [thing] occurs."
          Back:  ordered, numbered steps in YOUR OWN WORDS.

      5. FORMULA / APPLICATION.
          Front: "When would you use [formula|method]?",
                 "Apply [rule] to [scenario]."
          Back:  explanation + one worked example (in YOUR words).

      6. COMPARISON / CONTRAST.
          Front: "Compare [X] and [Y].", "How does [X] differ from [Y]?"
          Back:  the comparison in plain language, no copied text.

      7. PREDICTION / HYPOTHETICAL.
          Front: "What would happen if [scenario]?",
                 "Predict the outcome when [condition]."
          Back:  reasoned expectation, not a quote from the source.

    BAN LIST (REJECT AND REGENERATE ANY CARD THAT VIOLATES):

      · Cloze deletions or "____" patterns — NEVER.
      · Copied sentences from the source.
      · Sentences that begin with "According to the document,",
        "As stated in the passage,", "The text says,", "The
        chapter explains,", "Based on the PDF,", etc.
      · Cards where the answer is obvious from the question.
      · Trivia (meaningless dates, names without consequence).
      · Cards whose answer is merely the definition copied from
        a glossary entry — paraphrase the definition.

    SCHEMA (return ONLY this JSON; omit any cardType that you
    cannot fill out authentically):
    {
      "cards": [
        { "question":     String,
          "answer":       String,
          "topic":        String?,
          "cardType":     "definition" | "detail" | "relationship"
                        | "process" | "formula" | "comparison"
                        | "prediction"
        }, …
      ]
    }
    """

    // MARK: - Multiple Choice (Phase 17)

    public static let multipleChoiceDirective: String = """
    PRODUCT: MULTIPLE-CHOICE QUIZ.

    PURPOSE: Exam preparation. Each question tests REASONING the
    way a real AP / SAT / college exam would — never recognition,
    never trivia.

    REQUIREMENTS:

      · Exactly 4 choices, labelled A / B / C / D.
      · Exactly ONE correct answer.
      · Distractors must represent COMMON STUDENT MISCONCEPTIONS
        (confusing similar terms, swapping cause/effect, picking
        the obvious-but-incomplete answer). Distractors should
        be plausible to a student who half-understands the topic.
      · Question stem must require thinking. NEVER use fill-in-
        the-blANK or true/false wording. NEVER begin with
        "According to the document…", "The passage states…".
      · NEVER use "All of the above" or "None of the above" as a
        choice. The directive forbids both; QualityValidator
        downstream also blocks them.
      · Vary difficulty across the question set: recall, application,
        analysis, comparison, inference.

    GOOD STEM: "Which factor most directly caused the Compromise
    of 1877 to end Reconstruction?"
    BAD STEM:  "Fill in the blank: The Compromise of ____ ended
    Reconstruction."
    BAD STEM:  "According to the passage, what year did …?"

    After EACH question include:

      · `explanation`: 2-3 sentence rationale for WHY the correct
        answer is correct.
      · `whyWrong`: dict keyed by option index ("0","1","2","3")
        with a 1-2 sentence rationale for WHY that distractor
        is wrong (one entry per WRONG option; omit the correct
        one).

    SCHEMA (return ONLY this JSON; nothing else):
    {
      "questions": [
        { "question":            String,
          "options":             [String, String, String, String],
          "correctIndex":        0 | 1 | 2 | 3,
          "explanation":         String,
          "whyWrong":            { "<index>": String, … },
          "topic":               String?,
          "commonMisconception": String?  // e.g. "swaps cause and effect".
        }, …
      ]
    }
    """

    // MARK: - Open Answer (Phase 17)
    //
    // Rubric schema is now MUCH richer — see OpenAnswerRubric
    // below. The AI must include ideal-answer points, a scoring
    // rubric, and common student mistakes per question. This is
    // what enables the iOS grading screen to score answers
    // semantically rather than via string-equality.

    public static let openAnswerDirective: String = """
    PRODUCT: OPEN-ANSWER QUIZ.

    PURPOSE: Deeper understanding through composed answers.

    Question stems only from the following verbs / patterns:

      · Explain why …
      · Compare … and …
      · Analyze how …
      · Predict what would happen if …
      · Evaluate the significance of …
      · Describe the relationship between …
      · Discuss the causes / consequences of …
      · Justify why …

    REQUIREMENTS:

      · NEVER a yes/no question.
      · NEVER a question answerable in one word.
      · The prompt must synthesise LARGE SECTIONS of the source
        (or the entire source). One question per major topic.
      · Your `modelAnswer` must be written IN YOUR OWN WORDS,
        not copied from the source.

    For each question, return a complete grading RUBRIC:

      · `keyConcepts`: 3-5 must-mention concepts; the learner
        receives credit per concept hit, regardless of exact
        phrasing. (Required.)
      · `idealPoints`: 3-5 bullet points that should appear in
        an ideal answer. (Required.)
      · `scoringRubric`: { "0": "no credit", "1": "partial",
                            "2": "good", "3": "excellent" } keyed
        by integer scores 0-3. (Required.)
      · `commonMistakes`: 1-3 typical student errors for this
        question. (Required.)
      · `expectedAnswer`: a model answer example (in YOUR
        wording, not the source's).

    SCHEMA (return ONLY this JSON; nothing else):
    {
      "questions": [
        { "question":         String,
          "expectedAnswer":   String,
          "keyConcepts":      [String, …],
          "idealPoints":      [String, …],
          "scoringRubric":    { "0": String, "1": String,
                                 "2": String, "3": String },
          "commonMistakes":   [String, …],
          "topic":            String?
        }, …
      ]
    }
    """

    // MARK: - Study Guide (Phase 17)
    //
    // Heavier schema: the guide now requires a `quickReviewChecklist`,
    // a `frequentlyConfusedPairs` list, and a complete `markdownBody`
    // that renders with headings, subheadings, bullets, numbered
    // processes, comparison tables, and an end-of-guide summary
    // TABLE. This is what the iOS guide view renders with a
    // Markdown parser.

    public static let studyGuideDirective: String = """
    PRODUCT: STUDY GUIDE.

    PURPOSE: Teach the TOPIC from your understanding. The guide
    MUST be a study artefact a learner could master the topic
    from WITHOUT re-reading the source. NEVER paraphrase the
    source in paragraphs; REWRITE the knowledge in your own
    explanatory style.

    Produce a structured document with the following sections.
    Skip a section ONLY when genuinely inapplicable (e.g.
    timeline on a non-historical topic):

      1. BIG-PICTURE OVERVIEW
         A plain-language opening paragraph explaining the topic
         in YOUR OWN WORDS as if to a smart friend.

      2. KEY CONCEPTS
         3-7 entries. Each concept has a name AND a 2-4 sentence
         explanation in YOUR OWN WORDS.

      3. TIMELINE (history only — skip otherwise)
         Chronological dates + events. Each entry is its own
         object {date, event}.

      4. IMPORTANT PEOPLE / TERMS
         Who/what they are and WHY they matter. Each entry is
         its own object {name, description}.

      5. CAUSE AND EFFECT
         How ideas or events connect. Each entry is its own
         object {cause, effect}. Aim for 3-6 chains.

      6. COMMON MISTAKES
         Things students often misunderstand. Each entry should
         say WHAT they get wrong AND what the correction is.
         3-6 entries.

      7. EXAM CHECKLIST
         "What you should know before the test." A bulleted list
         of testable facts and skills. 5-10 entries.

      8. QUICK-REVIEW CHECKLIST
         A short list of 3-7 most-critical concepts to memorise
         the night before the exam.

      9. FREQUENTLY CONFUSED PAIRS
         Pairs of concepts students commonly confuse. Each
         entry is {conceptA, conceptB, clarification}.

      10. MARKDOWN BODY (REQUIRED)
          A fully-rendered MARKDOWN version of the guide with:
            · `##` topic headings,
            · `###` subheadings,
            · categorised bullet lists of causes/effects,
            · **bold** key terms,
            · numbered processes,
            · at least one COMPARISON TABLE marked up as
              `| term | definition | … |`,
            · a final quick-glossary table.

          This body MUST be self-consistent with the structured
          fields above. NEVER direct the reader to "review chapter
          X pages Y–Z". EVERY sentence must come from YOUR wording,
          not the source's.

    TONE: high-end note app · modern textbook · Apple-grade prose.
    No emoji. No marketing tone. No filler phrases. No "in
    conclusion" padding.

    SCHEMA (return ONLY this JSON; nothing else):
    {
      "guide": {
        "title":                   String,
        "overview":                String,
        "keyConcepts":             [ { "name": String,
                                       "explanation": String }, … ],
        "timeline":                [ { "date": String,
                                       "event":  String }, … ],
        "peopleTerms":             [ { "name": String,
                                       "description": String }, … ],
        "causeEffect":             [ { "cause": String,
                                       "effect":  String }, … ],
        "commonMistakes":          [String, …],
        "examChecklist":           [String, …],
        "quickReviewChecklist":    [String, …],
        "frequentlyConfusedPairs": [ { "conceptA":     String,
                                       "conceptB":     String,
                                       "clarification": String }, … ],
        "markdownBody":            String
      }
    }
    """

    // MARK: - Dispatcher

    /// Returns the full directive string for a given product at a
    /// given difficulty. Always prepends:
    ///   · the 4-stage content-quality preamble,
    ///   · a difficulty block calibrating vocabulary register,
    ///   · the product-specific instructions,
    ///   · a "source text follows" delimiter so the model clearly
    ///     knows where the instruction set ends and the user's
    ///     data begins.
    public static func directive(
        for product: GenerationProduct,
        difficulty: Difficulty = .highSchool
    ) -> String {
        let productBlock: String
        switch product {
        case .flashcards:     productBlock = flashcardsDirective
        case .multipleChoice: productBlock = multipleChoiceDirective
        case .openAnswer:     productBlock = openAnswerDirective
        case .studyGuide:     productBlock = studyGuideDirective
        }
        return contentQualityPreamble
             + "\n\n" + difficulty.promptFragment
             + "\n\n" + productBlock
             + "\n\n--- source text follows ---\n"
    }

    /// Backward-compat wrapper that callers used BEFORE the difficulty
    /// parameter existed. New callers should prefer
    /// `directive(for:difficulty:)`.
    public static func directive(for product: GenerationProduct) -> String {
        directive(for: product, difficulty: .highSchool)
    }

    /// Convenience kept for backward compatibility with the original
    /// single-product call site (UploadTabView line ~787).
    public static let directive: String = directive(for: .flashcards)

    /// Sentinel for tests / debugging to detect when the blueprint
    /// directive is active in a request payload.
    public static let sentinel: String = "[HIDDEN TEACHER TEST BLUEPRINT"
}


// MARK: - GenerationProduct

/// The four artefacts the AI generator knows how to emit. Decoupled
/// from `StudyLaunch.PracticeMode` because the launch surface is
/// about WHERE the user studies, while GenerationProduct is about
/// WHAT the AI was asked to produce.
enum GenerationProduct: String, Codable, CaseIterable {
    case flashcards     = "flashcards"
    case multipleChoice = "multiple_choice"
    case openAnswer     = "open_answer"
    case studyGuide     = "study_guide"

    var title: String {
        switch self {
        case .flashcards:     return "Flashcards"
        case .multipleChoice: return "Multiple choice"
        case .openAnswer:     return "Open answer"
        case .studyGuide:     return "Study guide"
        }
    }

    var subtitle: String {
        switch self {
        case .flashcards:     return "recall · memorize · swipe"
        case .multipleChoice: return "test yourself with distractors"
        case .openAnswer:     return "type your answer, then reveal"
        case .studyGuide:     return "teach me the topic"
        }
    }

    var systemIcon: String {
        switch self {
        case .flashcards:     return "rectangle.stack.fill"
        case .multipleChoice: return "list.bullet.rectangle.fill"
        case .openAnswer:     return "keyboard.fill"
        case .studyGuide:     return "book.pages.fill"
        }
    }
}
