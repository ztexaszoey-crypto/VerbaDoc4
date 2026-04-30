import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Document.createdAt, order: .reverse)]) private var documents: [Document]

    @State private var showAddMaterial = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(documents) { document in
                    NavigationLink {
                        DocumentDetailView(document: document)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(document.title.isEmpty ? "Untitled" : document.title)
                                .font(.headline)
                            Label(document.sourceType.displayName, systemImage: document.sourceType.systemIcon)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteDocuments)
            }
            .overlay {
                if documents.isEmpty {
                    ContentUnavailableView("No documents yet", systemImage: "books.vertical")
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddMaterial = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddMaterial) {
                AddMaterialView()
            }
        }
    }

    private func deleteDocuments(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(documents[index])
        }
    }
}
