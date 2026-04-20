import SwiftUI

struct DocumentDetailView: View {
    let document: Document

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(document.title.isEmpty ? "Untitled" : document.title)
                    .font(.title2.bold())

                Label(document.sourceType.displayName, systemImage: document.sourceType.systemIcon)
                    .foregroundStyle(.secondary)

                Text(document.extractedText.isEmpty ? "No content yet." : document.extractedText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Study items: \(document.studyItems?.count ?? 0)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Document")
    }
}

#Preview {
    DocumentDetailView(document: Document(title: "Preview", extractedText: "Example text"))
}
