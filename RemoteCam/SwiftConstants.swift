//
//  SwiftConstants.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/12/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import UIKit

public let tempFile = "remoteshutter_video.mov"

/// The self-timer preset, one preference shared by the classic remote and the
/// multicam director — a single key and accessor so the two can never drift.
enum TimerPreference {
    static let key = "timerDefault"
    static var seconds: Int {
        get { UserDefaults.standard.integer(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// The director's rig standby, remembered across sessions like the timer:
/// a rig that was left in standby opens in standby, and every camera that
/// joins is put there, without tapping the tray again. Unset means off.
enum RigStandbyPreference {
    static let key = "rig.standby"
    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Whether the director shows the exposure readouts and rulers. Off by
/// default: most users came for zoom, and manual exposure changes what a
/// photo is (single frame, no HDR merge), so the person asks for it once,
/// from the EXPOSURE tray tile, and it stays.
enum ExposureControlsPreference {
    static let key = "rig.exposureControls"
    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// "Send Media to Remote" (Settings): whether the camera pushes each capture
/// back to the remote that fired it. ONE reader for every remote surface —
/// the classic 1:1 monitor and the multicam director both put this on the
/// wire, and the Settings sheet edits it. Unset means on.
enum SendMediaPreference {
    static let key = "sendMediaToRemote"
    static var isEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: key) == nil
                ? true
                : UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

let AppStoreURL = URL(string: "https://apps.apple.com/us/app/remote-shutter/id633274861")!
// SKStoreReviewController is rate-limited by the system (~3/year) and can show
// nothing at all, so it is only fit for the unsolicited prompt. A deliberate tap
// goes here instead: the write-review deep link is never throttled.
let AppStoreReviewURL = URL(string: "https://apps.apple.com/us/app/remote-shutter/id633274861?action=write-review")!
let GearURL = URL(string: "https://remoteshutter.app/gear?src=app")!
public let disableAdsPID = "05"
public let enableVideoPID = "06"
public let enableTorchPID = "07"
public let enableVideoOnlyPID = "08"
public let tapToFocusPID = "09"
/// One-time pack: multicam directing at the paid camera cap. The id is
/// cap-agnostic on purpose — the same purchase grows with `maxPaidCameras`
/// as larger rigs are validated; only the marketing copy names a number.
public let maxCamerasPID = "max_cameras"
// Auto-renewable "Pro" subscription (group "Pro"). Unlocks every feature for
// the subscription period — the recurring equivalent of the one-time 06 bundle.
public let proMonthlyPID = "pro_monthly"
public let proYearlyPID = "pro_yearly"
// MARK: - Rate on App Store

func openAppStoreReview() {
    UIApplication.shared.open(AppStoreReviewURL)
}

// MARK: - Recommended Gear Web Page

// Deliberately the system browser rather than SFSafariViewController. The gear
// page sends people on to Amazon, and since iOS 11 an SFSafariViewController
// keeps its own cookie store, isolated from Safari — so an affiliate cookie set
// inside one is stranded there the moment the shopper continues in the Amazon
// app, and the referral goes uncredited. Handing off to Safari also lets
// Amazon's universal links open its app directly, which is what Amazon asks
// Associates to do.
func openGearPage() {
    UIApplication.shared.open(GearURL)
}
