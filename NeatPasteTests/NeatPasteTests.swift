import AppKit
import MacKitCore
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class HotkeyDefaultTests: XCTestCase {
    @MainActor
    func test_默认快捷键是CommandOptionV() {
        XCTAssertEqual(HotkeyManager.Shortcut.safeDefault.keyCode, UInt32(kVK_ANSI_V))
        XCTAssertEqual(HotkeyManager.Shortcut.safeDefault.modifiers, UInt32(cmdKey | optionKey))
        XCTAssertEqual(HotkeyManager.Shortcut.safeDefault.displayName, "⌘⌥V")
    }
}

final class HistoryRetentionTests: XCTestCase {
    func test_历史保留七天() {
        XCTAssertEqual(AppPreferences.historyLifetime, 7 * 24 * 3600)
        XCTAssertEqual(AppPreferences.clipboardPollInterval, 0.5, accuracy: 0.0001)
    }

    func test_面板默认尺寸是八成宽九成高() {
        XCTAssertEqual(AppPreferences.panelSize, NSSize(width: 320, height: 432))
    }

    @MainActor
    func test_菜单栏图标默认显示() {
        XCTAssertEqual(AppPreferences.Key.menuBarIconVisible, "menuBar.iconVisible")
        XCTAssertTrue(AppPreferences.menuBarIconVisibleDefault)
    }

    @MainActor
    func test_历史面板不可调整大小() {
        let panel = HistoryPanel(model: HistoryPanelModel(history: InMemoryHistoryStore()))
        XCTAssertFalse(panel.styleMask.contains(.resizable))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertEqual(panel.minSize, AppPreferences.panelSize)
        XCTAssertEqual(panel.maxSize, AppPreferences.panelSize)
    }
}

final class HistorySearchTests: XCTestCase {
    func test_假数据筛选不区分大小写() async {
        let store = InMemoryHistoryStore(records: InMemoryHistoryStore.fixtureItems())
        let all = await store.items()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.first?.plainText.contains("NeatPaste"), true)
        XCTAssertTrue(all.contains { $0.hasImage })

        let english = await store.search("neatpaste")
        XCTAssertEqual(english.count, 1)

        let chinese = await store.search("中文")
        XCTAssertEqual(chinese.count, 1)

        let empty = await store.search("   ")
        XCTAssertEqual(empty.count, 3)
    }

    func test_包含匹配是纯函数() {
        let item = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: "Hello NeatPaste",
            sourceBundleID: nil,
            hasImage: false
        )
        XCTAssertTrue(HistorySearch.matches(item, query: "neat"))
        XCTAssertFalse(HistorySearch.matches(item, query: "missing"))
    }
}

final class PasteboardCaptureTests: XCTestCase {
    func test_密码管理器标记不收录() {
        let decision = PasteboardCapture.decide(
            types: ["public.utf8-plain-text", PasteboardCapture.concealedType],
            sourceBundleID: "com.apple.Safari",
            ignoredApps: []
        )
        XCTAssertEqual(decision, .skipSensitive)
    }

    func test_瞬时内容不收录() {
        XCTAssertEqual(
            PasteboardCapture.decide(
                types: [PasteboardCapture.transientType, "public.utf8-plain-text"],
                sourceBundleID: nil,
                ignoredApps: []
            ),
            .skipSensitive
        )
    }

    func test_本应用写回不收录() {
        XCTAssertEqual(
            PasteboardCapture.decide(
                types: ["public.utf8-plain-text", PasteboardCapture.internalType],
                sourceBundleID: nil,
                ignoredApps: []
            ),
            .skipOwnWrite
        )
    }

    func test_忽略名单中的应用不收录() {
        XCTAssertEqual(
            PasteboardCapture.decide(
                types: ["public.utf8-plain-text"],
                sourceBundleID: "com.bank.app",
                ignoredApps: ["com.bank.app"]
            ),
            .skipIgnoredApp
        )
    }

    func test_普通文本会收录() {
        XCTAssertEqual(
            PasteboardCapture.decide(
                types: ["public.utf8-plain-text"],
                sourceBundleID: "com.apple.TextEdit",
                ignoredApps: []
            ),
            .capture
        )
    }

    func test_不读取Word链接源类型() {
        XCTAssertTrue(PasteboardCapture.isUnsafeToRead(PasteboardCapture.microsoftLinkSource))
        XCTAssertTrue(PasteboardCapture.isUnsafeToRead("com.microsoft.ole.source.doc"))
        XCTAssertFalse(PasteboardCapture.isUnsafeToRead("public.utf8-plain-text"))
    }

