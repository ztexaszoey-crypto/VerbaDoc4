import SwiftUI

// MARK: - AvatarBuilderView
//
// Full-screen avatar customizer, presented as a sheet from ProfileEditView.
// Live preview at top; 5 customization rows below: background, fur, eyes, blush, accessory.
// Saves to AppStorage on "done". Changes are previewed in real-time.

struct AvatarBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("profile.avatarConfig") private var avatarConfigJSON = ""

    @State private var draft: AvatarConfig = AvatarConfig()

    var body: some View {
        NavigationStack {
            ZStack {
                VerbaTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {

                        // ── Live Preview ───────────────────────────────────
                        preview

                        // ── Customization Rows ─────────────────────────────
                        VStack(alignment: .leading, spacing: 24) {
                            bgColorRow
                            furColorRow
                            eyeStyleRow
                            accessoryRow
                            blushRow
                        }
                        .padding(.horizontal, 20)

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("build your capy")
                        .font(VerbaFont.syne(.semibold, size: 16))
                        .foregroundStyle(VerbaTheme.ink)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                        .font(VerbaFont.syne(.regular, size: 14))
                        .foregroundStyle(VerbaTheme.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("done") {
                        avatarConfigJSON = draft.encoded()
                        HapticManager.success()
                        dismiss()
                    }
                    .font(VerbaFont.syne(.semibold, size: 14))
                    .foregroundStyle(VerbaTheme.green)
                }
            }
        }
        .onAppear {
            draft = AvatarConfig.load(from: avatarConfigJSON)
        }
    }

    // MARK: - Preview

    private var preview: some View {
        ZStack {
            // Soft halo behind avatar
            Circle()
                .fill(draft.bgColor.color.opacity(0.25))
                .frame(width: 160, height: 160)

            AvatarView(config: draft, size: 120)
                .animation(.verba, value: draft)
        }
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    // MARK: - Background Color

    private var bgColorRow: some View {
        builderSection(title: "background") {
            colorGrid(
                items: AvatarConfig.BgColor.allCases,
                selected: draft.bgColor,
                color: { $0.color },
                onSelect: { draft.bgColor = $0 }
            )
        }
    }

    // MARK: - Fur Color

    private var furColorRow: some View {
        builderSection(title: "fur") {
            colorGrid(
                items: AvatarConfig.FurColor.allCases,
                selected: draft.furColor,
                color: { $0.color },
                onSelect: { draft.furColor = $0 }
            )
        }
    }

    // MARK: - Eye Style

    private var eyeStyleRow: some View {
        builderSection(title: "eyes") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AvatarConfig.EyeStyle.allCases, id: \.self) { style in
                        Button {
                            HapticManager.selection()
                            withAnimation(.verbaSnappy) { draft.eyeStyle = style }
                        } label: {
                            VStack(spacing: 4) {
                                Text(style.icon)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(draft.eyeStyle == style ? VerbaTheme.green : VerbaTheme.ink)
                                Text(style.name)
                                    .font(VerbaFont.syne(.regular, size: 10))
                                    .foregroundStyle(VerbaTheme.muted)
                            }
                            .frame(width: 62, height: 52)
                            .background(draft.eyeStyle == style ? VerbaTheme.green.opacity(0.08) : VerbaTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous)
                                    .stroke(draft.eyeStyle == style ? VerbaTheme.green.opacity(0.40) : VerbaTheme.border, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(.horizontal, -2)
        }
    }

    // MARK: - Accessory

    private var accessoryRow: some View {
        builderSection(title: "accessory") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AvatarConfig.Accessory.allCases, id: \.self) { acc in
                        Button {
                            HapticManager.selection()
                            withAnimation(.verbaSnappy) { draft.accessory = acc }
                        } label: {
                            VStack(spacing: 4) {
                                if acc == .none {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(VerbaTheme.muted)
                                        .frame(height: 24)
                                } else {
                                    Text(acc.emoji)
                                        .font(.system(size: 22))
                                        .frame(height: 24)
                                }
                                Text(acc.name)
                                    .font(VerbaFont.syne(.regular, size: 10))
                                    .foregroundStyle(VerbaTheme.muted)
                            }
                            .frame(width: 62, height: 52)
                            .background(draft.accessory == acc ? VerbaTheme.green.opacity(0.08) : VerbaTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous)
                                    .stroke(draft.accessory == acc ? VerbaTheme.green.opacity(0.40) : VerbaTheme.border, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(.horizontal, -2)
        }
    }

    // MARK: - Blush Toggle

    private var blushRow: some View {
        builderSection(title: "blush") {
            HStack(spacing: 12) {
                Button {
                    HapticManager.selection()
                    withAnimation(.verbaSnappy) { draft.blush = true }
                } label: {
                    blushChip(label: "on 🌸", selected: draft.blush)
                }
                .buttonStyle(.plain)

                Button {
                    HapticManager.selection()
                    withAnimation(.verbaSnappy) { draft.blush = false }
                } label: {
                    blushChip(label: "off", selected: !draft.blush)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func blushChip(label: String, selected: Bool) -> some View {
        Text(label)
            .font(VerbaFont.syne(.medium, size: 13))
            .foregroundStyle(selected ? VerbaTheme.green : VerbaTheme.muted)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(selected ? VerbaTheme.green.opacity(0.08) : VerbaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous)
                    .stroke(selected ? VerbaTheme.green.opacity(0.40) : VerbaTheme.border, lineWidth: 1.5)
            )
    }

    // MARK: - Reusable Color Grid

    private func colorGrid<T: Hashable & CaseIterable>(
        items: T.AllCases,
        selected: T,
        color: @escaping (T) -> Color,
        onSelect: @escaping (T) -> Void
    ) -> some View where T.AllCases: RandomAccessCollection {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
            spacing: 10
        ) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button {
                    HapticManager.selection()
                    withAnimation(.verbaSnappy) { onSelect(item) }
                } label: {
                    ZStack {
                        Circle()
                            .fill(color(item))
                            .frame(width: 42, height: 42)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: selected == item ? 3 : 0)
                            )
                            .overlay(
                                Circle()
                                    .stroke(selected == item ? VerbaTheme.green : Color.clear, lineWidth: 2)
                                    .padding(-2)
                            )
                        if selected == item {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Section Container

    private func builderSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(VerbaFont.syne(.semibold, size: 11))
                .foregroundStyle(VerbaTheme.muted)
                .textCase(.uppercase)
                .tracking(0.6)
            content()
        }
    }
}
