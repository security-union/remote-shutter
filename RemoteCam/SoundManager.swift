//
//  SoundManager.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import AVFoundation

/// Plays the countdown beep sounds bundled with the app.
final class SoundManager {

    enum Beep {
        case slow
        case fast

        fileprivate var url: URL? {
            switch self {
            case .slow:
                return Bundle.main.url(forResource: "beep", withExtension: "m4a")
            case .fast:
                return Bundle.main.url(forResource: "fastBeep", withExtension: "aif")
            }
        }
    }

    private var player: AVAudioPlayer?

    func playBeepSound(_ beep: Beep) {
        stopPlayer()
        guard let url = beep.url, let player = try? AVAudioPlayer(contentsOf: url) else {
            return
        }
        self.player = player
        player.play()
    }

    func stopPlayer() {
        player?.stop()
        player = nil
    }
}