    func test_内容还没装上时不要把变化计数往前推() {
        XCTAssertFalse(PasteboardCapture.shouldAdvanceChangeCount(decision: .capture, didCapture: false))
        XCTAssertTrue(PasteboardCapture.shouldAdvanceChangeCount(decision: .capture, didCapture: true))
        XCTAssertTrue(PasteboardCapture.shouldAdvanceChangeCount(decision: .skipSensitive, didCapture: false))
        XCTAssertTrue(PasteboardCapture.shouldAdvanceChangeCount(decision: .skipOwnWrite, didCapture: false))
        XCTAssertTrue(PasteboardCapture.shouldAdvanceChangeCount(decision: .skipIgnoredApp, didCapture: false))
    }

    @MainActor
    func test_独立剪贴板能从整板字符串读出快照() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("neatpaste.test.string.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let token = "neatpaste-board-string-\(UUID().uuidString)"
        XCTAssertTrue(pasteboard.setString(token, forType: .string))

        let snapshot = PasteboardCapture.snapshot(from: pasteboard, sourceBundleID: nil, ignoredApps: [])
        XCTAssertEqual(
            snapshot?.payloads["public.utf8-plain-text"].flatMap { String(data: $0, encoding: .utf8) },
            token
        )
    }

    @MainActor
    func test_条目只有字符串没有字节时仍能读出() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("neatpaste.test.item-string.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let token = "neatpaste-item-string-\(UUID().uuidString)"
        let item = NSPasteboardItem()
        item.setString(token, forType: .string)
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let snapshot = PasteboardCapture.snapshot(from: pasteboard, sourceBundleID: nil, ignoredApps: [])
        XCTAssertEqual(
            snapshot?.payloads["public.utf8-plain-text"].flatMap { String(data: $0, encoding: .utf8) },
            token
        )
    }
}

final class HistoryIngestTests: XCTestCase {
    func test_空仓库默认没有假数据() async {
        let store = InMemoryHistoryStore()
        let all = await store.items()
        XCTAssertEqual(all.count, 0)
    }

    func test_收入快照后出现在列表最前() async {
        let store = InMemoryHistoryStore()
        let payload = Data("unique-clipboard-token-α".utf8)
        await store.ingest(
            PasteboardSnapshot(
                changeCount: 42,
                types: ["public.utf8-plain-text"],
                payloads: ["public.utf8-plain-text": payload],
                sourceBundleID: "com.apple.TextEdit"
            )
        )
        let all = await store.items()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.plainText, "unique-clipboard-token-α")
        XCTAssertEqual(all.first?.payloads["public.utf8-plain-text"], payload)
    }

    func test_过期记录会被清掉() async {
        let old = HistoryItem(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-8 * 24 * 3600),
            plainText: "too old",
            sourceBundleID: nil,
            hasImage: false
        )
        let store = InMemoryHistoryStore(records: [old])
        await store.ingest(
            PasteboardSnapshot(
                changeCount: 1,
                types: ["public.utf8-plain-text"],
                payloads: ["public.utf8-plain-text": Data("fresh".utf8)],
                sourceBundleID: nil
            )
        )
        let all = await store.items()
        XCTAssertEqual(all.map(\.plainText), ["fresh"])
    }

    func test_相同文本再次复制只留一条并顶到最上() async {
        let store = InMemoryHistoryStore()
        await store.ingest(textSnapshot("alpha", changeCount: 1))
        await store.ingest(textSnapshot("beta", changeCount: 2))
        await store.ingest(textSnapshot("alpha", changeCount: 3))
        let all = await store.items()
        XCTAssertEqual(all.map(\.plainText), ["alpha", "beta"])
    }

    func test_相同图片再次复制只留一条() async {
        let store = InMemoryHistoryStore()
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        await store.ingest(
            PasteboardSnapshot(
                changeCount: 1,
                types: ["public.png"],
                payloads: ["public.png": bytes],
                sourceBundleID: nil
            )
        )
        await store.ingest(
            PasteboardSnapshot(
                changeCount: 2,
                types: ["public.png", "public.utf8-plain-text"],
                payloads: [
                    "public.png": bytes,
                    "public.utf8-plain-text": Data("screenshot".utf8)
                ],
                sourceBundleID: "com.apple.screencapture"
            )
        )
        let all = await store.items()
        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(all[0].hasImage)
    }

    func test_落盘后新仓库能读回未过期记录() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("neatpaste-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = InMemoryHistoryStore(storageURL: url)
        await first.ingest(textSnapshot("survive-restart", changeCount: 1))
        let second = InMemoryHistoryStore(storageURL: url)
        let all = await second.items()
        XCTAssertEqual(all.map(\.plainText), ["survive-restart"])
        XCTAssertEqual(all.first?.payloads["public.utf8-plain-text"], Data("survive-restart".utf8))
    }

    func test_过期记录读盘时会被丢掉() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("neatpaste-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let old = HistoryItem(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-8 * 24 * 3600),
            plainText: "expired-on-disk",
            sourceBundleID: nil,
            hasImage: false,
            payloads: ["public.utf8-plain-text": Data("expired-on-disk".utf8)]
        )
        let fresh = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: "still-valid",
            sourceBundleID: nil,
            hasImage: false,
            payloads: ["public.utf8-plain-text": Data("still-valid".utf8)]
        )
        _ = InMemoryHistoryStore(records: [old, fresh], storageURL: url)
        let reloaded = InMemoryHistoryStore(storageURL: url)
        let all = await reloaded.items()
        XCTAssertEqual(all.map(\.plainText), ["still-valid"])
    }

    private func textSnapshot(_ text: String, changeCount: Int) -> PasteboardSnapshot {
        PasteboardSnapshot(
            changeCount: changeCount,
            types: ["public.utf8-plain-text"],
            payloads: ["public.utf8-plain-text": Data(text.utf8)],
            sourceBundleID: nil
        )
    }
}

