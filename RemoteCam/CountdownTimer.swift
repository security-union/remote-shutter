//
//  CountdownTimer.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import Foundation

/// Block-based countdown timer that ticks once per second on the main queue.
///
/// After each second, `timeRemaining` is decremented; `onTick` fires while
/// time remains, and `onCompletion` fires when the countdown reaches zero.
/// Starting with a duration of zero calls `onCompletion` synchronously.
final class CountdownTimer {

    private(set) var timeRemaining: Int = 0
    private var tickHandler: ((CountdownTimer) -> Void)?
    private var completionHandler: ((CountdownTimer) -> Void)?
    private var isCanceled = false

    func start(duration: Int,
               onTick: @escaping (CountdownTimer) -> Void,
               onCompletion: @escaping (CountdownTimer) -> Void) {
        guard duration > 0 else {
            onCompletion(self)
            return
        }
        timeRemaining = duration
        tickHandler = onTick
        completionHandler = onCompletion
        isCanceled = false
        scheduleTick()
    }

    func cancel() {
        isCanceled = true
        tickHandler = nil
        completionHandler = nil
    }

    private func scheduleTick() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self, !self.isCanceled else {
                return
            }
            self.timeRemaining -= 1
            if self.timeRemaining > 0 {
                self.tickHandler?(self)
                self.scheduleTick()
            } else {
                self.completionHandler?(self)
                self.completionHandler = nil
                self.tickHandler = nil
            }
        }
    }
}
