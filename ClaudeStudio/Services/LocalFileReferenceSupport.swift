import Foundation
import AppKit

enum LocalFileReferenceResolution: Equatable {
    case workspaceFile(URL)
    case externalFile(URL)
    case directory(URL)
    case invalid
}

enum LocalFileReferenceSupport {
    static func normalize(rawReference: String) -> URL? {
        let trimmed = rawReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidateURL: URL?
        if trimmed.lowercased().hasPrefix("file://") {
            candidateURL = URL(string: trimmed)
        } else if trimmed.hasPrefix("/") {
            candidateURL = URL(fileURLWithPath: trimmed)
        } else {
            candidateURL = nil
        }

        guard let candidateURL, candidateURL.isFileURL else { return nil }
        return candidateURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func resolve(rawReference: String, workspaceRoot: String?) -> LocalFileReferenceResolution {
        guard let normalizedURL = normalize(rawReference: rawReference) else {
            return .invalid
        }
        return resolve(url: normalizedURL, workspaceRoot: workspaceRoot)
    }

    static func resolve(url: URL, workspaceRoot: String?) -> LocalFileReferenceResolution {
        let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: normalizedURL.path, isDirectory: &isDirectory) else {
            return .invalid
        }

        if isDirectory.boolValue {
            return .directory(normalizedURL)
        }

        if let workspaceRootURL = canonicalWorkspaceRootURL(from: workspaceRoot),
           isDescendant(normalizedURL, of: workspaceRootURL) {
            return .workspaceFile(normalizedURL)
        }

        return .externalFile(normalizedURL)
    }

    static func displayPath(for rawReference: String, workspaceRoot: String?) -> String {
        guard let normalizedURL = normalize(rawReference: rawReference) else {
            return (rawReference as NSString).lastPathComponent
        }
        return displayPath(for: normalizedURL, workspaceRoot: workspaceRoot)
    }

    static func displayPath(for url: URL, workspaceRoot: String?) -> String {
        let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        if let workspaceRootURL = canonicalWorkspaceRootURL(from: workspaceRoot),
           isDescendant(normalizedURL, of: workspaceRootURL) {
            let relativePath = String(normalizedURL.path.dropFirst(workspaceRootURL.path.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !relativePath.isEmpty {
                return relativePath
            }
        }

        return normalizedURL.lastPathComponent.isEmpty ? normalizedURL.path : normalizedURL.lastPathComponent
    }

    static func localReferenceString(from url: URL) -> String? {
        if url.isFileURL {
            return url.absoluteString
        }
        if url.scheme == nil, url.path.hasPrefix("/") {
            return url.path
        }
        return nil
    }

    @MainActor
    static func open(rawReference: String, workspaceRoot: String?, windowState: WindowState) {
        switch resolve(rawReference: rawReference, workspaceRoot: workspaceRoot) {
        case .workspaceFile(let url):
            windowState.openInspectorFile(at: url)
        case .externalFile(let url):
            NSWorkspace.shared.open(url)
        case .directory(let url):
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
        case .invalid:
            Log.chat.warning("Ignoring invalid local file reference: \(rawReference, privacy: .public)")
        }
    }

    @MainActor
    static func open(url: URL, workspaceRoot: String?, windowState: WindowState) {
        switch resolve(url: url, workspaceRoot: workspaceRoot) {
        case .workspaceFile(let resolvedURL):
            windowState.openInspectorFile(at: resolvedURL)
        case .externalFile(let resolvedURL):
            NSWorkspace.shared.open(resolvedURL)
        case .directory(let resolvedURL):
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: resolvedURL.path)
        case .invalid:
            Log.chat.warning("Ignoring invalid local file URL: \(url.path, privacy: .public)")
        }
    }

    private static func canonicalWorkspaceRootURL(from workspaceRoot: String?) -> URL? {
        guard let workspaceRoot else { return nil }
        let trimmed = workspaceRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func isDescendant(_ url: URL, of rootURL: URL) -> Bool {
        let filePath = url.path
        let rootPath = rootURL.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }
}