final class HistoryPayloadVaultTests: XCTestCase {
    func test_图片收入后外置且内存无整图() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("neatpaste-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.json")

        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let store = InMemoryHistoryStore(storageURL: url)
        await store.ingest(
            PasteboardSnapshot(
                changeCount: 1,
                types: ["public.png", "NeXT TIFF v4.0 pasteboard type"],
                payloads: [
                    "public.png": png,
                    "NeXT TIFF v4.0 pasteboard type": png
                ],
                sourceBundleID: nil
            )
        )

        let items = await store.items()
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].externalPayloadTypes.contains("public.png"))
        XCTAssertNil(items[0].payloads["public.png"])
        XCTAssertNotNil(items[0].preferredExternalImageURL())

        let json = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(json.contains(png.base64EncodedString()), "瘦 JSON 不应再含整图 Base64")

        let materialized = await store.materializePayloads(id: items[0].id)
        XCTAssertEqual(materialized["public.png"], png)
        XCTAssertEqual(materialized["NeXT TIFF v4.0 pasteboard type"], png)

        let payloadsDir = dir.appendingPathComponent("payloads")
        let itemDir = payloadsDir.appendingPathComponent(items[0].id.uuidString)
        let files = try FileManager.default.contentsOfDirectory(atPath: itemDir.path)
        // manifest + 同一字节只一份 blob
        XCTAssertEqual(files.filter { $0 != "manifest.json" }.count, 1)
    }

    func test_相同图片外置后仍去重() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("neatpaste-dedupe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.json")
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 7, count: 200)

        let store = InMemoryHistoryStore(storageURL: url)
        await store.ingest(
            PasteboardSnapshot(
                changeCount: 1,
                types: ["public.png"],
                payloads: ["public.png": bytes],
                sourceBundleID: nil
            )
        )
        await store.ingest(
            PasteboardSnapshot(
                changeCount: 2,
                types: ["public.png", "public.utf8-plain-text"],
                payloads: [
                    "public.png": bytes,
                    "public.utf8-plain-text": Data("screenshot".utf8)
                ],
                sourceBundleID: "com.apple.screencapture"
            )
        )
        let all = await store.items()
        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(all[0].hasImage)
    }

    func test_旧胖JSON启动时外置迁移() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("neatpaste-migrate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.json")

        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let legacyID = UUID()
        let legacy: [[String: Any]] = [[
            "id": legacyID.uuidString,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "plainText": "legacy-shot",
            "hasImage": true,
            "hasFilePromise": false,
            "types": ["public.png"],
            "payloads": ["public.png": png.base64EncodedString()]
        ]]
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        try legacyData.write(to: url)

        let store = InMemoryHistoryStore(storageURL: url)
        let items = await store.items()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].plainText, "legacy-shot")
        XCTAssertTrue(items[0].externalPayloadTypes.contains("public.png"))
        XCTAssertNil(items[0].payloads["public.png"])

        let rewritten = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(rewritten.contains("inlinePayloads"))
        XCTAssertTrue(rewritten.contains("externalPayloadTypes"))
        XCTAssertFalse(rewritten.contains(png.base64EncodedString()))

        let thumb = HistoryThumbnail.image(for: items[0])
        XCTAssertNotNil(thumb)

        let preview = try QuickLookPreviewFile.makeURL(for: items[0])
        XCTAssertTrue(FileManager.default.fileExists(atPath: preview.path))
    }

    func test_过期清理会删旁路目录() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("neatpaste-expire-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.json")
        let png = Data(repeating: 9, count: 128)

        let store = InMemoryHistoryStore(storageURL: url)
        await store.ingest(
            PasteboardSnapshot(
                changeCount: 1,
                types: ["public.png"],
                payloads: ["public.png": png],
                sourceBundleID: nil
            )
        )
        let items = await store.items()
        let itemID = try XCTUnwrap(items.first?.id)
        let itemDir = dir.appendingPathComponent("payloads").appendingPathComponent(itemID.uuidString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: itemDir.path))

        await store.sweepExpired(olderThan: Date().addingTimeInterval(3600))
        XCTAssertFalse(FileManager.default.fileExists(atPath: itemDir.path))
        let remaining = await store.items()
        XCTAssertTrue(remaining.isEmpty)
    }
}

