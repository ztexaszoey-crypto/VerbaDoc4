import SwiftUI
import SwiftData

// MARK: - ReadinessBreakdownView
//
// Explains *why* the readiness score is what it is.
// Surfaced by tapping the readiness % in DocumentDetailView.
//
// Architecture note: each visual section is a separate private struct.
// This keeps every type-checking context small and prevents the Swift
// type-checker from timing out across a single large struct.

struct ReadinessBreakdownView: View {

    let document: Document
    let studyItems: [StudyItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                VerbaTheme.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        RBScoreCard(document: document, studyItems: studyItems)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                        RBDragsSection(studyItems: studyItems)
                            .padding(.horizontal, 20)
                        RBStrengthsSection(studyItems: studyItems)
                            .padding(.horizontal, 20)
                        RBNextActionSection(studyItems: studyItems)
                            .padding(.horizontal, 20)
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("readiness breakdown")
                        .font(VerbaFont.syne(.semibold, size: 16))
                        .foregroundStyle(VerbaTheme.ink)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("done") { dismiss() }
                        .font(VerbaFont.syne(.regular, size: 15))
                        .foregroundStyle(VerbaTheme.green)
                }
            }
        }
    }
}

// MARK: - Shared Helpers
// Free functions — accessible by all sub-structs without any `self` context.

private func rbMasteryColor(_ pct: Int) -> Color {
    if pct >= 75 { return VerbaTheme.green }
    if pct >= 40 { return VerbaTheme.orange }
    return VerbaTheme.danger
}

private func rbSectionHeader(_ text: String) -> some View {
    Text(text)
        .font(VerbaFont.syne(.semibold, size: 11))
        .foregroundStyle(VerbaTheme.muted)
        .textCase(.uppercase)
        .tracking(0.6)
}

// MARK: - Score Card

private struct RBScoreCard: View {
    let document: Document
    let studyItems: [StudyItem]

    private var mastery: Int {
        guard !studyItems.isEmpty else { return 0 }
        return studyItems.reduce(0) { $0 + $1.mastery } / studyItems.count
    }
    private var slippingCount: Int {
        studyItems.filter { $0.nextReviewAt <= Date() }.count
    }
    private var stuckCount: Int {
        studyItems.filter { $0.consecutiveMisses >= 2 }.count
    }
    private var freshnessPenalty: Int {
        guard !studyItems.isEmpty else { return 0 }
        let ratio = Double(slippingCount) / Double(studyItems.count)
        return Int(ratio * 25.0)
    }
    private var stuckPenalty: Int {
        guard !studyItems.isEmpty else { return 0 }
        let ratio = Double(stuckCount) / Double(studyItems.count)
        return min(15, Int(ratio * 20.0))
    }
    private var readinessPct: Int {
        max(0, min(100, mastery - freshnessPenalty))
    }
    private var readinessColor: Color {
        if readinessPct >= 75 { return VerbaTheme.green }
        if readinessPct >= 45 { return VerbaTheme.orange }
        return VerbaTheme.danger
    }
    private var readinessLabel: String {
        if readinessPct >= 88 { return "exam ready" }
        if readinessPct >= 70 { return "almost there" }
        if readinessPct >= 45 { return "building up" }
        return "just starting"
    }
    private var sessionGainEstimate: String {
        let weakCount = studyItems.filter { $0.mastery < 40 }.count
        let drillCount = min(weakCount + slippingCount, 20)
        guard drillCount > 0 else { return "you're in maintenance mode — review on schedule." }
        let masteryGain = Int(Double(min(weakCount, 15)) * 0.7 * 10.0) / max(studyItems.count, 1)
        let freshnessGain = slippingCount == 0 ? 0 : min(freshnessPenalty, 10)
        let totalGain = min(masteryGain + freshnessGain, 20)
        if totalGain > 0 { return "one session could move you +\(totalGain)%." }
        return "keep your review streak going."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(readinessPct)%")
                    .font(VerbaFont.syne(.bold, size: 52))
                    .foregroundStyle(readinessColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(readinessLabel)
                        .font(VerbaFont.syne(.semibold, size: 14))
                        .foregroundStyle(readinessColor)
                    Text(document.title)
                        .font(VerbaFont.syne(.regular, size: 12))
                        .foregroundStyle(VerbaTheme.muted)
                        .lineLimit(1)
                }
                .padding(.bottom, 4)
            }

            Divider()

