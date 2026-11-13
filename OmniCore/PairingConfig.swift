import Foundation

/// Réglages reçus par le QR code de l'admin (omnicore://pair?d=…) ou saisis à la main. Même format que l'app Android.
/// La clé Tailscale éventuelle est ignorée : sur iPhone, c'est l'app Tailscale qui donne accès au réseau privé.
struct PairingConfig: Equatable {
    let server: String
    let code: String?

    private static let serverPattern = #"^[A-Za-z0-9.-]{1,253}(:\d{1,5})?$"#
    private static let codePattern = #"^([A-Za-z0-9_-]{43}|[A-HJ-NP-Z2-9]{8})$"#

    /// Toute valeur inattendue est refusée.
    static func build(server: String, code: String?) -> PairingConfig? {
        guard server.range(of: serverPattern, options: .regularExpression) != nil else { return nil }
        if let code, code.range(of: codePattern, options: .regularExpression) == nil { return nil }
        return PairingConfig(server: server, code: code)
    }

    /// Contenu du QR code : JSON encodé en base64url.
    static func fromLink(_ url: URL) -> PairingConfig? {
        guard url.scheme == "omnicore", url.host == "pair",
              let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "d" })?.value
        else { return nil }
        var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mode = json["mode"] as? String, mode == "lan" || mode == "tailnet",
              let server = json["server"] as? String
        else { return nil }
        let code = (json["code"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return build(server: server, code: code)
    }

    /// Adresse et code court affichés sous le QR code de l'admin.
    static func manual(server: String, code: String) -> PairingConfig? {
        var host = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("http://") { host.removeFirst("http://".count) }
        while host.hasSuffix("/") { host.removeLast() }
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().replacingOccurrences(of: "-", with: "")
        return build(server: host, code: cleaned.isEmpty ? nil : cleaned)
    }

    /// Première page : la confirmation du QR code, ou l'accueil quand l'appareil est déjà connecté.
    var startURL: URL? {
        URL(string: code.map { "http://\(server)/connexion?code=\($0)" } ?? "http://\(server)/")
    }
}
