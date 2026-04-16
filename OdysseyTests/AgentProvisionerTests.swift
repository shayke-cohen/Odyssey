import Foundation
import SwiftData
import XCTest
@testable import Odyssey

@MainActor
final class AgentProvisionerTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Agent.self, Session.self, Skill.self, MCPServer.self, PermissionSet.self, AgentGroup.self,
            configurations: config
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // ─── runtimeModeSettings (pure) ───────────────────────────

    func testRuntimeModeSettings_worker() {
        let settings = AgentProvisioner.runtimeModeSettings(agent: nil, mode: .worker)
        XCTAssertFalse(settings.interactive)
        XCTAssertEqual(settings.instancePolicy, AgentInstancePolicy.singleton.rawValue)
        XCTAssertNil(settings.instancePolicyPoolMax)
    }

    func testRuntimeModeSettings_autonomous() {
        let settings = AgentProvisioner.runtimeModeSettings(agent: nil, mode: .autonomous)
        XCTAssertFalse(settings.interactive)
        XCTAssertEqual(settings.instancePolicy, AgentInstancePolicy.spawn.rawValue)
        XCTAssertNil(settings.instancePolicyPoolMax)
    }

    func testRuntimeModeSettings_interactive_noAgent() {
        let settings = AgentProvisioner.runtimeModeSettings(agent: nil, mode: .interactive)
        XCTAssertTrue(settings.interactive)
        XCTAssertNil(settings.instancePolicy)
        XCTAssertNil(settings.instancePolicyPoolMax)
    }

    func testRuntimeModeSettings_interactive_agentDefault() {
        let agent = Agent(name: "A")
        agent.instancePolicy = .agentDefault
        let settings = AgentProvisioner.runtimeModeSettings(agent: agent, mode: .interactive)
        XCTAssertTrue(settings.interactive)
        XCTAssertNil(settings.instancePolicy, "agentDefault must NOT force an explicit policy")
    }

    func testRuntimeModeSettings_interactive_pool() {
        let agent = Agent(name: "A")
        agent.instancePolicy = .pool
        agent.instancePolicyPoolMax = 4
        let settings = AgentProvisioner.runtimeModeSettings(agent: agent, mode: .interactive)
        XCTAssertTrue(settings.interactive)
        XCTAssertEqual(settings.instancePolicy, AgentInstancePolicy.pool.rawValue)
        XCTAssertEqual(settings.instancePolicyPoolMax, 4)
    }

    func testRuntimeModeSettings_interactive_singleton_ignoresPoolMax() {
        let agent = Agent(name: "A")
        agent.instancePolicy = .singleton
        agent.instancePolicyPoolMax = 99
        let settings = AgentProvisioner.runtimeModeSettings(agent: agent, mode: .interactive)
        XCTAssertEqual(settings.instancePolicy, AgentInstancePolicy.singleton.rawValue)
        XCTAssertNil(settings.instancePolicyPoolMax, "poolMax only applies for .pool policy")
    }

    // ─── provision() ──────────────────────────────────────────

    func testProvision_usesWorkingDirOverride() {
        let agent = Agent(name: "Coder", systemPrompt: "you code")
        context.insert(agent)
        let provisioner = AgentProvisioner(modelContext: context)

        let (config, session) = provisioner.provision(
            agent: agent,
            mission: nil,
            mode: .interactive,
            workingDirOverride: "/tmp/project"
        )

        XCTAssertEqual(config.workingDirectory, "/tmp/project")
        XCTAssertEqual(session.workingDirectory, "/tmp/project")
    }

    func testProvision_appendsMissionToSystemPrompt() {
        let agent = Agent(name: "Coder", systemPrompt: "base prompt")
        context.insert(agent)
        let provisioner = AgentProvisioner(modelContext: context)

        let (config, _) = provisioner.provision(
            agent: agent,
            mission: "Ship the v2 feature",
            workingDirOverride: "/tmp"
        )

        XCTAssertTrue(config.systemPrompt.contains("base prompt"))
        XCTAssertTrue(config.systemPrompt.contains("Current Mission"))
        XCTAssertTrue(config.systemPrompt.contains("Ship the v2 feature"))
    }

    func testProvision_workerMode_producesNonInteractiveSingleton() {
        let agent = Agent(name: "Worker", systemPrompt: "")
        context.insert(agent)
        let provisioner = AgentProvisioner(modelContext: context)

        let (config, _) = provisioner.provision(
            agent: agent,
            mission: nil,
            mode: .worker,
            workingDirOverride: "/tmp"
        )

        XCTAssertNil(config.interactive, "worker mode is not interactive")
        XCTAssertEqual(config.instancePolicy, AgentInstancePolicy.singleton.rawValue)
    }

    func testProvision_permissionsDefault_whenNoneSet() {
        let agent = Agent(name: "Bare", systemPrompt: "")
        context.insert(agent)
        let provisioner = AgentProvisioner(modelContext: context)

        let (config, _) = provisioner.provision(agent: agent, mission: nil, workingDirOverride: "/tmp")

        // Default allowed tools when no permission set is attached
        XCTAssertEqual(Set(config.allowedTools), Set(["Read", "Write", "Bash", "Grep", "Glob"]))
    }

    func testProvision_resolvesSkillsAndMcpIncludesSkillMcps() {
        // One MCP owned directly, one via skill — both should appear in the config.
        let directMcp = MCPServer(name: "Direct", transport: .stdio(command: "/bin/cat", args: [], env: [:]))
        let skillMcp = MCPServer(name: "SkillMcp", transport: .stdio(command: "/bin/cat", args: [], env: [:]))
        let skill = Skill(name: "Research", content: "# research\n")
        skill.mcpServerIds = [skillMcp.id]
        let agent = Agent(name: "Composer", systemPrompt: "")
        agent.extraMCPServerIds = [directMcp.id]
        agent.skillIds = [skill.id]

        context.insert(directMcp)
        context.insert(skillMcp)
        context.insert(skill)
        context.insert(agent)

        let provisioner = AgentProvisioner(modelContext: context)
        let (config, _) = provisioner.provision(agent: agent, mission: nil, workingDirOverride: "/tmp")

        let names = config.mcpServers.map { $0.name }
        XCTAssertTrue(names.contains("Direct"), "direct MCP missing from config")
        XCTAssertTrue(names.contains("SkillMcp"), "skill-declared MCP missing from config")
        XCTAssertEqual(config.skills.map { $0.name }, ["Research"])
    }

    func testConfig_forSession_returnsNilWhenAgentNil() {
        // Session without an attached agent returns nil
        let session = Session(agent: nil, workingDirectory: "/tmp")
        let provisioner = AgentProvisioner(modelContext: context)
        XCTAssertNil(provisioner.config(for: session))
    }
}
