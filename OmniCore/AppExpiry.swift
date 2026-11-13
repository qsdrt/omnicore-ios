import Foundation

/// Date d'expiration de l'app installée avec un compte Apple gratuit (profil « embedded.mobileprovision »).
/// Apple limite cette signature à 7 jours ; Sideloadly la renouvelle seul tant que le PC est allumé et l'iPhone sur le même Wi-Fi.
enum AppExpiry {
    static func date() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }

    /// Message à afficher quand il reste 2 jours ou moins ; rien sinon.
    static func warning(now: Date = Date()) -> String? {
        guard let expiry = date() else { return nil }
        let hours = expiry.timeIntervalSince(now) / 3600
        guard hours <= 48 else { return nil }
        if hours <= 0 { return "OmniCore doit être renouvelée : allume le PC avec Sideloadly, iPhone sur le même Wi-Fi." }
        let when = hours < 24 ? "dans moins d’un jour" : "dans 2 jours"
        return "OmniCore expire \(when). Laisse le PC allumé (Sideloadly) et l’iPhone sur le Wi-Fi de la maison : elle sera renouvelée toute seule."
    }
}
