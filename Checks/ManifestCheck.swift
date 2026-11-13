import CryptoKit
import Foundation

// The fixture runs on macOS before the iPhone target is built.
struct PrivateContentError: Error { let code: String }

@main
enum ManifestCheck {
    enum Failure: Error { case unexpectedResult }

    static func main() throws {
        let id = UUID(), row = UUID()
        let content = Data("Example file".utf8)
        let key = SymmetricKey(size: .bits256)
        let rawKey = key.withUnsafeBytes { Data($0) }
        let expectedHash = Data(SHA256.hash(data: content))

        func package(version: Int, hash: Data) throws -> Data {
            let payload: [String: Any] = [
                "project": ["id": id.uuidString,
                            "rules": [["id": row.uuidString, "relativePath": "Documents/note.txt",
                                       "replacementData": content]]],
                "replacementDigests": [row.uuidString: hash]
            ]
            let bytes = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
            let aad = Data("3105PATCH/v\(version)/payload/\(id.uuidString)".utf8)
            let box = try AES.GCM.seal(bytes, using: key, authenticating: aad)
            guard let encrypted = box.combined else { throw Failure.unexpectedResult }
            let envelope: [String: Any] = ["schemaVersion": version, "packageID": id.uuidString,
                                           "keyFingerprint": Data(SHA256.hash(data: rawKey)),
                                           "encryptedPayload": encrypted]
            return Data("3105PATCH\0".utf8) + (try PropertyListSerialization.data(fromPropertyList: envelope, format: .binary, options: 0))
        }

        for version in [1, 2, 3, 9] {
            let encoded = try package(version: version, hash: expectedHash)
            let files = try CatalogManifest.files(in: encoded, key: rawKey, packageID: id.uuidString.lowercased())
            guard files.count == 1, files[0].id == row, files[0].name == "note.txt",
                  files[0].size == content.count else { throw Failure.unexpectedResult }
        }

        let corrupt = try package(version: 3, hash: Data(repeating: 0, count: 32))
        do {
            _ = try CatalogManifest.files(in: corrupt, key: rawKey, packageID: id.uuidString)
            throw Failure.unexpectedResult
        } catch let e as PrivateContentError {
            guard e.code == "integrity" else { throw Failure.unexpectedResult }
        }
        print("Catalog manifest checks passed")
    }
}
