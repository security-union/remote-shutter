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
    return UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first(where: { $0.activationState == .foregroundActive })?
        .interfaceOrientation ?? .portrait
}
