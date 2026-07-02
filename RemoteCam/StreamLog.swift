//
//  StreamLog.swift
//  RemoteShutter
//
//  Structured loggers for the preview streaming pipeline. Filter in Console.app
//  by subsystem + category, e.g. category:stream.transport. Per-frame chatter is
//  logged at .debug (off by default); recovery events (watchdog fired, stall,
//  codec fallback) at .info/.error so field issues are diagnosable from a sysdiagnose.
//

import Foundation
import os

enum StreamLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "RemoteShutter"
    static let encode = Logger(subsystem: subsystem, category: "stream.encode")
    static let decode = Logger(subsystem: subsystem, category: "stream.decode")
    static let transport = Logger(subsystem: subsystem, category: "stream.transport")
    static let lifecycle = Logger(subsystem: subsystem, category: "stream.lifecycle")
}
