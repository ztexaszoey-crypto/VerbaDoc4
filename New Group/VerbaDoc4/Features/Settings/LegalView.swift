import SwiftUI

// MARK: - LegalView
//
// Displays Privacy Policy or Terms of Service.
// Reachable from Settings. Required for App Store submission.

enum LegalType {
    case privacy
    case terms

    var title: String {
        switch self {
        case .privacy: return "Privacy Policy"
        case .terms:   return "Terms of Service"
        }
    }

    var effectiveDate: String { "May 14, 2026" }
}

struct LegalView: View {
    let type: LegalType

    var body: some View {
        ZStack {
            VerbaTheme.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text(type.title.lowercased())
                            .font(VerbaFont.serif(size: 26))
                            .foregroundStyle(VerbaTheme.ink)
                        Text("effective \(type.effectiveDate)")
                            .font(VerbaFont.syne(.regular, size: 13))
                            .foregroundStyle(VerbaTheme.muted)
                    }
                    .padding(.top, 4)

                    // Body
                    switch type {
                    case .privacy: privacyContent
                    case .terms:   termsContent
                    }

                    Spacer(minLength: 60)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(type.title.lowercased())
                    .font(VerbaFont.syne(.semibold, size: 16))
                    .foregroundStyle(VerbaTheme.ink)
            }
        }
    }

    // MARK: - Privacy Policy Content

    private var privacyContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            legalSection("what we collect") {
                """
                VerbaDoc processes the text content you provide (notes, PDFs, photos) solely to generate flashcards and study materials. This content is sent to our AI provider (Groq, Inc.) to produce your study set and is not stored on our servers beyond the duration of that request.

                All flashcard data, mastery scores, and study history are stored locally on your device using Apple's SwiftData framework. We do not have access to this data.
                """
            }

            legalSection("what we do not collect") {
                """
                We do not collect your name, email address, or any account information. We do not track your location. We do not use advertising identifiers. We do not sell, rent, or share your data with third parties for marketing purposes.
                """
            }

            legalSection("third-party services") {
                """
                VerbaDoc uses Groq, Inc. to process content for flashcard generation. Content you submit is subject to Groq's privacy policy (groq.com). We transmit only the text you provide for processing — no device identifiers or personal data are included in these requests.
                """
            }

            legalSection("data storage & security") {
                """
                Your study data is stored locally on your device and protected by iOS's built-in security. We do not operate servers that store your personal information. If you delete the app, all local data is permanently removed.
                """
            }

            legalSection("children's privacy") {
                """
                VerbaDoc is not directed to children under 13. We do not knowingly collect personal information from children.
                """
            }

            legalSection("changes to this policy") {
                """
                We may update this Privacy Policy from time to time. Continued use of VerbaDoc after changes are posted constitutes acceptance of the revised policy.
                """
            }

            legalSection("contact") {
                """
                For questions about this Privacy Policy, contact us at: support@verbadoc.app
                """
            }
        }
    }

    // MARK: - Terms of Service Content

    private var termsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            legalSection("acceptance") {
                """
                By downloading or using VerbaDoc, you agree to these Terms of Service. If you do not agree, do not use the app.
                """
            }

            legalSection("permitted use") {
                """
                VerbaDoc is licensed to you for personal, non-commercial educational use. You may use the app to study your own notes and documents. You may not use VerbaDoc to generate content for resale, distribution, or any commercial purpose.
                """
            }

            legalSection("your content") {
                """
                You retain ownership of the notes and documents you submit. By using VerbaDoc, you grant us a limited license to process your content solely for the purpose of generating your study materials. You are responsible for ensuring you have the right to submit any content you provide.
                """
            }

            legalSection("intellectual property") {
                """
                VerbaDoc and all associated software, design, and trademarks are the property of VerbaDoc and are protected by applicable intellectual property laws. You may not copy, modify, distribute, or reverse-engineer any part of the app.
                """
            }

            legalSection("disclaimer of warranties") {
                """
                VerbaDoc is provided "as is" without warranties of any kind. We do not guarantee that the app will be error-free, uninterrupted, or that the study materials generated will be accurate. AI-generated content should be verified against authoritative sources.
                """
            }

            legalSection("limitation of liability") {
                """
                To the maximum extent permitted by law, VerbaDoc shall not be liable for any indirect, incidental, or consequential damages arising from your use of the app, including but not limited to exam outcomes or academic results.
                """
            }

            legalSection("termination") {
                """
                We reserve the right to terminate or restrict access to VerbaDoc at any time, without notice, for any reason.
                """
            }

            legalSection("governing law") {
                """
                These Terms are governed by the laws of the jurisdiction in which VerbaDoc is incorporated, without regard to conflict of law principles.
                """
            }

            legalSection("contact") {
                """
                For questions about these Terms, contact us at: support@verbadoc.app
                """
            }
        }
    }

    // MARK: - Section Builder

    private func legalSection(_ heading: String, body: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading)
                .font(VerbaFont.syne(.semibold, size: 13))
                .foregroundStyle(VerbaTheme.ink)
                .textCase(.uppercase)
                .tracking(0.4)
            Text(body())
                .font(VerbaFont.syne(.regular, size: 14))
                .foregroundStyle(VerbaTheme.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
