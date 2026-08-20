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

    /// Playback touches the audio session, whose (re)activation blocks on the
    /// audio daemon — and right after a backgrounding that negotiation can
    /// stall for tens of seconds. It happens HERE, on a dedicated queue, so a
    /// cold audio session can never stall the caller (the countdown chimes
    /// fire on main, where one stalled `play()` sat in front of record-start).
    private let playbackQueue = DispatchQueue(label: "SoundManager.playback")
    /// playbackQueue-confined.
    private var player: AVAudioPlayer?

    func playBeepSound(_ beep: Beep) {
        playbackQueue.async { [weak self] in
            guard let self else { return }
            SessionDebug.note("♪ chime: play begin")
            self.player?.stop()
            self.player = nil
            guard let url = beep.url, let player = try? AVAudioPlayer(contentsOf: url) else {
                return
            }
            self.player = player
            player.play()
            SessionDebug.note("♪ chime: play end")
        }
    }

    func stopPlayer() {
        playbackQueue.async { [weak self] in
            self?.player?.stop()
            self?.player = nil
        }
    }
}
