import SwiftUI

// The app's type scale.
//
// macOS's semantic sizes (body 13, callout 12, caption 10) read a little small
// in a dense transcript window, so every style is raised by roughly 15%.
// The sizes are explicit because `dynamicTypeSize` has no effect on AppKit:
// applying it does not scale SwiftUI fonts on macOS.
//
// Keep every text style in the UI in this one place so the scale stays
// consistent and is easy to tune.
enum AppFont {
    // Text
    static let body = Font.system(size: 15)
    static let callout = Font.system(size: 13.5)
    static let caption = Font.system(size: 11.5)
    static let caption2 = Font.system(size: 11)
    static let headline = Font.system(size: 15, weight: .semibold)
    static let title3 = Font.system(size: 17, weight: .semibold)
    static let captionStrong = Font.system(size: 11.5, weight: .semibold)

    // Monospaced (code, paths, tool output)
    static let monoCallout = Font.system(size: 13.5, design: .monospaced)
    static let monoCaption = Font.system(size: 11.5, design: .monospaced)
    static let monoCaption2 = Font.system(size: 11, design: .monospaced)
}
