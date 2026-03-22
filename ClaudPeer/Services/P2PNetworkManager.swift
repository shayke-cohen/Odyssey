import Foundation
import Network
import SwiftData

struct DiscoveredLanPeer: Identifiable {
    let id: String
    let displayName: String
    let endpoint: NWEndpoint
    let metadata: String
}

@MainActor
final class P2PNetworkManager: ObservableObject {
    @Published private(set) var peers: [DiscoveredLanPeer] = []
    @Published private(set) var isRunning = false
    @Published var lastError: String?

    private var browser: NWBrowser?
    private let server: PeerCatalogServer
    private let browserQueue = DispatchQueue(label: "com.claudpeer.p2p.browser")
    private var modelContext: ModelContext?

    init() {
        let empty = try! JSONEncoder().encode(WireAgentExportList(agents: []))
        server = PeerCatalogServer(initialJSON: empty)
    }

    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshExportCache()
    }

    func start() {
        guard !isRunning else { return }
        lastError = nil
        do {
            try server.start()
        } catch {
            lastError = error.localizedDescription
            return
        }
        startBrowser()
        isRunning = true
        refreshExportCache()
    }

    func stop() {
        browser?.cancel()
        browser = nil
        server.stop()
        peers = []
        isRunning = false
    }

    func refreshExportCache() {
        guard let ctx = modelContext else { return }
        let data = Self.buildExportData(modelContext: ctx)
        server.updateJSON(data)
    }

    func fetchAgents(from peer: DiscoveredLanPeer) async throws -> [WireAgentExport] {
        try await Self.httpGetAgents(endpoint: peer.endpoint)
    }

    // MARK: - Browser

    private func startBrowser() {
        let params = NWParameters.tcp
        let b = NWBrowser(for: .bonjour(type: "_claudpeer._tcp", domain: nil), using: params)
        b.stateUpdateHandler = { [weak self] state in
            if case .failed(let err) = state {
                Task { @MainActor in
                    self?.lastError = err.localizedDescription
                }
            }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            Task { @MainActor in
                self.peers = Self.mapBrowseResults(results)
            }
        }
        b.start(queue: browserQueue)
        browser = b
    }

    private static func mapBrowseResults(_ results: Set<NWBrowser.Result>) -> [DiscoveredLanPeer] {
        var list: [DiscoveredLanPeer] = []
        let myAdvertisedName = bonjourNameStatic()
        for item in results {
            switch item.endpoint {
            case let .service(name, type, domain, _):
                if name == myAdvertisedName { continue }
                let id = "\(name).\(type).\(domain)"
                list.append(DiscoveredLanPeer(
                    id: id,
                    displayName: name,
                    endpoint: item.endpoint,
                    metadata: ""
                ))
            default:
                break
            }
        }
        list.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return list
    }

    private static func bonjourNameStatic() -> String {
        let host = ProcessInfo.processInfo.hostName.split(separator: ".").first.map(String.init) ?? "Mac"
        return "\(host)-\(InstanceConfig.name)"
    }

    // MARK: - Export

    private static func buildExportData(modelContext: ModelContext) -> Data {
        let desc = FetchDescriptor<Agent>(sortBy: [SortDescriptor(\.name)])
        let agents = (try? modelContext.fetch(desc)) ?? []
        let skills = (try? modelContext.fetch(FetchDescriptor<Skill>())) ?? []
        let mcps = (try? modelContext.fetch(FetchDescriptor<MCPServer>())) ?? []
        let perms = (try? modelContext.fetch(FetchDescriptor<PermissionSet>())) ?? []

        let skillById = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })
        let mcpById = Dictionary(uniqueKeysWithValues: mcps.map { ($0.id, $0) })
        let permById = Dictionary(uniqueKeysWithValues: perms.map { ($0.id, $0) })

        let exports: [WireAgentExport] = agents.map { a in
            let skillNames = a.skillIds.compactMap { skillById[$0]?.name }
            let mcpNames = a.extraMCPServerIds.compactMap { mcpById[$0]?.name }
            let permName = a.permissionSetId.flatMap { permById[$0]?.name }
            return WireAgentExport(
                id: a.id,
                name: a.name,
                agentDescription: a.agentDescription,
                systemPrompt: a.systemPrompt,
                model: a.model,
                maxTurns: a.maxTurns,
                maxBudget: a.maxBudget,
                maxThinkingTokens: a.maxThinkingTokens,
                icon: a.icon,
                color: a.color,
                instancePolicyKind: a.instancePolicyKind,
                instancePolicyPoolMax: a.instancePolicyPoolMax,
                defaultWorkingDirectory: a.defaultWorkingDirectory,
                githubRepo: a.githubRepo,
                githubDefaultBranch: a.githubDefaultBranch,
                skillNames: skillNames,
                extraMCPNames: mcpNames,
                permissionSetName: permName
            )
        }
        let list = WireAgentExportList(agents: exports)
        return (try? JSONEncoder().encode(list)) ?? Data("{\"agents\":[]}".utf8)
    }

    // MARK: - HTTP over NWConnection

    private static func httpGetAgents(endpoint: NWEndpoint) async throws -> [WireAgentExport] {
        try await withCheckedThrowingContinuation { continuation in
            let conn = NWConnection(to: endpoint, using: .tcp)
            let queue = DispatchQueue(label: "com.claudpeer.p2p.http.client")
            var buffer = Data()

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let req = """
                    GET /claudpeer/v1/agents HTTP/1.1\r
                    Host: claudpeer.local\r
                    Connection: close\r
                    \r

                    """
                    conn.send(content: Data(req.utf8), completion: .contentProcessed { err in
                        if let err {
                            conn.cancel()
                            continuation.resume(throwing: err)
                        }
                    })
                case .failed(let err):
                    continuation.resume(throwing: err)
                default:
                    break
                }
            }

            func receiveMore() {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { data, _, isComplete, error in
                    if let error {
                        conn.cancel()
                        continuation.resume(throwing: error)
                        return
                    }
                    if let data, !data.isEmpty {
                        buffer.append(data)
                    }
                    if isComplete {
                        conn.cancel()
                        do {
                            let agents = try parseAgentsHTTPResponse(buffer)
                            continuation.resume(returning: agents)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    } else {
                        receiveMore()
                    }
                }
            }

            conn.start(queue: queue)
            receiveMore()
        }
    }

    private static func parseAgentsHTTPResponse(_ data: Data) throws -> [WireAgentExport] {
        guard let str = String(data: data, encoding: .utf8),
              let range = str.range(of: "\r\n\r\n") else {
            throw P2PClientError.invalidResponse
        }
        let body = str[range.upperBound...]
        let bodyData = Data(body.utf8)
        let decoded = try JSONDecoder().decode(WireAgentExportList.self, from: bodyData)
        return decoded.agents
    }
}

enum P2PClientError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Could not read agent list from peer."
        }
    }
}

