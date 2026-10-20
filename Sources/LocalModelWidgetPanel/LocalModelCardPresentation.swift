import Foundation
import ModelWidgetCore

public struct LocalModelCardPresentation: Equatable {
    public struct Loaded: Equatable {
        public let name: String
        public let hostName: String

        public init(name: String, hostName: String) {
            self.name = name
            self.hostName = hostName
        }
    }

    public struct UnloadButton: Equatable {
        public let title: String
        public let isEnabled: Bool
        public let accessibilityLabel: String
    }

    public static let noModelText = "No model loaded"

    public let line: String
    public let loaded: Loaded?
    /// Present only while a model is loaded.
    public let unloadButton: UnloadButton?

    public static func make(activeModel: LocalModelIdentity?, isBusy: Bool) -> LocalModelCardPresentation {
        guard let activeModel else {
            return LocalModelCardPresentation(line: noModelText, loaded: nil, unloadButton: nil)
        }

        let loaded = Loaded(name: activeModel.name, hostName: hostName(for: activeModel.providerID))
        return LocalModelCardPresentation(
            line: "\(loaded.name) · \(loaded.hostName)",
            loaded: loaded,
            unloadButton: UnloadButton(
                title: "Unload",
                isEnabled: isBusy == false,
                accessibilityLabel: "Unload \(loaded.name) from \(loaded.hostName)"
            )
        )
    }

    /// Mirrors each client's `displayName`, so the card can name a host from a model identity alone.
    public static func hostName(for providerID: String) -> String {
        switch providerID {
        case "bonsai":
            return "Bonsai"
        case "magnitude":
            return "Magnitude"
        case "ollama":
            return "Ollama"
        default:
            return providerID
        }
    }
}
