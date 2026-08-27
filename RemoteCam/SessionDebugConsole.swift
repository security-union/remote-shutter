//
//  SessionDebugConsole.swift
//  RemoteShutter
//
//  Signpost-style session observability. The pattern mirrors how Apple's own
//  tooling watches a live process:
//
//  - `SessionDebug` is the always-compiled facade (like os_signpost): its API
//    exists in every build so production code never wraps calls in #if DEBUG,
//    but Release bodies are identity/no-op and cost nothing.
//  - `DebugWiretap` is a delegate-proxy decorator (like URLProtocol
//    interposition) around `MultipeerServiceProtocol` — the ONE seam every
//    wire command, peer change, and resource transfer already flows through.
//    It is installed once, at the transport's composition root; no message
//    handler anywhere knows it exists.
//  - `SessionDebugOverlay` renders the collected picture: local session
//    state, connected devices, the latest CameraStateReport per peer, and a
//    rolling command log (frames filtered — they'd drown everything). Tap a
//    command row to see the message's fields (`MessageDump`).
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import Combine
import SwiftUI

// MARK: - Message dump (always compiled; pure, so it is unit-tested)

/// Renders any `Message` as "field: value" lines by reflection, so every
/// command — present and future — is inspectable in the console without a
/// per-type describer. Nested payloads (capabilities, exposure state) indent;
/// arrays show their count then their elements; shutter durations also show
/// as a fraction so `0.008` reads as `1/125`.
enum MessageDump {
    /// Nesting past this shows a one-line summary instead of more fields.
    static let maxDepth = 4

    static func describe(_ message: Message) -> String {
        let lines = fields(of: message, indent: 0)
        return lines.isEmpty ? "(no fields)" : lines.joined(separator: "\n")
    }

    /// One line per stored property, walking up the class chain (payloads
    /// subclass `Message`); the `sender` plumbing is not a field of interest.
    private static func fields(of value: Any, indent: Int) -> [String] {
        var lines: [String] = []
        var mirror: Mirror? = Mirror(reflecting: value)
        while let current = mirror {
            for child in current.children {
                guard let label = child.label, label != "sender" else { continue }
                lines += render(label: label, value: child.value, indent: indent)
            }
            mirror = current.superclassMirror
        }
        return lines
    }

    private static func render(label: String, value: Any, indent: Int) -> [String] {
        let pad = String(repeating: "  ", count: indent)
        if isScalar(value) { return ["\(pad)\(label): \(scalar(value))"] }

        let mirror = Mirror(reflecting: value)
        switch mirror.displayStyle {
        case .optional:
            guard let inner = mirror.children.first?.value else { return ["\(pad)\(label): nil"] }
            return render(label: label, value: inner, indent: indent)
        case .collection, .set:
            let items = mirror.children.map(\.value)
            guard !items.isEmpty else { return ["\(pad)\(label): []"] }
            var out = ["\(pad)\(label): [\(items.count)]"]
            guard indent < maxDepth else { return out }
            for (index, item) in items.enumerated() {
                out += render(label: "[\(index)]", value: item, indent: indent + 1)
            }
            return out
        case .struct, .class:
            guard indent < maxDepth else { return ["\(pad)\(label): \(scalar(value))"] }
            let nested = fields(of: value, indent: indent + 1)
            guard !nested.isEmpty else { return ["\(pad)\(label): \(scalar(value))"] }
            return ["\(pad)\(label):"] + nested
        default:
            // Enums (associated values print via description), tuples, ObjC.
            return ["\(pad)\(label): \(scalar(value))"]
        }
    }

    private static func isScalar(_ value: Any) -> Bool {
        value is any BinaryInteger || value is any BinaryFloatingPoint
            || value is Bool || value is String || value is Date || value is UUID
    }

    private static func scalar(_ value: Any) -> String {
        switch value {
        case let double as Double: return number(double)
        case let float as Float: return number(Double(float))
        case let cgFloat as CGFloat: return number(Double(cgFloat))
        case let error as Error: return "error(\(error._domain) \(error._code))"
        default: return String(describing: value)
        }
    }

    /// Sub-second values double as a shutter fraction: `0.008 (1/125)`.
    private static func number(_ value: Double) -> String {
        guard value > 0, value < 0.25 else { return String(describing: value) }
        return "\(value) (1/\(Int((1 / value).rounded())))"
    }
}

