import CryptoKit
import Foundation

struct CatalogFile: Identifiable {
    let id: UUID
    let name: String
    let size: Int
}

// Only filenames and sizes leave the reader. File contents stay in memory.
enum CatalogManifest {
    private struct Envelope: Decodable {
        let schemaVersion: Int
        let packageID: UUID
        let keyFingerprint: Data
        let encryptedPayload: Data
    }

    private struct Contents: Decodable {
        struct Project: Decodable {
            struct File: Decodable {
                let id: UUID
                let relativePath: String
                let replacementData: Data
            }
            let id: UUID
            let rules: [File]
        }
        let project: Project
        let replacementDigests: [String: Data]
    }

    static func files(in package: Data, key: Data, packageID: String) throws -> [CatalogFile] {
        let magic = Data("3105PATCH\0".utf8)
        let invalid = PrivateContentError(code: "integrity")
        guard package.starts(with: magic), package.count <= 8 * 1024 * 1024, key.count == 32 else {
            throw invalid
        }
        let envelope = try PropertyListDecoder().decode(Envelope.self, from: Data(package.dropFirst(magic.count)))
        guard [1, 2, 3, 9].contains(envelope.schemaVersion),
              envelope.packageID == UUID(uuidString: packageID),
              Data(SHA256.hash(data: key)) == envelope.keyFingerprint else { throw invalid }

        let aad = Data("3105PATCH/v\(envelope.schemaVersion)/payload/\(envelope.packageID.uuidString)".utf8)
        var bytes = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.encryptedPayload),
                                     using: SymmetricKey(data: key), authenticating: aad)
        defer { bytes.resetBytes(in: 0..<bytes.count) }
        let manifest = try PropertyListDecoder().decode(Contents.self, from: bytes)
        guard manifest.project.id == envelope.packageID else { throw invalid }
        var seen = Set<UUID>()
        return try manifest.project.rules.map { file in
            guard seen.insert(file.id).inserted,
                  let hash = manifest.replacementDigests[file.id.uuidString],
                  hash == Data(SHA256.hash(data: file.replacementData)),
                  let name = file.relativePath.split(separator: "/").last, !name.isEmpty else { throw invalid }
            return CatalogFile(id: file.id, name: String(name), size: file.replacementData.count)
        }
    }
}