final class HistoryPanelDismissTests: XCTestCase {
    func test_点在面板里不要关() {
        let panel = CGRect(x: 100, y: 100, width: 400, height: 480)
        XCTAssertFalse(HistoryPanelDismiss.shouldHide(click: CGPoint(x: 200, y: 200), keptFrames: [panel]))
    }

    func test_点在面板外要立刻关() {
        let panel = CGRect(x: 100, y: 100, width: 400, height: 480)
        XCTAssertTrue(HistoryPanelDismiss.shouldHide(click: CGPoint(x: 20, y: 20), keptFrames: [panel]))
    }

    func test_点在系统预览上不要关() {
        let panel = CGRect(x: 100, y: 100, width: 400, height: 480)
        let preview = CGRect(x: 520, y: 220, width: 480, height: 360)
        XCTAssertFalse(HistoryPanelDismiss.shouldHide(click: CGPoint(x: 700, y: 300), keptFrames: [panel, preview]))
    }

    func test_点在菜单栏本图标上不要关() {
        let panel = CGRect(x: 100, y: 100, width: 400, height: 480)
        let statusItem = CGRect(x: 1200, y: 870, width: 28, height: 22)
        XCTAssertFalse(HistoryPanelDismiss.shouldHide(click: CGPoint(x: 1210, y: 880), keptFrames: [panel, statusItem]))
        XCTAssertTrue(HistoryPanelDismiss.shouldHide(click: CGPoint(x: 1100, y: 880), keptFrames: [panel, statusItem]))
    }
}

final class PanelAnchorTests: XCTestCase {
    func test_光标下方有空间时面板放在光标下面() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let caret = NSRect(x: 400, y: 500, width: 2, height: 16)
        let size = NSSize(width: 400, height: 480)
        let origin = PanelAnchor.origin(for: size, on: visible, preferredRect: caret)
        XCTAssertEqual(origin.y, caret.minY - size.height - 12, accuracy: 0.5)
        XCTAssertEqual(origin.x, caret.midX - size.width / 2, accuracy: 0.5)
    }

    func test_大输入框收成靠近鼠标的小锚点() {
        let field = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let mouse = NSPoint(x: 300, y: 400)
        let compact = PanelAnchor.compactAnchor(from: field, mouse: mouse)
        XCTAssertEqual(compact.width, 2)
        XCTAssertEqual(compact.height, 16)
        XCTAssertEqual(compact.minX, 300, accuracy: 0.5)
        XCTAssertEqual(compact.minY, 392, accuracy: 0.5)
    }

    func test_小输入框保持原样() {
        let field = NSRect(x: 100, y: 200, width: 240, height: 22)
        let compact = PanelAnchor.compactAnchor(from: field, mouse: .zero)
        XCTAssertEqual(compact, field)
    }
}

