import SwiftUI

struct RolePickerView: View {
    let onCamera: () -> Void
    let onRemote: () -> Void
    let onWatchRemote: (() -> Void)?

    /// Live pairing state — WCSession activation completes asynchronously, so
    /// observing keeps the Watch Remote button from being missing on cold launch.
    @ObservedObject private var watchManager = WatchSessionManager.shared

    @State private var appeared = false

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient

            VStack(spacing: 12) {
                Spacer()

                Button(action: openGearPage) {
                    glassPanel(
                        icon: "bag.fill",
                        title: NSLocalizedString("Recommended Gear", comment: ""),
                        subtitle: NSLocalizedString("Tripods, mounts & lenses", comment: ""),
                        tint: AppTheme.accentLight
                    )
                }
                .buttonStyle(.plain)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)

                Button(action: onCamera) {
                    glassPanel(
                        icon: "camera.fill",
                        title: NSLocalizedString("Camera", comment: ""),
                        subtitle: NSLocalizedString("Capture photos & video", comment: ""),
                        tint: AppTheme.accent
                    )
                }
                .buttonStyle(.plain)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)

                Button(action: onRemote) {
                    glassPanel(
                        icon: "antenna.radiowaves.left.and.right",
                        title: NSLocalizedString("Remote", comment: ""),
                        subtitle: NSLocalizedString("Control the shutter", comment: ""),
                        tint: AppTheme.secondary
                    )
                }
                .buttonStyle(.plain)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)

                if watchManager.watchPaired, let onWatchRemote = onWatchRemote {
                    Button(action: onWatchRemote) {
                        glassPanel(
                            icon: "applewatch",
                            title: NSLocalizedString("Watch Remote", comment: ""),
                            subtitle: NSLocalizedString("Control from your wrist", comment: ""),
                            tint: Color.green
                        )
                    }
                    .buttonStyle(.plain)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                appeared = true
            }
        }
    }

    // MARK: - Glass Panel

    private func glassPanel(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 56, height: 56)

                Circle()
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 56, height: 56)

                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundColor(tint.opacity(0.6))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(AppTheme.glassBorder, lineWidth: 0.5)
                )
                .shadow(color: AppTheme.glassShadow, radius: 8, y: 4)
        )
    }
}

// MARK: - Preview

struct RolePickerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            RolePickerView(
                onCamera: {},
                onRemote: {},
                onWatchRemote: {}
            )
            .navigationTitle(NSLocalizedString("Pick a role", comment: ""))
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
