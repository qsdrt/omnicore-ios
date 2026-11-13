import BackgroundTasks
import Foundation
import Network
import Photos
import Security
import UIKit

/// Sauvegarde automatique des photos de l'iPhone vers OmniCore, comme Apple/Google Photos mais chez soi.
/// Vignette d'abord, puis l'original (HEIC converti en JPEG), trois photos à la fois ; reprend là où elle s'est arrêtée.
/// iOS décide quand l'app peut travailler en arrière-plan : la sauvegarde avance aussi à chaque ouverture de l'app.
final class PhotoBackup {
    static let shared = PhotoBackup()
    static let taskIdentifier = "com.omnicore.ios.photobackup"

    private let defaults = UserDefaults.standard
    private let queue = DispatchQueue(label: "omnicore.photobackup")
    private var running = false
    private let monitor = NWPathMonitor()
    private var expensiveNetwork = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in self?.expensiveNetwork = path.isExpensive }
        monitor.start(queue: queue)
    }

    // MARK: Réglages

    var enabled: Bool { defaults.bool(forKey: "backup.enabled") }
    private var wifiOnly: Bool { defaults.object(forKey: "backup.wifiOnly") as? Bool ?? true }
    private var cursor: Date {
        get { Date(timeIntervalSince1970: defaults.double(forKey: "backup.cursor")) }
        set { defaults.set(newValue.timeIntervalSince1970, forKey: "backup.cursor") }
    }
    private func count(_ key: String) -> Int { defaults.integer(forKey: key) }
    private func bump(_ key: String) { defaults.set(defaults.integer(forKey: key) + 1, forKey: key) }

    /// État lu par la page Photos (même format que l'app Android).
    func statusJSON() -> String {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let object: [String: Any] = [
            "enabled": enabled,
            "wifiOnly": wifiOnly,
            "permission": status == .authorized || status == .limited,
            "uploaded": count("backup.uploaded"),
            "skipped": count("backup.skipped"),
            "pending": count("backup.pending"),
            "running": running,
            "lastRun": defaults.double(forKey: "backup.lastRun"),
            "lastError": defaults.string(forKey: "backup.lastError") ?? NSNull(),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    func enable(token: String, includeExisting: Bool, wifiOnly: Bool) {
        guard token.range(of: "^[A-Za-z0-9_-]{40,64}$", options: .regularExpression) != nil else { return }
        let firstTime = Keychain.read() == nil
        Keychain.save(token)
        defaults.set(true, forKey: "backup.enabled")
        defaults.set(wifiOnly, forKey: "backup.wifiOnly")
        defaults.removeObject(forKey: "backup.lastError")
        if firstTime { cursor = includeExisting ? Date(timeIntervalSince1970: 0) : Date() }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            if status == .authorized || status == .limited {
                self.runSoon()
                self.scheduleBackground()
            } else {
                self.defaults.set("Autorise l’accès aux photos dans Réglages › OmniCore › Photos (« Toutes les photos »).", forKey: "backup.lastError")
            }
        }
    }

    func disable() {
        defaults.set(false, forKey: "backup.enabled")
        Keychain.delete()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    }

    func runSoon() {
        Task { await run() }
    }

    // MARK: Arrière-plan

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            let work = Task { await self.run(); task.setTaskCompleted(success: true) }
            task.expirationHandler = { work.cancel() }
            self.scheduleBackground()
        }
    }

    func scheduleBackground() {
        guard enabled else { return }
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: Envoi

    private enum Outcome { case sent, duplicate, skipped, retry, unauthorized }

    private func run() async {
        guard enabled, !running, let token = Keychain.read(), let server = defaults.string(forKey: "omnicore.server") else { return }
        if wifiOnly && expensiveNetwork { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }
        running = true
        defer {
            running = false
            defaults.set(Date().timeIntervalSince1970 * 1000, forKey: "backup.lastRun")
        }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate > %@", cursor as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        defaults.set(assets.count, forKey: "backup.pending")
        let base = "http://\(server)"
        var index = 0
        while index < assets.count, !Task.isCancelled {
            let group = Array(assets[index..<min(index + 3, assets.count)])
            let outcomes = await withTaskGroup(of: (Int, Outcome).self) { tasks -> [Outcome] in
                for (position, asset) in group.enumerated() { tasks.addTask { (position, await self.upload(asset, base: base, token: token)) } }
                var collected = Array(repeating: Outcome.retry, count: group.count)
                for await (position, outcome) in tasks { collected[position] = outcome }
                return collected
            }
            // Le curseur n'avance que jusqu'à la dernière photo réussie sans trou : rien n'est sauté.
            for (position, outcome) in outcomes.enumerated() {
                switch outcome {
                case .sent: bump("backup.uploaded")
                case .skipped: bump("backup.skipped")
                case .duplicate: break
                case .unauthorized:
                    defaults.set("Le serveur a refusé ce téléphone : réactive la sauvegarde depuis la page Photos.", forKey: "backup.lastError")
                    disable()
                    return
                case .retry:
                    return
                }
                if let date = group[position].creationDate { cursor = date }
                defaults.set(max(0, count("backup.pending") - 1), forKey: "backup.pending")
            }
            index += group.count
        }
    }

    private func upload(_ asset: PHAsset, base: String, token: String) async -> Outcome {
        guard let original = await originalJPEG(asset), let thumb = await thumbnail(asset) else { return .skipped }
        let clientId = UUID().uuidString.lowercased()
        let name = (PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "photo.jpg")
            .replacingOccurrences(of: "\\.(heic|heif)$", with: ".jpg", options: [.regularExpression, .caseInsensitive])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let headers = [
            "x-client-id": clientId,
            "x-name": name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "photo.jpg",
            "x-size": String(original.count),
            "x-modified": String(Int((asset.modificationDate ?? asset.creationDate ?? Date()).timeIntervalSince1970 * 1000)),
            "x-taken-at": asset.creationDate.map { formatter.string(from: $0) } ?? "",
        ]
        let first = await post("\(base)/api/photos/import/thumb", token: token, type: "image/jpeg", headers: headers, body: thumb)
        switch first.status {
        case 401, 403: return .unauthorized
        case 200...299 where first.duplicate: return .duplicate
        case 200...299: break
        case 429, 500...599, 0: return .retry
        default: return .skipped
        }
        for attempt in 1...5 {
            let second = await post("\(base)/api/photos/import/original", token: token, type: "application/octet-stream", headers: ["x-client-id": clientId], body: original)
            switch second.status {
            case 200...299: return second.duplicate ? .duplicate : .sent
            case 401, 403: return .unauthorized
            case 400...499 where second.status != 429: return .skipped
            default: try? await Task.sleep(nanoseconds: UInt64(attempt) * 800_000_000)
            }
        }
        return .retry
    }

    private func post(_ address: String, token: String, type: String, headers: [String: String], body: Data) async -> (status: Int, duplicate: Bool) {
        guard let url = URL(string: address) else { return (0, false) }
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(type, forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: body)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            return (status, json?["duplicate"] as? Bool ?? false)
        } catch {
            return (0, false)
        }
    }

    /// Original de la photo ; le HEIC de l'iPhone est converti en JPEG (format lu partout, y compris par OmniCore).
    private func originalJPEG(_ asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
                guard let data else { continuation.resume(returning: nil); return }
                let isJPEG = (uti ?? "").lowercased().contains("jpeg")
                continuation.resume(returning: isJPEG ? data : UIImage(data: data)?.jpegData(compressionQuality: 0.92))
            }
        }
    }

    private func thumbnail(_ asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 360, height: 360), contentMode: .aspectFit, options: options) { image, _ in
                continuation.resume(returning: image?.jpegData(compressionQuality: 0.72))
            }
        }
    }
}

/// Jeton de sauvegarde gardé dans le trousseau iOS (jamais en clair dans les réglages).
enum Keychain {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "omnicore.photobackup"]

    static func save(_ token: String) {
        delete()
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func read() -> String? {
        var item = query
        item[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
