import SwiftUI
import UIKit
import Security

private final class LicenseTransport: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class LicenseSession: ObservableObject {
    @Published private(set) var needsUpdate = false
    @Published private(set) var maintenance = false
    @Published private(set) var allowed = false
    @Published private(set) var busy = false
    @Published private(set) var message = ""
    private static let item: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "VintageLite.activation",
        kSecAttrAccount as String: "license"
    ]
    @Published private(set) var hasSavedKey = false
    @Published private(set) var expiresAt: Date?
    private(set) var activeKey = ""

    init() {
        var query = Self.item
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty {
            activeKey = key
            hasSavedKey = true
        }
    }

    private func remember(_ key: String) throws {
        if hasSavedKey && activeKey == key { return }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        var status = SecItemUpdate(Self.item as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = Self.item.merging(attributes) { _, value in value }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw LicenseFailure("Не удалось сохранить ключ на iPhone.") }
        hasSavedKey = true
    }
    private func deviceIdentifier() throws -> String {
        var item = Self.item
        item[kSecAttrAccount as String] = "device-id"
        var query = item
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
           let value = String(data: data, encoding: .utf8), UUID(uuidString: value) != nil {
            return value
        }
        guard status == errSecItemNotFound, let identifier = UIDevice.current.identifierForVendor else {
            throw LicenseFailure("Не удалось прочитать ID этого устройства.")
        }
        let value = identifier.uuidString
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw LicenseFailure("Не удалось сохранить ID этого устройства.")
        }
        return value
    }

    func forgetKey() {
        let status = SecItemDelete(Self.item as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            message = "Не удалось сбросить сохранённый ключ."
            return
        }
        suspend()
        activeKey = ""
        hasSavedKey = false
        expiresAt = nil
        message = ""
        maintenance = false
        needsUpdate = false
    }

    private var generation = UUID()
    private var timer: Task<Void, Never>?
    private let client = URLSession(configuration: .ephemeral, delegate: LicenseTransport(), delegateQueue: nil)

    func suspend() {
        generation = UUID()
        timer?.cancel()
        busy = false
        allowed = false
    }

    func resume() async {
        guard !busy, !allowed else { return }
        if !activeKey.isEmpty {
            _ = await verify(activeKey)
        } else {
            guard var components = URLComponents(url: VintageRelease.server.appendingPathComponent("api/status"),
                                                 resolvingAgainstBaseURL: false) else { return }
            components.queryItems = [
                URLQueryItem(name: "app_version", value: VintageRelease.version),
                URLQueryItem(name: "app_build", value: VintageRelease.build)
            ]
            guard let url = components.url else { return }
            let attempt = generation
            busy = true
            defer { if generation == attempt { busy = false } }
            struct Status: Decodable {
                let maintenance: Bool
                let update_required: Bool?
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            guard let (data, response) = try? await client.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200, generation == attempt,
                  let status = try? JSONDecoder().decode(Status.self, from: data) else { return }
            maintenance = status.maintenance
            needsUpdate = status.update_required == true
        }
    }

    func contentCredentials() throws -> PrivateContentCredentials {
        guard allowed, !activeKey.isEmpty else { throw PrivateContentError(code: "license_denied") }
        return PrivateContentCredentials(key: activeKey, device: try deviceIdentifier())
    }


    func verify(_ supplied: String) async -> Bool {
        let attempt = UUID()
        generation = attempt
        timer?.cancel()
        busy = true
        message = ""
        let key = supplied.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        defer { if generation == attempt { busy = false } }
        do {
            let device = try deviceIdentifier()
            var request = URLRequest(url: VintageRelease.server.appendingPathComponent("api/check"))
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["key": key, "device": device,
                                                        "app_version": VintageRelease.version,
                                                        "app_build": VintageRelease.build])
            let (data, response) = try await client.data(for: request)
            guard generation == attempt else { return false }
            struct Reply: Decodable {
                let valid: Bool?
                let remaining: Int?
                let error: String?
                let update_required: Bool?
            }
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            if (response as? HTTPURLResponse)?.statusCode == 503, reply.error == "maintenance" {
                allowed = false
                maintenance = true
                needsUpdate = reply.update_required == true
                return false
            }
            maintenance = false
            needsUpdate = false
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  reply.valid == true, let seconds = reply.remaining, seconds > 0 else {
                let reasons = ["expired": "Срок ключа истёк.", "full": "Все места на ключе заняты.",
                               "blocked": "Это устройство отключено.", "invalid": "Ключ неверный или отозван."]
                if (response as? HTTPURLResponse)?.statusCode == 403,
                   reasons[reply.error ?? ""] != nil {
                    SecItemDelete(Self.item as CFDictionary)
                    hasSavedKey = false
                    activeKey = ""
                }
                throw LicenseFailure(reasons[reply.error ?? ""] ?? "Сервер не подтвердил доступ.")
            }
            try remember(key)
            activeKey = key
            expiresAt = Date().addingTimeInterval(TimeInterval(seconds))
            allowed = true
            timer = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(min(seconds, 30)) * 1_000_000_000) }
                catch { return }
                guard let self, self.generation == attempt else { return }
                if seconds <= 30 { self.allowed = false }
                // A separate task lets verify cancel the previous timer without cancelling the request.
                Task { _ = await self.verify(key) }
            }
            return true
        } catch {
            guard generation == attempt else { return false }
            allowed = false
            message = (error as? LicenseFailure)?.text ?? "Не удалось проверить ключ. Проверь подключение."
            return false
        }
    }

    private struct LicenseFailure: Error {
        let text: String
        init(_ text: String) { self.text = text }
    }
}

enum VintageRelease {
    static let server = URL(string: "https://vintage-lite-license.vintage-lite-keys.workers.dev")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "2.2.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "11"
    }
}
