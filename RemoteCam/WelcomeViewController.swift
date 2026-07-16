import UIKit
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
            if StoreManager.shared.hasFullAccess() {
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

        swiftUIHostingController = embedSwiftUIView(welcomeView)
    }

    // MARK: - Navigation

    func goToConnectViewController() {
        let rolePicker = RolePickerController()
        navigationController?.pushViewController(rolePicker, animated: true)
    }

    func showHelp() {
        presentHelpSheet()
    }

    // MARK: - Review

    private func reviewApp() {
        openAppStoreReview()
    }

}
