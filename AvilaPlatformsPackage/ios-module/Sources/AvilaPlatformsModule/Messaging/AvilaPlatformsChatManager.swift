import Foundation

public extension Notification.Name {
    /// Posted when the app should open a conversation with a provider. `userInfo["providerID"]` is the barber **profile** id (e.g. bookings-simple `barberId`).
    static let avilaPlatformsStartProviderChat = Notification.Name("AvilaPlatformsStartProviderChat")
}

/// Host apps observe `avilaPlatformsStartProviderChat` (or mirror it into `NavigationPath`) to open messaging.
public enum AvilaPlatformsChatManager {
    public static func start(providerID: String) {
        let trimmed = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NotificationCenter.default.post(
            name: .avilaPlatformsStartProviderChat,
            object: nil,
            userInfo: ["providerID": trimmed]
        )
    }
}
