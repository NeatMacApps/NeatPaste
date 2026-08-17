**Languages:** English | [简体中文](README.zh-CN.md)

# NeatPaste

<p align="center">
  <img src="design/app-icon/AppIcon-1024.png" width="128" height="128" alt="NeatPaste app icon">
</p>

NeatPaste is a **macOS clipboard history manager**. It lives in the menu bar, records what you copy, and lets you pick a recent item with a global shortcut so you can paste it back into the app you were typing in.

This is a macOS clipboard history manager, unrelated to the iOS text-cleaning app of the same name.

**Requires macOS 26 or later, Apple silicon.** Open source under the MIT License. History stays on your Mac - there is no account, no sync, and no network.

<!-- 截图待补：将面板图与设置窗图存入 docs/images/ 后取消注释
<p align="center">
  <img src="docs/images/panel-light.png" width="360" alt="NeatPaste history panel with search field and item list">
  <img src="docs/images/settings.png" width="360" alt="NeatPaste settings window with shortcut and launch-at-login options">
</p>
-->

## Install

A signed disk image is not published yet. Build from source:

1. Install Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
2. Clone this repository.
3. From the repository root:

```bash
xcodegen generate
xcodebuild -project NeatPaste.xcodeproj -scheme NeatPaste -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData build
rm -rf /Applications/NeatPaste.app
ditto build/DerivedData/Build/Products/Release/NeatPaste.app /Applications/NeatPaste.app
open /Applications/NeatPaste.app
```

Then click the menu bar icon or press **⌘⌥V**.

## Usage

1. Press <kbd>⌘</kbd>+<kbd>⌥</kbd>+<kbd>V</kbd> (or click the menu bar icon) to open the panel. The newest item is already selected.
2. Type to filter. Move with <kbd>↑</kbd> / <kbd>↓</kbd>. Press <kbd>Enter</kbd> to paste into the app you were typing in. Press <kbd>Space</kbd> for Quick Look, <kbd>Esc</kbd> or click outside to close.
3. <kbd>⌘</kbd>+<kbd>,</kbd> opens Settings: shortcut, launch at login (off by default), and ignored apps (coming next).
4. Automatic paste needs Accessibility permission. Without it, NeatPaste still copies the item to the system clipboard so you can paste with <kbd>⌘</kbd>+<kbd>V</kbd> yourself.

## Features

- Keyboard-first: open, filter, paste without touching the mouse
- Text and images, thumbnails inline, no format downgrading
- Duplicates merge; the latest copy moves to the top
- History kept for 7 days and survives restarts, stored only on your Mac
- Panel appears next to your text cursor

## Not in scope

Pinning, favorites, cloud sync, AI, other platforms, an App Store build, or downgrading rich content to plain text.

## License

[MIT](LICENSE)
