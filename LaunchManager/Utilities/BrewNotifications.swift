import Foundation

extension Notification.Name {
    static let brewServicesDidChange = Notification.Name("brewServicesDidChange")
}

struct BrewRowActions {
    let onStart: (HomebrewService) -> Void
    let onStop: (HomebrewService) -> Void
    let onRestart: (HomebrewService) -> Void
}
