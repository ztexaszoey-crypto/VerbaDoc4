import SwiftData
import SwiftUI

struct PracticeView: View {
    @Query(sort: [SortDescriptor(\StudyItem.createdAt, order: .reverse)]) private var items: [StudyItem]
    @State private var selectedFilter: StudyFilter = .all

    private var filteredItems: [StudyItem] {
        StudyEngine.items(for: selectedFilter, from: items)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Mode", selection: $selectedFilter) {
                        ForEach(StudyFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Study modes") {
                    NavigationLink {
                        TodayPracticeView(items: StudyEngine.items(for: .all, from: items), sessionTitle: "Practice All")
                    } label: {
                        practiceRow(title: "Practice all cards", detail: "\(items.count) cards", icon: "rectangle.stack.fill")
                    }
                    .disabled(items.isEmpty)

                    NavigationLink {
                        TodayPracticeView(items: StudyEngine.items(for: .due, from: items), sessionTitle: "Due Review")
                    } label: {
                        practiceRow(title: "Start studying", detail: "\(StudyEngine.items(for: .due, from: items).count) cards due", icon: "calendar.badge.clock")
                    }
                    .disabled(StudyEngine.items(for: .due, from: items).isEmpty)

                    NavigationLink {
                        TodayPracticeView(items: StudyEngine.items(for: .weak, from: items), sessionTitle: "Weak Card Practice")
                    } label: {
                        practiceRow(title: "Practice weak cards", detail: "\(StudyEngine.items(for: .weak, from: items).count) cards under 60%", icon: "bolt.heart.fill")
                    }
                    .disabled(StudyEngine.items(for: .weak, from: items).isEmpty)

                    NavigationLink {
                        ExamView()
                    } label: {
                        practiceRow(title: "Exam mode", detail: "Timed question flow by document", icon: "checklist")
                    }
                }

                Section("\(selectedFilter.title) cards") {
                    if filteredItems.isEmpty {
                        ContentUnavailableView("No cards in this mode", systemImage: "rectangle.stack")
                    } else {
                        ForEach(filteredItems) { item in
                            NavigationLink {
                                TutorView(item: item)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.question)
                                        .font(.headline)
                                    Text(item.answer)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        Text(item.nextReviewAt <= Date() ? "Due now" : "Next \(item.nextReviewAt.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption2)
                                            .foregroundStyle(item.nextReviewAt <= Date() ? .orange : .secondary)
                                        Spacer()
                                        Text("\(StudyEngine.mastery(for: item))%")
                                            .font(.caption.bold())
                                            .foregroundStyle(VerbaTheme.green)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Practice")
        }
    }

    private func practiceRow(title: String, detail: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(VerbaTheme.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
