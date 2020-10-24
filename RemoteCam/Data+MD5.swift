//
//  Data+MD5.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/13/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import CommonCrypto

extension Data {
    var md5 : String {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        _ =  self.withUnsafeBytes { bytes in
            CC_MD5(bytes, CC_LONG(self.count), &digest)
        }
        var digestHex = ""
        for index in 0..<Int(CC_MD5_DIGEST_LENGTH) {
            digestHex += String(format: "%02x", digest[index])
        }
        return digestHex
    }
}
