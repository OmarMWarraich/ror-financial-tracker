@preconcurrency import HotwireNative
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var navigator: Navigator?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        self.window = window

        if let policy = (UIApplication.shared.delegate as? AppDelegate)?.policy {
            let navigator = Navigator(configuration: .init(name: "main", startLocation: policy.baseURL))
            self.navigator = navigator
            window.rootViewController = navigator.rootViewController
            navigator.start()
        } else {
            let controller = UIViewController()
            controller.view.backgroundColor = .systemBackground
            let label = UILabel()
            label.text = "Invalid development URL. Use http://127.0.0.1:PORT or http://localhost:PORT."
            label.numberOfLines = 0
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            controller.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
                label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor)
            ])
            window.rootViewController = controller
        }
        window.makeKeyAndVisible()
    }
}
