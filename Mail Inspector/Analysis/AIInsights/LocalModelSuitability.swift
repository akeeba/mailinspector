//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation
import Metal

/// Whether an on-device MLX model can be offered on this Mac right now, and if not, why not.
nonisolated enum LocalModelDecision: Equatable {
    case allowed
    case unsupportedHardware
    case insufficientMemory(physicalBytes: Int64, requiredBytes: Int64)
    case insufficientDisk(needsBytes: Int64, availableBytes: Int64)

    /// A human-readable explanation for the Settings UI and `AIEngineFactory`'s unavailable
    /// reasons — `nil` when `.allowed`.
    var unavailableReason: String? {
        let byteFormatter = ByteCountFormatter()
        switch self {
        case .allowed:
            return nil
        case .unsupportedHardware:
            return "Requires a Mac with an Apple Silicon processor."
        case .insufficientMemory(let physicalBytes, let requiredBytes):
            byteFormatter.countStyle = .memory
            return "Needs more unified memory than this Mac has (about \(byteFormatter.string(fromByteCount: requiredBytes)) needed, \(byteFormatter.string(fromByteCount: physicalBytes)) available)."
        case .insufficientDisk(let needsBytes, let availableBytes):
            byteFormatter.countStyle = .file
            return "Needs \(byteFormatter.string(fromByteCount: needsBytes)) of free disk space (\(byteFormatter.string(fromByteCount: availableBytes)) available)."
        }
    }
}

/// Apple-Silicon + unified-memory + free-disk gating for on-device MLX models, mirroring the
/// pattern already proven at `~/Projects/grafida/grafida-ipad` (`LocalModelSuitability.swift`).
/// Deliberately never cached — free disk space changes while the app runs, and everything here
/// is cheap enough to recompute on every call.
nonisolated enum LocalModelSuitability {
    /// Apple's own GPU-family generations below this don't exist on Intel Macs — asking the GPU
    /// directly is a more reliable "is this genuinely Apple Silicon" check than inspecting the
    /// CPU architecture, since it doesn't care which architecture slice of a universal binary
    /// happens to be executing. Same threshold Grafida's own suitability check uses.
    private static let requiredGPUFamily = MTLGPUFamily.apple7

    /// Marketed memory figures (8GB, 16GB, ...) and what `ProcessInfo.physicalMemory` actually
    /// reports differ by roughly this much on real hardware (confirmed in the Grafida project:
    /// an advertised "12GB" iPad reported 11.59GiB). Subtracted from a descriptor's
    /// `memoryGateBytes` before comparing against the real reported figure, so a Mac marketed at
    /// exactly the gate figure isn't incorrectly rejected.
    private static let memoryCarveOutBytes: Int64 = Int64(1.5 * 1_073_741_824)

    /// Headroom kept free beyond the download itself, so installing a model doesn't leave the
    /// user's disk completely full.
    private static let diskHeadroomBytes: Int64 = 1_073_741_824

    @MainActor
    static func decision(for descriptor: LocalModelDescriptor) -> LocalModelDecision {
        guard isAppleSilicon else { return .unsupportedHardware }

        let physicalBytes = Int64(ProcessInfo.processInfo.physicalMemory)
        let requiredBytes = descriptor.memoryGateBytes - memoryCarveOutBytes
        guard physicalBytes >= requiredBytes else {
            return .insufficientMemory(physicalBytes: physicalBytes, requiredBytes: requiredBytes)
        }

        let neededBytes = descriptor.downloadBytes + diskHeadroomBytes
        let availableBytes = LocalModelStore.shared.availableCapacityBytes() ?? .max
        guard availableBytes >= neededBytes else {
            return .insufficientDisk(needsBytes: neededBytes, availableBytes: availableBytes)
        }

        return .allowed
    }

    private static var isAppleSilicon: Bool {
        MTLCreateSystemDefaultDevice()?.supportsFamily(requiredGPUFamily) ?? false
    }
}
