import Foundation

enum UtilityKind: String, Sendable {
    case calculation
    case percentage
    case unitConversion
    case dateTime
    case timestamp
    case currency

    var systemImage: String {
        switch self {
        case .calculation:    return "function"
        case .percentage:     return "percent"
        case .unitConversion: return "ruler"
        case .dateTime:       return "calendar"
        case .timestamp:      return "clock"
        case .currency:       return "dollarsign.arrow.circlepath"
        }
    }
}

struct UtilityResult: Sendable {
    let kind: UtilityKind
    /// Value copied to the pasteboard on Enter / tap.
    let copyText: String
    /// Large primary display (inline preview + result row).
    let previewText: String
    /// Secondary line (timezone, tip total, unit breakdown).
    let detailText: String?

    nonisolated init(kind: UtilityKind, copyText: String, previewText: String, detailText: String? = nil) {
        self.kind = kind
        self.copyText = copyText
        self.previewText = previewText
        self.detailText = detailText
    }
}
