import Foundation

enum GitHubIntegrationError: LocalizedError, Equatable {
    case emptyRepository
    case gitNotFound
    case workDirMissing
    case commandFailed(command: String, message: String)

    var errorDescription: String? {
        switch self {
        case .emptyRepository:
            return "No GitHub repository configured."
        case .gitNotFound:
            return "git was not found. Install Xcode Command Line Tools or add git to your PATH."
        case .workDirMissing:
            return "Working directory does not exist."
        case .commandFailed(_, let message):
            return message
        }
    }
}

/// Runs `git` to clone or update a repository used as an agent workspace.
enum GitHubIntegration {
    private static func gitExecutablePath() -> String {
        let candidates = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/git"
    }

    /// Ensures `destinationPath` contains the repo on `branch`, cloning if needed.
    static func ensureClone(repoInput: String, branch: String, destinationPath: String) async throws {
        let trimmedRepo = repoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRepo.isEmpty else { throw GitHubIntegrationError.emptyRepository }

        let url = WorkspaceResolver.cloneURL(from: trimmedRepo)
        let git = gitExecutablePath()
        guard FileManager.default.isExecutableFile(atPath: git) else {
            throw GitHubIntegrationError.gitNotFound
        }

        let fm = FileManager.default
        let branchName = branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "main" : branch

        let gitDir = (destinationPath as NSString).appendingPathComponent(".git")
        if fm.fileExists(atPath: gitDir) {
            try await runGit(
                git: git,
                arguments: ["-C", destinationPath, "fetch", "--quiet", "origin"],
                description: "git fetch"
            )
            do {
                try await runGit(
                    git: git,
                    arguments: ["-C", destinationPath, "checkout", "-q", branchName],
                    description: "git checkout"
                )
            } catch {
                try await runGit(
                    git: git,
                    arguments: ["-C", destinationPath, "checkout", "-q", "-B", branchName, "origin/\(branchName)"],
                    description: "git checkout tracking branch"
                )
            }
            return
        }

        let parent = (destinationPath as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
        if fm.fileExists(atPath: destinationPath) {
            try fm.removeItem(atPath: destinationPath)
        }

        do {
            try await runGit(
                git: git,
                arguments: ["clone", "--depth", "1", "--branch", branchName, url, destinationPath],
                description: "git clone"
            )
        } catch {
            try await runGit(
                git: git,
                arguments: ["clone", "--depth", "1", url, destinationPath],
                description: "git clone default branch"
            )
            try await runGit(
                git: git,
                arguments: ["-C", destinationPath, "checkout", "-q", branchName],
                description: "git checkout branch"
            )
        }
    }

    private static func runGit(git: String, arguments: [String], description: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: git)
                process.arguments = arguments
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard process.terminationStatus == 0 else {
                        let msg = errText.isEmpty ? "\(description) failed (exit \(process.terminationStatus))." : errText
                        continuation.resume(throwing: GitHubIntegrationError.commandFailed(command: description, message: msg))
                        return
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: GitHubIntegrationError.commandFailed(
                        command: description,
                        message: error.localizedDescription
                    ))
                }
            }
        }
    }
}
