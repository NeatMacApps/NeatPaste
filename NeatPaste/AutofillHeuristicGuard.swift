import Foundation

/// 关掉 macOS 的 AutoFill 启发式，避免系统把 SafariPlatformSupport 补全列表挂到任意输入框。
///
/// macOS 27 上该远程视图在菜单栏项重新上屏时会触发 ViewBridge 断言并抛未捕获异常，直接杀死应用。
/// 使用 `register` 而非 `set`：不写入用户偏好，用户仍可自行覆盖；「编辑」菜单里的手动自动填充不受影响。
nonisolated enum AutofillHeuristicGuard {
    static let defaultsKey = "NSAutoFillHeuristicControllerEnabled"
    static let defaultEnabled = false

    /// 应用级默认值（可单测）。
    static func registeredDefaults() -> [String: Bool] {
        [defaultsKey: defaultEnabled]
    }

    static func install(defaults: UserDefaults = .standard) {
        defaults.register(defaults: registeredDefaults())
    }
}
