//
//  CinematicControls.swift
//  RemoteShutter
//
//  The director's Cinematic controls: the APERTURE ruler (the same
//  `RulerPill` zoom and exposure use), the subject boxes drawn over the
//  focused camera's preview, and the pure mapping from a viewfinder tap to a
//  Cinematic focus request. Ranges come from the camera's `CinematicState`,
//  never from constants. See Docs/cinematic.md.
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import SwiftUI

// MARK: - Aperture

enum CinematicApertureStops {

    /// Whole f-stops, the detents a photographer expects under the thumb.
    static let fNumbers: [Double] = [1.4, 2, 2.8, 4, 5.6, 8, 11, 16]

    /// "f/2", "f/2.8", "f/16".
    static func label(_ fNumber: Double) -> String {
        guard fNumber > 0 else { return "—" }
        let rounded = (fNumber * 10).rounded() / 10
        let number = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return "f/\(number)"
    }

    /// The ruler for this camera: log-spaced like zoom (each whole stop is an
    /// equal step), bounded by the Cinematic format's own range.
    static func track(_ cinematic: CinematicState) -> RulerTrack {
        RulerTrack(min: Double(cinematic.minAperture), max: Double(cinematic.maxAperture), stops: fNumbers)
    }
}

/// The APERTURE ruler: shallow (small f-number) to deep. The camera takes
/// the aperture before a take only, so while the rig records the ruler stays
/// on screen, showing the value, but does not move.
struct CinematicApertureRulerPill: View {
    let cinematic: CinematicState
    let axis: Axis
    let isEnabled: Bool
    let onChange: (Double) -> Void

    var body: some View {
        RulerPill(track: CinematicApertureStops.track(cinematic),
                  currentValue: Double(cinematic.aperture),
                  readout: { CinematicApertureStops.label($0) },
                  accessibilityLabel: NSLocalizedString("Cinematic aperture", comment: "a11y: simulated aperture ruler"),
                  trackLength: ExposureRulerMetrics.track(axis: axis),
                  axis: axis,
                  onChange: onChange,
                  leading: { _ in EmptyView() },
                  // Every pill in the column keeps the same end slot, so the
                  // aperture capsule lines up with the exposure rulers.
                  trailing: { _ in RulerEndSlot { EmptyView() } })
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - Subjects

/// One lane's live Cinematic report, isolated like `FrameDisplayModel`: the
/// camera pushes it ~10 Hz, and only the subject overlay observes it.
final class CinematicOverlayModel: ObservableObject {
    @Published var report: CinematicSubjectsReport?
}

/// Pure geometry and hit-testing for the subject boxes. Boxes arrive
/// normalized in the upright image (origin top-left), the same space
/// `FocusPointMapping.normalizedImagePoint` maps a tap into, so a tap is
/// tested against them without any conversion.
enum CinematicSubjectLayout {

    /// The boxes worth drawing: a body is dropped when a face or head of the
    /// same subject is there (one box per person or pet, not two).
    static func visibleSubjects(_ subjects: [CinematicSubject]) -> [CinematicSubject] {
        let heads: Set<Int> = Set(subjects.filter { $0.kind.isHead }.map(\.groupID))
        return subjects.filter { subject in
            !(subject.kind.isBody && subject.groupID >= 0 && heads.contains(subject.groupID))
        }
    }

    /// The subject under a tap: the smallest visible box containing it (a
    /// face inside a salient object wins).
    static func subject(at point: CGPoint, in subjects: [CinematicSubject]) -> CinematicSubject? {
        visibleSubjects(subjects)
            .filter { $0.rect.contains(point) }
            .min { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
    }

    /// A tap with Cinematic on: lock onto the subject under the finger, or
    /// track whatever is at that point. A long press holds focus at that
    /// distance instead.
    static func focus(forTap point: CGPoint, subjects: [CinematicSubject], isLongPress: Bool) -> CinematicFocus {
        if isLongPress {
            return .fixedPoint(x: Float(point.x), y: Float(point.y))
        }
        if let subject = subject(at: point, in: subjects) {
            return .subject(id: subject.id, strength: .strong)
        }
        return .trackPoint(x: Float(point.x), y: Float(point.y), strength: .strong)
    }

    /// Where the image sits in an aspect-fit (letterboxed) viewfinder — the
    /// rectangle `LiveFrameView` draws into.
    static func imageFrame(viewSize: CGSize, imageSize: CGSize) -> CGRect? {
        FocusPointMapping.fittedImageFrame(viewSize: viewSize, imageSize: imageSize)
    }

    /// A normalized box on screen.
    static func viewRect(_ normalized: CGRect, in imageFrame: CGRect) -> CGRect {
        CGRect(x: imageFrame.minX + normalized.minX * imageFrame.width,
               y: imageFrame.minY + normalized.minY * imageFrame.height,
               width: normalized.width * imageFrame.width,
               height: normalized.height * imageFrame.height)
    }
}

private extension CinematicSubjectKind {
    var isHead: Bool { self == .face || self == .catHead || self == .dogHead }
    var isBody: Bool { self == .humanBody || self == .catBody || self == .dogBody }
}

/// The boxes Cinematic sees, over the focused camera's preview: white for a
/// subject it could focus on, gold for the one in focus (solid when locked,
/// dashed when the camera may move on). Drawn only, never hit-tested: taps
/// go through the viewfinder's gesture layer beneath and are matched against
/// these boxes there.
struct CinematicSubjectOverlay: View {
    @ObservedObject var model: CinematicOverlayModel
    /// Read at render time; the overlay redraws with each report, not with
    /// each frame.
    let imageSize: () -> CGSize?

    var body: some View {
        GeometryReader { geo in
            if let report = model.report,
               let size = imageSize(),
               let frame = CinematicSubjectLayout.imageFrame(viewSize: geo.size, imageSize: size) {
                ZStack(alignment: .topLeading) {
                    ForEach(CinematicSubjectLayout.visibleSubjects(report.subjects), id: \.id) { subject in
                        box(for: subject, rect: CinematicSubjectLayout.viewRect(subject.rect, in: frame))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
        .allowsHitTesting(false)
    }

    private func box(for subject: CinematicSubject, rect: CGRect) -> some View {
        let focused = subject.focus != nil || subject.isFixedFocus
        let dashed = subject.focus == .weak
        return RoundedRectangle(cornerRadius: 6)
            .stroke(focused ? AppTheme.accent : Color.white.opacity(0.7),
                    style: StrokeStyle(lineWidth: focused ? 2 : 1, dash: dashed ? [6, 4] : []))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

/// "More light needed": the camera says the scene is too dark for Cinematic
/// to separate the subject from the background.
struct CinematicLightWarning: View {
    @ObservedObject var model: CinematicOverlayModel

    var body: some View {
        if model.report?.notEnoughLight == true {
            Label(NSLocalizedString("More light needed", comment: "Cinematic: the scene is too dark for the effect"),
                  systemImage: "sun.min")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.ultraThinMaterial))
                .allowsHitTesting(false)
        }
    }
}
