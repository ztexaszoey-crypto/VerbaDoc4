import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var streakManager: StreakManager
    @Query private var documents: [Document]
    @State private var searchText: String = ""
    @State private var showingAddMaterial: Bool = false
    @State private var deletingDocument: Document? = nil
    
    private var filteredDocuments: [Document] {
        if searchText.isEmpty {
            return documents
        } else {
            return documents.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                VerbaTheme.background.ignoresSafeArea()
                if documents.isEmpty {
                    EmptyLibraryState {
                        showingAddMaterial = true
                        vibrate()
                    }
                } else {
                    List {
                        ForEach(filteredDocuments) { doc in
                            NavigationLink {
                                DocumentDetailView(document: doc)
                            } label: {
                                DocumentRow(document: doc)
                            }
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deletingDocument = doc
                                    vibrate()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: filteredDocuments.count)
                        }
                    }
                    .background(Color.clear)
                    .listStyle(.plain)
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddMaterial = true
                        vibrate()
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.bold())
                            .foregroundColor(VerbaTheme.green)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add Material")
                }
            }
            .sheet(isPresented: $showingAddMaterial) {
                AddMaterialView()
            }
            .alert("Delete Document?", isPresented: .constant(deletingDocument != nil), presenting: deletingDocument) { doc in
                Button("Delete", role: .destructive) {
                    if let doc = deletingDocument {
                        deleteDocument(doc)
                    }
                    deletingDocument = nil
                }
                Button("Cancel", role: .cancel) {
                    deletingDocument = nil
                }
            } message: { doc in
                Text("""
                     This will also remove all study items linked to \
                     \"\(doc.title.trimmingCharacters(in: .whitespacesAndNewlines))\". 
                     You can't undo this.
                     """)
            }
        }
    }
    
    private func deleteDocument(_ document: Document) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            modelContext.delete(document)
        }
    }
    
    private func vibrate() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

// MARK: - Document Row
private struct DocumentRow: View {
    let document: Document
    
    var mastery: Double {
        let all = document.studyItems?.count ?? 0
        guard all > 0 else { return 0 }
        let mastered = document.studyItems?.filter { $0.mastery >= 80 }.count ?? 0
        return Double(mastered) / Double(all) * 100
    }
    var masteryColor: Color {
        switch mastery {
        case 80...:   return VerbaTheme.green
        case 60..<80: return VerbaTheme.gold
        default:      return VerbaTheme.red
        }
    }
    
    var body: some View {
        HStack(spacing: 14) {
            SourceTypeIcon(type: document.sourceType)
            VStack(alignment: .leading, spacing: 6) {
                Text(document.title)
                    .font(VerbaTheme.Font.heading2)
                    .foregroundColor(VerbaTheme.textMain)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Label("\(document.studyItems?.count ?? 0)", systemImage: "doc.on.doc")
                        .font(VerbaTheme.Font.bodySmall)
                        .foregroundColor(.secondary)
                    MasteryPill(percent: mastery, color: masteryColor)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 18).weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(VerbaTheme.card)
        .cornerRadius(20, style: .continuous)
        .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: document.studyItems?.count)
    }
}

// MARK: - Mastery Pill
private struct MasteryPill: View {
    let percent: Double
    let color: Color
    var body: some View {
        Text("\(Int(percent))%")
            .font(VerbaTheme.Font.bodySmall.italic())
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background(color.opacity(0.18))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// MARK: - Source Type Icon
private struct SourceTypeIcon: View {
    let type: Document.SourceType
    var body: some View {
        let (icon, color): (String, Color) = {
            switch type {
            case .pdf:      return ("doc.richtext", VerbaTheme.green)
            case .photo:    return ("photo", VerbaTheme.brown)
            case .text:     return ("text.alignleft", VerbaTheme.gold)
            }
        }()
        return Image(systemName: icon)
            .font(.system(size: 30))
            .foregroundColor(color)
            .opacity(0.90)
            .padding(8)
    }
}

// MARK: - Empty State View
private struct EmptyLibraryState: View {
    let action: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Image("capybara-reading")
                .resizable()
                .scaledToFit()
                .frame(height: 160)
                .accessibilityHidden(true)
            Text("Your library is empty!")
                .font(VerbaTheme.Font.heading1.italic())
                .foregroundColor(VerbaTheme.brown)
            Text("Upload your first material — PDFs, notes, or text — and let Verba the capybara help turn them into flashcards.")
                .font(VerbaTheme.Font.body)
                .foregroundColor(VerbaTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                action()
            } label: {
                Text("Add Material")
                    .font(VerbaTheme.Font.button)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 36)
                    .background(VerbaTheme.green)
                    .foregroundColor(.white)
                    .cornerRadius(14, style: .continuous)
                    .scaleEffectOnPress()
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VerbaTheme.background)
    }
}
