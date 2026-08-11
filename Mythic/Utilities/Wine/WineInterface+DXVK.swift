//
//  WineInterface+DXVK.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 11/11/2025.
//

// Copyright © 2023-2026 vapidinfinity

import Foundation

private struct DXVKPayload {
    let x64Directory: URL
    let x32Directory: URL
}

private struct DXVKIncompletePayloadError: LocalizedError {
    var errorDescription: String? = "Unable to enable DXVK: neither the legacy Engine/DXVK/x64 and x32 payload nor the modern Engine/wine/lib/dxvk/x86_64-windows and i386-windows payload is complete."
}

private struct DXVKIncompleteBuiltInPayloadError: LocalizedError {
    var errorDescription: String? = "Unable to disable DXVK: the engine's built-in d3d10core.dll and d3d11.dll payload is incomplete for one or both architectures."
}

extension Wine {
    final class DXVK {
        private static let legacyPayload = DXVKPayload(
            x64Directory: Engine.directory.appending(path: "DXVK/x64"),
            x32Directory: Engine.directory.appending(path: "DXVK/x32")
        )

        private static let modernPayload = DXVKPayload(
            x64Directory: Engine.directory.appending(path: "wine/lib/dxvk/x86_64-windows"),
            x32Directory: Engine.directory.appending(path: "wine/lib/dxvk/i386-windows")
        )

        private static let builtInPayload = DXVKPayload(
            x64Directory: Engine.directory.appending(path: "wine/lib/wine/x86_64-windows"),
            x32Directory: Engine.directory.appending(path: "wine/lib/wine/i386-windows")
        )

        private static let requiredDLLs: [String] = ["d3d10core.dll", "d3d11.dll"]

        /// CX26 selects its engine-owned DXVK runtime when these minimum dependencies are available.
        static var hasModernEmbeddedPayload: Bool {
            let hasD3D11 = FileManager.default.fileExists(
                atPath: modernPayload.x64Directory.appending(path: "d3d11.dll").path
            )
            let moltenVKLocations: [URL] = [
                Engine.directory.appending(path: "wine/lib/wine/x86_64-unix/libMoltenVK.dylib"),
                Engine.directory.appending(path: "wine/lib64/libMoltenVK.dylib")
            ]

            return hasD3D11 && moltenVKLocations.contains {
                FileManager.default.fileExists(atPath: $0.path)
            }
        }

        /// Replaces the Engine’s DirectX DLLs in the specified Wine container with their DXVK equivalents.
        static func install(toContainerAtURL containerURL: URL) async throws {
            let payload = try resolvePayload()
            try Wine.killAll(at: containerURL)

            // remove existing d3d dlls
            // x64
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/system32/d3d10core.dll"))
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/system32/d3d11.dll"))

            // x32
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/syswow64/d3d10core.dll"))
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/syswow64/d3d11.dll"))

            // copy d3d dlls from dxvk
            // x64
            try FileManager.default.forceCopyItem(
                at: payload.x64Directory.appending(path: "d3d10core.dll"),
                to: containerURL.appending(path: "drive_c/windows/system32")
            )
            try FileManager.default.forceCopyItem(
                at: payload.x64Directory.appending(path: "d3d11.dll"),
                to: containerURL.appending(path: "drive_c/windows/system32")
            )

            // x32
            try FileManager.default.forceCopyItem(
                at: payload.x32Directory.appending(path: "d3d10core.dll"),
                to: containerURL.appending(path: "drive_c/windows/syswow64")
            )
            try FileManager.default.forceCopyItem(
                at: payload.x32Directory.appending(path: "d3d11.dll"),
                to: containerURL.appending(path: "drive_c/windows/syswow64")
            )
        }

        /// Restores the Engine's built-in DirectX DLLs in the specified Wine container.
        static func uninstall(fromContainerAtURL containerURL: URL) async throws {
            let payload = try resolveBuiltInPayload()
            try Wine.killAll(at: containerURL)

            // remove existing d3d dlls
            // x64
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/system32/d3d10core.dll"))
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/system32/d3d11.dll"))

            // x32
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/syswow64/d3d10core.dll"))
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/syswow64/d3d11.dll"))

            // copy built-in d3d dlls from the Engine
            // x64
            try FileManager.default.forceCopyItem(
                at: payload.x64Directory.appending(path: "d3d10core.dll"),
                to: containerURL.appending(path: "drive_c/windows/system32")
            )
            try FileManager.default.forceCopyItem(
                at: payload.x64Directory.appending(path: "d3d11.dll"),
                to: containerURL.appending(path: "drive_c/windows/system32")
            )

            // x32
            try FileManager.default.forceCopyItem(
                at: payload.x32Directory.appending(path: "d3d10core.dll"),
                to: containerURL.appending(path: "drive_c/windows/syswow64")
            )
            try FileManager.default.forceCopyItem(
                at: payload.x32Directory.appending(path: "d3d11.dll"),
                to: containerURL.appending(path: "drive_c/windows/syswow64")
            )
        }

        private static func resolvePayload() throws -> DXVKPayload {
            if isComplete(legacyPayload) {
                return legacyPayload
            }

            if isComplete(modernPayload) {
                return modernPayload
            }

            throw DXVKIncompletePayloadError()
        }

        private static func resolveBuiltInPayload() throws -> DXVKPayload {
            guard isComplete(builtInPayload) else {
                throw DXVKIncompleteBuiltInPayloadError()
            }

            return builtInPayload
        }

        private static func isComplete(_ payload: DXVKPayload) -> Bool {
            [payload.x64Directory, payload.x32Directory].allSatisfy { directory in
                requiredDLLs.allSatisfy { dll in
                    FileManager.default.fileExists(atPath: directory.appending(path: dll).path)
                }
            }
        }
    }
}
