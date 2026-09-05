import AppKit

/// 整窗通透玻璃。公开 API 只有 regular/clear，要去掉压暗层需探测私有属性；探不到就静默跳过。
@available(macOS 26.0, *)
final class PanelGlassView: NSGlassEffectView {
    private typealias IntegerSetter = @convention(c) (AnyObject, Selector, Int) -> Void
    private let glassCornerRadius: CGFloat

    init(frame frameRect: NSRect, cornerRadius: CGFloat) {
        glassCornerRadius = cornerRadius
        super.init(frame: frameRect)
        applyClearGlass()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("不支持通过归档创建玻璃底板")
    }

    override func layout() {
        super.layout()
        cornerRadius = glassCornerRadius
        applyClearGlass()
    }

    private func applyClearGlass() {
        style = .clear
        tintColor = .clear
        setPrivateIntegerProperty("variant", value: 2)
        setPrivateIntegerProperty("scrimState", value: 0)
        setPrivateIntegerProperty("subduedState", value: 0)
    }

    private func setPrivateIntegerProperty(_ key: String, value: Int) {
        let selectorNames = [
            "set_\(key):",
            "set\(key.prefix(1).uppercased())\(key.dropFirst()):"
        ]
        guard let selectorName = selectorNames.first(where: {
            responds(to: NSSelectorFromString($0))
        }) else {
            return
        }
        let selector = NSSelectorFromString(selectorName)
        let implementation = method(for: selector)
        let setter = unsafeBitCast(implementation, to: IntegerSetter.self)
        setter(self, selector, value)
    }
}
