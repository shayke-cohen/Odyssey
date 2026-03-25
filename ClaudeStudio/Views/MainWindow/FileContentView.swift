import SwiftUI
import AppKit

enum FileViewMode: String, CaseIterable, Identifiable {
    case preview = "Preview"
    case source = "Source"
    case diff = "Diff"

    var id: String { rawValue }
}

struct FileContentView: View {
    let node: FileNode
    let rootURL: URL
    let onBack: () -> Void

    @State private var viewMode: FileViewMode = .source
    @State private var fileContent: String?
    @State private var diffContent: String?
    @State private var diffSummary: (added: Int, removed: Int) = (0, 0)
    @State private var isBinary = false
    @State private var isLoading = true

    private var isMarkdown: Bool {
        FileSystemService.isMarkdownFile(node.name)
    }

    private var hasDiff: Bool {
        node.gitStatus != nil
    }

    private var availableModes: [FileViewMode] {
        var modes: [FileViewMode] = []
        if isMarkdown { modes.append(.preview) }
        modes.append(.source)
        if hasDiff { modes.append(.diff) }
        return modes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()
            metadataBar
            if availableModes.count > 1 {
                modePicker
                Divider()
            }
            contentArea
            Divider()
            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadContent() }
        .onChange(of: node.id) { _, _ in Task { await loadContent() } }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Back to file tree")
            .xrayId("inspector.fileContent.backButton")
            .accessibilityLabel("Back to file tree")

            Image(systemName: FileSystemService.fileIcon(for: node.fileExtension))
                .foregroundStyle(.secondary)
                .font(.caption)

