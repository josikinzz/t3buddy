import AppKit

public enum DesktopPanelWindowMode: String, CaseIterable, Identifiable {
    case desktop = "Desktop"
    case floating = "Float"

    public var id: Self { self }
    public var title: String { rawValue }

    public var windowLevel: NSWindow.Level {
        switch self {
        case .desktop:
            return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .floating:
            return .floating
        }
    }

    public var collectionBehavior: NSWindow.CollectionBehavior {
        switch self {
        case .desktop:
            return [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        case .floating:
            return [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        }
    }
}
