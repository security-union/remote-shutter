import Correcto
import CorrectoCheck
import Foundation
import SessionModel
import SessionWorld

// Drive the session machine by hand.
//
// Every move offered here comes from `SessionWorld.choices`, which is the same
// function the explorer calls to decide what to try next. So walking this by
// hand walks the same graph the checker searches, one edge at a time, and
// pressing `c` hands whatever world you have reached to the checker.

// MARK: - Printing

let bold = "\u{001B}[1m", dim = "\u{001B}[2m", reset = "\u{001B}[0m"
let red = "\u{001B}[31m", green = "\u{001B}[32m", yellow = "\u{001B}[33m", cyan = "\u{001B}[36m"

func describe(_ phase: SessionState) -> String {
    switch phase {
    case .waitingForLobby: return "waitingForLobby"
    case .lobby: return "lobby"
    case .scanning: return "scanning"
    case let .reconnecting(peer): return "reconnecting(\(peer.displayName))"
    case .connected: return "connected"
    case .camera: return "camera"
    case let .cameraTakingPic(sendMedia, generation):
        return "cameraTakingPic(send: \(sendMedia), gen: \(generation))"
    case .cameraRecordingVideo: return "cameraRecordingVideo"
    case .cameraTransmittingVideo: return "cameraTransmittingVideo"
    case .watchCamera: return "watchCamera"
    case let .watchCameraTakingPic(generation): return "watchCameraTakingPic(gen: \(generation))"
    case let .watchCameraStartingVideo(generation): return "watchCameraStartingVideo(gen: \(generation))"
    case let .watchCameraRecordingVideo(stop): return "watchCameraRecordingVideo(stop: \(stop.map(String.init) ?? "nil"))"
    }
}

func flags(_ state: DeviceState) -> String {
    var on: [String] = []
    if state.alertUp { on.append("alert up") }
    if state.captureOutstanding { on.append("capture outstanding") }
    if state.capturesAwaited > 0 {
        on.append("awaiting \(state.capturesAwaited) picture(s)")
    }
    if state.recordingsAwaited > 0 {
        on.append("awaiting \(state.recordingsAwaited) recording reply/replies")
    }
    if state.believesRecording { on.append("believes recording") }
    return on.isEmpty ? "" : "  \(dim)\(on.joined(separator: ", "))\(reset)"
}

/// Who causes a move. The person is one of the actors on screen, which is the
/// honest way to show it: most of the interesting orders are the world's, not
/// the app's.
enum Source: String {
    case you = "you"
    case peer = "the peer"
    case transport = "the link"
    case hardware = "the camera hardware"
    case watchdog = "the watchdog"
    case world = "the world"

    static func of(_ event: SessionEvent?) -> Source {
        guard let event else { return .world }
        switch event {
        case .invite, .becomeCamera, .pressShutter, .pressRecord, .pressStop, .leaveSession:
            return .you
        case .wire: return .peer
        case .peerConnected, .peerLost, .sendFailed: return .transport
        case .pictureCaptured, .captureFailed, .recordingStarted, .recordingFailed, .clipReady:
            return .hardware
        case .stateTimeout: return .watchdog
        }
    }
}

// MARK: - The sequence diagram, drawn as you go

/// The conversation, one row per thing that happened.
///
/// A sequence diagram is the right picture for this because the state of each
/// device is only half the story. The other half is what is in flight between
/// them, and that is exactly where the orders nobody enumerated come from. So a
/// send and its delivery are two rows, not one: dashed when the message is
/// queued, solid when the receiver actually steps on it. Watching the dashed
/// arrows pile up and then land in the order you chose is the whole idea of the
/// checker, by hand.
struct Diagram {
    struct Row {
        var from: Int       // lane index, or -1 for a row with no source
        var to: Int
        var label: String
        var queued: Bool    // a send that has not been delivered yet
        var note: String
    }

    /// "you" is a lane because the person is one of the actors. The hardware
    /// and the watchdog are drawn as marks on the device's own lifeline, since
    /// giving them lanes buys nothing and costs width.
    let lanes: [String]
    var rows: [Row] = []

    static let laneWidth = 11

    init(machines: [MachineID]) {
        lanes = ["you"] + machines.map(\.name)
    }

    func lane(_ name: String) -> Int { lanes.firstIndex(of: name) ?? 0 }

    mutating func add(_ row: Row) { rows.append(row) }

