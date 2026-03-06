import SwiftUI

struct RolePickerView: View {
    let onCamera: () -> Void
    let onRemote: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                roleCard(
                    icon: "camera.fill",
                    title: NSLocalizedString("Camera", comment: ""),
                    description: NSLocalizedString("The device that captures the photo.", comment: ""),
                    tip: NSLocalizedString("Choose the device with the best camera.", comment: ""),
                    tint: .blue,
                    action: onCamera
                )

                roleCard(
                    icon: "antenna.radiowaves.left.and.right",
                    title: NSLocalizedString("Remote", comment: ""),
                    description: NSLocalizedString("The device that triggers the shutter.", comment: ""),
                    tip: NSLocalizedString("Works from up to 50 feet away.", comment: ""),
                    tint: .red,
                    action: onRemote
                )
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - Role Card

    private func roleCard(
        icon: String,
        title: String,
        description: String,
        tip: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(tint)
                    .frame(width: 56, height: 56)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text(tip)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundColor(tint.opacity(0.5))
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(tint.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

struct RolePickerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            RolePickerView(
                onCamera: {},
                onRemote: {},
                onSettings: {}
            )
            .navigationTitle(NSLocalizedString("Pick a role", comment: ""))
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
