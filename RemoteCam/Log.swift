//
//  Log.swift
//  RemoteShutter
//
//  Created by Claude on 2026-03-03.
//

import Foundation

enum Log {
    enum Level: Int, Comparable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3
        case off = 4

        static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Set this to control which messages are printed.
    /// Only messages at this level or above will appear.
    /// Default is `.debug` (everything). Set to `.off` to silence all logs.
    static var level: Level = .debug

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static func log(_ lvl: Level, _ tag: String, _ message: String) {
        guard lvl >= level else { return }
        let ts = formatter.string(from: Date())
        print("\(ts) [\(tag)] \(message)")
    }

    static func debug(_ message: String) { log(.debug, "DEBUG", message) }
    static func info(_ message: String)  { log(.info, "INFO", message) }
    static func warning(_ message: String) { log(.warning, "WARN", message) }
    static func error(_ message: String) { log(.error, "ERROR", message) }
}
