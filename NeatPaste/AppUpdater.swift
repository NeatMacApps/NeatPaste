import Sparkle

/// 统一持有 Sparkle 控制器，保证自动检查器在应用整个生命周期内持续存活。
/// 菜单栏应用的「检查更新…」入口也由这里提供 target-action。
@MainActor
final class AppUpdater: NSObject {
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    override init() {
        super.init()
        _ = controller
    }

    var updater: SPUUpdater {
        controller.updater
    }

    /// 给菜单项当 target 用；Sparkle 自己弹检查与安装窗口。
    @objc
    func checkForUpdates(_ sender: Any?) {
        updater.checkForUpdates()
    }
}
