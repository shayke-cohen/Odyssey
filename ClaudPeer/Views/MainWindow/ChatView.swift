import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

struct ChatView: View {
    let conversationId: UUID
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @State private var inputText = ""
    @State private var isProcessing = false
    @State private var lastTokenTime: Date?
    @State private var processingStartTime: Date?
    @State private var isEditingTopic = false
    @State private var editedTopic = ""
    @State private var showClearConfirmation = false
    @State private var pendingAttachments: [(id: UUID, data: Data, mediaType: String, fileName: String)] = []
    @State private var showFileImporter = false
    @State private var previewAttachment: MessageAttachment?
    @State private var previewImageFromPending: (data: Data, mediaType: String)?
    @State private var delegateTarget: Agent?
    @State private var isStreamingThinkingExpanded = false
    /// Sidecar `Session.id` string currently receiving stream (sequential multi-agent).
    @State private var activeStreamSessionKey: String?
    @State private var streamingDisplayName: String = "Claude"
    @State private var showSlashHelp = false
    @State private var showUnknownSlash = false
    @State private var unknownSlashName = ""
    @State private var showMentionError = false
    @State private var mentionErrorDetail = ""
    @State private var showAddAgentsSheet = false
    @FocusState private var topicFieldFocused: Bool

    @Query private var allConversations: [Conversation]
    @Query private var allAgents: [Agent]

    private var conversation: Conversation? {
        allConversations.first { $0.id == conversationId }
    }

