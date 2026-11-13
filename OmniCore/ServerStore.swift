import Foundation

/// Adresse du serveur gardée sur l'iPhone. Le code du QR ne sert qu'une fois : il n'est jamais enregistré.
@MainActor
final class ServerStore: ObservableObject {
    @Published private(set) var startURL: URL?
    @Published private(set) var error: String?
    /// Change à chaque connexion : le navigateur repart de zéro, même pour la même adresse.
    @Published private(set) var session = UUID()

    private let key = "omnicore.server"

    init() {
        startURL = savedConfig()?.startURL
    }

    var savedServer: String? { UserDefaults.standard.string(forKey: key) }

    func connect(_ config: PairingConfig) {
        UserDefaults.standard.set(config.server, forKey: key)
        error = nil
        session = UUID()
        startURL = config.startURL
    }

    func fail(_ message: String) {
        error = message
        startURL = nil
    }

    func retry() {
        guard let config = savedConfig() else { return }
        error = nil
        session = UUID()
        startURL = config.startURL
    }

    private func savedConfig() -> PairingConfig? {
        savedServer.flatMap { PairingConfig.build(server: $0, code: nil) }
    }
}
