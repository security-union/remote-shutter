//
//  WatchConnectionView.swift
//  RemoteShutterWatch
//
//  Shown when iPhone app is not connected yet. Includes retry button.
//

import SwiftUI

struct WatchConnectionView: View {
    @EnvironmentObject var viewModel: WatchCameraViewModel
    @EnvironmentObject var session: WatchSessionDelegate

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "applewatch.and.arrow.forward")
                    .font(.system(size: 36))
                    .foregroundColor(.green)

                Text("Remote Shutter")
                    .font(.headline)
                    .foregroundColor(.white)

                if viewModel.isPhoneReachable {
                    Text("iPhone found. Syncing...")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if viewModel.isSessionActive {
                    Text("iPhone not reachable")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("Open the app on your iPhone and select \"Watch Remote\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

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
            .padding()
        }
    }
}
