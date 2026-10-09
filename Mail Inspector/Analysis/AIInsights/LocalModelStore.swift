//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// On-disk inventory for on-device MLX models — where they live, whether they're installed, and
/// how much room is left for new ones. Downloading itself is `LocalModelDownloader`'s job; this
/// type only knows about the filesystem, so `LocalModelSuitability`'s disk-space check and
/// `AIEngineFactory`'s "is this model ready to use" check can both ask it cheaply, without
/// touching the network.
@MainActor
final class LocalModelStore {
    static let shared = LocalModelStore()

    private let fileManager = FileManager.default

    private lazy var modelsRootDirectory: URL = {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Mail Inspector/Models", isDirectory: true)
    }()

    func installDirectory(for descriptor: LocalModelDescriptor) -> URL {
        modelsRootDirectory.appendingPathComponent(descriptor.key, isDirectory: true)
    }

    private func receiptURL(for descriptor: LocalModelDescriptor) -> URL {
        installDirectory(for: descriptor).appendingPathComponent(".mailinspector-model.json")
    }

    /// Whether this exact pinned revision is already downloaded and installed. A stale
    /// installation at a different revision (which can't happen today, since revisions are
    /// hardcoded in `LocalModelCatalogue`, but would if a model entry's pin ever moves) reports
    /// `false` rather than silently serving old weights.
    func isInstalled(_ descriptor: LocalModelDescriptor) -> Bool {
        guard let data = try? Data(contentsOf: receiptURL(for: descriptor)),
              let receipt = try? JSONDecoder().decode(InstallReceipt.self, from: data) else {
            return false
        }
        return receipt.revision == descriptor.revision
    }

    /// Free space on the volume models are installed to, or `nil` if it can't be determined
    /// (treated as "don't block the download" by callers, since this is just a courtesy check).
    func availableCapacityBytes() -> Int64? {
        let values = try? modelsRootDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let capacity = values?.volumeAvailableCapacityForImportantUsage else { return nil }
        return capacity
    }

    /// Removes an installed model from disk, freeing its space. Safe to call even if the model
    /// isn't installed.
    func delete(_ descriptor: LocalModelDescriptor) throws {
        let directory = installDirectory(for: descriptor)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    /// Writes the install receipt once every file for this model has finished downloading. Only
    /// `LocalModelDownloader` calls this — never called on a partial download, so a receipt
    /// existing is itself the atomicity guarantee `isInstalled(_:)` relies on.
    func markInstalled(_ descriptor: LocalModelDescriptor) throws {
        let directory = installDirectory(for: descriptor)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let receipt = InstallReceipt(revision: descriptor.revision)
        let data = try JSONEncoder().encode(receipt)
        try data.write(to: receiptURL(for: descriptor), options: .atomic)
    }

    private struct InstallReceipt: Codable {
        let revision: String
    }
}
