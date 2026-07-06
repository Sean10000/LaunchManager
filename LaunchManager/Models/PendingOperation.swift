import SwiftUI

enum PendingOperation: Equatable {
    case starting
    case stopping
    case loading
    case unloading
    case enabling
    case restarting

    var localizedLabel: LocalizedStringKey {
        switch self {
        case .starting:  return "启动中…"
        case .stopping:  return "停止中…"
        case .loading:   return "载入中…"
        case .unloading: return "移除中…"
        case .enabling:  return "启用中…"
        case .restarting: return "重启中…"
        }
    }
}
