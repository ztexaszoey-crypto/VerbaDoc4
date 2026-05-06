import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyItem.nextReviewAt) private var allItems: [StudyItem]
    @Query(sort: [SortDescriptor(\Document.createdAt, order: .reverse)]) private var documents: [Document]

    @State private var showAddMaterial = false

    private var dueItems: [StudyItem] {
        let now = Date()
        return allItems.filter { $0.nextReviewAt <= now }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VerbaTheme.spacing24) {
                    headerSection
                    uploadCard
                    if !dueItems.isEmpty {
                        practiceCard
                    }
                    if !documents.isEmpty {
                        recentSection
                    }
                }
                .padding(.horizontal, VerbaTheme.spacing16)
                .padding(.top, VerbaTheme.spacing8)
                .padding(.bottom, VerbaTheme.spacing32)
            }
            .background(VerbaTheme.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAddMaterial) {
                AddMaterialView()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            VerbaTitle(text: "VerbaDoc")
            VerbaSecondary(text: "Turn notes into flashcards & exams")
        }
        .padding(.top, VerbaTheme.spacing8)
    }

    // MARK: - Upload Card

    private var uploadCard: some View {
        VerbaCardView {
            VStack(alignment: .leading, spacing: VerbaTheme.spacing16) {
                HStack(spacing: VerbaTheme.spacing16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: VerbaTheme.radiusSmall)
                            .fill(VerbaTheme.primary.opacity(0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(VerbaTheme.primary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        VerbaSectionHeader(text: "Upload Document")
                        VerbaSecondary(text: "PDF, Notes, Text")
                    }
                }
                PrimaryButton("Choose File", icon: "plus") {
                    showAddMaterial = true
                }
            }
        }
    }

    // MARK: - Practice Card

    private var practiceCard: some View {
        VerbaCardView {
            VStack(alignment: .leading, spacing: VerbaTheme.spacing16) {
                HStack(spacing: VerbaTheme.spacing16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: VerbaTheme.radiusSmall)
                            .fill(Color.orange.opacity(0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: "flame.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        VerbaSectionHeader(text: "\(dueItems.count) Cards Due")
                        VerbaSecondary(text: "Ready for review today")
                    }
                }
                NavigationLink {
                    TodayPracticeView(items: dueItems)
                } label: {
                    HStack(spacing: VerbaTheme.spacing8) {
                        Image(systemName: "play.fill")
                        Text("Start Session")
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

    // MARK: - Recent Section

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: VerbaTheme.spacing16) {
            VerbaSectionHeader(text: "Recent")
            ForEach(documents.prefix(5)) { document in
                recentDocumentCard(document)
            }
        }
    }

    private func recentDocumentCard(_ document: Document) -> some View {
        VerbaCardView {
            HStack(spacing: VerbaTheme.spacing16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.title.isEmpty ? "Untitled" : document.title)
                        .font(VerbaTypography.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(VerbaTheme.textPrimary)
                    VerbaSecondary(text: document.createdAt.formatted(date: .abbreviated, time: .omitted))
                }
                Spacer()
                NavigationLink {
                    TodayPracticeView(items: document.studyItems ?? [])
                } label: {
                    Text("Practice")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VerbaTheme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(VerbaTheme.primary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.radiusSmall))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
