//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

nonisolated enum LocalModelDownloadEvent: Sendable, Equatable {
    case progress(completedBytes: Int64, totalBytes: Int64)
    case installed
}

nonisolated enum LocalModelDownloadError: Error {
    case invalidRepository
    case serverError
}

/// Downloads an on-device MLX model's weights straight from Hugging Face, with no third-party
/// downloader dependency and no Hugging Face token — both model repositories this app offers are
/// public, same as the proven pattern at `~/Projects/grafida/grafida-ipad`
/// (`LocalModelDownloading.swift`). Deliberately bypasses `AITransportPolicy` and the
/// Settings-driven endpoint machinery entirely: this is a fixed, pinned, one-time download of
/// model weights, not a per-message request to a user-configured AI provider.
///
/// **v1 simplification, deliberate**: downloads each file whole (no byte-range resume), so
/// progress only advances per-file, not smoothly within the large `.safetensors` weight file —
/// acceptable for a handful of files per model. Unlike the proven Grafida downloader, there's no
/// chunked range-resume here; a failed download just restarts from scratch next time, which this
/// app surfaces as a plain retry in Settings.
@MainActor
final class LocalModelDownloader {
    static let shared = LocalModelDownloader()

    private struct TreeEntry: Decodable {
        let type: String
        let path: String
        let size: Int64?
    }

    /// Lists this model's files from Hugging Face's tree API for the pinned revision, then
    /// downloads each one into a staging directory before atomically installing it — so a
    /// failed or cancelled download never leaves a half-written model that
    /// `LocalModelStore.isInstalled` would mistake for a good one.
    func download(_ descriptor: LocalModelDescriptor) -> AsyncThrowingStream<LocalModelDownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let stagingDirectory = Self.stagingDirectory(for: descriptor)
                do {
                    let entries = try await fetchFileList(for: descriptor)
                    let totalBytes = entries.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
                    try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

                    var completedBytes: Int64 = 0
                    for entry in entries {
                        try Task.checkCancellation()
                        let destination = stagingDirectory.appendingPathComponent(entry.path)
                        try await downloadFile(descriptor: descriptor, path: entry.path, to: destination)
                        completedBytes += entry.size ?? 0
                        continuation.yield(.progress(completedBytes: completedBytes, totalBytes: totalBytes))
                    }

                    try install(from: stagingDirectory, descriptor: descriptor)
                    try? FileManager.default.removeItem(at: stagingDirectory)
                    continuation.yield(.installed)
                    continuation.finish()
                } catch {
                    try? FileManager.default.removeItem(at: stagingDirectory)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func fetchFileList(for descriptor: LocalModelDescriptor) async throws -> [TreeEntry] {
        guard let url = URL(string: "https://huggingface.co/api/models/\(descriptor.repository)/tree/\(descriptor.revision)?recursive=true") else {
            throw LocalModelDownloadError.invalidRepository
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LocalModelDownloadError.serverError
        }
        let entries = try JSONDecoder().decode([TreeEntry].self, from: data)
        return entries.filter { $0.type == "file" }
    }

    private func downloadFile(descriptor: LocalModelDescriptor, path: String, to destination: URL) async throws {
        guard let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://huggingface.co/\(descriptor.repository)/resolve/\(descriptor.revision)/\(encodedPath)") else {
            throw LocalModelDownloadError.invalidRepository
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LocalModelDownloadError.serverError
        }
        _ = try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }

    private func install(from stagingDirectory: URL, descriptor: LocalModelDescriptor) throws {
        let finalDirectory = LocalModelStore.shared.installDirectory(for: descriptor)
        if FileManager.default.fileExists(atPath: finalDirectory.path) {
            try FileManager.default.removeItem(at: finalDirectory)
        }
        try FileManager.default.createDirectory(at: finalDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: stagingDirectory, to: finalDirectory)
        try LocalModelStore.shared.markInstalled(descriptor)
    }

    private static func stagingDirectory(for descriptor: LocalModelDescriptor) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mailinspector-model-staging-\(descriptor.key)-\(UUID().uuidString)", isDirectory: true)
    }
}
