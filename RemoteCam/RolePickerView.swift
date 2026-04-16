import SwiftUI

struct RolePickerView: View {
    let onCamera: () -> Void
    let onRemote: () -> Void
    let onWatchRemote: (() -> Void)?
    let isWatchPaired: Bool

    @State private var appeared = false

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 20)

                // Two glass panels
                VStack(spacing: 12) {
                    Button(action: onCamera) {
                        glassPanel(
                            icon: "camera.fill",
                            title: NSLocalizedString("Camera", comment: ""),
                            subtitle: NSLocalizedString("Capture photos & video", comment: ""),
                            detail: NSLocalizedString("Use the device with the best lens", comment: ""),
                            tint: AppTheme.accent
                        )
                    }
                    .buttonStyle(GlassButtonStyle())
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)

                    Button(action: onRemote) {
                        glassPanel(
                            icon: "antenna.radiowaves.left.and.right",
                            title: NSLocalizedString("Remote", comment: ""),
                            subtitle: NSLocalizedString("Control the shutter", comment: ""),
                            detail: NSLocalizedString("Works up to 50 feet away", comment: ""),
                            tint: AppTheme.secondary
                        )
                    }
                    .buttonStyle(GlassButtonStyle())
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)

                    if isWatchPaired, let onWatchRemote = onWatchRemote {
                        Button(action: onWatchRemote) {
                            glassPanel(
                                icon: "applewatch",
                                title: NSLocalizedString("Watch Remote", comment: ""),
                                subtitle: NSLocalizedString("Control from your wrist", comment: ""),
                                detail: NSLocalizedString("No second device needed", comment: ""),
                                tint: Color.green
                            )
                        }
                        .buttonStyle(GlassButtonStyle())
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
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
        detail: String,
        tint: Color
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(AppTheme.glassBorder, lineWidth: 0.5)
                )
                .shadow(color: AppTheme.glassShadow, radius: 16, y: 8)

            VStack(spacing: 12) {
                Spacer()

                // Icon with glow
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.12))
                        .frame(width: 80, height: 80)

                    Circle()
                        .strokeBorder(tint.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 80, height: 80)

                    Image(systemName: icon)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(tint)
                }

                VStack(spacing: 6) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Bottom detail
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.caption2)
                        .foregroundColor(tint.opacity(0.7))
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(tint)
                }
                .padding(12)
                .background(tint.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Press Effect

private struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

struct RolePickerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            RolePickerView(
                onCamera: {},
                onRemote: {},
                onWatchRemote: {},
                isWatchPaired: true
            )
            .navigationTitle(NSLocalizedString("Pick a role", comment: ""))
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