    private func centre(_ index: Int) -> Int { index * Self.laneWidth + 4 }

    /// The header: lane names centred over their own lifelines.
    func header() -> String {
        var cells = Array(repeating: Character(" "), count: lanes.count * Self.laneWidth + 2)
        for (index, name) in lanes.enumerated() {
            let text = Array(name.prefix(Self.laneWidth - 1))
            let start = max(0, centre(index) - text.count / 2)
            for (offset, character) in text.enumerated() where start + offset < cells.count {
                cells[start + offset] = character
            }
        }
        return "  " + String(cells)
    }

    /// One row of the diagram: the lifelines, the arrow, then the label.
    private func render(_ row: Row) -> String {
        var cells = Array(repeating: Character(" "), count: lanes.count * Self.laneWidth)
        for index in lanes.indices { cells[centre(index)] = "\u{2502}" }   // │

        if row.from >= 0 && row.to >= 0 && row.from != row.to {
            let fill: Character = row.queued ? "\u{254C}" : "\u{2500}"    // ╌ or ─
            let left = min(centre(row.from), centre(row.to))
            let right = max(centre(row.from), centre(row.to))
            for position in (left + 1)..<right { cells[position] = fill }
            let goingRight = row.to > row.from
            cells[centre(row.from)] = goingRight ? "\u{251C}" : "\u{2524}"  // ├ or ┤
            cells[centre(row.to)] = goingRight ? "\u{25B6}" : "\u{25C0}"    // ▶ or ◀
        } else if row.to >= 0 {
            cells[centre(row.to)] = "\u{25CF}"                              // ●
        }

        let spine = String(cells)
        let note = row.note.isEmpty ? "" : "  \(dim)\(row.note)\(reset)"
        let label = row.queued ? "\(dim)\(row.label)\(reset)" : row.label
        return "  " + spine + "  " + label + note
    }

    /// The last `limit` rows, so a long walk still fits a terminal.
    func lines(limit: Int = 14) -> [String] {
        let shown = rows.suffix(limit)
        var out = [header()]
        if rows.count > shown.count {
            out.append("  \(dim)(\(rows.count - shown.count) earlier row(s); press d for the whole diagram)\(reset)")
        }
        out += shown.map(render)
        return out
    }

    /// The same thing as Mermaid, for pasting into a document or an issue.
    func mermaid() -> String {
        var out = ["sequenceDiagram"]
        out += lanes.map { "    participant \($0)" }
        for row in rows {
            guard row.from >= 0, row.to >= 0 else { continue }
            let arrow = row.queued ? "-->>" : "->>"
            var text = row.note.isEmpty ? row.label : "\(row.label) [\(row.note)]"
            // A bare `#` starts an entity reference in Mermaid, and
            // "watchdog#1" is all over these labels.
            text = text.replacingOccurrences(of: "#", with: "#35;")
            out.append("    \(lanes[row.from])\(arrow)\(lanes[row.to]): \(text)")
        }
        return out.joined(separator: "\n")
    }
}

/// A tiny seeded generator, so a random walk can be replayed. An unrepeatable
/// walk that broke a rule is a story; a seed is a bug report.
struct Seeded: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - The session being driven

struct Runner {
    var world: World<SessionDevice, SessionEnv>
    var history: [(label: String, world: World<SessionDevice, SessionEnv>,
                   diagram: Diagram)] = []
    var diagram: Diagram
    /// What a person would see happen: the effects performed, tallied.
    var picturesSaved = 0
    var clipsSaved = 0
    var alertsOnScreen = 0

    init(world: World<SessionDevice, SessionEnv>) {
        self.world = world
        self.diagram = Diagram(machines: world.machines.keys.sorted { first, second in
            // The remote on the left, cameras to its right: arrows then read
            // the way the protocol does.
            let firstIsRemote = first.name.contains("remote")
            let secondIsRemote = second.name.contains("remote")
            if firstIsRemote != secondIsRemote { return firstIsRemote }
            return first.name < second.name
        })
    }