            Text(node.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
                .xrayId("inspector.fileContent.fileName")

            Spacer()

            if let status = node.gitStatus {
                gitBadge(status)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Metadata

    private var metadataBar: some View {
        HStack(spacing: 6) {
            if viewMode == .diff, hasDiff {
                Text(node.gitStatus?.label ?? "Changed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if diffSummary.added > 0 {
                    Text("+\(diffSummary.added)")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                if diffSummary.removed > 0 {
                    Text("-\(diffSummary.removed)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            } else {
                Text(FileSystemService.formatFileSize(node.size))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                Text(node.fileExtension.isEmpty ? "file" : node.fileExtension)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let date = node.modifiedDate {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .xrayId("inspector.fileContent.metadataBar")
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("View Mode", selection: $viewMode) {
            ForEach(availableModes) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .xrayId("inspector.fileContent.modePicker")
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .xrayId("inspector.fileContent.loading")
        } else if isBinary {
            binaryPlaceholder
        } else {
            switch viewMode {
            case .preview:
                markdownPreview
            case .source:
                sourceView
            case .diff:
                diffView
            }
        }
    }

    @ViewBuilder
    private var markdownPreview: some View {
        if let content = fileContent {
            ScrollView {
                MarkdownContent(text: content)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .xrayId("inspector.fileContent.markdownPreview")
        } else {
            emptyContentPlaceholder
        }
    }

    @ViewBuilder
    private var sourceView: some View {
        if let content = fileContent {
            let lang = FileSystemService.languageForExtension(node.fileExtension)
            HighlightedCodeView(code: content, language: lang, showLineNumbers: true)
                .frame(maxWidth: .infinity, minHeight: 80, maxHeight: .infinity)
                .xrayId("inspector.fileContent.sourceView")
        } else {
            emptyContentPlaceholder
        }
    }

    @ViewBuilder
    private var diffView: some View {
        if let diff = diffContent, !diff.isEmpty {
            DiffTextView(diffText: diff)
                .xrayId("inspector.fileContent.diffView")
        } else if node.gitStatus == .untracked, let content = fileContent {
            DiffTextView(diffText: allAddedDiff(content))
                .xrayId("inspector.fileContent.diffView")
        } else {
            ContentUnavailableView("No Changes", systemImage: "checkmark.circle", description: Text("This file has no uncommitted changes."))
        }
    }

    private var binaryPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Binary File")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(FileSystemService.formatFileSize(node.size))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Open in Default App") {
                NSWorkspace.shared.open(node.url)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .xrayId("inspector.fileContent.openInDefaultAppButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .xrayId("inspector.fileContent.binaryPlaceholder")
    }

    private var emptyContentPlaceholder: some View {
        ContentUnavailableView("Unable to Read", systemImage: "exclamationmark.triangle", description: Text("Could not read file contents."))
            .xrayId("inspector.fileContent.emptyPlaceholder")
    }

    // MARK: - Actions

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                NSWorkspace.shared.open(node.url)
            } label: {
                Label("Open in Editor", systemImage: "pencil.and.outline")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Open in default editor")
            .xrayId("inspector.fileContent.openInEditorButton")

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.url.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.clipboard")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Copy file path to clipboard")
            .xrayId("inspector.fileContent.copyPathButton")

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func loadContent() async {
        isLoading = true

        let nodeURL = node.url
        let relPath = relativePath
        let root = rootURL
        let wantDiff = hasDiff

        let result = await Task.detached { () -> (Bool, String?, String?, Int, Int) in
            let binary = FileSystemService.isBinaryFile(at: nodeURL)
            let content = binary ? nil : FileSystemService.readFileContents(at: nodeURL)
            let diff = wantDiff ? GitService.fullDiff(file: relPath, in: root) : nil
            let summary = wantDiff ? GitService.diffSummary(file: relPath, in: root) : (0, 0)
            return (binary, content, diff, summary.0, summary.1)
        }.value

        isBinary = result.0
        fileContent = result.1
        diffContent = result.2
        diffSummary = (added: result.3, removed: result.4)

        if isMarkdown && !isBinary {
            viewMode = .preview
        } else {
            viewMode = .source
        }

        isLoading = false
    }

    private var relativePath: String {
        let full = node.url.path
        let root = rootURL.path
        if full.hasPrefix(root) {
            return String(full.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return node.name
    }

    private func allAddedDiff(_ content: String) -> String {
        content.components(separatedBy: "\n").map { "+ \($0)" }.joined(separator: "\n")
    }

    @ViewBuilder
    private func gitBadge(_ status: GitFileStatus) -> some View {
        Circle()
            .fill(colorForStatus(status))
            .frame(width: 7, height: 7)
            .help(status.label)
    }

    private func colorForStatus(_ status: GitFileStatus) -> Color {
        switch status {
        case .modified:  return .orange
        case .added:     return .green
        case .deleted:   return .red
        case .renamed:   return .blue
        case .untracked: return .gray
        case .copied:    return .teal
        }
    }
}

// MARK: - Diff Text View

struct DiffTextView: View {
    let diffText: String

    private var lines: [(index: Int, text: String)] {
        diffText.components(separatedBy: "\n").enumerated().map { ($0.offset, $0.element) }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines, id: \.index) { item in
                    DiffLine(text: item.text)
                }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DiffLine: View {
    let text: String

    private var style: DiffLineStyle {
        if text.hasPrefix("+") && !text.hasPrefix("+++") { return .added }
        if text.hasPrefix("-") && !text.hasPrefix("---") { return .removed }
        if text.hasPrefix("@@") { return .hunk }
        if text.hasPrefix("diff ") || text.hasPrefix("index ") || text.hasPrefix("---") || text.hasPrefix("+++") { return .header }
        return .context
    }

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(style.foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 0.5)
            .background(style.background)
    }
}

private enum DiffLineStyle {
    case added, removed, hunk, header, context

    var background: Color {
        switch self {
        case .added:   return Color.green.opacity(0.15)
        case .removed: return Color.red.opacity(0.15)
        case .hunk:    return Color.blue.opacity(0.08)
        case .header:  return .clear
        case .context: return .clear
        }
    }

    var foreground: Color {
        switch self {
        case .added:   return .primary
        case .removed: return .primary
        case .hunk:    return .secondary
        case .header:  return .secondary
        case .context: return .primary
        }
    }
}
