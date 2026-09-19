import SwiftUI
import RevenueCat

// MARK: - PaywallView (Phase 2 — pastel matcha rewrite of the previous
// dark-gold premium intent)
//
// Visual language: same chunky 3D + sticky-note chassis as the rest of
// VerbaFlow. Gold → mint/cream/capybara-yellow accents. Same animation
// phases & RevenueCat wiring; only the visual chassis has shifted to
// FELIwS pastel.

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var purchases = PurchaseService.shared

    @State private var selectedPlan: PlanType = .annual
    @State private var purchaseError: String? = nil

    // Animation phases
    @State private var phase0 = false // hero
    @State private var phase1 = false // stats
    @State private var phase2 = false // features
    @State private var phase3 = false // plans
    @State private var glowPulse = false

    enum PlanType { case monthly, annual }

    // MARK: - RevenueCat

    private var monthlyPackage: Package? { purchases.monthlyPackage }
    private var annualPackage:  Package? { purchases.annualPackage  }

    private func price(for plan: PlanType) -> String {
        switch plan {
        case .monthly: return monthlyPackage?.storeProduct.localizedPriceString ?? "$5.99"
        case .annual:  return annualPackage?.storeProduct.localizedPriceString  ?? "$34.99"
        }
    }

    private var monthlyEquivalentFromAnnual: String {
        guard let pkg = annualPackage else { return "$2.92" }
        let monthly = pkg.storeProduct.price as Decimal / 12
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.locale = pkg.storeProduct.priceFormatter?.locale ?? .current
        return fmt.string(from: monthly as NSDecimalNumber) ?? "$2.92"
    }

    private var selectedPackage: Package? {
        selectedPlan == .annual ? annualPackage : monthlyPackage
    }

    // MARK: - Features

    private struct Feature {
        let icon: String
        let title: String
        let detail: String
        let proOnly: Bool
    }

    private let features: [Feature] = [
        Feature(icon: "sparkles",             title: "Unlimited AI",       detail: "Generate forever",          proOnly: true),
        Feature(icon: "rectangle.stack.fill", title: "Unlimited Decks",    detail: "No cap, ever",              proOnly: true),
        Feature(icon: "infinity",             title: "Unlimited Cards",    detail: "Per deck, always",          proOnly: true),
        Feature(icon: "checkmark.seal.fill",  title: "Exam Mode",          detail: "Multiple choice tests",     proOnly: true),
        Feature(icon: "chart.xyaxis.line",    title: "Analytics",          detail: "Track retention over time", proOnly: true),
        Feature(icon: "square.and.arrow.up",  title: "File Export",        detail: "Anki, CSV, more",           proOnly: true),
        Feature(icon: "brain.head.profile",   title: "Spaced Repetition",  detail: "SM-2 algorithm",            proOnly: false),
        Feature(icon: "bolt.fill",            title: "Quiz Portal",        detail: "Pick notes, get tested",    proOnly: false),
        Feature(icon: "gamecontroller.fill",  title: "Capy Surfers",       detail: "Endless runner game",       proOnly: false),
    ]

    // MARK: - Body

    var body: some View {
        CozyBackdrop {
            ScrollView(showsIndicators: false) {
                // Cap dynamic-type at xxxLarge so the 52pt GO PRO headline
                // and 60pt CTA do not overflow on accessibility text scales.
                // Trust pills + body type below respect the user's scale
                // preference (Syne is laid out at .medium/.regular).
                VStack(spacing: 0) {
                    hero
                    statsStrip
                        .padding(.top, 28)
                        .opacity(phase1 ? 1 : 0)
                        .offset(y: phase1 ? 0 : 16)
                    featureGrid
                        .padding(.top, 28)
                        .padding(.horizontal, 20)
                        .opacity(phase2 ? 1 : 0)
                        .offset(y: phase2 ? 0 : 20)
                    planPicker
                        .padding(.top, 28)
                        .padding(.horizontal, 20)
                        .opacity(phase3 ? 1 : 0)
                        .offset(y: phase3 ? 0 : 20)
                    ctaBlock
                        .padding(.top, 24)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 52)
                        .opacity(phase3 ? 1 : 0)
                }
            }
            // Phase 6: dynamicTypeSize cap removed \u2014 let cozyBlockButtonStyle scale naturally.

            // Close (top-trailing)
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            // >=16pt + 44x44 to satisfy iOS 44pt-tap-target legibility
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(VerbaTheme.cozyForest)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(VerbaTheme.cozySage))
                            .overlay(Circle().stroke(VerbaTheme.cozyForest, lineWidth: 4))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)
                Spacer()
            }
        }
        .alert("Purchase Error", isPresented: Binding(get: { purchaseError != nil }, set: { if !$0 { purchaseError = nil } })) {
            Button("OK", role: .cancel) { purchaseError = nil }
        } message: { Text(purchaseError ?? "") }
        .alert(restoreTitle, isPresented: Binding(get: { purchases.restoreMessage != nil }, set: { if !$0 { purchases.clearRestoreMessage() } })) {
            Button("OK", role: .cancel) {
                purchases.clearRestoreMessage()
                if purchases.isPro { dismiss() }
            }
        } message: { Text(restoreBody) }
        .task { await purchases.fetchOfferings() }
        .onAppear { startAnimations() }
        .onChange(of: purchases.isPro) { _, isPro in if isPro { dismiss() } }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            VerbaTheme.cozySage

            VStack(spacing: 0) {
                Spacer().frame(height: 78)

                // Mascot hero block — cozy sage
                ZStack {
                    Circle()
                        .fill(VerbaTheme.cozySage)
                        .frame(width: 130, height: 130)
                        .overlay(
                            Circle()
                                .stroke(VerbaTheme.cozyForest, lineWidth: VerbaTheme.cozyStroke)
                        )
                    VerbaMascot(mood: .excited, size: 88)
                }
                .opacity(phase0 ? 1 : 0)
                .scaleEffect(phase0 ? 1 : 0.75)
                .padding(.bottom, 28)

                // Headline
                VStack(spacing: 6) {
                    Text("GO PRO.")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .tracking(-1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .allowsTightening(true)
                        .opacity(phase0 ? 1 : 0)
                        .offset(y: phase0 ? 0 : 18)

                    HStack(spacing: 0) {
                        Text("Everything. ")
                            .foregroundStyle(VerbaTheme.oliveBorder)
                        Text("Unlimited.")
                            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    }
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .opacity(phase0 ? 1 : 0)
                    .offset(y: phase0 ? 0 : 12)
                }

                // Diagonal divider
                pastelDivider
                    .padding(.top, 28)
                    .opacity(phase0 ? 1 : 0)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .frame(height: 440)
        .clipShape(Rectangle())
    }

    private var pastelDivider: some View {
        HStack(spacing: 0) {
            Rectangle().fill(VerbaTheme.oliveBorder.opacity(0.0))
            Rectangle().fill(VerbaTheme.oliveBorder.opacity(0.45)).frame(height: 1)
            Rectangle().fill(VerbaTheme.oliveBorder.opacity(0.0))
        }
        .frame(height: 1)
    }

    // MARK: - Stats Strip

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statCell(value: "∞", label: "decks")
            dividerV
            statCell(value: "∞", label: "AI gens")
            dividerV
            statCell(value: monthlyEquivalentFromAnnual, label: "per month")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(VerbaTheme.cozySage)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VerbaTheme.cozyForest, lineWidth: 4)
        )
        .padding(.horizontal, 20)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(VerbaTheme.oliveBorder)
            Text(label)
                .font(VerbaFont.syne(.medium, size: 12))
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
        }
        .frame(maxWidth: .infinity)
    }

    private var dividerV: some View {
        Rectangle()
            .fill(VerbaTheme.oliveBorder.opacity(0.30))
            .frame(width: 1, height: 36)
    }

    // MARK: - Feature Grid

    private var featureGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WHAT YOU GET")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(VerbaTheme.oliveBorder)
                .tracking(2)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(features, id: \.title) { f in
                    featureCard(f)
                }
            }
        }
    }

    private func featureCard(_ f: Feature) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: f.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(f.proOnly ? VerbaTheme.oliveBorder : VerbaTheme.ctaTop)
                .frame(width: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(f.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(VerbaTheme.cozyForest)
                    .lineLimit(1)
                Text(f.detail)
                    .font(VerbaFont.syne(.regular, size: 11))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(f.proOnly ? VerbaTheme.cozyMustard : VerbaTheme.cozySage)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VerbaTheme.cozyForest, lineWidth: 4)
        )
    }

    // MARK: - Plan Picker

    private var planPicker: some View {
        VStack(spacing: 10) {
            Text("CHOOSE YOUR PLAN")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(VerbaTheme.oliveBorder)
                .tracking(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Annual (mint chip — selected)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selectedPlan = .annual }
            } label: {
                HStack(spacing: 14) {
                    radioDot(selected: selectedPlan == .annual,
                             color: VerbaTheme.flowerGold)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Annual")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(VerbaTheme.cozyForest)
                            Text("BEST VALUE")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(VerbaTheme.cozyForest)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(VerbaTheme.flowerGold)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        Text("\(monthlyEquivalentFromAnnual)/mo · billed as \(price(for: .annual))")
                            .font(VerbaFont.syne(.regular, size: 12))
                            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Save 51%")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(VerbaTheme.oliveBorder)
                        Text(price(for: .annual))
                            .font(VerbaFont.syne(.bold, size: 14))
                            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    }
                }
                .padding(18)
                .background(selectedPlan == .annual ? VerbaTheme.cozyLime : VerbaTheme.cozySage)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(VerbaTheme.cozyForest, lineWidth: 4)
                )
            }

            // Monthly (compact cream chip)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selectedPlan = .monthly }
            } label: {
                HStack(spacing: 14) {
                    radioDot(selected: selectedPlan == .monthly,
                             color: VerbaTheme.darkOliveInk.opacity(0.6))

                    Text("Monthly")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(VerbaTheme.darkOliveInk.opacity(0.85))

                    Spacer()

                    Text(price(for: .monthly) + "/mo")
                        .font(VerbaFont.syne(.bold, size: 14))
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(VerbaTheme.cozySage)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(VerbaTheme.cozyForest, lineWidth: 4)
                )
            }
        }
    }

    private func radioDot(selected: Bool, color: Color) -> some View {
        ZStack {
            Circle()
                // Unselected ring uses mediumOliveMuted (#697A4A) for AA-grade
                // contrast against cream card chassis; the previous low-opacity
                // olive ring shipped <3.0:1 and read as faint.
                .stroke(selected ? color : VerbaTheme.mediumOliveMuted, lineWidth: 2)
                .frame(width: 20, height: 20)
            if selected {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .transition(.scale)
            }
        }
    }

    // MARK: - CTA

    private var ctaBlock: some View {
        VStack(spacing: 14) {
            // Cozy 3D purchase button (no hardcoded height)
            Button {
                Task { await purchase() }
            } label: {
                HStack(spacing: 10) {
                    if purchases.isLoading {
                        ProgressView().tint(VerbaTheme.darkOliveInk)
                    } else {
                        Text("Start Pro")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(VerbaTheme.cozyForest)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .allowsTightening(true)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(VerbaTheme.cozyForest)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .cozyBlockButtonStyle()
            .disabled(purchases.isLoading || selectedPackage == nil)
            .animation(.spring(response: 0.3), value: purchases.isLoading)

            // Trust pills
            HStack(spacing: 18) {
                trustPill(icon: "lock.fill",        text: "Secure")
                trustPill(icon: "arrow.uturn.left", text: "Cancel anytime")
                trustPill(icon: "applelogo",        text: "App Store")
            }
            .frame(maxWidth: .infinity)

            // ── Required App Store subscription disclosure (Guideline 3.1.2) ──
            // This text is mandatory. Do not remove or shorten it.
            Text("Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless auto-renew is turned off at least 24 hours before the end of the current period. Manage subscriptions in App Store settings.")
                .font(VerbaFont.syne(.regular, size: 11))
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("restore purchases") { Task { await purchases.restorePurchases() } }
                    .disabled(purchases.isLoading)
                Text("·").foregroundStyle(VerbaTheme.cozyOliveSubtext.opacity(0.5))
                Link("terms",   destination: URL(string: "https://verbadoc.app/terms")!)
                Text("·").foregroundStyle(VerbaTheme.cozyOliveSubtext.opacity(0.5))
                Link("privacy", destination: URL(string: "https://verbadoc.app/privacy")!)
            }
            .font(VerbaFont.syne(.regular, size: 12))
            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
        }
    }

    private func trustPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(VerbaFont.syne(.medium, size: 11))
        }
        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
    }

    // MARK: - Purchase

    private func purchase() async {
        guard let pkg = selectedPackage else {
            await purchases.fetchOfferings()
            guard let pkg2 = selectedPackage else {
                purchaseError = "Could not load products. Check your connection and try again."
                return
            }
            if let err = await purchases.purchase(package: pkg2) { purchaseError = err }
            return
        }
        if let err = await purchases.purchase(package: pkg) { purchaseError = err }
    }

    // MARK: - Alerts

    private var restoreTitle: String {
        switch purchases.restoreMessage {
        case .restored:         return "Pro Restored"
        case .nothingToRestore: return "Nothing to Restore"
        case .error:            return "Restore Failed"
        case nil:               return ""
        }
    }

    private var restoreBody: String {
        switch purchases.restoreMessage {
        case .restored:           return "Your Pro subscription has been restored."
        case .nothingToRestore:   return "No active Pro subscription found on this Apple ID."
        case .error(let msg):     return msg
        case nil:                 return ""
        }
    }

    // MARK: - Animations

    private func startAnimations() {
        // Respect Reduce Motion (Settings → Accessibility → Reduce Motion).
        if UIAccessibility.isReduceMotionEnabled {
            phase0 = true
            phase1 = true
            phase2 = true
            phase3 = true
            // glowPulse left off — pure motion.
            return
        }

        withAnimation(.spring(response: 0.6, dampingFraction: 0.72).delay(0.05)) { phase0 = true }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(0.30)) { phase1 = true }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(0.50)) { phase2 = true }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(0.65)) { phase3 = true }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true))  { glowPulse = true }
    }
}
