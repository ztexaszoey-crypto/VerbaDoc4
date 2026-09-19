import SwiftUI

// MARK: - NotesView
// Displays the original source content (PDF text, pasted notes, etc.) as
// a clean readable document, plus a topic-tagged card index at the bottom.

struct NotesView: View {
    let document: Document
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var expandedTopics: Set<String> = []

    private var topics: [String] {
        let all = document.studyItems.compactMap { $0.topic.isEmpty ? nil : $0.topic }
        return Array(Set(all)).sorted()
    }

    private var hasContent: Bool {
        !document.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            VerbaTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav bar
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("back")
                                .font(VerbaFont.syne(.medium, size: 15))
                        }
                        .foregroundStyle(VerbaTheme.ink)
                    }

                    Spacer()

                    HStack(spacing: 5) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 12))
                        Text("notes")
                            .font(VerbaFont.syne(.bold, size: 14))
                    }
                    .foregroundStyle(VerbaTheme.muted)

                    Spacer()
                    // Balance
                    Color.clear.frame(width: 60)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {

                        // ── Title ──────────────────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Text(document.title)
                                .font(VerbaFont.serif(size: 24))
                                .foregroundStyle(VerbaTheme.ink)

                            HStack(spacing: 12) {
                                Label("\(document.studyItems.count) cards", systemImage: "rectangle.stack.fill")
                                if !topics.isEmpty {
                                    Label("\(topics.count) topics", systemImage: "tag.fill")
                                }
                                if let exam = document.examDate {
                                    Label(examLabel(exam), systemImage: "calendar")
                                        .foregroundStyle(VerbaTheme.orange)
                                }
                            }
                            .font(VerbaFont.syne(.regular, size: 12))
                            .foregroundStyle(VerbaTheme.muted)
                        }
                        .padding(.horizontal, 20)

                        // ── Source Content ────────────────────────────────────
                        if hasContent {
                            VStack(alignment: .leading, spacing: 10) {
                                sectionHeader("source material", icon: "text.alignleft")

                                Text(document.content)
                                    .font(VerbaFont.syne(.regular, size: 14))
                                    .foregroundStyle(VerbaTheme.ink)
                                    .lineSpacing(5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                                    .background(VerbaTheme.card)
                                    .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                                            .stroke(VerbaTheme.border, lineWidth: 1)
                                    )
                            }
                            .padding(.horizontal, 20)
                        }

                        // ── Key Concepts (by topic) ───────────────────────────
                        if !topics.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionHeader("key concepts", icon: "lightbulb.fill")
                                    .padding(.horizontal, 20)

                                ForEach(topics, id: \.self) { topic in
                                    topicSection(topic)
                                }
                            }
                        } else if !document.studyItems.isEmpty {
                            // No topics — flat card list
                            VStack(alignment: .leading, spacing: 12) {
                                sectionHeader("key concepts", icon: "lightbulb.fill")
                                    .padding(.horizontal, 20)

                                VStack(spacing: 8) {
                                    ForEach(document.studyItems, id: \.id) { item in
                                        noteRow(item)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }

                        Spacer(minLength: 48)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            // Expand all topics by default
            expandedTopics = Set(topics)
        }
    }

    // MARK: - Topic Section

    private func topicSection(_ topic: String) -> some View {
        let items = document.studyItems.filter { $0.topic == topic }
        let isExpanded = expandedTopics.contains(topic)

        return VStack(alignment: .leading, spacing: 0) {
            // Topic header (tappable collapse)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if isExpanded {
                        expandedTopics.remove(topic)
                    } else {
                        expandedTopics.insert(topic)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(topic)
                        .font(VerbaFont.syne(.bold, size: 13))
                        .foregroundStyle(VerbaTheme.ink)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Text("\(items.count)")
                        .font(VerbaFont.syne(.bold, size: 11))
                        .foregroundStyle(VerbaTheme.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(VerbaTheme.green.opacity(0.12))
                        .clipShape(Capsule())

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VerbaTheme.muted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(VerbaTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                        .stroke(VerbaTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(items, id: \.id) { item in
                        noteRow(item)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func noteRow(_ item: StudyItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(masteryColor(item.mastery))
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)

                Text(item.question)
                    .font(VerbaFont.syne(.semibold, size: 14))
                    .foregroundStyle(VerbaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(item.answer)
                .font(VerbaFont.syne(.regular, size: 13))
                .foregroundStyle(VerbaTheme.muted)
                .lineSpacing(3)
                .padding(.leading, 16)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                .stroke(VerbaTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VerbaTheme.green)
            Text(title)
                .font(VerbaFont.syne(.semibold, size: 12))
                .foregroundStyle(VerbaTheme.muted)
                .textCase(.uppercase)
                .tracking(0.8)
        }
    }

    private func masteryColor(_ mastery: Int) -> Color {
        mastery >= 80 ? VerbaTheme.green : mastery >= 50 ? VerbaTheme.orange : VerbaTheme.danger
    }

    private func examLabel(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        return days <= 0 ? "exam today" : "\(days)d to exam"
    }
}