    private var sortedMessages: [ConversationMessage] {
        (conversation?.messages ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    private var primarySession: Session? {
        conversation?.primarySession
    }

    private var currentModel: String? {
        primarySession?.agent?.model
    }

    private var aggregatedLiveCost: Double {
        guard let convo = conversation else { return 0 }
        var sum = 0.0
        for s in convo.sessions {
            sum += appState.activeSessions[s.id]?.cost ?? s.totalCost
        }
        return sum
    }

    private var liveCost: Double? {
        let c = aggregatedLiveCost
        return c > 0 ? c : nil
    }

    private var streamSessionKeyForUI: String? {
        activeStreamSessionKey ?? primarySession?.id.uuidString
    }

    private var liveStreamingText: String? {
        guard let key = streamSessionKeyForUI else { return nil }
        let text = appState.streamingText[key]
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private var liveThinkingText: String? {
        guard let key = streamSessionKeyForUI else { return nil }
        let text = appState.thinkingText[key]
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private var mentionAutocompleteAgents: [Agent] {
        guard let r = inputText.range(of: #"@([^\s@]*)$"#, options: .regularExpression) else { return [] }
        let token = String(inputText[r]).dropFirst().lowercased()
        guard !token.isEmpty else { return Array(allAgents.prefix(8)) }
        return allAgents.filter { $0.name.lowercased().hasPrefix(token) }.prefix(8).map { $0 }
    }

    private var sendingToSubtitle: String? {
        guard let c = conversation, c.sessions.count > 1 else { return nil }
        let names = c.sessions.compactMap { $0.agent?.name ?? "Assistant" }
        return "Group — " + names.joined(separator: ", ") + " · peer replies reach everyone"
    }

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider()
            messageList
            Divider()
            inputArea
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            checkForPendingResponse()
        }
        .onReceive(appState.$lastSessionEvent) { events in
            checkForCompletion(events: events)
        }
        .onReceive(appState.$streamingText) { texts in
            if let key = streamSessionKeyForUI, texts[key] != nil {
                lastTokenTime = Date()
            }
        }
        .onReceive(appState.$sidecarStatus) { status in
            if status != .connected && isProcessing {
                isProcessing = false
                processingStartTime = nil
            }
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            guard isProcessing, let start = processingStartTime else { return }
            let elapsed = Date().timeIntervalSince(start)
            let key = streamSessionKeyForUI ?? ""
            let hasStreamingText = !(appState.streamingText[key]?.isEmpty ?? true)
            if elapsed > 120 && !hasStreamingText {
                print("[ChatView] Timeout: no response after \(Int(elapsed))s for \(key)")
                isProcessing = false
                processingStartTime = nil
                if !key.isEmpty {
                    appState.lastSessionEvent[key] = .error("No response received (timeout)")
                }
            }
        }
        .onChange(of: sortedMessages.count) { oldCount, newCount in
            if oldCount == 0, newCount > 0 {
                checkForPendingResponse()
            }
        }
        .task(id: isProcessing) {
            guard isProcessing else { return }
            while isProcessing {
                try? await Task.sleep(for: .seconds(3))
                guard isProcessing else { return }
                let key = streamSessionKeyForUI ?? ""
                let hasText = appState.streamingText[key] != nil
                let stale = lastTokenTime.map { Date().timeIntervalSince($0) > 3 } ?? false
                if hasText && stale {
                    collectResponseIfSingle()
                    return
                }
            }
        }
        .alert("Clear Messages?", isPresented: $showClearConfirmation) {
            Button("Clear All", role: .destructive) { clearMessages() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All messages in this conversation will be deleted. The conversation will remain.")
        }
        .sheet(item: $previewAttachment) { attachment in
            ImagePreviewOverlay(attachment: attachment)
        }
        .sheet(isPresented: Binding(
            get: { previewImageFromPending != nil },
            set: { if !$0 { previewImageFromPending = nil } }
        )) {
            if let pending = previewImageFromPending {
                ImagePreviewOverlay(imageData: pending.data, mediaType: pending.mediaType)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: AttachmentStore.supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .sheet(item: $delegateTarget) { agent in
            DelegateSheet(
                agent: agent,
                initialTask: inputText.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceSessionId: primarySession?.id ?? conversationId
            ) {
                inputText = ""
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $showAddAgentsSheet) {
            AddAgentsToChatSheet(conversationId: conversationId)
                .environmentObject(appState)
                .environment(\.modelContext, modelContext)
        }
        .alert("Commands", isPresented: $showSlashHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("/help — this list\n/topic <name> or /rename <name> — rename conversation\n/agents — add agents to this chat\n@AgentName — add that agent to the group if missing; everyone still receives each message")
        }
        .alert("Unknown command", isPresented: $showUnknownSlash) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Unknown command /\(unknownSlashName). Try /help.")
        }
        .alert("Mention", isPresented: $showMentionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mentionErrorDetail)
        }
    }

    // MARK: - Chat Header

    @ViewBuilder
    private var chatHeader: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                agentIconButton

                if isEditingTopic {
                    TextField("Conversation name", text: $editedTopic)
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)
                        .focused($topicFieldFocused)
                        .frame(maxWidth: 300)
                        .onSubmit { commitRename() }
                        .onExitCommand { cancelRename() }
                        .accessibilityIdentifier("chat.topicField")
                } else {
                    Text(conversation?.topic ?? "Chat")
                        .font(.headline)
                        .lineLimit(1)
                        .accessibilityIdentifier("chat.topicTitle")
                }

                Spacer()

                if let model = currentModel {
                    Text(modelShortName(model))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("chat.modelPill")
                }

                if let cost = liveCost, cost > 0 {
                    Text(String(format: "$%.4f", cost))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityIdentifier("chat.liveCostLabel")
                }

                if let convo = conversation {
                    headerActions(convo)
                }
            }

            if let mission = primarySession?.mission, !mission.isEmpty {
                HStack {
                    Text(mission)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityIdentifier("chat.missionPreview")
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var agentIconButton: some View {
        if let convo = conversation, convo.sessions.count > 1 {
            HStack(spacing: -6) {
                ForEach(convo.sessions.prefix(4), id: \.id) { s in
                    if let ag = s.agent {
                        Image(systemName: ag.icon)
                            .foregroundStyle(Color.fromAgentColor(ag.color))
                            .font(.caption)
                            .padding(4)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                if convo.sessions.count > 4 {
                    Text("+\(convo.sessions.count - 4)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("chat.groupAgentIcons")
        } else if let agent = primarySession?.agent {
            Button {
                appState.showAgentLibrary = true
            } label: {
                Image(systemName: agent.icon)
                    .foregroundStyle(Color.fromAgentColor(agent.color))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Open agent: \(agent.name)")
            .accessibilityIdentifier("chat.agentIconButton")
            .accessibilityLabel("Open agent \(agent.name)")
        } else {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundStyle(.blue)
                .font(.title3)
                .accessibilityIdentifier("chat.chatIcon")
        }
    }

    @ViewBuilder
    private func headerActions(_ convo: Conversation) -> some View {
        HStack(spacing: 6) {
            if convo.status == .active {
                Button { pauseSession() } label: {
                    Image(systemName: "pause.fill")
                }
                .help("Pause session")
                .accessibilityIdentifier("chat.pauseButton")
                .accessibilityLabel("Pause session")

                Button { closeConversation(convo) } label: {
                    Image(systemName: "stop.circle")
                }
                .help("Close session")
                .accessibilityIdentifier("chat.closeSessionButton")
                .accessibilityLabel("Close session")
            } else if convo.sessions.contains(where: { $0.status == .paused }) {
                Button { resumeSession() } label: {
                    Image(systemName: "play.fill")
                }
                .help("Resume session")
                .accessibilityIdentifier("chat.resumeButton")
                .accessibilityLabel("Resume session")
            }

            Menu {
                if !convo.sessions.isEmpty {
                    Button { forkConversation() } label: {
                        Label("Fork Conversation", systemImage: "arrow.branch")
                    }
                    .accessibilityIdentifier("chat.moreOptions.fork")
                }
                Button {
                    editedTopic = convo.topic ?? ""
                    isEditingTopic = true
                    topicFieldFocused = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .accessibilityIdentifier("chat.moreOptions.rename")
                Button { duplicateConversation(convo) } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("chat.moreOptions.duplicate")
                Divider()
                Button { showClearConfirmation = true } label: {
                    Label("Clear Messages", systemImage: "trash")
                }
                .accessibilityIdentifier("chat.moreOptions.clearMessages")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
            .help("More options")
            .accessibilityIdentifier("chat.moreOptionsMenu")
            .accessibilityLabel("More options")
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Message List

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(sortedMessages) { message in
                        MessageBubble(
                            message: message,
                            participants: conversation?.participants ?? [],
                            onTapAttachment: { attachment in
                                previewAttachment = attachment
                            },
                            onForkFromHere: {
                                forkFromMessage(message)
                            }
                        )
                        .id(message.id)
                    }

                    if isProcessing {
                        streamingBubble
                            .id("streaming")
                    }
                }
                .padding()
            }
            .accessibilityIdentifier("chat.messageScrollView")
            .onChange(of: sortedMessages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: liveStreamingText) { _, _ in
                if isProcessing {
                    scrollToBottom(proxy)
                }
            }
        }
    }

    // MARK: - Input Area

    private var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !pendingAttachments.isEmpty) && !isProcessing
    }

    @ViewBuilder
    private var inputArea: some View {
        VStack(spacing: 0) {
            if !pendingAttachments.isEmpty {
                pendingAttachmentStrip
            }

            if let sub = sendingToSubtitle {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .accessibilityIdentifier("chat.sendingToHint")
            }

            if !mentionAutocompleteAgents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(mentionAutocompleteAgents) { agent in
                            Button {
                                insertMentionCompletion(agentName: agent.name)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name)
                                        .font(.caption)
                                    Text(agentMentionHint(for: agent))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("chat.mentionSuggestion.\(agent.id.uuidString)")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("chat.mentionSuggestions")
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("chat.attachButton")
                .accessibilityLabel("Attach file")
                .help("Attach file")
                .disabled(isProcessing)

                delegateMenu

                PasteableTextField(
                    text: $inputText,
                    onImagePaste: { data, mediaType in
                        guard AttachmentStore.validate(data: data, mediaType: mediaType) else { return }
                        pendingAttachments.append((id: UUID(), data: data, mediaType: mediaType, fileName: "pasted.png"))
                    },
                    onSubmit: { if canSend { sendMessage() } },
                    canSubmitOnReturn: { canSend }
                )
                .accessibilityIdentifier("chat.messageInput")
                .help("Return sends when there is text or attachments. Shift-Return inserts a new line. ⌘↩ also sends.")

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("chat.sendButton")
                .accessibilityLabel("Send message")
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send message (Return or ⌘Return)")
            }
            .padding(12)
        }
        .background(.bar)
        .onDrop(of: [.image, .fileURL, .plainText, .pdf], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
    }

    @ViewBuilder
    private var pendingAttachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(pendingAttachments.enumerated()), id: \.element.id) { index, item in
                    ZStack(alignment: .topTrailing) {
                        if item.mediaType.hasPrefix("image/"), let nsImage = NSImage(data: item.data) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture {
                                    previewImageFromPending = (data: item.data, mediaType: item.mediaType)
                                }
                                .accessibilityIdentifier("chat.pendingAttachment.\(index)")
                        } else {
                            VStack(spacing: 2) {
                                Image(systemName: iconForMediaType(item.mediaType))
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text(item.fileName)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 56)
                            }
                            .frame(width: 60, height: 60)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                            .accessibilityIdentifier("chat.pendingAttachment.\(index)")
                        }

                        Button {
                            pendingAttachments.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .background(Circle().fill(.black.opacity(0.6)))
                        }
                        .buttonStyle(.borderless)
                        .offset(x: 4, y: -4)
                        .accessibilityIdentifier("chat.pendingAttachment.remove.\(index)")
                        .accessibilityLabel("Remove attachment")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .accessibilityIdentifier("chat.pendingAttachments")
    }

    @ViewBuilder
    private var delegateMenu: some View {
        let inChatAgentIds = Set((conversation?.sessions ?? []).compactMap(\.agent?.id))
        let eligibleAgents = allAgents.filter { !inChatAgentIds.contains($0.id) }

        Menu {
            Section("Delegate to...") {
                ForEach(eligibleAgents, id: \.id) { agent in
                    Button {
                        delegateTarget = agent
                    } label: {
                        Label(agent.name, systemImage: agent.icon)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.triangle.branch")
                .font(.body)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 20)
        .accessibilityIdentifier("chat.delegateButton")
        .accessibilityLabel("Delegate to agent")
        .help("Delegate task to another agent")
        .disabled(isProcessing || appState.sidecarStatus != .connected || eligibleAgents.isEmpty)
    }

    private func iconForMediaType(_ mediaType: String) -> String {
        switch mediaType {
        case "text/plain", "text/markdown": return "doc.text"
        case "application/pdf": return "doc.richtext"
        default: return mediaType.hasPrefix("image/") ? "photo" : "doc"
        }
    }

    // MARK: - Image Input Handlers

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                loadImageFromProvider(provider)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let urlData = data as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                    let ext = url.pathExtension.lowercased()
                    guard AttachmentStore.supportedExtensions.contains(ext) else { return }
                    guard let fileData = try? Data(contentsOf: url) else { return }
                    let mediaType = AttachmentStore.mediaTypeForURL(url)
                    guard AttachmentStore.validate(data: fileData, mediaType: mediaType) else { return }
                    DispatchQueue.main.async {
                        pendingAttachments.append((id: UUID(), data: fileData, mediaType: mediaType, fileName: url.lastPathComponent))
                    }
                }
            }
        }
    }

    private func loadImageFromProvider(_ provider: NSItemProvider) {
        let imageTypes: [UTType] = [.png, .jpeg, .tiff, .gif]
        for type in imageTypes {
            if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    guard let data, AttachmentStore.validate(data: data, mediaType: "image/png") else { return }
                    let resolved: (Data, String)
                    if type == .tiff {
                        guard let nsImage = NSImage(data: data),
                              let converted = AttachmentStore.mediaTypeFromNSImage(nsImage) else { return }
                        resolved = converted
                    } else {
                        resolved = (data, AttachmentStore.mediaTypeFromData(data))
                    }
                    DispatchQueue.main.async {
                        pendingAttachments.append((id: UUID(), data: resolved.0, mediaType: resolved.1, fileName: "pasted.png"))
                    }
                }
                return
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { continue }
            let mediaType = AttachmentStore.mediaTypeForURL(url)
            guard AttachmentStore.validate(data: data, mediaType: mediaType) else { continue }
            pendingAttachments.append((id: UUID(), data: data, mediaType: mediaType, fileName: url.lastPathComponent))
        }
    }

    // MARK: - Streaming Bubble

    @ViewBuilder
    private var streamingBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                    Text(streamingDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let thinking = liveThinkingText {
                    streamingThinkingSection(thinking)
                }

                if let text = liveStreamingText {
                    MarkdownContent(text: text)
                } else if liveThinkingText == nil {
                    StreamingIndicator()
                }
            }

            Spacer(minLength: 60)
        }
        .accessibilityIdentifier("chat.streamingBubble")
    }

    @ViewBuilder
    private func streamingThinkingSection(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isStreamingThinkingExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.caption2)
                        .foregroundStyle(.indigo)
                    Text("Thinking...")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.indigo)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isStreamingThinkingExpanded ? 90 : 0))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat.streamingThinkingToggle")
            .accessibilityLabel(isStreamingThinkingExpanded ? "Collapse thinking" : "Expand thinking")

            if isStreamingThinkingExpanded {
                Divider()
                ScrollView {
                    Text(thinking)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .frame(maxHeight: 200)
            }
        }
        .background(.indigo.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.indigo.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if isProcessing {
            withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
        } else if let lastId = sortedMessages.last?.id {
            withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
        }
    }

    private var participantSummary: String {
        guard let convo = conversation else { return "" }
        let names = convo.participants.map(\.displayName)
        return names.joined(separator: " + ")
    }

    private func modelShortName(_ model: String) -> String {
        if model.contains("sonnet") { return "sonnet" }
        if model.contains("opus") { return "opus" }
        if model.contains("haiku") { return "haiku" }
        return model
    }

    private func commitRename() {
        let name = editedTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, let convo = conversation {
            convo.topic = name
            try? modelContext.save()
        }
        isEditingTopic = false
    }

    private func cancelRename() {
        isEditingTopic = false
    }

    // MARK: - Auto Naming

    private func autoNameConversation(_ convo: Conversation, firstMessage: String) {
        guard convo.topic == "New Chat" || convo.topic == nil else { return }

        let trimmed = firstMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated: String
        if trimmed.count <= 50 {
            truncated = trimmed
        } else {
            let cutoff = trimmed.index(trimmed.startIndex, offsetBy: 50)
            let substring = trimmed[..<cutoff]
            if let lastSpace = substring.lastIndex(of: " ") {
                truncated = String(substring[..<lastSpace]) + "..."
            } else {
                truncated = String(substring) + "..."
            }
        }

        let agentName = convo.primarySession?.agent?.name
        convo.topic = agentName.map { "\($0): \(truncated)" } ?? truncated
    }

    private func agentMentionHint(for agent: Agent) -> String {
        conversation?.sessions.contains(where: { $0.agent?.id == agent.id }) == true ? "In chat" : "Adds on send"
    }

    private func insertMentionCompletion(agentName: String) {
        guard let r = inputText.range(of: #"@([^\s@]*)$"#, options: .regularExpression) else { return }
        inputText.replaceSubrange(r, with: "@\(agentName) ")
    }

    /// Freeform / quick chat: ensure one `Session` + Claude participant exist before first model call.
    private func ensureFreeformSidecarSession(in convo: Conversation) -> Session? {
        if let existing = convo.primarySession, convo.sessions.count == 1, existing.agent == nil {
            return existing
        }
        if let s = convo.primarySession, s.agent != nil { return s }
        let session = Session(
            agent: nil,
            mission: nil,
            mode: .interactive,
            workingDirectory: appState.instanceWorkingDirectory ?? NSHomeDirectory()
        )
        session.conversations = [convo]
        convo.sessions.append(session)
        let agentParticipant = Participant(
            type: .agentSession(sessionId: session.id),
            displayName: "Claude"
        )
        agentParticipant.conversation = convo
        convo.participants.append(agentParticipant)
        modelContext.insert(session)
        modelContext.insert(agentParticipant)
        try? modelContext.save()
        return session
    }

    private func participantForSession(_ session: Session, in convo: Conversation) -> Participant? {
        convo.participants.first {
            if case .agentSession(let sid) = $0.type { return sid == session.id }
            return false
        }
    }

    // MARK: - Send Message

    private func sendMessage() {
        let rawInput = inputText
        let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !text.isEmpty || !attachments.isEmpty, let convo = conversation else {
            return
        }

        if text.first == "/", !text.hasPrefix("//"), let slash = ChatSendRouting.parseSlashCommand(rawInput) {
            switch slash {
            case .help:
                showSlashHelp = true
            case .topic(let title):
                let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    convo.topic = t
                    try? modelContext.save()
                }
            case .agents:
                showAddAgentsSheet = true
            case .unknown(let name):
                unknownSlashName = name
                showUnknownSlash = true
            }
            if case .topic = slash, text.split(separator: " ").count <= 1, slash != .help {
                // /topic with no title — still consume input? skip clear
            }
            inputText = ""
            pendingAttachments = []
            return
        }

        inputText = ""
        pendingAttachments = []

        let mentionNames = ChatSendRouting.mentionedAgentNames(in: text)
        let (resolvedMentionAgents, unknownMentions) = ChatSendRouting.resolveMentionedAgents(
            names: mentionNames,
            agents: allAgents
        )
        if !unknownMentions.isEmpty {
            mentionErrorDetail = "Unknown agent(s): \(unknownMentions.joined(separator: ", "))"
            showMentionError = true
            return
        }

        for ag in resolvedMentionAgents {
            if convo.sessions.contains(where: { $0.agent?.id == ag.id }) { continue }
            let primaryWd = (convo.primarySession?.workingDirectory ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let wd = !primaryWd.isEmpty ? primaryWd : ""
            let session = Session(
                agent: ag,
                mission: convo.primarySession?.mission,
                mode: convo.primarySession?.mode ?? .interactive,
                workingDirectory: wd
            )
            session.conversations = [convo]
            convo.sessions.append(session)
            let p = Participant(type: .agentSession(sessionId: session.id), displayName: ag.name)
            p.conversation = convo
            convo.participants.append(p)
            modelContext.insert(session)
            modelContext.insert(p)
        }
        GroupWorkingDirectory.ensureShared(
            for: convo,
            instanceDefault: appState.instanceWorkingDirectory,
            modelContext: modelContext
        )
        try? modelContext.save()

        var targetSessions: [Session] = convo.sessions.sorted(by: { $0.startedAt < $1.startedAt })
        if targetSessions.isEmpty {
            if let s = ensureFreeformSidecarSession(in: convo) {
                targetSessions = [s]
            }
        }

        guard !targetSessions.isEmpty else {
            mentionErrorDetail = "No agent session to send to. Pick an agent or use New Session."
            showMentionError = true
            return
        }

        let userParticipant = convo.participants.first { $0.type == .user }
        let isFirstChat = convo.messages.filter({ $0.type == .chat }).isEmpty

        let message = ConversationMessage(
            senderParticipantId: userParticipant?.id,
            text: text,
            type: .chat,
            conversation: convo
        )

        var wireAttachments: [WireAttachment] = []
        for item in attachments {
            let attachment = AttachmentStore.save(data: item.data, mediaType: item.mediaType, fileName: item.fileName)
            attachment.message = message
            message.attachments.append(attachment)
            modelContext.insert(attachment)
            wireAttachments.append(WireAttachment(
                data: item.data.base64EncodedString(),
                mediaType: item.mediaType,
                fileName: item.fileName
            ))
        }

        convo.messages.append(message)
        modelContext.insert(message)
        if isFirstChat {
            let nameHint: String
            if text.isEmpty {
                let fileCount = attachments.count
                nameHint = "Shared \(fileCount) file\(fileCount == 1 ? "" : "s")"
            } else {
                nameHint = text
            }
            autoNameConversation(convo, firstMessage: nameHint)
        }

        try? modelContext.save()

        guard appState.sidecarStatus == .connected,
              let manager = appState.sidecarManager else {
            isProcessing = false
            return
        }

        isProcessing = true
        processingStartTime = Date()

        let mentionHighlightNames = resolvedMentionAgents.map(\.name)
        Task { @MainActor in
            await runSequentialAgentTurns(
                convo: convo,
                targetSessions: targetSessions,
                latestUserText: text,
                highlightedMentionAgentNames: mentionHighlightNames,
                wireAttachments: wireAttachments,
                manager: manager
            )
        }
    }

    @MainActor
    private func runSequentialAgentTurns(
        convo: Conversation,
        targetSessions: [Session],
        latestUserText: String,
        highlightedMentionAgentNames: [String],
        wireAttachments: [WireAttachment],
        manager: SidecarManager
    ) async {
        GroupWorkingDirectory.ensureShared(
            for: convo,
            instanceDefault: appState.instanceWorkingDirectory,
            modelContext: modelContext
        )
        let participants = convo.participants
        let provisioner = AgentProvisioner(modelContext: modelContext)
        let fanOutContext = GroupPeerFanOutContext()

        for (index, session) in targetSessions.enumerated() {
            let sidecarKey = session.id.uuidString
            activeStreamSessionKey = sidecarKey
            streamingDisplayName = session.agent?.name ?? "Claude"

            appState.streamingText.removeValue(forKey: sidecarKey)
            appState.thinkingText.removeValue(forKey: sidecarKey)
            appState.lastSessionEvent.removeValue(forKey: sidecarKey)

            var createConfig: AgentConfig?
            if !appState.createdSessions.contains(sidecarKey) {
                if let agent = session.agent {
                    let (cfg, _) = provisioner.provision(
                        agent: agent,
                        mission: session.mission,
                        workingDirOverride: session.workingDirectory
                    )
                    createConfig = cfg
                } else {
                    createConfig = makeFreeformAgentConfig()
                }
            }

            let promptText = GroupPromptBuilder.buildMessageText(
                conversation: convo,
                targetSession: session,
                latestUserMessageText: latestUserText,
                participants: participants,
                highlightedMentionAgentNames: highlightedMentionAgentNames
            )

            do {
                if let config = createConfig {
                    try await manager.send(.sessionCreate(
                        conversationId: sidecarKey,
                        agentConfig: config
                    ))
                    appState.createdSessions.insert(sidecarKey)
                }
                try await manager.send(.sessionMessage(
                    sessionId: sidecarKey,
                    text: promptText,
                    attachments: wireAttachments
                ))
            } catch {
                isProcessing = false
                activeStreamSessionKey = nil
                appState.lastSessionEvent[sidecarKey] = .error("Failed to send: \(error.localizedDescription)")
                return
            }

            await waitForSessionCompletion(sidecarKey: sidecarKey)

            guard let stillConvo = conversation, stillConvo.id == convo.id else {
                isProcessing = false
                activeStreamSessionKey = nil
                return
            }

            if let reply = finalizeAssistantStreamIntoMessage(
                convo: stillConvo,
                session: session,
                sidecarKey: sidecarKey
            ) {
                let pendingUserTurnIds = Set(targetSessions.suffix(from: index + 1).map(\.id))
                await fanOutPeerNotifications(
                    fromSession: session,
                    triggerMessage: reply,
                    convo: stillConvo,
                    skipRecipientSessionIds: pendingUserTurnIds,
                    manager: manager,
                    provisioner: provisioner,
                    participants: participants,
                    context: fanOutContext
                )
            }
        }

        isProcessing = false
        activeStreamSessionKey = nil
        streamingDisplayName = "Claude"
    }

    private func makeFreeformAgentConfig() -> AgentConfig {
        AgentConfig(
            name: "Claude",
            systemPrompt: "You are a helpful assistant. Be concise and clear.",
            allowedTools: [],
            mcpServers: [],
            model: "claude-sonnet-4-6",
            maxTurns: 1,
            maxBudget: nil,
            maxThinkingTokens: 10000,
            workingDirectory: appState.instanceWorkingDirectory ?? NSHomeDirectory(),
            skills: []
        )
    }

    /// Delivers peer messages to other agents (`may_reply`); skips recipients that still have their user-turn prompt pending in `runSequentialAgentTurns`.
    @MainActor
    private func fanOutPeerNotifications(
        fromSession: Session,
        triggerMessage: ConversationMessage,
        convo: Conversation,
        skipRecipientSessionIds: Set<UUID>,
        manager: SidecarManager,
        provisioner: AgentProvisioner,
        participants: [Participant],
        context: GroupPeerFanOutContext
    ) async {
        guard convo.sessions.count > 1 else { return }

        let senderLabel = GroupPromptBuilder.senderDisplayLabel(for: triggerMessage, participants: participants)
        let sortedOthers = convo.sessions
            .filter { $0.id != fromSession.id && !skipRecipientSessionIds.contains($0.id) }
            .sorted { $0.startedAt < $1.startedAt }

        for other in sortedOthers {
            guard context.trySchedulePeerDelivery(targetSessionId: other.id, triggerMessageId: triggerMessage.id) else {
                continue
            }

            let key = other.id.uuidString
            activeStreamSessionKey = key
            streamingDisplayName = other.agent?.name ?? "Claude"
            appState.streamingText.removeValue(forKey: key)
            appState.thinkingText.removeValue(forKey: key)
            appState.lastSessionEvent.removeValue(forKey: key)

            var createConfig: AgentConfig?
            if !appState.createdSessions.contains(key) {
                if let agent = other.agent {
                    let (cfg, _) = provisioner.provision(
                        agent: agent,
                        mission: other.mission,
                        workingDirOverride: other.workingDirectory
                    )
                    createConfig = cfg
                } else {
                    createConfig = makeFreeformAgentConfig()
                }
            }

            let prompt = GroupPromptBuilder.buildPeerNotifyPrompt(
                senderLabel: senderLabel,
                peerMessageText: triggerMessage.text,
                recipientSession: other
            )

            do {
                if let config = createConfig {
                    try await manager.send(.sessionCreate(
                        conversationId: key,
                        agentConfig: config
                    ))
                    appState.createdSessions.insert(key)
                }
                try await manager.send(.sessionMessage(
                    sessionId: key,
                    text: prompt,
                    attachments: []
                ))
            } catch {
                appState.lastSessionEvent[key] = .error("Peer notify failed: \(error.localizedDescription)")
                continue
            }

            await waitForSessionCompletion(sidecarKey: key)

            guard let liveConvo = conversation, liveConvo.id == convo.id else { return }

            if let peerReply = finalizeAssistantStreamIntoMessage(convo: liveConvo, session: other, sidecarKey: key) {
                await fanOutPeerNotifications(
                    fromSession: other,
                    triggerMessage: peerReply,
                    convo: liveConvo,
                    skipRecipientSessionIds: [],
                    manager: manager,
                    provisioner: provisioner,
                    participants: participants,
                    context: context
                )
            }
        }
    }

    private func waitForSessionCompletion(sidecarKey: String) async {
        let maxWait = 600
        var iterations = 0
        while iterations < maxWait {
            if let ev = await MainActor.run(body: { appState.lastSessionEvent[sidecarKey] }) {
                switch ev {
                case .result, .error:
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(100))
            iterations += 1
        }
    }

    // MARK: - Session Events

    private func checkForPendingResponse() {
        guard let key = streamSessionKeyForUI else { return }
        if let event = appState.lastSessionEvent[key] {
            isProcessing = true
            switch event {
            case .result:
                collectResponseIfSingle()
            case .error(let msg):
                collectResponseIfSingle(errorMessage: msg)
            }
            return
        }

        if let text = appState.streamingText[key], !text.isEmpty, !isProcessing {
            isProcessing = true
        }
    }

    private func checkForCompletion(events: [String: AppState.SessionEventKind]? = nil) {
        guard let key = streamSessionKeyForUI else { return }
        let source = events ?? appState.lastSessionEvent
        guard let event = source[key] else { return }

        isProcessing = true
        switch event {
        case .result:
            collectResponseIfSingle()
        case .error(let msg):
            collectResponseIfSingle(errorMessage: msg)
        }
    }

    /// Legacy path when not using sequential multi-send (e.g. recovery).
    private func collectResponseIfSingle(errorMessage: String? = nil) {
        guard let key = streamSessionKeyForUI,
              let convo = conversation,
              let session = convo.sessions.first(where: { $0.id.uuidString == key }) else {
            isProcessing = false
            return
        }
        _ = finalizeAssistantStreamIntoMessage(convo: convo, session: session, sidecarKey: key, errorMessage: errorMessage)
        isProcessing = false
        activeStreamSessionKey = nil
    }

    @discardableResult
    private func finalizeAssistantStreamIntoMessage(
        convo: Conversation,
        session: Session,
        sidecarKey: String,
        errorMessage: String? = nil
    ) -> ConversationMessage? {
        var err = errorMessage
        if err == nil, case .error(let m) = appState.lastSessionEvent[sidecarKey] {
            err = m
        }
        let streamedText = appState.streamingText[sidecarKey] ?? ""
        guard !streamedText.isEmpty || err != nil else {
            return nil
        }
        let responseText = !streamedText.isEmpty ? streamedText : (err ?? "(no response)")

        let agentParticipant = participantForSession(session, in: convo)
        let response = ConversationMessage(
            senderParticipantId: agentParticipant?.id,
            text: responseText,
            type: .chat,
            conversation: convo
        )
        let thinking = appState.thinkingText[sidecarKey]
        if let thinking, !thinking.isEmpty {
            response.thinkingText = thinking
        }
        convo.messages.append(response)
        modelContext.insert(response)
        GroupPromptBuilder.advanceWatermark(session: session, assistantMessage: response)
        try? modelContext.save()
        appState.streamingText.removeValue(forKey: sidecarKey)
        appState.thinkingText.removeValue(forKey: sidecarKey)
        appState.lastSessionEvent.removeValue(forKey: sidecarKey)
        isStreamingThinkingExpanded = false
        return response
    }

    // MARK: - Actions

    private func forkConversation() {
        guard let newConvo = cloneConversationForFork(from: conversation, throughMessage: nil),
              let oldPrimary = conversation?.primarySession,
              let newPrimary = newConvo.primarySession else { return }
        appState.selectedConversationId = newConvo.id
        Task {
            try? await appState.sidecarManager?.send(.sessionFork(
                parentSessionId: oldPrimary.id.uuidString,
                childSessionId: newPrimary.id.uuidString
            ))
        }
    }

    private func forkFromMessage(_ pivot: ConversationMessage) {
        guard let newConvo = cloneConversationForFork(from: conversation, throughMessage: pivot),
              let oldPrimary = conversation?.primarySession,
              let newPrimary = newConvo.primarySession else { return }
        appState.selectedConversationId = newConvo.id
        Task {
            try? await appState.sidecarManager?.send(.sessionFork(
                parentSessionId: oldPrimary.id.uuidString,
                childSessionId: newPrimary.id.uuidString
            ))
        }
    }

    /// Duplicate conversation structure and optionally copy messages up to `throughMessage` (inclusive).
    private func cloneConversationForFork(from source: Conversation?, throughMessage: ConversationMessage?) -> Conversation? {
        guard let source else { return nil }
        let topicBase = source.topic ?? "Chat"
        let newConvo = Conversation(topic: topicBase + " (fork)")
        newConvo.parentConversationId = source.id

        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = newConvo
        newConvo.participants.append(userParticipant)

        var oldToNewSession: [UUID: Session] = [:]
        for oldSession in source.sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let newSession = Session(
                agent: oldSession.agent,
                mission: oldSession.mission,
                mode: oldSession.mode,
                workingDirectory: oldSession.workingDirectory,
                workspaceType: oldSession.workspaceType
            )
            let agent = oldSession.agent
            newSession.conversations = [newConvo]
            newConvo.sessions.append(newSession)
            oldToNewSession[oldSession.id] = newSession

            let p = Participant(type: .agentSession(sessionId: newSession.id), displayName: agent?.name ?? "Agent")
            p.conversation = newConvo
            newConvo.participants.append(p)
            modelContext.insert(newSession)
        }

        let ordered = source.messages.sorted { $0.timestamp < $1.timestamp }
        let slice: [ConversationMessage]
        if let pivot = throughMessage, let idx = ordered.firstIndex(where: { $0.id == pivot.id }) {
            slice = Array(ordered[...idx])
        } else {
            slice = ordered
        }

        for oldMsg in slice where oldMsg.type == .chat {
            let newSender: UUID? = {
                guard let sid = oldMsg.senderParticipantId,
                      let oldP = source.participants.first(where: { $0.id == sid }) else { return userParticipant.id }
                if oldP.type == .user { return userParticipant.id }
                if case .agentSession(let osid) = oldP.type,
                   let ns = oldToNewSession[osid],
                   let np = participantForSession(ns, in: newConvo) {
                    return np.id
                }
                return userParticipant.id
            }()
            let nm = ConversationMessage(senderParticipantId: newSender, text: oldMsg.text, type: .chat, conversation: newConvo)
            nm.timestamp = oldMsg.timestamp
            nm.thinkingText = oldMsg.thinkingText
            newConvo.messages.append(nm)
            modelContext.insert(nm)
        }

        modelContext.insert(newConvo)
        try? modelContext.save()
        return newConvo
    }

    private func pauseSession() {
        guard let convo = conversation else { return }
        for session in convo.sessions {
            appState.sendToSidecar(.sessionPause(sessionId: session.id.uuidString))
            session.status = .paused
        }
        try? modelContext.save()
    }

    private func resumeSession() {
        guard let convo = conversation,
              let session = convo.primarySession,
              let claudeSessionId = session.claudeSessionId else { return }
        let sessionId = session.id.uuidString
        appState.sendToSidecar(.sessionResume(sessionId: sessionId, claudeSessionId: claudeSessionId))
        session.status = .active
        convo.status = .active
        try? modelContext.save()
    }

    private func closeConversation(_ convo: Conversation) {
        convo.status = .closed
        convo.closedAt = Date()
        for session in convo.sessions {
            appState.sendToSidecar(.sessionPause(sessionId: session.id.uuidString))
            session.status = .paused
        }
        try? modelContext.save()
    }

    private func clearMessages() {
        guard let convo = conversation else { return }
        for message in convo.messages {
            modelContext.delete(message)
        }
        convo.messages.removeAll()
        try? modelContext.save()
    }

    private func duplicateConversation(_ convo: Conversation) {
        let newConvo = Conversation(topic: (convo.topic ?? "Untitled") + " (copy)")
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = newConvo
        newConvo.participants.append(userParticipant)

        for session in convo.sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let newSession = Session(
                agent: session.agent,
                mission: session.mission,
                mode: session.mode,
                workingDirectory: session.workingDirectory,
                workspaceType: session.workspaceType
            )
            newSession.conversations = [newConvo]
            newConvo.sessions.append(newSession)

            let displayName = session.agent?.name ?? "Agent"
            let agentParticipant = Participant(
                type: .agentSession(sessionId: newSession.id),
                displayName: displayName
            )
            agentParticipant.conversation = newConvo
            newConvo.participants.append(agentParticipant)
            modelContext.insert(newSession)
        }

        modelContext.insert(newConvo)
        try? modelContext.save()
        appState.selectedConversationId = newConvo.id
    }
}