    mutating func apply(_ choice: Choice<SessionDevice, SessionEnv>) -> [SessionEffect] {
        history.append((choice.label, world, diagram))
        var next = world
        next.env = choice.env
        var effects: [SessionEffect] = []
        if let machine = choice.machine, let event = choice.event,
           let before = world.machines[machine] {
            let step = SessionDevice.step(before, event)
            next.machines[machine] = step.state
            SessionWorld.absorb(&next.env, from: machine, effects: step.effects)
            effects = step.effects
            record(event: event, on: machine, label: choice.label,
                   ignored: step.state == before && step.effects.isEmpty, effects: effects)
        } else {
            // An environment-only move, such as a message being dropped.
            diagram.add(.init(from: -1, to: -1, label: choice.label, queued: false, note: ""))
        }
        world = next
        for effect in effects {
            switch effect {
            case .saveToLibrary: picturesSaved += 1
            case .saveClip: clipsSaved += 1
            case .showAlert: alertsOnScreen += 1
            case .dismissAlert: alertsOnScreen = max(0, alertsOnScreen - 1)
            default: break
            }
        }
        return effects
    }

    mutating func undo() -> String? {
        guard let last = history.popLast() else { return nil }
        world = last.world
        diagram = last.diagram
        return last.label
    }

    /// One row for what just arrived, then a dashed row for each message it put
    /// in flight. The local effects become the row's note, because a person
    /// cares that an alert went up, not that the world changed shape.
    private mutating func record(
        event: SessionEvent, on machine: MachineID, label: String,
        ignored: Bool, effects: [SessionEffect]
    ) {
        let target = diagram.lane(machine.name)
        var source = target
        var text = label
        switch event {
        case .invite, .becomeCamera, .pressShutter, .pressRecord, .pressStop, .leaveSession:
            source = diagram.lane("you")
            text = personLabel(event)
        case let .wire(message, from):
            source = diagram.lane(from.name)
            text = "\(message)"
        // The transport is telling this one device something, so these are
        // marks on its own lifeline rather than messages from the peer. Drawing
        // them as arrows said the peer sent its own disconnection, which is the
        // opposite of what a dropped link means.
        case let .peerConnected(peer):
            text = "link up with \(peer)"
        case let .peerLost(peer):
            text = "link to \(peer) lost"
        case let .sendFailed(peer):
            text = "send to \(peer) failed"
        case .pictureCaptured: text = "picture captured"
        case .captureFailed: text = "capture failed"
        case .recordingStarted: text = "recording started"
        case .recordingFailed: text = "recording failed"
        case .clipReady: text = "clip ready"
        case let .stateTimeout(generation): text = "watchdog#\(generation) fires"
        }

        var notes = effects.compactMap(localNote)
        if ignored { notes.insert("ignored", at: 0) }
        diagram.add(.init(from: source, to: target, label: text,
                          queued: false, note: notes.joined(separator: ", ")))

        for effect in effects {
            guard case let .send(message, to) = effect else { continue }
            diagram.add(.init(from: target, to: diagram.lane(to.name),
                              label: "\(message)", queued: true, note: "queued"))
        }
    }

    private func personLabel(_ event: SessionEvent) -> String {
        switch event {
        case let .invite(peer): return "invite \(peer)"
        case .becomeCamera: return "pick the camera role"
        case .pressShutter: return "press the shutter"
        case .pressRecord: return "press record"
        case .pressStop: return "press stop"
        case .leaveSession: return "leave the session"
        default: return "\(event)"
        }
    }

    /// The effects a person would notice, as short words. Sends are drawn as
    /// their own rows instead.
    private func localNote(_ effect: SessionEffect) -> String? {
        switch effect {
        case .showAlert: return "alert up"
        case .dismissAlert: return "alert down"
        case .saveToLibrary: return "saved"
        case .saveClip: return "clip saved"
        case .takePicture: return "camera: take picture"
        case .startRecording: return "camera: start recording"
        case .stopRecording: return "camera: stop recording"
        case let .armTimeout(generation): return "watchdog#\(generation) armed"
        case .invite: return "inviting"
        case .send: return nil
        }
    }

    var choices: [Choice<SessionDevice, SessionEnv>] { SessionWorld.choices(world.env, world.machines) }

    var brokenRules: [String] {
        let quiescent = choices.isEmpty
        return SessionRules.all.compactMap { rule in
            switch rule.when {
            case .always: return rule.holds(world) ? nil : rule.name
            case .quiescent: return (quiescent && !rule.holds(world)) ? rule.name : nil
            }
        }
    }

