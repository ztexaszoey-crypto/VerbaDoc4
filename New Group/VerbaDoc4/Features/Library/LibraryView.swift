import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Document.createdAt, order: .reverse)]) private var documents: [Document]

    @State private var showAddMaterial = false
    @State private var searchText = ""

    private var filteredDocuments: [Document] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return documents }
        return documents.filter { document in
            let dateText = document.createdAt.formatted(date: .abbreviated, time: .omitted).lowercased()
            return document.title.lowercased().contains(query)
                || document.extractedText.lowercased().contains(query)
                || dateText.contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredDocuments) { document in
                    NavigationLink {
                        DocumentDetailView(document: document)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(document.title.isEmpty ? "Untitled" : document.title)
                                        .font(.headline)
                                        .foregroundStyle(VerbaTheme.ink)
                                    Label(document.sourceType.displayName, systemImage: document.sourceType.systemIcon)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                masteryBadge(for: document)
                            }

                            HStack(spacing: 12) {
                                libraryMeta(icon: "calendar", text: document.createdAt.formatted(date: .abbreviated, time: .omitted))
                                libraryMeta(icon: "rectangle.stack.fill", text: "\(document.studyItems?.count ?? 0) cards")
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .onDelete(perform: deleteDocuments)
            }
            .overlay {
                if filteredDocuments.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No documents yet" : "No matches found",
                        systemImage: "books.vertical"
                    )
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search title, content, or date")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddMaterial = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddMaterial) {
                AddMaterialView()
            }
        }
    }

    private func libraryMeta(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func masteryBadge(for document: Document) -> some View {
        Text("\(StudyEngine.mastery(for: document))% mastery")
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(VerbaTheme.green.opacity(0.12))
            .foregroundStyle(VerbaTheme.green)
            .clipShape(Capsule())
    }

    private func deleteDocuments(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredDocuments[index])
        }
        try? modelContext.save()
    }
}
