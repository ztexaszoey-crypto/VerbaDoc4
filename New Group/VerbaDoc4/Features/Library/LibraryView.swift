import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Document.createdAt, order: .reverse)]) private var documents: [Document]

    @State private var showAddMaterial = false
    @State private var regeneratingID: UUID? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VerbaTheme.spacing24) {
                    headerSection
                    if documents.isEmpty {
                        emptyState
                    } else {
                        documentsSection
                    }
                }
                .padding(.horizontal, VerbaTheme.spacing16)
                .padding(.top, VerbaTheme.spacing8)
                .padding(.bottom, VerbaTheme.spacing32)
            }
            .background(VerbaTheme.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddMaterial = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                            .foregroundStyle(VerbaTheme.primary)
                    }
                }
            }
            .sheet(isPresented: $showAddMaterial) {
                AddMaterialView()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            VerbaTitle(text: "Library")
            VerbaSecondary(text: "\(documents.count) document\(documents.count == 1 ? "" : "s")")
        }
        .padding(.top, VerbaTheme.spacing8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VerbaCardView {
            VStack(spacing: VerbaTheme.spacing16) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 40))
                    .foregroundStyle(VerbaTheme.textSecondary)
                VerbaBody(text: "No documents yet")
                VerbaSecondary(text: "Tap + to add your first document")
                PrimaryButton("Add Document", icon: "plus") {
                    showAddMaterial = true
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, VerbaTheme.spacing16)
        }
    }

    // MARK: - Documents

    private var documentsSection: some View {
        VStack(spacing: VerbaTheme.spacing16) {
            ForEach(documents) { document in
                documentCard(document)
            }
        }
    }

    private func documentCard(_ document: Document) -> some View {
        VerbaCardView {
            VStack(alignment: .leading, spacing: VerbaTheme.spacing16) {
                HStack(spacing: VerbaTheme.spacing16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: VerbaTheme.radiusSmall)
                            .fill(VerbaTheme.primary.opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: document.sourceType.systemIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(VerbaTheme.primary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.title.isEmpty ? "Untitled" : document.title)
                            .font(VerbaTypography.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(VerbaTheme.textPrimary)
                            .lineLimit(1)
                        VerbaSecondary(text: document.createdAt.formatted(date: .abbreviated, time: .omitted))
                    }
                    Spacer()
                    NavigationLink {
                        DocumentDetailView(document: document)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(VerbaTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: VerbaTheme.spacing8) {
                    NavigationLink {
                        TodayPracticeView(items: document.studyItems ?? [])
                    } label: {
                        Text("Practice")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(VerbaTheme.primary)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.radiusSmall, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled((document.studyItems ?? []).isEmpty)

                    Button {
                        regenerateCards(for: document)
                    } label: {
                        HStack(spacing: 4) {
                            if regeneratingID == document.id {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(VerbaTheme.primary)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Text("Regenerate")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color.clear)
                        .foregroundStyle(VerbaTheme.primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: VerbaTheme.radiusSmall, style: .continuous)
                                .stroke(VerbaTheme.primary, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(regeneratingID == document.id)
                }
            }
        }
    }

    // MARK: - Actions

    private func regenerateCards(for document: Document) {
        regeneratingID = document.id
        let existing = document.studyItems ?? []
        for item in existing { modelContext.delete(item) }
        document.studyItems = []
        let cards = StudyGenerator.generateCards(from: document.extractedText, documentTitle: document.title, maxCards: 12)
        for card in cards {
            modelContext.insert(card)
            document.studyItems?.append(card)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            regeneratingID = nil
        }
    }
}