final class HistoryTextTests: XCTestCase {
    func test_从UTF8载荷抽出纯文本() {
        let text = HistoryText.plainText(from: [
            "public.utf8-plain-text": Data("hello".utf8)
        ])
        XCTAssertEqual(text, "hello")
    }

    func test_图片临时文件名不当标题() {
        let uuidName = "890D4B19-D55D-45F5-8549-775A75AFDD13_4.png"
        XCTAssertTrue(HistoryText.isMachineGeneratedName(uuidName))
        XCTAssertEqual(
            HistoryText.listTitle(plainText: uuidName, hasImage: true),
            String(localized: "panel.image.placeholder")
        )
        XCTAssertEqual(
            HistoryText.listTitle(
                plainText: "file:///var/folders/xx/T/\(uuidName)",
                hasImage: true
            ),
            String(localized: "panel.image.placeholder")
        )
    }

    func test_真人能认的截图文件名要保留() {
        let name = "Screenshot 2026-08-15 at 17.12.00.png"
        XCTAssertFalse(HistoryText.isMachineGeneratedName(name))
        XCTAssertEqual(HistoryText.listTitle(plainText: name, hasImage: true), name)
    }

    func test_普通文本标题保持原样() {
        XCTAssertEqual(HistoryText.listTitle(plainText: "hello", hasImage: false), "hello")
    }
}

final class HistoryThumbnailTests: XCTestCase {
    func test_能从外置旁路文件做出缩略图() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("neatpaste-thumb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let id = UUID()
        let vault = PayloadVault(rootURL: dir)
        _ = try vault.spill(itemID: id, payloads: ["public.png": png])

        let item = HistoryItem(
            id: id,
            createdAt: Date(),
            plainText: "shot",
            sourceBundleID: nil,
            hasImage: true,
            types: ["public.png"],
            payloads: [:],
            externalPayloadTypes: ["public.png"],
            payloadDirectoryURL: dir
        )
        let thumbnail = HistoryThumbnail.image(for: item)
        XCTAssertNotNil(thumbnail)
        XCTAssertGreaterThan(thumbnail?.size.width ?? 0, 0)
    }

    func test_能从png字节做出缩略图() {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let item = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: "890D4B19-D55D-45F5-8549-775A75AFDD13_4.png",
            sourceBundleID: nil,
            hasImage: true,
            types: ["public.png"],
            payloads: ["public.png": png]
        )
        let thumbnail = HistoryThumbnail.image(for: item)
        XCTAssertNotNil(thumbnail)
        XCTAssertGreaterThan(thumbnail?.size.width ?? 0, 0)
        XCTAssertGreaterThan(thumbnail?.size.height ?? 0, 0)
    }
}

final class AutofillHeuristicGuardTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "NeatPasteTests.autofill.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_注册默认值关闭AutoFill启发式() {
        XCTAssertEqual(
            AutofillHeuristicGuard.registeredDefaults()[AutofillHeuristicGuard.defaultsKey],
            false
        )
        AutofillHeuristicGuard.install(defaults: defaults)
        XCTAssertEqual(defaults.object(forKey: AutofillHeuristicGuard.defaultsKey) as? Bool, false)
    }
}

final class AppDelegateTests: XCTestCase {
    @MainActor
    func test_用户主动退出会放行并发出终止请求() {
        let delegate = AppDelegate()
        var didRequestTermination = false
        delegate.requestTermination {
            didRequestTermination = true
        }
        XCTAssertTrue(didRequestTermination)
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow)
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}

final class MenuBarRecoveryPolicyTests: XCTestCase {
    func test_图标隐藏时再次打开必须出示恢复窗() {
        XCTAssertEqual(
            MenuBarReopenPolicy.presentation(iconVisible: false, isReopenOrLaunch: true),
            .showRecoveryWindow
        )
        XCTAssertTrue(MenuBarReopenPolicy.shouldShowRecoveryWindow(iconVisible: false))
    }

    func test_图标可见时再次打开不要用恢复窗顶替() {
        XCTAssertEqual(
            MenuBarReopenPolicy.presentation(iconVisible: true, isReopenOrLaunch: true),
            .none
        )
        XCTAssertFalse(MenuBarReopenPolicy.shouldShowRecoveryWindow(iconVisible: true))
    }

    func test_待批准不能当成开机自启已打开() {
        XCTAssertTrue(LaunchAtLoginStatus.on.isEffectivelyEnabled)
        XCTAssertFalse(LaunchAtLoginStatus.needsApproval.isEffectivelyEnabled)
        XCTAssertFalse(LaunchAtLoginStatus.off.isEffectivelyEnabled)
    }
}

