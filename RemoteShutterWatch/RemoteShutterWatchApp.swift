//
//  RemoteShutterWatchApp.swift
//  RemoteShutterWatch
//
//  Apple Watch companion app for Remote Shutter.
//  Acts as a standalone remote control for the paired iPhone's camera.
//

import SwiftUI
import WatchKit

@main
struct RemoteShutterWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.viewModel)
                .environmentObject(appDelegate.sessionDelegate)
        }
    }
}

// MARK: - App Delegate

class WatchAppDelegate: NSObject, WKApplicationDelegate {
    let viewModel = WatchCameraViewModel()
    lazy var sessionDelegate: WatchSessionDelegate = WatchSessionDelegate(viewModel: viewModel)

    func applicationDidFinishLaunching() {
        sessionDelegate.activate()
    }
}

// MARK: - Content View (routes between connected/disconnected)

struct ContentView: View {
    @EnvironmentObject var viewModel: WatchCameraViewModel

    var body: some View {
        NavigationStack {
            // Show controls if we have state OR if the phone is reachable
            if viewModel.isConnected || viewModel.isPhoneReachable {
                WatchControlView()
            } else {
                WatchConnectionView()
            }
        }
    }
}
