//
//  Data+MD5.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/13/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import CryptoKit

extension Data {
    var md5: String {
        Insecure.MD5.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
