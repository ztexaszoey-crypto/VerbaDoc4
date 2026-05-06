import SwiftUI
import SwiftData

struct PracticeView: View {
    @Query(sort: [SortDescriptor(\StudyItem.createdAt, order: .reverse)]) private var items: [StudyItem]
    @Query(sort: [SortDescriptor(\Document.createdAt, order: .reverse)]) private var documents: [Document]
    @EnvironmentObject private var streakManager: StreakManager

    private var dueItems: [StudyItem] {
        let now = Date()
        return items.filter { $0.nextReviewAt <= now }
    }

    private var weakItems: [StudyItem] {
        items.filter { $0.lastRating == "again" || $0.reps == 0 }
    }

    private var accuracy: Int {
        guard !items.isEmpty else { return 0 }
        let goodOrEasy = items.filter { $0.lastRating == "good" || $0.lastRating == "easy" }.count
        return Int((Double(goodOrEasy) / Double(items.count)) * 100)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VerbaTheme.spacing24) {
                    headerSection
                    if !items.isEmpty {
                        continueSessionCard
                    }
                    modeCardsSection
                    progressStrip
                }
                .padding(.horizontal, VerbaTheme.spacing16)
                .padding(.top, VerbaTheme.spacing8)
                .padding(.bottom, VerbaTheme.spacing32)
            }
            .background(VerbaTheme.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            VerbaTitle(text: "Practice")
            VerbaSecondary(text: "Train with your generated content")
        }
        .padding(.top, VerbaTheme.spacing8)
    }

    // MARK: - Continue Session Card

    private var continueSessionCard: some View {
        VerbaCardView {
            VStack(alignment: .leading, spacing: VerbaTheme.spacing16) {
                HStack(spacing: VerbaTheme.spacing16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: VerbaTheme.radiusSmall)
                            .fill(VerbaTheme.primary.opacity(0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(VerbaTheme.primary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        VerbaSectionHeader(text: "Continue Session")
                        VerbaSecondary(text: "\(dueItems.count) cards due · \(items.count) total")
                    }
                }
                NavigationLink {
                    TodayPracticeView(items: dueItems.isEmpty ? Array(items.prefix(10)) : dueItems)
                } label: {
                    HStack(spacing: VerbaTheme.spacing8) {
                        Image(systemName: "play.fill")
                        Text("Resume")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(VerbaTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.radiusMedium, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Mode Cards

    private var modeCardsSection: some View {
        VStack(alignment: .leading, spacing: VerbaTheme.spacing16) {
            VerbaSectionHeader(text: "Modes")
            HStack(spacing: VerbaTheme.spacing16) {
                modeCard(
                    title: "Flashcards",
                    subtitle: "Active recall",
                    icon: "rectangle.stack.fill",
                    color: VerbaTheme.primary,
                    destination: AnyView(TodayPracticeView(items: Array(items.prefix(20))))
                )
                modeCard(
                    title: "Exam",
                    subtitle: "Test yourself",
                    icon: "checkmark.seal.fill",
                    color: Color(red: 0.49, green: 0.24, blue: 0.93),
                    destination: AnyView(ExamView())
                )
                modeCard(
                    title: "Weak Areas",
                    subtitle: "Focus on gaps",
                    icon: "exclamationmark.triangle.fill",
                    color: VerbaTheme.error,
                    destination: AnyView(TodayPracticeView(items: weakItems.isEmpty ? Array(items.prefix(10)) : weakItems))
                )
            }
        }
    }

    @ViewBuilder
    private func modeCard(title: String, subtitle: String, icon: String, color: Color, destination: AnyView) -> some View {
        NavigationLink {
            destination
        } label: {
            VStack(spacing: VerbaTheme.spacing8) {
                ZStack {
                    RoundedRectangle(cornerRadius: VerbaTheme.radiusSmall)
                        .fill(color.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VerbaTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(VerbaTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(VerbaTheme.spacing16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.radiusLarge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.radiusLarge, style: .continuous)
                    .stroke(VerbaTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(items.isEmpty)
    }

    // MARK: - Progress Strip

    private var progressStrip: some View {
        HStack(spacing: 0) {
            progressStat(value: "\(streakManager.currentStreak)", label: "Streak", icon: "flame.fill", color: .orange)
            Divider().frame(height: 32)
            progressStat(value: "\(accuracy)%", label: "Accuracy", icon: "target", color: VerbaTheme.primary)
            Divider().frame(height: 32)
            progressStat(value: "\(items.count)", label: "Cards", icon: "rectangle.stack.fill", color: VerbaTheme.success)
        }
        .padding(.vertical, VerbaTheme.spacing16)
        .padding(.horizontal, VerbaTheme.spacing8)
        .background(VerbaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.radiusLarge, style: .continuous)
                .stroke(VerbaTheme.border, lineWidth: 1)
        )
    }

    private func progressStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(VerbaTheme.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(VerbaTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