// MARK: - Facade (always compiled; free in Release)

enum SessionDebug {
    /// Wraps the transport in the wiretap. Identity in Release.
    static func instrument(_ service: any MultipeerServiceProtocol) -> any MultipeerServiceProtocol {
        #if DEBUG
        return DebugWiretap(wrapping: service)
        #else
        return service
        #endif
    }

    /// The one state tap, called from the coordinator's single mutation
    /// point (`transition(to:)`). No-op in Release.
    static func stateChanged(_ name: String) {
        #if DEBUG
        SessionDebugLog.shared.recordState(name)
        #endif
    }

    /// Recording-pipeline phase tap (arming and finalize spans), so the
    /// console shows WHERE time goes between "start commanded" and "first
    /// frame written". Signposts at the pipeline's choke points only; no-op
    /// in Release.
    static func pipelinePhase(_ label: @autoclosure () -> String) {
        #if DEBUG
        SessionDebugLog.shared.recordLifecycle("⛭ \(label())")
        #endif
    }

    /// General-purpose console note for suspects under observation (e.g. the
    /// chime bracketing an audio-session stall). No-op in Release.
    static func note(_ label: @autoclosure () -> String) {
        #if DEBUG
        SessionDebugLog.shared.recordLifecycle(label())
        #endif
    }
}

#if DEBUG

// MARK: - Wiretap (delegate-proxy decorator over the transport seam)

/// Forwards every `MultipeerServiceProtocol` call to the real service and
/// every delegate callback to the real delegate, teeing what it sees into
/// `SessionDebugLog`. Stateless apart from the two references.
final class DebugWiretap: MultipeerServiceProtocol, MultipeerServiceDelegate, @unchecked Sendable {
    private let real: any MultipeerServiceProtocol
    private weak var outer: MultipeerServiceDelegate?
    private let log = SessionDebugLog.shared

    init(wrapping service: any MultipeerServiceProtocol) {
        real = service
        outer = service.delegate
        service.delegate = self
    }

    // MARK: Service side (outbound)

    var delegate: MultipeerServiceDelegate? {
        get { outer }
        set { outer = newValue; real.delegate = self }
    }
    var session: MCSession! { real.session }
    var connectedPeers: [MCPeerID] { real.connectedPeers }
    var progressCancellables: Set<AnyCancellable> {
        get { real.progressCancellables }
        set { real.progressCancellables = newValue }
    }

    func startAdvertisingOnly(discoveryInfo: [String: String]?) {
        log.recordLifecycle("advertise")
        real.startAdvertisingOnly(discoveryInfo: discoveryInfo)
    }
    func startBrowsingOnly() {
        log.recordLifecycle("browse")
        real.startBrowsingOnly()
    }
    func stopAdvertisingAndBrowsing() {
        log.recordLifecycle("stop radios")
        real.stopAdvertisingAndBrowsing()
    }
    func disconnect() {
        log.recordLifecycle("disconnect")
        real.disconnect()
    }
    func stopSession() {
        log.recordLifecycle("stop session")
        real.stopSession()
    }
    func invitePeer(_ peer: MCPeerID, timeout: TimeInterval) {
        log.recordLifecycle("invite \(peer.displayName)")
        real.invitePeer(peer, timeout: timeout)
    }

    @discardableResult
    func send(_ msg: Message, to peers: [MCPeerID],
              mode: MCSessionSendDataMode) -> Bool {
        let ok = real.send(msg, to: peers, mode: mode)
        log.recordCommand(.sent, msg, peer: peers.first?.displayName, ok: ok)
        return ok
    }

    func sendResource(at url: URL, withName name: String,
                      toPeer peer: MCPeerID,
                      completion: @escaping (Error?) -> Void) -> Progress? {
        log.recordLifecycle("resource → \(name)")
        return real.sendResource(at: url, withName: name, toPeer: peer, completion: completion)
    }

    // MARK: Delegate side (inbound)

