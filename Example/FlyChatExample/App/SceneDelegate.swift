import FlyChat
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = makeRootViewController()
        self.window = window
        window.makeKeyAndVisible()
    }

    // MARK: - Root

    /// Builds the root controller, branching to the auto-chat deep link when requested.
    ///
    /// Pass the launch argument `-FCLExampleAutoChat` or set the environment variable
    /// `FCL_EXAMPLE_AUTOCHAT=1` to open straight into the populated Liquid Glass chat for
    /// testing and screenshots; otherwise the entry → style → list → chat flow is unchanged.
    private func makeRootViewController() -> UIViewController {
        if ExampleLaunchOptions.autoChatRequested {
            return makeAutoChatNavigationController()
        }
        return UINavigationController(rootViewController: ExampleEntryViewController())
    }

    /// A navigation stack that opens directly on the Liquid Glass chat with "Alice Doe".
    ///
    /// The Liquid Glass chat list sits underneath so the floating glass back button pops to a
    /// real screen, matching the entry-flow navigation behavior.
    private func makeAutoChatNavigationController() -> UINavigationController {
        let delegate = ExamplePresets.delegate(for: .liquidGlass)
        let navigationController = UINavigationController()

        let listVC = FCLUIKitBridge.makeChatListViewController(
            chats: ExampleSampleData.chats,
            title: ExampleStyle.liquidGlass.listTitle,
            onChatTap: { [weak navigationController] summary in
                let chatVC = ExampleChatScene.makeChatViewController(
                    for: summary,
                    delegate: delegate,
                    onBack: { [weak navigationController] in
                        navigationController?.popViewController(animated: true)
                    }
                )
                navigationController?.pushViewController(chatVC, animated: true)
            },
            delegate: delegate
        )

        let chatVC = ExampleChatScene.makeChatViewController(
            for: ExampleSampleData.aliceChat,
            delegate: delegate,
            onBack: { [weak navigationController] in
                navigationController?.popViewController(animated: true)
            }
        )
        navigationController.viewControllers = [listVC, chatVC]
        return navigationController
    }
}

// MARK: - ExampleLaunchOptions

/// Reads the launch toggles that drive deep links for testing and screenshots.
enum ExampleLaunchOptions {
    /// `true` when launched with `-FCLExampleAutoChat` or `FCL_EXAMPLE_AUTOCHAT=1`.
    static var autoChatRequested: Bool {
        let info = ProcessInfo.processInfo
        return info.arguments.contains("-FCLExampleAutoChat")
            || info.environment["FCL_EXAMPLE_AUTOCHAT"] == "1"
    }
}
