import Foundation

nonisolated enum EmailImportError: Error, Sendable, Equatable, LocalizedError {
    case readFailed
    case tooLarge(limit: Int)

    var errorDescription: String? {
        switch self {
        case .readFailed:
            return "The file could not be read."
        case .tooLarge(let limit):
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)
            return "The message exceeds the maximum allowed size of \(formatted)."
        }
    }
}

/// Imports untrusted `.eml` data from disk and hands it to the parser off the main thread.
///
/// Imported messages are treated as untrusted binary input: size is checked before and after
/// reading, and parsing happens on a background task so malformed or very large input never
/// blocks the UI.
nonisolated enum EmailImportCoordinator {
    static func importMessage(
        from url: URL,
        maxMessageSize: Int,
        sourceDescription: String? = nil
    ) async throws -> EmailMessage {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let rawData = try readData(at: url, maxMessageSize: maxMessageSize)
        let data = url.pathExtension.lowercased() == "emlx" ? EMLXUnwrapper.unwrap(rawData) : rawData
        return try await parse(
            data: data,
            sourceDescription: sourceDescription ?? url.lastPathComponent,
            maxMessageSize: maxMessageSize
        )
    }

    static func importMessage(
        data: Data,
        sourceDescription: String,
        maxMessageSize: Int
    ) async throws -> EmailMessage {
        guard data.count <= maxMessageSize else { throw EmailImportError.tooLarge(limit: maxMessageSize) }
        return try await parse(data: data, sourceDescription: sourceDescription, maxMessageSize: maxMessageSize)
    }

    private static func readData(at url: URL, maxMessageSize: Int) throws -> Data {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxMessageSize {
            throw EmailImportError.tooLarge(limit: maxMessageSize)
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw EmailImportError.readFailed
        }
        defer { try? handle.close() }
        // Read one byte beyond the limit so an over-sized file is reliably detected even when
        // its reported file size was unavailable or inaccurate.
        guard let data = try? handle.read(upToCount: maxMessageSize + 1) else {
            throw EmailImportError.readFailed
        }
        if data.count > maxMessageSize {
            throw EmailImportError.tooLarge(limit: maxMessageSize)
        }
        return data
    }

    private static func parse(
        data: Data,
        sourceDescription: String,
        maxMessageSize: Int
    ) async throws -> EmailMessage {
        try await Task.detached(priority: .userInitiated) {
            let parsed = try EmailHeaderParser.parse(data: data, maxMessageSize: maxMessageSize)
            return EmailMessage(parsed: parsed, sourceDescription: sourceDescription)
        }.value
    }
}
