//
//  WatchSettingsView.swift
//  RemoteShutterWatch
//
//  Settings screen for the Watch app. Timer duration picker.
//

import SwiftUI

struct WatchSettingsView: View {
    @EnvironmentObject var viewModel: WatchCameraViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            Section("Timer") {
                ForEach(WatchCameraViewModel.timerOptions, id: \.self) { seconds in
                    Button(action: {
                        viewModel.timerSeconds = seconds
                        dismiss()
                    }) {
                        HStack {
                            Text(seconds == 0 ? "Off" : "\(seconds)s")
                                .foregroundColor(.white)
                            Spacer()
                            if viewModel.timerSeconds == seconds {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }
}
