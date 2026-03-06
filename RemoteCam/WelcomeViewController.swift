import UIKit
import StoreKit
import SwiftUI

class WelcomeViewController: UIViewController {

    let viewModel = WelcomeViewModel()
    private var swiftUIHostingController: UIHostingController<WelcomeView>?
    private var isInitialAppLaunch = true

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSwiftUIView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = false
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.title = NSLocalizedString("Welcome", comment: "")

        // Refresh data when returning
        viewModel.loadProducts()

        if isInitialAppLaunch {
            isInitialAppLaunch = false
            if InAppPurchasesManager.shared()!.hasProMode() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.goToConnectViewController()
                }
            }
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    // MARK: - SwiftUI Setup

    private func setupSwiftUIView() {
        let welcomeView = WelcomeView(
            viewModel: viewModel,
            onContinue: { [weak self] in
                self?.goToConnectViewController()
            },
            onHelp: { [weak self] in
                self?.showHelp()
            },
            onReviewApp: { [weak self] in
                self?.reviewApp()
            }
        )

        let hostingController = UIHostingController(rootView: welcomeView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        swiftUIHostingController = hostingController
    }

    // MARK: - Navigation

    func goToConnectViewController() {
        let scanner = DeviceScannerViewController()
        navigationController?.pushViewController(scanner, animated: true)
    }

    func showHelp() {
        let helpView = RemoteShutterHelpView(onDismiss: { [weak self] in
            self?.dismiss(animated: true)
        })
        let hostingController = UIHostingController(rootView: helpView)
        hostingController.modalPresentationStyle = .pageSheet
        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(hostingController, animated: true)
    }

    // MARK: - Review

    private func reviewApp() {
        var count = UserDefaults.standard.integer(forKey: reviewCounterKey)
        count += 1
        UserDefaults.standard.set(count, forKey: reviewCounterKey)

        let infoDictionaryKey = kCFBundleVersionKey as String
        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String else { return }
        let lastVersionPrompted = UserDefaults.standard.string(forKey: lastVersionPromptedForReviewKey)

        if count <= 4 && currentVersion != lastVersionPrompted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard self?.navigationController?.topViewController is WelcomeViewController else { return }
                SKStoreReviewController.requestReview()
                UserDefaults.standard.set(currentVersion, forKey: lastVersionPromptedForReviewKey)
            }
        }
    }

}
