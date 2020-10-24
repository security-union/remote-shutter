//
//  Photos.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 9/23/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation

func goToPhotos() {
    #if targetEnvironment(macCatalyst)
    UIApplication.shared.open(URL(string: "/Applications/Photos.app")!)
    #else
    UIApplication.shared.open(URL(string: "photos-redirect://")!)
    #endif
}

func getOrientation() -> UIInterfaceOrientation {
    if #available(iOS 13.0, *) {
        return UIApplication.shared.windows.first?
                .windowScene?
                .interfaceOrientation ?? UIApplication.shared.statusBarOrientation
    } else {
        return UIApplication.shared.statusBarOrientation
    }
}
