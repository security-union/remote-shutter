//
//  ViewfinderGestureLayer.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import SwiftUI
import UIKit

/// The viewfinder's touch surface, shared by the 1:1 monitor and the multicam
/// director: single tap focuses (mapped through `FocusPointMapping`, reticle
/// under the finger), double tap flips the camera, pinch zooms. The screen
/// supplies routing through callbacks — on the 1:1 monitor they address *the*
/// camera, on the director the *focused* camera — while this layer owns the
/// gesture mechanics, the tap→image mapping, and the reticle, so the two
/// screens cannot drift apart.
///
/// Place it inside the ZStack that draws the live frame, and apply
/// `ignoresSafeArea` to that ZStack as a whole: the gesture location, the
/// measured size, and the reticle then share one coordinate space. Keep it
/// BELOW the chrome so a tap on a control is never stolen as a focus tap.
struct ViewfinderGestureLayer: View {

    /// Read at tap time: the live frame whose pixel size maps the tap into
    /// normalized image space (nil while no frame has arrived — taps ignored).
    let cameraImage: () -> UIImage?
    /// The camera's zoom model, for pinch (same values the zoom pill uses).
    let zoomScale: ZoomScale
    let currentZoomFactor: CGFloat
    /// Whether single-tap focus is offered at all. The director turns this off
    /// when the focused camera can't focus at a point, so the user gets no
    /// reticle promising something the camera won't do — and a free user isn't
    /// routed to the paywall for a feature that can't work here.
    let focusEnabled: Bool
    /// A tap landed on the image (not the letterbox), in normalized upright
    /// image coordinates, origin top-left.
    let onFocusTap: (CGPoint) -> Void
    let onDoubleTap: () -> Void
    let onZoomChange: (CGFloat) -> Void

    @State private var viewSize: CGSize = .zero
    @State private var focusReticle: FocusReticle?
    @State private var zoomAtGestureStart: CGFloat?

    var body: some View {
        ZStack {
            // Double tap toggles the camera; a single tap focuses (simultaneous
            // so the reticle is instant — an exclusive gesture would stall it
            // for the double-tap window); pinch zooms. The translation guard
            // keeps drags and pinches from focusing.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    onDoubleTap()
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            if abs(value.translation.width) < 10, abs(value.translation.height) < 10 {
                                handleFocusTap(at: value.location)
                            }
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if zoomAtGestureStart == nil {
                                zoomAtGestureStart = currentZoomFactor
                            }
                            let start = zoomAtGestureStart!
                            onZoomChange(zoomScale.pinched(from: start, magnification: value))
                        }
                        .onEnded { _ in
                            zoomAtGestureStart = nil
                        }
                )

            // Drawn in the same coordinate space the tap was measured in.
            // Non-interactive so it never eats a subsequent tap.
            if let reticle = focusReticle {
                FocusReticleView()
                    .id(reticle.id)
                    .position(reticle.point)
                    .allowsHitTesting(false)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ViewfinderSizeKey.self, value: geo.size)
            }
        )
        .onPreferenceChange(ViewfinderSizeKey.self) { viewSize = $0 }
    }

    /// Maps a tap into a normalized image point and, if it landed on the image
    /// (not the letterbox), shows the reticle and forwards it to the screen.
    private func handleFocusTap(at location: CGPoint) {
        guard focusEnabled,
              let image = cameraImage(),
              let normalized = FocusPointMapping.normalizedImagePoint(
                tap: location, viewSize: viewSize, imageSize: image.size)
        else { return }
        let reticle = FocusReticle(point: location)
        focusReticle = reticle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if focusReticle?.id == reticle.id { focusReticle = nil }
        }
        onFocusTap(normalized)
    }
}

/// One tap-to-focus reticle: its view-space position plus an identity so a new
/// tap re-instantiates `FocusReticleView` and replays its animation.
struct FocusReticle: Equatable {
    let id = UUID()
    let point: CGPoint
}

/// Measures the viewfinder's size so a tap can be mapped to a normalized image
/// point. A preference key avoids mutating `@State` during layout.
private struct ViewfinderSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// The animated focus square: a yellow reticle that pulses in and fades. Purely
/// local tap feedback — the focus command travels separately.
struct FocusReticleView: View {
    @State private var scale: CGFloat = 1.25
    @State private var opacity: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(Color.yellow, lineWidth: 1.5)
            .frame(width: 78, height: 78)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.12)) {
                    scale = 1.0
                    opacity = 1
                }
                withAnimation(.easeIn(duration: 0.2).delay(0.35)) {
                    opacity = 0
                }
            }
    }
}
