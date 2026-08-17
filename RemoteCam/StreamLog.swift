//
//  StreamLog.swift
//  RemoteShutter
//
//  Structured loggers for the preview streaming pipeline, gated by the same
//  single knob as everything else (`AppLog.level`): debug chatter and stream
//  stats appear only at `.debug`, recovery events at `.info`, failures at
//  `.warning`. Output still goes through os.Logger, so Console.app filtering
//  by subsystem + category (e.g. category:stream.transport) keeps working.
//

import Foundation
import os

enum StreamLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "RemoteShutter"
    static let encode = Channel(Logger(subsystem: subsystem, category: "stream.encode"))
    static let decode = Channel(Logger(subsystem: subsystem, category: "stream.decode"))
    static let transport = Channel(Logger(subsystem: subsystem, category: "stream.transport"))
    static let lifecycle = Channel(Logger(subsystem: subsystem, category: "stream.lifecycle"))

    /// An os.Logger that answers to `AppLog.level` — the message is built only
    /// when the level allows, and Release compiles the calls out entirely.
    struct Channel {
        let logger: Logger
        init(_ logger: Logger) { self.logger = logger }

        func debug(_ message: @autoclosure () -> String) {
            #if DEBUG
            if AppLog.level >= .debug { logger.debug("\(message(), privacy: .public)") }
            #endif
        }

        func info(_ message: @autoclosure () -> String) {
            #if DEBUG
            if AppLog.level >= .info { logger.info("\(message(), privacy: .public)") }
            #endif
        }

        func error(_ message: @autoclosure () -> String) {
            #if DEBUG
            if AppLog.level >= .warning { logger.error("\(message(), privacy: .public)") }
            #endif
        }
    }
}