final class QuickLookPreviewFileTests: XCTestCase {
    func test_纯文本落成txt() throws {
        let item = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: "Hello Quick Look",
            sourceBundleID: nil,
            hasImage: false,
            payloads: ["public.utf8-plain-text": Data("Hello Quick Look".utf8)]
        )
        let url = try QuickLookPreviewFile.makeURL(for: item)
        XCTAssertEqual(url.pathExtension, "txt")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Hello Quick Look")
    }

    func test_图片优先用png字节() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let item = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: "screenshot",
            sourceBundleID: nil,
            hasImage: true,
            types: ["public.png"],
            payloads: ["public.png": png]
        )
        let url = try QuickLookPreviewFile.makeURL(for: item)
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: url), png)
    }

    func test_存在的本地文件直接用原路径() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("neatpaste-ql-source.txt")
        try "from disk".write(to: file, atomically: true, encoding: .utf8)
        let item = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: "from disk",
            sourceBundleID: nil,
            hasImage: false,
            payloads: ["public.file-url": Data(file.absoluteString.utf8)]
        )
        let url = try QuickLookPreviewFile.makeURL(for: item)
        XCTAssertEqual(url.standardizedFileURL, file.standardizedFileURL)
    }

    func test_预览窗默认尺寸保持小窗() {
        XCTAssertEqual(AppPreferences.quickLookSize, NSSize(width: 480, height: 360))
        XCTAssertLessThanOrEqual(AppPreferences.quickLookMaxSize.width, 560)
        XCTAssertLessThanOrEqual(AppPreferences.quickLookMaxSize.height, 420)
        XCTAssertGreaterThan(AppPreferences.quickLookMaxSize.width, AppPreferences.quickLookSize.width)
        XCTAssertGreaterThan(AppPreferences.quickLookMaxSize.height, AppPreferences.quickLookSize.height)
    }
}

final class PasteEngineWriteTests: XCTestCase {
    @MainActor
    func test_文本和文件地址一次写入后都还在() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("neatpaste-writeback-\(UUID().uuidString).txt")
        try "from disk".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let text = "hello-with-file-\(UUID().uuidString)"
        let record = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: text,
            sourceBundleID: nil,
            hasImage: false,
            types: ["public.utf8-plain-text", NSPasteboard.PasteboardType.fileURL.rawValue],
            payloads: [
                "public.utf8-plain-text": Data(text.utf8),
                NSPasteboard.PasteboardType.fileURL.rawValue: Data(file.absoluteString.utf8)
            ]
        )
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("neatpaste.test.write.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        PasteEngine.write(record, to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), text)
        let fileURL = pasteboard.string(forType: .fileURL)
            ?? pasteboard.pasteboardItems?.compactMap { $0.string(forType: .fileURL) }.first
        XCTAssertTrue(
            fileURL?.contains(file.lastPathComponent) == true,
            "写回后应仍带文件地址，实际=\(fileURL ?? "nil")"
        )
        XCTAssertNotNil(pasteboard.data(forType: NSPasteboard.PasteboardType(PasteboardCapture.internalType)))
    }
}

final class HistorySelectionTests: XCTestCase {
    @MainActor
    func test_连续下移会走到后面的条目() async {
        let store = InMemoryHistoryStore(records: InMemoryHistoryStore.fixtureItems())
        let model = HistoryPanelModel(history: store)
        await model.reload()
        XCTAssertEqual(model.visibleItems.count, 3)

        let first = model.selectedID
        model.moveSelection(1)
        let second = model.selectedID
        XCTAssertNotEqual(first, second)
        model.moveSelection(1)
        XCTAssertNotEqual(model.selectedID, second)
        XCTAssertNotEqual(model.selectedID, first)
    }
}

final class HistoryItemClickTests: XCTestCase {
    @MainActor
    func test_未选中再点只选中_已选中再点则粘贴() {
        XCTAssertEqual(HistoryItemClick.action(isAlreadySelected: false), .select)
        XCTAssertEqual(HistoryItemClick.action(isAlreadySelected: true), .paste)
    }