    func didReceiveMessage(_ message: Message, from peer: MCPeerID) {
        log.recordCommand(.received, message, peer: peer.displayName, ok: true)
        outer?.didReceiveMessage(message, from: peer)
    }
    // Frames are deliberately not logged — 30/s would drown the console.
    func didReceiveFrameRequest(_ request: RemoteCmd.RequestFrame) {
        outer?.didReceiveFrameRequest(request)
    }
    func didReceiveFrame(_ frame: RemoteCmd.SendFrame, from peer: MCPeerID) {
        outer?.didReceiveFrame(frame, from: peer)
    }
    func peerDidConnect(_ peer: MCPeerID) {
        log.recordLifecycle("connected \(peer.displayName)")
        log.updatePeers(real.connectedPeers.map(\.displayName))
        outer?.peerDidConnect(peer)
    }
    func peerDidDisconnect(_ peer: MCPeerID) {
        log.recordLifecycle("dropped \(peer.displayName)")
        log.updatePeers(real.connectedPeers.map(\.displayName))
        outer?.peerDidDisconnect(peer)
    }
    func didDetectIncompatibility() {
        log.recordLifecycle("incompatible peer")
        outer?.didDetectIncompatibility()
    }
    func didStartReceivingResource(name: String, from peer: MCPeerID, progress: Progress) {
        log.recordLifecycle("resource ← \(name)")
        outer?.didStartReceivingResource(name: name, from: peer, progress: progress)
    }
    func didFinishReceivingResource(name: String, from peer: MCPeerID, at localURL: URL?, error: Error?) {
        log.recordLifecycle("resource ← \(name) \(error == nil ? "done" : "FAILED")")
        outer?.didFinishReceivingResource(name: name, from: peer, at: localURL, error: error)
    }
    func browserDidFindPeer(_ peer: MCPeerID) { outer?.browserDidFindPeer(peer) }
    func browserDidLosePeer(_ peer: MCPeerID) { outer?.browserDidLosePeer(peer) }
    func browserDidFail(_ error: Error) {
        log.recordLifecycle("browser FAILED")
        outer?.browserDidFail(error)
    }
    func advertiserDidFail(_ error: Error) {
        log.recordLifecycle("advertiser FAILED")
        outer?.advertiserDidFail(error)
    }
}

// MARK: - Log store

/// Everything the console shows. Recorded from any thread, published on main.
final class SessionDebugLog: ObservableObject, @unchecked Sendable {
    static let shared = SessionDebugLog()

    enum Direction { case sent, received }

    struct ReportEntry: Identifiable, Equatable {
        var id: String { "\(peerName)|\(direction == .sent ? "s" : "r")" }
        let peerName: String
        let direction: Direction
        let seq: UInt64
        let state: RemoteCmd.CameraStateReport.RecordingState
        let at: Date
        static func == (lhs: ReportEntry, rhs: ReportEntry) -> Bool { lhs.id == rhs.id && lhs.seq == rhs.seq }
    }

    struct TrafficEntry: Identifiable {
        enum Kind { case sent(ok: Bool), received, lifecycle }
        let id = UUID()
        let at: Date
        let kind: Kind
        let label: String
        let peerName: String?
        /// The message's fields (`MessageDump`), shown when the row is
        /// tapped. Empty for lifecycle notes.
        var detail: String = ""
    }

    private static let trafficCap = 24

    // Main-confined.
    @Published private(set) var stateName = "—"
    @Published private(set) var stateChangedAt: Date?
    @Published private(set) var peers: [String] = []
    @Published private(set) var reports: [ReportEntry] = []
    @Published private(set) var traffic: [TrafficEntry] = []

    func recordState(_ name: String) {
        let now = Date()
        DispatchQueue.main.async {
            self.stateName = name
            self.stateChangedAt = now
        }
    }

    func updatePeers(_ names: [String]) {
        DispatchQueue.main.async { self.peers = names }
    }

    func recordCommand(_ direction: Direction, _ message: Message, peer: String?, ok: Bool) {
        // Frame plumbing is throttled out of the console entirely.
        if message is RemoteCmd.SendFrame || message is RemoteCmd.RequestFrame { return }
        let entry = TrafficEntry(
            at: Date(),
            kind: direction == .sent ? .sent(ok: ok) : .received,
            label: String(describing: type(of: message)),
            peerName: peer,
            detail: MessageDump.describe(message))
        DispatchQueue.main.async {
            self.traffic.insert(entry, at: 0)
            if self.traffic.count > Self.trafficCap { self.traffic.removeLast() }
        }
        // The recording-truth channel additionally keeps a per-peer latest.
        if let report = message as? RemoteCmd.CameraStateReport {
            let reportEntry = ReportEntry(
                peerName: peer ?? "—", direction: direction,
                seq: report.seq, state: report.state, at: entry.at)
            DispatchQueue.main.async {
                self.reports.removeAll { $0.id == reportEntry.id }
                self.reports.insert(reportEntry, at: 0)
            }
        }
    }

