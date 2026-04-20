import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: [SortDescriptor<Document>(\.createdAt, order: .reverse)]) private var documents: [Document]
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List(documents, id: \.id) { document in
                NavigationLink(document.title.isEmpty ? "Untitled" : document.title) {
                    DocumentDetailView(document: document)
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddMaterialView()
            }
        }
    }
}

#Preview {
    LibraryView()
}