    @MainActor
    func test_点另一条只改选中不关面板() async {
        let store = InMemoryHistoryStore(records: InMemoryHistoryStore.fixtureItems())
        let model = HistoryPanelModel(history: store)
        var hid = false
        model.onHide = { hid = true }
        await model.reload()
        let first = model.selectedID
        let second = model.visibleItems[1].id
        XCTAssertNotEqual(first, second)

        await model.handleItemClick(second)
        XCTAssertEqual(model.selectedID, second)
        XCTAssertFalse(hid)
        XCTAssertFalse(model.needsAccessibilityPrompt)
    }
}

final class HistoryDeleteTests: XCTestCase {
    @MainActor
    func test_删除当前条后选中落到同位置下一条且不关面板() async {
        let store = InMemoryHistoryStore(records: InMemoryHistoryStore.fixtureItems())
        let model = HistoryPanelModel(history: store)
        var hid = false
        model.onHide = { hid = true }
        await model.reload()
        XCTAssertEqual(model.visibleItems.count, 3)
        let first = model.visibleItems[0].id
        let second = model.visibleItems[1].id

        await model.deleteItem(first)
        XCTAssertEqual(model.visibleItems.count, 2)
        XCTAssertEqual(model.selectedID, second)
        XCTAssertFalse(hid)
        let remaining = await store.items()
        XCTAssertFalse(remaining.contains { $0.id == first })
    }

    @MainActor
    func test_删除最后一条后选中落到上一条() async {
        let store = InMemoryHistoryStore(records: InMemoryHistoryStore.fixtureItems())
        let model = HistoryPanelModel(history: store)
        await model.reload()
        let last = model.visibleItems[2].id
        let previous = model.visibleItems[1].id
        model.select(last)

        await model.deleteItem(last)
        XCTAssertEqual(model.visibleItems.count, 2)
        XCTAssertEqual(model.selectedID, previous)
    }

    @MainActor
    func test_删除非选中条时保留原选中() async {
        let store = InMemoryHistoryStore(records: InMemoryHistoryStore.fixtureItems())
        let model = HistoryPanelModel(history: store)
        await model.reload()
        let first = model.visibleItems[0].id
        let third = model.visibleItems[2].id

        await model.deleteItem(third)
        XCTAssertEqual(model.visibleItems.count, 2)
        XCTAssertEqual(model.selectedID, first)
    }
}

final class ArrowKeyRepeatTests: XCTestCase {
    @MainActor
    func test_按住会按间隔连续走步() async {
        var held = true
        let repeater = ArrowKeyRepeat(delay: 0.04, interval: 0.04, isKeyPressed: { _ in held })
        var steps: [Int] = []
        let repeating = expectation(description: "连续走步")
        repeating.assertForOverFulfill = false
        repeater.onStep = { delta in
            steps.append(delta)
            if steps.count >= 3 {
                repeating.fulfill()
            }
        }

        repeater.keyDown(keyCode: 125, isARepeat: false, delta: 1)
        XCTAssertEqual(steps, [1])
        await fulfillment(of: [repeating], timeout: 1)
        XCTAssertGreaterThanOrEqual(steps.count, 3)
        XCTAssertTrue(steps.allSatisfy { $0 == 1 })

        repeater.keyUp(keyCode: 125)
        held = false
        let frozen = steps.count
        let idle = expectation(description: "松手后停")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            idle.fulfill()
        }
        await fulfillment(of: [idle], timeout: 1)
        XCTAssertEqual(steps.count, frozen)
        repeater.stop()
    }

    @MainActor
    func test_系统连发事件不再走一步() {
        let repeater = ArrowKeyRepeat(delay: 10, interval: 10, isKeyPressed: { _ in true })
        var count = 0
        repeater.onStep = { _ in count += 1 }
        repeater.keyDown(keyCode: 126, isARepeat: false, delta: -1)
        repeater.keyDown(keyCode: 126, isARepeat: true, delta: -1)
        repeater.keyDown(keyCode: 126, isARepeat: true, delta: -1)
        XCTAssertEqual(count, 1)
        repeater.stop()
    }

    @MainActor
    func test_同一键重复按下不连跳() {
        let repeater = ArrowKeyRepeat(delay: 10, interval: 10, isKeyPressed: { _ in true })
        var count = 0
        repeater.onStep = { _ in count += 1 }
        repeater.keyDown(keyCode: 125, isARepeat: false, delta: 1)
        repeater.keyDown(keyCode: 125, isARepeat: false, delta: 1)
        repeater.keyDown(keyCode: 125, isARepeat: false, delta: 1)
        XCTAssertEqual(count, 1)
        repeater.stop()
    }
}
