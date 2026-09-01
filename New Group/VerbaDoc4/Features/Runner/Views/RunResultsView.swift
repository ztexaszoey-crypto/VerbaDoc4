import SwiftUI

// MARK: - RunResultsView
//
// Post-run summary shown as an overlay inside VerbaRunnerView.
// Receives a RunResult value and two action callbacks — no @StateObject here.

struct RunResultsView: View {
    let result:   RunResult
    let onReplay: () -> Void
    let onExit:   () -> Void

    var body: some View {
        ZStack {
            // Frosted backdrop
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Headline ───────────────────────────────────────────────
                VStack(spacing: 6) {
                    Text(headline)
                        .font(VerbaFont.serif(size: 30))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(subline)
                        .font(VerbaFont.syne(.regular, size: 14))
                        .foregroundStyle(.white.opacity(0.60))
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 32)

                // ── Stats grid ─────────────────────────────────────────────
                VStack(spacing: 1) {
                    HStack(spacing: 1) {
                        statCell(
                            value: "\(result.score)",
                            label: "score",
                            badge: result.isNewBestScore ? "best" : nil,
                            color: .white
                        )
                        statCell(
                            value: "\(result.distance) m",
                            label: "distance",
                            badge: result.isNewBestDistance ? "best" : nil,
                            color: .white
                        )
                    }
                    HStack(spacing: 1) {
                        statCell(
                            value: formattedDuration,
                            label: "time",
                            badge: nil,
                            color: .white
                        )
                        statCell(
                            value: "\(Int(result.distance / max(Int(result.duration), 1))) m/s",
                            label: "avg speed",
                            badge: nil,
                            color: .white
                        )
                    }
                }
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 36)

                // ── Actions ────────────────────────────────────────────────
                VStack(spacing: 10) {
                    Button(action: onReplay) {
                        Text("run again")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryButtonStyle()

                    Button(action: onExit) {
                        Text("done")
                            .font(VerbaFont.syne(.regular, size: 15))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 60)
            }
        }
    }

    // MARK: - Helpers

    private var headline: String {
        if result.isNewBestScore || result.isNewBestDistance { return "new personal best." }
        if result.distance > 500  { return "solid run." }
        if result.distance > 200  { return "keep going." }
        return "just getting started."
    }

    private var subline: String {
        if result.isNewBestScore && result.isNewBestDistance {
            return "new record on both score and distance."
        }
        if result.isNewBestScore    { return "best score yet." }
        if result.isNewBestDistance { return "furthest you've gone." }
        return "you've got more in you — run it back."
    }

    private var formattedDuration: String {
        let total = Int(result.duration)
        let m = total / 60
        let s = total % 60
        return m > 0 ? "\(m):\(String(format: "%02d", s))" : "\(s)s"
    }

    private func statCell(value: String, label: String, badge: String?, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Text(value)
                    .font(VerbaFont.syne(.bold, size: 22))
                    .foregroundStyle(color)
                if let badge {
                    Text(badge)
                        .font(VerbaFont.syne(.semibold, size: 9))
                        .foregroundStyle(VerbaTheme.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(VerbaTheme.green.opacity(0.20))
                        .clipShape(Capsule())
                }
            }
            Text(label)
                .font(VerbaFont.syne(.regular, size: 11))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}
