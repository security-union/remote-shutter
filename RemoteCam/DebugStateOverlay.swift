//
//  DebugStateOverlay.swift
//  RemoteShutter
//
//  Debug-only overlay that shows the current state machine state name.
//

#if DEBUG

import UIKit

class DebugStateOverlay {

    static let shared = DebugStateOverlay()

    private var window: UIWindow?
    private var label: UILabel?

    private init() {}

    private func setupWindow() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        let overlay = UIWindow(windowScene: scene)
        overlay.windowLevel = .statusBar + 1
        overlay.isUserInteractionEnabled = false

        let lbl = UILabel()
        lbl.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        lbl.textColor = .white
        lbl.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        lbl.textAlignment = .center
        lbl.text = "—"
        lbl.layer.cornerRadius = 4
        lbl.clipsToBounds = true

        let container = UIViewController()
        container.view.backgroundColor = .clear
        container.view.addSubview(lbl)

        lbl.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            lbl.centerXAnchor.constraint(equalTo: container.view.centerXAnchor),
            lbl.bottomAnchor.constraint(equalTo: container.view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
            lbl.heightAnchor.constraint(equalToConstant: 20),
            lbl.widthAnchor.constraint(greaterThanOrEqualToConstant: 100)
        ])

        overlay.rootViewController = container
        overlay.isHidden = false
        self.label = lbl
        self.window = overlay
    }

    func update(state: String) {
        DispatchQueue.main.async {
            if self.window == nil { self.setupWindow() }
            self.label?.text = "  \(state)  "
        }
    }
}

#endif