            VStack(spacing: 10) {
                formulaRow(
                    label: "average mastery",
                    value: "+\(mastery)%",
                    valueColor: rbMasteryColor(mastery),
                    detail: "\(studyItems.count) cards tracked · how well you know the material"
                )
                freshnessRow
                if stuckCount > 0 {
                    formulaRow(
                        label: "stuck concept drag",
                        value: "−\(stuckPenalty)% est.",
                        valueColor: VerbaTheme.danger,
                        detail: "\(stuckCount) card\(stuckCount == 1 ? "" : "s") missed repeatedly — suppresses mastery gains"
                    )
                }
                Divider().padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("= \(readinessPct)% predicted readiness")
                        .font(VerbaFont.syne(.semibold, size: 13))
                        .foregroundStyle(VerbaTheme.ink)
                    Text(sessionGainEstimate)
                        .font(VerbaFont.syne(.regular, size: 12))
                        .foregroundStyle(VerbaTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                .stroke(readinessColor.opacity(0.18), lineWidth: 1)
        )
    }

    // Extracted to avoid nested ternaries in a ViewBuilder call site
    private var freshnessRow: some View {
        let value = freshnessPenalty > 0 ? "−\(freshnessPenalty)%" : "±0%"
        let color: Color = freshnessPenalty > 0 ? VerbaTheme.orange : VerbaTheme.muted
        let plural = slippingCount == 1 ? "" : "s"
        let detail = freshnessPenalty > 0
            ? "\(slippingCount) card\(plural) overdue — memory decays without review"
            : "all cards reviewed on schedule"
        return formulaRow(label: "freshness penalty", value: value, valueColor: color, detail: detail)
    }

    private func formulaRow(label: String, value: String, valueColor: Color, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(VerbaFont.syne(.medium, size: 13))
                    .foregroundStyle(VerbaTheme.ink)
                Text(detail)
                    .font(VerbaFont.syne(.regular, size: 12))
                    .foregroundStyle(VerbaTheme.muted)
                    .lineSpacing(1.5)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(VerbaFont.syne(.bold, size: 15))
                .foregroundStyle(valueColor)
        }
    }
}

// MARK: - Drags Section

private struct RBDragsSection: View {
    let studyItems: [StudyItem]

    struct DragItem: Identifiable {
        let id: String
        let question: String
        let stat: String
    }

    private var stuckItems: [StudyItem] {
        studyItems.filter { $0.consecutiveMisses >= 2 }
            .sorted { $0.consecutiveMisses > $1.consecutiveMisses }
    }
    private var slippingItems: [StudyItem] {
        studyItems.filter { $0.nextReviewAt <= Date() }
            .sorted { $0.mastery < $1.mastery }
    }
    private var weakItems: [StudyItem] {
        studyItems.filter { $0.mastery < 40 }
            .sorted { $0.mastery < $1.mastery }
    }
    private var hasAnyDrags: Bool {
        !stuckItems.isEmpty || !slippingItems.isEmpty || !weakItems.isEmpty
    }
    private var stuckMissLabel: String {
        guard let top = stuckItems.first else { return "multiple" }
        return "\(top.consecutiveMisses)×"
    }

    var body: some View {
        if hasAnyDrags {
            VStack(alignment: .leading, spacing: 12) {
                rbSectionHeader("what's hurting your score")
                VStack(spacing: 8) {
                    if !stuckItems.isEmpty {
                        dragCard(
                            icon: "arrow.trianglehead.2.clockwise",
                            color: VerbaTheme.danger,
                            headline: "\(stuckItems.count) card\(stuckItems.count == 1 ? "" : "s") you keep missing",
                            detail: "missed \(stuckMissLabel) in a row — the tutor can help unlock them.",
                            items: stuckItems.prefix(3).map {
                                DragItem(id: $0.id, question: $0.question, stat: "\($0.consecutiveMisses)× missed")
                            }
                        )
                    }
                    if !slippingItems.isEmpty {
                        dragCard(
                            icon: "exclamationmark.circle",
                            color: VerbaTheme.orange,
                            headline: "\(slippingItems.count) card\(slippingItems.count == 1 ? "" : "s") overdue for review",
                            detail: "memory degrades exponentially. each day without review makes retrieval harder.",
                            items: slippingItems.prefix(3).map {
                                DragItem(id: $0.id, question: $0.question, stat: "\($0.mastery)% mastery")
                            }
                        )
                    }
                    if !weakItems.isEmpty {
                        dragCard(
                            icon: "chart.bar.fill",
                            color: VerbaTheme.muted,
                            headline: "\(weakItems.count) card\(weakItems.count == 1 ? "" : "s") under 40% mastery",
                            detail: "low mastery drags the average down. 2–3 correct recalls on each moves the needle.",
                            items: weakItems.prefix(3).map {
                                DragItem(id: $0.id, question: $0.question, stat: "\($0.mastery)% mastery")
                            }
                        )
                    }
                }
            }
        }
    }

