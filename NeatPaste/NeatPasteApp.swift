import AppKit
import Foundation
import SwiftUI

@main
struct NeatPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var hiddenMenuInserted = false

    init() {
        AutofillHeuristicGuard.install()
    }

    var body: some Scene {
        // 永远隐藏：只为满足 SwiftUI App 必须有 Scene 的协议，真正菜单栏在 AppDelegate。
        MenuBarExtra("", isInserted: $hiddenMenuInserted) {
            EmptyView()
        }
    }
}
