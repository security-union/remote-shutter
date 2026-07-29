//
//  PeerLinkStatus.swift
//  RemoteShutter
//
//  The peer link as published state, not as a presented alert.
//

import SwiftUI

/// Whether the remote peer is reachable right now, published for the screens
/// to render.
///
/// The reconnect UI is a pure function of this value — `.linked` has no branch
/// that draws an overlay, so an alert cannot outlive a reconnect. (The imperative
/// version could: `UIAlertController` presented in its own window survived the
/// pop back to the scanner, and the later `dismiss` no-oped.)
///
/// The session coordinator is the only writer, via `SessionCoordinator`'s
/// `peerLinkStatus` seam; the value is derived from the machine's own view of
/// the peer, so "we are talking to the peer" and "the overlay is gone" are the
/// same fact rather than two facts that can disagree.
@MainActor
final class PeerLinkStatus: ObservableObject {

    enum Link: Equatable {
        /// Traffic flows (or no session is up — nothing to say).
        case linked
        /// The peer announced it was backgrounding, or its link dropped and we
        /// are re-inviting. Same user-facing story: waiting, with a way out.
        case reconnecting(peerName: String)
    }

    /// Shared instance: the screens observe it, the coordinator writes it.
    /// Tests use their own instance through the coordinator's setter.
    /// `nonisolated` so non-main contexts (the session actor) can hold a
    /// reference; the instance's state stays main-actor-isolated.
    nonisolated static let shared = PeerLinkStatus()

    nonisolated init() {}

    @Published private(set) var link: Link = .linked

    /// Invoked when the user asks to stop waiting. Set by the screen that owns
    /// the session (`DeviceScannerViewController`).
    var onCancel: (() -> Void)?

    func setReconnecting(peerName: String) {
        link = .reconnecting(peerName: peerName)
    }

    func setLinked() {
        link = .linked
    }

    func cancel() {
        onCancel?()
    }
}

/// The waiting overlay. Rendered only where `link` says so; there is no
/// dismiss path to forget.
struct PeerLinkOverlay: View {
    @ObservedObject var status: PeerLinkStatus

    var body: some View {
        if case .reconnecting(let peerName) = status.link {
            ZStack {
                Color.black.opacity(0.65)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)

                    Text(String(
                        format: NSLocalizedString(
                            "PeerBackgroundedReconnecting",
                            value: "%@ is in the background — reconnecting…",
                            comment: "Shown while waiting for a backgrounded peer to return"),
                        peerName))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(NSLocalizedString("Cancel", comment: "")) {
                        status.cancel()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
                }
                .padding(28)
                .frame(maxWidth: 320)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.55)))
            }
            .transition(.opacity)
        }
    }
}