    private func dragCard(icon: String, color: Color, headline: String, detail: String, items: [DragItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                Text(headline)
                    .font(VerbaFont.syne(.semibold, size: 13))
                    .foregroundStyle(VerbaTheme.ink)
            }
            Text(detail)
                .font(VerbaFont.syne(.regular, size: 12))
                .foregroundStyle(VerbaTheme.muted)
                .lineSpacing(2)
            VStack(spacing: 5) {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(color.opacity(0.4))
                            .frame(width: 3, height: 14)
                        Text(item.question)
                            .font(VerbaFont.syne(.regular, size: 12))
                            .foregroundStyle(VerbaTheme.ink)
                            .lineLimit(1)
                        Spacer()
                        Text(item.stat)
                            .font(VerbaFont.syne(.medium, size: 11))
                            .foregroundStyle(VerbaTheme.muted)
                    }
                }
            }
        }
        .padding(14)
        .background(color.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                .stroke(color.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Strengths Section

private struct RBStrengthsSection: View {
    let studyItems: [StudyItem]

    private var strongItems: [StudyItem] {
        studyItems.filter { $0.mastery >= 75 }
            .sorted { $0.mastery > $1.mastery }
    }

    var body: some View {
        if !strongItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                rbSectionHeader("what's working")
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(VerbaTheme.green)
                        Text("\(strongItems.count) card\(strongItems.count == 1 ? "" : "s") at 75%+ mastery")
                            .font(VerbaFont.syne(.semibold, size: 13))
                            .foregroundStyle(VerbaTheme.ink)
                    }
                    Text("these concepts are solid. SRS spaces them automatically — just keep reviewing on schedule.")
                        .font(VerbaFont.syne(.regular, size: 12))
                        .foregroundStyle(VerbaTheme.muted)
                        .lineSpacing(2)
                    VStack(spacing: 5) {
                        ForEach(Array(strongItems.prefix(3))) { item in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(VerbaTheme.green.opacity(0.4))
                                    .frame(width: 3, height: 14)
                                Text(item.question)
                                    .font(VerbaFont.syne(.regular, size: 12))
                                    .foregroundStyle(VerbaTheme.ink)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(item.mastery)%")
                                    .font(VerbaFont.syne(.medium, size: 11))
                                    .foregroundStyle(VerbaTheme.green.opacity(0.7))
                            }
                        }
                    }
                }
                .padding(14)
                .background(VerbaTheme.green.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                        .stroke(VerbaTheme.green.opacity(0.12), lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Next Action Section

private struct RBNextActionSection: View {
    let studyItems: [StudyItem]

    struct Action: Identifiable {
        let id = UUID()
        let rank: Int
        let label: String
        let why: String
        let color: Color
    }

    private var stuckItems: [StudyItem] {
        studyItems.filter { $0.consecutiveMisses >= 2 }
            .sorted { $0.consecutiveMisses > $1.consecutiveMisses }
    }
    private var slippingItems: [StudyItem] {
        studyItems.filter { $0.nextReviewAt <= Date() }
    }
    private var weakItems: [StudyItem] {
        studyItems.filter { $0.mastery < 40 }
    }

    private var actions: [Action] {
        var result: [Action] = []

        if let top = stuckItems.first {
            let q = top.question
            let preview = q.count > 40 ? String(q.prefix(40)) + "…" : q
            result.append(Action(
                rank: result.count + 1,
                label: "break the miss streak on \"\(preview)\"",
                why: "2 correct recalls in a row resets the miss counter and unlocks mastery gains",
                color: VerbaTheme.danger
            ))
        }
        if !slippingItems.isEmpty {
            let n = slippingItems.count
            result.append(Action(
                rank: result.count + 1,
                label: "review \(n) overdue card\(n == 1 ? "" : "s") today",
                why: "removes the freshness penalty and stops memory decay — highest ROI right now",
                color: VerbaTheme.orange
            ))
        }
        if weakItems.count > stuckItems.count {
            let n = weakItems.count
            result.append(Action(
                rank: result.count + 1,
                label: "drill weak spots (\(n) card\(n == 1 ? "" : "s") under 40%)",
                why: "each correct answer adds mastery — a single session here can move readiness 5–15%",
                color: VerbaTheme.muted
            ))
        }
        result.append(Action(
            rank: result.count + 1,
            label: "review on schedule every day",
            why: "SRS schedules cards at the exact moment before forgetting — daily use compounds faster than cramming",
            color: VerbaTheme.green
        ))
        return Array(result.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            rbSectionHeader("fastest path to exam-ready")
            VStack(spacing: 8) {
                ForEach(actions) { action in
                    actionRow(action)
                }
            }
        }
    }

    private func actionRow(_ action: Action) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(action.rank)")
                .font(VerbaFont.syne(.bold, size: 13))
                .foregroundStyle(action.color)
                .frame(width: 20, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(action.label)
                    .font(VerbaFont.syne(.semibold, size: 13))
                    .foregroundStyle(VerbaTheme.ink)
                    .lineSpacing(1.5)
                Text(action.why)
                    .font(VerbaFont.syne(.regular, size: 12))
                    .foregroundStyle(VerbaTheme.muted)
                    .lineSpacing(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                .stroke(VerbaTheme.border, lineWidth: 1)
        )
    }
}
