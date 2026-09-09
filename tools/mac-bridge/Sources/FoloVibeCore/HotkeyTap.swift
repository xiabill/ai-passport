import Foundation

/// How a hotkey is delivered to an input method. Doubao's hands-free mode wants
/// a double click; Typeless answers a single press. Which one an input method
/// expects is not something the bridge can detect, and it changes between
/// versions, so it is left to the user.
public enum HotkeyTap: String, Codable, CaseIterable, Equatable {
    case single
    case double

    public var title: String {
        switch self {
        case .single: return "单击"
        case .double: return "双击"
        }
    }
}
