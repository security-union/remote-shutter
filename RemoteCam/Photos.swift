//
//  Photos.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 9/23/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import UIKit

func goToPhotos() {
    #if targetEnvironment(macCatalyst)
    UIApplication.shared.open(URL(string: "/Applications/Photos.app")!)
    #else
    UIApplication.shared.open(URL(string: "photos-redirect://")!)
    #endif
}

func getOrientation() -> UIInterfaceOrientation {
    #if targetEnvironment(macCatalyst)
    // Macs don't rotate and their cameras are landscape-native: report a
    // fixed landscape orientation so capture connections and streamed frames
    // stay unrotated and monitors render them as-is.
    return .landscapeRight
    #else
    return UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first(where: { $0.activationState == .foregroundActive })?
        .interfaceOrientation ?? .portrait
    #endif
}
