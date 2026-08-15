**Languages:** English | [简体中文](README.zh.md)

# NeatPaste

<p align="center">
  <img src="design/app-icon/AppIcon-1024.png" width="128" height="128" alt="NeatPaste app icon">
</p>

NeatPaste is a **macOS clipboard history manager**. It lives in the menu bar, records what you copy, and lets you pick a recent item with a global shortcut so you can paste it back into the app you were typing in.

This is a macOS clipboard history manager, unrelated to the iOS text-cleaning app of the same name.

**Requires macOS 26 or later, Apple silicon.** Open source under the MIT License. History stays on your Mac — there is no account, no sync, and no network.

## Install

A signed disk image is not published yet. Build from source:

1. Install Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
2. Clone this repository.
3. From `app-macos/`:

```bash
xcodegen generate
xcodebuild -project NeatPaste.xcodeproj -scheme NeatPaste -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData build
rm -rf /Applications/NeatPaste.app
ditto build/DerivedData/Build/Products/Release/NeatPaste.app /Applications/NeatPaste.app
open /Applications/NeatPaste.app
```

Then click the menu bar icon or press **⌘⇧V**.

## Usage

- Open the panel from the menu bar or with the global shortcut (default **⌘⇧V**).
- Type to filter. Use ↑ / ↓ to move. Press **Enter** to paste. Press **Esc** or click outside to close.
- **⌘,** opens Settings: shortcut, launch at login (off by default), and ignored apps (coming next).
- Automatic paste needs Accessibility permission. Without it, NeatPaste still copies the item to the system clipboard so you can paste with ⌘V yourself.

## Not in scope

Pinning, favorites, cloud sync, AI, other platforms, an App Store build, or downgrading rich content to plain text.

## License

[MIT](LICENSE)
