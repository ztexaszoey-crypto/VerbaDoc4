import SwiftUI
import SwiftData

// MARK: - ExamDatePickerSheet
//
// Presented from DocumentDetailView when the user taps "Set Exam Date".
// Stores the date on the Document model. SRSScheduler reads it to compress
// review intervals as the exam approaches.

struct ExamDatePickerSheet: View {
    let document: Document
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date

    init(document: Document) {
        self.document = document
        // Default: 7 days from today if no date is set
        let fallback = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        _selectedDate = State(initialValue: document.examDate ?? fallback)
    }

    private var daysFromNow: Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: selectedDate)
        ).day ?? 0
    }

    private var intensityColor: Color {
        switch daysFromNow {
        case ...7:  return VerbaTheme.danger
        case 8...30: return VerbaTheme.orange
        default:    return VerbaTheme.green
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VerbaTheme.bg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {

                    // Context card
                    VStack(alignment: .leading, spacing: 8) {
                        Text(document.title)
                            .font(VerbaFont.syne(.semibold, size: 15))
                            .foregroundStyle(VerbaTheme.ink)
                            .lineLimit(2)
                        Text("VerbaDoc will tighten your review schedule as the exam approaches — so you hit peak readiness on the day, not after.")
                            .font(VerbaFont.syne(.regular, size: 13))
                            .foregroundStyle(VerbaTheme.muted)
                            .lineSpacing(2)
                    }
                    .padding(16)
                    .background(VerbaTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                            .stroke(VerbaTheme.border, lineWidth: 1)
                    )

                    // Date picker
                    DatePicker(
                        "exam date",
                        selection: $selectedDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(VerbaTheme.green)
                    .padding(16)
                    .background(VerbaTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                            .stroke(VerbaTheme.border, lineWidth: 1)
                    )

                    // Intensity preview
                    let intensity = StudyScheduler.examIntensity(daysToExam: daysFromNow)
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(intensityColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(daysFromNow) day\(daysFromNow == 1 ? "" : "s") away · \(intensity)")
                                .font(VerbaFont.syne(.semibold, size: 13))
                                .foregroundStyle(intensityColor)
                            Text(intensityDescription(daysFromNow: daysFromNow))
                                .font(VerbaFont.syne(.regular, size: 12))
                                .foregroundStyle(VerbaTheme.muted)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(intensityColor.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                            .stroke(intensityColor.opacity(0.15), lineWidth: 1)
                    )

                    Spacer()

                    // Save
                    Button {
                        document.examDate = selectedDate
                        try? modelContext.save()
                        dismiss()
                    } label: {
                        Text("set exam date")
                            .font(VerbaFont.syne(.semibold, size: 15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(VerbaTheme.green)
                            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("set exam date")
                        .font(VerbaFont.syne(.semibold, size: 16))
                        .foregroundStyle(VerbaTheme.ink)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                        .font(VerbaFont.syne(.regular, size: 15))
                        .foregroundStyle(VerbaTheme.muted)
                }
            }
        }
    }

    private func intensityDescription(daysFromNow: Int) -> String {
        switch daysFromNow {
        case ...0:
            return "exam is today — keep calm and recall."
        case 1...7:
            return "cram mode: reviews compress to every 1–2 days. all weak cards prioritised."
        case 8...30:
            return "intensive mode: intervals halved. weak cards reviewed twice as often."
        default:
            return "standard mode: SRS schedules normally until 30 days out."
        }
    }
}