    func show(diagramRows: Int = 14) {
        print("")
        if !diagram.rows.isEmpty {
            for line in diagram.lines(limit: diagramRows) { print(line) }
            print("")
        }
        for id in world.machines.keys.sorted() {
            guard let state = world.machines[id] else { continue }
            let role = state.role == .undecided ? "" : "  \(cyan)\(state.role.rawValue)\(reset)"
            let peer = state.peers.isEmpty ? ""
                : "  \(dim)paired with \(state.peers.map(\.name).joined(separator: " + "))\(reset)"
            print("  \(bold)\(id.name.padding(toLength: 8, withPad: " ", startingAt: 0))\(reset) "
                  + "\(describe(state.phase))\(role)\(peer)\(flags(state))")
        }
        if !world.env.wire.inFlight.isEmpty {
            print("  \(dim)wire\(reset)     " + world.env.wire.inFlight
                .map { "\($0.message) \($0.from)→\($0.to)" }.joined(separator: ", "))
        }
        if !world.env.timers.armed.isEmpty {
            print("  \(dim)timers\(reset)   " + world.env.timers.armed
                .map { "\($0.id)#\($0.generation) on \($0.owner)" }.joined(separator: ", "))
        }
        if !world.env.hardware.pending.isEmpty {
            print("  \(dim)hardware\(reset) " + world.env.hardware.pending
                .map { "\($0.command) on \($0.owner)" }.joined(separator: ", "))
        }
        var seen: [String] = []
        if picturesSaved > 0 { seen.append("\(picturesSaved) picture(s) saved") }
        if clipsSaved > 0 { seen.append("\(clipsSaved) clip(s) saved") }
        if alertsOnScreen > 0 { seen.append("\(alertsOnScreen) alert(s) on screen") }
        if !seen.isEmpty { print("  \(dim)seen\(reset)     \(seen.joined(separator: ", "))") }

        let budgets = world.env
        print("  \(dim)budget\(reset)   invites \(budgets.invites), "
              + "shutter \(budgets.shutterPresses), recordings \(budgets.recordings), "
              + "stops \(budgets.stops), goodbyes \(budgets.goodbyes), drops \(budgets.drops)")

        let broken = brokenRules
        for name in broken { print("  \(red)\(bold)RULE BROKEN\(reset) \(red)\(name)\(reset)") }
        if choices.isEmpty && broken.isEmpty {
            print("  \(green)nothing more can happen, and every rule holds\(reset)")
        }
    }

    func showChoices() {
        let moves = choices
        guard !moves.isEmpty else { return }
        print("")
        var index = 1
        for source in [Source.you, .peer, .transport, .hardware, .watchdog, .world] {
            let mine = moves.enumerated().filter { Source.of($0.element.event) == source }
            guard !mine.isEmpty else { continue }
            print("  \(dim)\(source.rawValue)\(reset)")
            for (position, move) in mine {
                print("   \(yellow)\(String(format: "%2d", position + 1))\(reset)  \(move.label)")
            }
            index += mine.count
        }
        _ = index
    }
}

// MARK: - Checking from wherever you are

func check(_ world: World<SessionDevice, SessionEnv>) {
    let explorer = Explorer<SessionDevice, SessionEnv>(
        environment: SessionWorld.environment,
        invariants: SessionRules.all,
        transitionInvariants: SessionRules.allTransitions)
    let started = Date()
    let report = explorer.explore(from: world)
    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
    print("\n\(bold)checker, from this world\(reset)")
    print(report.description.split(separator: "\n").map { "  \($0)" }.joined(separator: "\n"))
    print("  \(dim)\(elapsed) ms\(reset)")
    if !report.exhaustive {
        print("  \(red)\(bold)this is not a proof\(reset)\(red): the search stopped at a limit, so "
              + "the worlds past it were never visited. Tighten the budgets or raise the limit.\(reset)")
    }
}

// MARK: - Arguments

var arguments = Array(CommandLine.arguments.dropFirst())
let wantsRig = arguments.contains("--rig")
/// A remote already holding both cameras: one tap, two cameras.
let wantsMulticam = arguments.contains("--multicam")
let wantsPaired = arguments.contains("--paired")
let checkOnly = arguments.contains("--check")
func value(_ name: String) -> Int? {
    guard let at = arguments.firstIndex(of: name), at + 1 < arguments.count else { return nil }
    return Int(arguments[at + 1])
}
/// A semicolon separated list of exactly what you would have typed, so a walk
/// can be replayed, pasted into a bug report, or run in CI.
///
/// Semicolons rather than commas because move names contain commas:
/// `takePicResp(failed: false, carriesMedia: true)` is one move, and splitting
/// it in half silently matched something else.
let script = (arguments.firstIndex(of: "--script").map { arguments[$0 + 1] } ?? "")
    .split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty }

var env = SessionEnv(
    invites: value("--invites") ?? (wantsRig ? 2 : 1),
    shutterPresses: value("--shutter") ?? 1,
    recordings: value("--recordings") ?? 1,
    stops: value("--stops"),
    goodbyes: value("--goodbyes") ?? 1,
    drops: value("--drops") ?? 0)
if wantsPaired || wantsMulticam { env.invites = 0 }

/// `--seed N` makes `r` and `a` repeatable. Without one a seed is chosen and
/// printed, so a walk worth keeping can always be replayed.
let seed = UInt64(value("--seed") ?? Int.random(in: 1...999_999))
var generator = Seeded(seed: seed)

var runner = Runner(
    world: wantsMulticam ? SessionWorld.multicam(env: env)
        : wantsPaired ? SessionWorld.paired(env: env)
        : wantsRig ? SessionWorld.rig(env: env)
        : SessionWorld.pair(env: env))

if checkOnly {
    check(runner.world)
    exit(0)
}

print("""

\(bold)Remote Shutter, as a state machine you can walk\(reset)
\(dim)Every move below comes from the same function the checker uses to decide what to
try next, so this walks the graph the search walks. Pick a number, or:
  c  hand this world to the checker       u  undo      r  random move
  a  run 20 random moves                  h  history   q  quit
  d  the whole diagram, and its Mermaid source
Random moves use seed \(seed); pass --seed \(seed) to walk this way again.\(reset)
""")

var scripted = script
while true {
    runner.show()
    runner.showChoices()
    let moves = runner.choices

    var line: String?
    if let next = scripted.first {
        scripted.removeFirst()
        line = next
        print("\n> \(next)  \(dim)(scripted)\(reset)")
    } else if !script.isEmpty {
        break   // the script ran out: stop rather than wait on a pipe
    } else {
        print("\n> ", terminator: "")
        line = readLine()
    }

    guard let input = line?.trimmingCharacters(in: .whitespaces), !input.isEmpty else {
        if line == nil { break }   // no tty, or EOF
        continue
    }

    switch input {
    case "q", "quit", "exit":
        exit(0)
    case "c", "check":
        check(runner.world)
    case "u", "undo":
        if let label = runner.undo() { print("  \(dim)undid: \(label)\(reset)") }
        else { print("  \(dim)nothing to undo\(reset)") }
    case "d", "diagram":
        guard !runner.diagram.rows.isEmpty else {
            print("  \(dim)nothing has happened yet\(reset)")
            continue
        }
        print("\n\(bold)the whole conversation\(reset)")
        for line in runner.diagram.lines(limit: Int.max) { print(line) }
        print("\n\(bold)the same thing as Mermaid\(reset)\n")
        print(runner.diagram.mermaid())
    case "h", "history":
        if runner.history.isEmpty { print("  \(dim)nothing yet\(reset)") }
        for (index, entry) in runner.history.enumerated() {
            print("  \(String(format: "%2d", index + 1)). \(entry.label)")
        }
    case "r", "a":
        let rounds = input == "a" ? 20 : 1
        for _ in 0..<rounds {
            let available = runner.choices
            guard let pick = available.randomElement(using: &generator) else { break }
            let effects = runner.apply(pick)
            print("  \(dim)\(pick.label)\(reset)"
                  + (effects.isEmpty ? "" : "  \(dim)→ \(effects.map { "\($0)" }.joined(separator: ", "))\(reset)"))
            if !runner.brokenRules.isEmpty { break }
        }
    default:
        // A number, or any part of a move's name. Names are what make a
        // recorded walk worth keeping: the numbers shift every time the world
        // changes, the names do not.
        var found: Choice<SessionDevice, SessionEnv>?
        if let pick = Int(input), pick >= 1, pick <= moves.count {
            found = moves[pick - 1]
        } else {
            let needle = input.lowercased()
            found = moves.first { $0.label.lowercased().contains(needle) }
        }
        guard let choice = found else {
            print("  \(dim)no move matches \u{22}\(input)\u{22}\(reset)")
            continue
        }
        let effects = runner.apply(choice)
        print("  \(bold)\(choice.label)\(reset)"
              + (effects.isEmpty ? "" : "\n  \(dim)effects: \(effects.map { "\($0)" }.joined(separator: ", "))\(reset)"))
    }
}
