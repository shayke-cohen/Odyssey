import Foundation

public struct MCPBridgeSummary: Codable, Sendable, Equatable {
    public var configuredServers: [String]
    public var discoveredTools: [LocalAgentToolDefinition]

    public init(configuredServers: [String], discoveredTools: [LocalAgentToolDefinition]) {
        self.configuredServers = configuredServers
        self.discoveredTools = discoveredTools
    }
}

public actor MCPBridge {
    private var clients: [String: MCPClient] = [:]
    private var toolIndex: [String: Set<String>] = [:]

    public init() {}

    public func summarize(servers: [LocalAgentMCPServer]) async -> MCPBridgeSummary {
        let tools = await discoverTools(for: servers)
        return MCPBridgeSummary(
            configuredServers: servers.map(\.name),
            discoveredTools: tools
        )
    }

    public func discoverTools(for servers: [LocalAgentMCPServer]) async -> [LocalAgentToolDefinition] {
        var definitions = [LocalAgentToolDefinition]()
        for server in servers {
            do {
                let client = try await client(for: server)
                let tools = try await client.listTools()
                toolIndex[serverKey(for: server)] = Set(tools.map(\.name))
                definitions.append(contentsOf: tools.map {
                    LocalAgentToolDefinition(name: $0.name, description: $0.description, inputSchema: $0.inputSchema)
                })
            } catch {
                definitions.append(
                    LocalAgentToolDefinition(
                        name: "mcp_error_\(server.name)",
                        description: "MCP discovery failed for \(server.name): \(error.localizedDescription)"
                    )
                )
            }
        }
        return definitions.sorted { $0.name < $1.name }
    }

    public func supports(toolName: String, servers: [LocalAgentMCPServer]) async -> Bool {
        for server in servers {
            let key = serverKey(for: server)
            if let knownTools = toolIndex[key], knownTools.contains(toolName) {
                return true
            }

            do {
                let client = try await client(for: server)
                let tools = try await client.listTools()
                let names = Set(tools.map(\.name))
                toolIndex[key] = names
                if names.contains(toolName) {
                    return true
                }
            } catch {
                continue
            }
        }
        return false
    }

    public func callTool(
        named toolName: String,
        arguments: [String: DynamicValue],
        servers: [LocalAgentMCPServer]
    ) async throws -> ToolExecutionResult {
        for server in servers {
            guard await supports(toolName: toolName, servers: [server]) else { continue }
            let client = try await client(for: server)
            return try await client.callTool(named: toolName, arguments: arguments)
        }

        return ToolExecutionResult(success: false, output: "No MCP server exposes tool \(toolName)")
    }

    private func client(for server: LocalAgentMCPServer) async throws -> MCPClient {
        let key = serverKey(for: server)
        if let existing = clients[key] {
            return existing
        }

        let client = try await MCPClient(server: server)
        clients[key] = client
        return client
    }

    private func serverKey(for server: LocalAgentMCPServer) -> String {
        if let command = server.command {
            return ([server.name, command] + (server.args ?? [])).joined(separator: "|")
        }
        return "\(server.name)|\(server.url ?? "")"
    }
}
