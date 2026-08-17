//
//  DebugLog.swift
//  RemoteShutter
//
//  Leveled console logging. `AppLog.level` is the one knob: `.off` silences
//  everything, `.warning` keeps failures, `.info` adds lifecycle events,
//  `.debug` adds the firehose (state transitions, per-command chatter).
//
//  Debug builds default to `.info`; override per-run with the `LOG_LEVEL`
//  scheme environment variable (off | warning | info | debug — same idea as
//  QUIC_DEBUG), or from lldb: `e AppLog.level = .debug`. Release is hard
//  `.off` and every call compiles to nothing, exactly like the old
//  DEBUG-only debugLog.
//
//  The preview-streaming pipeline logs through `StreamLog` (os.Logger)
//  instead, which carries its own per-category levels for Console.app.
//

import Foundation

enum LogLevel: Int, Comparable {
    case off = 0
    case warning
    case info
    case debug

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum AppLog {
    #if DEBUG
    static var level: LogLevel = levelFromEnvironment() ?? .info

    private static func levelFromEnvironment() -> LogLevel? {
        switch ProcessInfo.processInfo.environment["LOG_LEVEL"]?.lowercased() {
        case "off": return LogLevel.off
        case "warning": return LogLevel.warning
        case "info": return LogLevel.info
        case "debug": return LogLevel.debug
        default: return nil
        }
    }
    #else
    static let level: LogLevel = .off
    #endif
}

@inline(__always)
func logWarning(_ message: @autoclosure () -> String) {
    #if DEBUG
    if AppLog.level >= .warning { print("⚠️ \(message())") }
    #endif
}

@inline(__always)
func logInfo(_ message: @autoclosure () -> String) {
    #if DEBUG
    if AppLog.level >= .info { print(message()) }
    #endif
}

@inline(__always)
func logDebug(_ message: @autoclosure () -> String) {
    #if DEBUG
    if AppLog.level >= .debug { print(message()) }
    #endif
}

/// Legacy name — every existing call site is debug-level chatter.
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    logDebug(message())
}