    func recordLifecycle(_ label: String) {
        let entry = TrafficEntry(at: Date(), kind: .lifecycle, label: label, peerName: nil)
        DispatchQueue.main.async {
            self.traffic.insert(entry, at: 0)
            if self.traffic.count > Self.trafficCap { self.traffic.removeLast() }
        }
    }
}

// MARK: - Overlay

/// The console UI. The toggle button sits on the LEADING EDGE, VERTICALLY
/// CENTERED — no screen puts chrome there (the back button owns the top-left
/// corner). Drop into any screen's ZStack.
struct SessionDebugOverlay: View {
    @ObservedObject private var log = SessionDebugLog.shared
    @State private var isOpen = false
    /// The traffic row whose message fields are unfolded (one at a time).
    @State private var expandedEntryID: UUID?

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Button {
                isOpen.toggle()
            } label: {
                Image(systemName: isOpen ? "ant.circle.fill" : "ant.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.yellow)
                    .padding(6)
                    .background(Color.black.opacity(0.4), in: Circle())
            }
            .accessibilityLabel("Session debug console")

            if isOpen {
                panel
            }
            Spacer()
        }
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var panel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                sessionSection
                if !log.reports.isEmpty { reportsSection }
                trafficSection
            }
            .padding(10)
        }
        .frame(maxWidth: 360, maxHeight: 420)
        .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Sections

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            header("SESSION")
            HStack(spacing: 6) {
                Text(log.stateName)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                if let at = log.stateChangedAt {
                    Text("since \(Self.clock.string(from: at))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            if log.peers.isEmpty {
                caption("no devices connected")
            } else {
                ForEach(log.peers, id: \.self) { name in
                    caption("● \(name)", color: .green)
                }
            }
        }
    }

    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            header("STATE REPORTS")
            ForEach(log.reports) { entry in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(entry.peerName)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(entry.direction == .sent ? "sent" : "recv")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(entry.direction == .sent ? .orange : .cyan)
                        stateBadge(entry.state)
                    }
                    caption("at \(Self.clock.string(from: entry.at))  seq …\(entry.seq % 1_000_000)")
                }
            }
        }
    }

    private var trafficSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            header("TRAFFIC (frames hidden · tap a command for its fields)")
            if log.traffic.isEmpty { caption("quiet") }
            ForEach(log.traffic) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    trafficRow(entry)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !entry.detail.isEmpty else { return }
                            expandedEntryID = expandedEntryID == entry.id ? nil : entry.id
                        }
                    if expandedEntryID == entry.id {
                        Text(entry.detail)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                            .textSelection(.enabled)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    private func trafficRow(_ entry: SessionDebugLog.TrafficEntry) -> some View {
        HStack(spacing: 5) {
            Text(Self.clock.string(from: entry.at))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
            switch entry.kind {
            case .sent(let ok):
                Text(ok ? "→" : "→✗")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(ok ? .orange : .red)
                commandLabel(entry)
            case .received:
                Text("←")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                commandLabel(entry)
            case .lifecycle:
                Text("· \(entry.label)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .italic()
            }
            Spacer(minLength: 0)
        }
    }

    private func commandLabel(_ entry: SessionDebugLog.TrafficEntry) -> some View {
        HStack(spacing: 4) {
            Text(entry.label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
            if let peer = entry.peerName {
                Text(peer)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Bits

    @ViewBuilder
    private func stateBadge(_ state: RemoteCmd.CameraStateReport.RecordingState) -> some View {
        switch state {
        case .idle:
            Text("IDLE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.green)
        case .recording(let elapsedMillis):
            Text("REC \(RecordingTimer.format(elapsedMillis))")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.red)
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.yellow)
    }

    private func caption(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(color)
    }
}

#endif
