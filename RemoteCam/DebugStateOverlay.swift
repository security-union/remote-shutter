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
    private let label = UILabel()

    private init() {}

    private func setupWindow() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        let overlay = UIWindow(windowScene: scene)
        overlay.windowLevel = .statusBar + 1
        overlay.isUserInteractionEnabled = false

        label.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.text = "—"
        label.layer.cornerRadius = 4
        label.clipsToBounds = true

        let container = UIViewController()
        container.view.backgroundColor = .clear
        container.view.addSubview(label)

        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: container.view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
            label.heightAnchor.constraint(equalToConstant: 20),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 100)
        ])

        overlay.rootViewController = container
        overlay.isHidden = false
        self.window = overlay
    }

    func update(state: String) {
        DispatchQueue.main.async {
            if self.window == nil { self.setupWindow() }
            self.label.text = "  \(state)  "
        }
    }
}

#endif
