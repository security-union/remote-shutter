//
//  Photos.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 9/23/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation

func goToPhotos() {
    UIApplication.shared.open(URL(string: "photos-redirect://")!)
}
