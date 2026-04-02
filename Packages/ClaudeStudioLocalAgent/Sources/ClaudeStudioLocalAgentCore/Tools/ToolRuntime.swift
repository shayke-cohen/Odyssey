import Foundation

public struct ToolExecutionContext: Sendable {
    public var sessionId: String
    public var workingDirectory: String
    public var configuredMCPServers: [LocalAgentMCPServer]
    public var configuredRemoteTools: Set<String>
    public var localPermissionRules: [String]
    public var allowedBuiltInTools: Set<String>

    public init(
        sessionId: String,
        workingDirectory: String,
        configuredMCPServers: [LocalAgentMCPServer] = [],
        configuredRemoteTools: Set<String> = [],
        localPermissionRules: [String] = [],
        allowedBuiltInTools: Set<String> = []
    ) {
        self.sessionId = sessionId
        self.workingDirectory = workingDirectory
        self.configuredMCPServers = configuredMCPServers
        self.configuredRemoteTools = configuredRemoteTools
        self.localPermissionRules = localPermissionRules
        self.allowedBuiltInTools = allowedBuiltInTools
    }
}

public struct ToolExecutionResult: Codable, Sendable, Equatable {
    public var success: Bool
    public var output: String

    public init(success: Bool, output: String) {
        self.success = success
        self.output = output
    }
}

public protocol RemoteToolCalling: Sendable {
    func callTool(name: String, arguments: [String: DynamicValue], context: ToolExecutionContext) async throws -> ToolExecutionResult
}

public struct ToolDefinition: Sendable {
    public typealias Handler = @Sendable ([String: DynamicValue], ToolExecutionContext) async throws -> ToolExecutionResult

    public var name: String
    public var description: String
    public var inputSchema: [String: String]
    public var handler: Handler

    public init(
        name: String,
        description: String,
        inputSchema: [String: String] = [:],
        handler: @escaping Handler
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.handler = handler
    }
}

public actor ToolRegistry {
    private var tools: [String: ToolDefinition]

    public init(tools: [ToolDefinition] = []) {
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }

    public func register(_ tool: ToolDefinition) {
        tools[tool.name] = tool
    }

    public func register(contentsOf newTools: [ToolDefinition]) {
        for tool in newTools {
            tools[tool.name] = tool
        }
    }

    public func definition(named name: String) -> ToolDefinition? {
        tools[name]
    }

    public func allToolDefinitions() -> [LocalAgentToolDefinition] {
        tools.values.sorted { $0.name < $1.name }.map {
            LocalAgentToolDefinition(name: $0.name, description: $0.description, inputSchema: $0.inputSchema)
        }
    }

    public func availableTools(allowing names: [String]) -> [LocalAgentToolDefinition] {
        let selected = names.isEmpty ? Array(tools.values) : names.compactMap { tools[$0] }
        return selected.sorted { $0.name < $1.name }.map {
            LocalAgentToolDefinition(name: $0.name, description: $0.description, inputSchema: $0.inputSchema)
        }
    }
}

public actor ToolExecutor {
    private let registry: ToolRegistry
    private let remoteToolCaller: (any RemoteToolCalling)?
    private let mcpBridge: MCPBridge

    public init(
        registry: ToolRegistry,
        remoteToolCaller: (any RemoteToolCalling)? = nil,
        mcpBridge: MCPBridge = MCPBridge()
    ) {
        self.registry = registry
        self.remoteToolCaller = remoteToolCaller
        self.mcpBridge = mcpBridge
    }

    public func execute(
        toolName: String,
        arguments: [String: DynamicValue],
        context: ToolExecutionContext
    ) async throws -> ToolExecutionResult {
        if let definition = await registry.definition(named: toolName) {
            let accessPolicy = LocalToolAccessPolicy(rules: context.localPermissionRules)
            guard context.allowedBuiltInTools.contains(toolName) || accessPolicy.allowsAllBuiltInTools else {
                return ToolExecutionResult(success: false, output: "Tool \(toolName) is not enabled for this session")
            }
            guard accessPolicy.allowsInvocation(
                toolName: toolName,
                arguments: arguments,
                workingDirectory: context.workingDirectory
            ) else {
                return ToolExecutionResult(success: false, output: "Tool \(toolName) is not allowed by the current permission rules")
            }
            return try await definition.handler(arguments, context)
        }

        if context.configuredRemoteTools.contains(toolName), let remoteToolCaller {
            return try await remoteToolCaller.callTool(name: toolName, arguments: arguments, context: context)
        }

        if await mcpBridge.supports(toolName: toolName, servers: context.configuredMCPServers) {
            return try await mcpBridge.callTool(named: toolName, arguments: arguments, servers: context.configuredMCPServers)
        }

        return ToolExecutionResult(success: false, output: "Unknown tool: \(toolName)")
    }
}
