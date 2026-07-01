//
//  WatchConnectionView.swift
//  RemoteShutterWatch
//
//  Shown whenever the camera controls can't be used yet. The message tracks
//  the connection phase so the user always knows the next step to take.
//

import SwiftUI

struct WatchConnectionView: View {
    @EnvironmentObject var viewModel: WatchCameraViewModel
    @EnvironmentObject var session: WatchSessionDelegate

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundColor(iconColor)

                Text("Remote Shutter")
                    .font(.headline)
                    .foregroundColor(.white)

                Text(message)
                    .font(.caption)
                    .foregroundColor(messageColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                // No action button while the phone is backgrounded/closed: there is
                // nothing the user can do from the Watch to reopen the iPhone app
                // (Apple exposes no public API to foreground the companion app), and
                // a button would only invite people to keep trying to shoot.
                if viewModel.phase != .phoneNotReady {
                    Button(action: {
                        session.manualRetry()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .font(.body)
                        .foregroundColor(.green)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }
            }
            .padding()
        }
    }

    private var icon: String {
        switch viewModel.phase {
        case .phoneNotInWatchMode: return "iphone.gen3"
        case .phoneNotReady: return "iphone.gen3"
        default: return "applewatch.and.arrow.forward"
        }
    }

    private var iconColor: Color {
        switch viewModel.phase {
        case .phoneNotInWatchMode, .phoneNotReady: return .orange
        default: return .green
        }
    }

    private var message: LocalizedStringKey {
        switch viewModel.phase {
        case .phoneNotInWatchMode:
            return "On your iPhone, tap “Watch Remote”"
        case .phoneNotReady:
            return "Remote Shutter app was closed on your phone"
        case .connecting:
            return viewModel.isPhoneReachable
                ? "Found your iPhone. Getting ready…"
                : "Can’t reach your iPhone"
        case .inactive, .ready:
            return "Open Remote Shutter on your iPhone and choose “Watch Remote”"
        }
    }

    private var messageColor: Color {
        switch viewModel.phase {
        case .phoneNotInWatchMode, .phoneNotReady: return .orange
        case .connecting: return viewModel.isPhoneReachable ? .green : .orange
        case .inactive, .ready: return .secondary
        }
    }
}
