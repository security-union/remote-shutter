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
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.viewModel)
                .environmentObject(appDelegate.sessionDelegate)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Drive the state poll loop from the scene phase. Reopening must re-sync
            // (activation/reachability callbacks don't fire when the app resumes while
            // the phone stayed reachable, and the last state shown may be long stale);
            // deactivating stops polling so the Watch isn't chattering in the pocket.
            appDelegate.sessionDelegate.setActive(newPhase == .active)
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
            // Controls only when the camera is actually live — a reachable phone
            // whose app isn't in Watch Remote mode must not show dead buttons.
            if viewModel.phase == .ready {
                WatchControlView()
            } else {
                WatchConnectionView()
            }
        }
    }
}
