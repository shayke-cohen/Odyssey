import Foundation
import SwiftData
import XCTest
@testable import ClaudeStudio

@MainActor
final class AgentDefaultsTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        AppSettings.store.removeObject(forKey: AppSettings.defaultProviderKey)
        AppSettings.store.removeObject(forKey: AppSettings.defaultClaudeModelKey)
        AppSettings.store.removeObject(forKey: AppSettings.defaultCodexModelKey)

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Agent.self, Session.self, Skill.self, MCPServer.self, PermissionSet.self,
            configurations: config
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        AppSettings.store.removeObject(forKey: AppSettings.defaultProviderKey)
        AppSettings.store.removeObject(forKey: AppSettings.defaultClaudeModelKey)
        AppSettings.store.removeObject(forKey: AppSettings.defaultCodexModelKey)
        context = nil
        container = nil
    }

    func testSessionInheritsSystemProviderAndModelDefaults() {
        AppSettings.store.set(ProviderSelection.codex.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set(CodexModel.gpt5Codex.rawValue, forKey: AppSettings.defaultCodexModelKey)

        let agent = Agent(name: "System Agent")
        let session = Session(agent: agent, workingDirectory: "/tmp")

        XCTAssertEqual(agent.provider, ProviderSelection.system.rawValue)
        XCTAssertEqual(agent.model, AgentDefaults.inheritMarker)
        XCTAssertEqual(session.provider, ProviderSelection.codex.rawValue)
        XCTAssertEqual(session.model, CodexModel.gpt5Codex.rawValue)
    }

    func testExplicitAgentProviderUsesProviderSpecificDefaultModelWhenModelInherits() {
        AppSettings.store.set(ProviderSelection.claude.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set(ClaudeModel.haiku.rawValue, forKey: AppSettings.defaultClaudeModelKey)

        let agent = Agent(
            name: "Claude Agent",
            provider: ProviderSelection.claude.rawValue,
            model: AgentDefaults.inheritMarker
        )
        let session = Session(agent: agent, workingDirectory: "/tmp")

        XCTAssertEqual(session.provider, ProviderSelection.claude.rawValue)
        XCTAssertEqual(session.model, ClaudeModel.haiku.rawValue)
    }

    func testSessionOverrideTakesPrecedenceOverAgentAndSystemProviderDefaults() {
        AppSettings.store.set(ProviderSelection.claude.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set(ClaudeModel.sonnet.rawValue, forKey: AppSettings.defaultClaudeModelKey)
        AppSettings.store.set(CodexModel.gpt5Codex.rawValue, forKey: AppSettings.defaultCodexModelKey)

        let agent = Agent(
            name: "Inherited Agent",
            provider: ProviderSelection.system.rawValue,
            model: AgentDefaults.inheritMarker
        )

        let effectiveProvider = AgentDefaults.resolveEffectiveProvider(
            sessionOverride: ProviderSelection.codex.rawValue,
            agentSelection: agent.provider
        )
        let effectiveModel = AgentDefaults.resolveEffectiveModel(
            sessionOverride: AgentDefaults.inheritMarker,
            agentSelection: agent.model,
            provider: effectiveProvider
        )

        XCTAssertEqual(effectiveProvider, ProviderSelection.codex.rawValue)
        XCTAssertEqual(effectiveModel, CodexModel.gpt5Codex.rawValue)
    }

    func testIncompatibleExplicitModelFallsBackToEffectiveProviderDefault() {
        AppSettings.store.set(ProviderSelection.codex.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set(CodexModel.gpt5Codex.rawValue, forKey: AppSettings.defaultCodexModelKey)

        let agent = Agent(
            name: "Codex Agent",
            provider: ProviderSelection.codex.rawValue,
            model: ClaudeModel.opus.rawValue
        )
        let session = Session(agent: agent, workingDirectory: "/tmp")

        XCTAssertEqual(session.provider, ProviderSelection.codex.rawValue)
        XCTAssertEqual(session.model, CodexModel.gpt5Codex.rawValue)
    }

    func testSessionModelOverrideBeatsAgentModelWhenCompatible() {
        AppSettings.store.set(ProviderSelection.claude.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set(ClaudeModel.sonnet.rawValue, forKey: AppSettings.defaultClaudeModelKey)

        let resolved = AgentDefaults.resolveEffectiveModel(
            sessionOverride: ClaudeModel.opus.rawValue,
            agentSelection: ClaudeModel.haiku.rawValue,
            provider: ProviderSelection.claude.rawValue
        )

        XCTAssertEqual(resolved, ClaudeModel.opus.rawValue)
    }

    func testSessionModelOverrideFallsBackWhenIncompatibleWithEffectiveProvider() {
        AppSettings.store.set(ProviderSelection.codex.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set(CodexModel.gpt5Codex.rawValue, forKey: AppSettings.defaultCodexModelKey)

        let resolved = AgentDefaults.resolveEffectiveModel(
            sessionOverride: ClaudeModel.opus.rawValue,
            agentSelection: ClaudeModel.haiku.rawValue,
            provider: ProviderSelection.codex.rawValue
        )

        XCTAssertEqual(resolved, CodexModel.gpt5Codex.rawValue)
    }

    func testProvisionerUsesSessionEffectiveProviderAndModel() {
        AppSettings.store.set(ProviderSelection.claude.rawValue, forKey: AppSettings.defaultProviderKey)

        let agent = Agent(name: "Resolver", model: ClaudeModel.sonnet.rawValue)
        context.insert(agent)

        let session = Session(agent: agent, mission: "Ship it", workingDirectory: "/tmp/work")
        session.provider = ProviderSelection.codex.rawValue
        session.model = CodexModel.gpt5Codex.rawValue

        let provisioner = AgentProvisioner(modelContext: context)
        let config = provisioner.config(for: session)

        XCTAssertEqual(config?.provider, ProviderSelection.codex.rawValue)
        XCTAssertEqual(config?.model, CodexModel.gpt5Codex.rawValue)
        XCTAssertEqual(config?.workingDirectory, "/tmp/work")
    }

    func testPeerWireProviderDefaultsToSystemWhenMissing() throws {
        let data = """
        {
          "id":"DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF",
          "name":"PeerAgent",
          "agentDescription":"desc",
          "systemPrompt":"prompt",
          "model":"sonnet",
          "icon":"cpu",
          "color":"blue",
          "skillNames":[],
          "extraMCPNames":[]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WireAgentExport.self, from: data)
        XCTAssertEqual(decoded.provider, ProviderSelection.system.rawValue)
    }

    func testConfigDTOProviderDefaultsToSystemWhenMissing() throws {
        let data = """
        {
          "name":"ConfigAgent",
          "enabled":true,
          "agentDescription":"desc",
          "model":"sonnet",
          "icon":"cpu",
          "color":"blue",
          "skillNames":[],
          "mcpServerNames":[],
          "permissionSetName":"Full Access"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AgentConfigDTO.self, from: data)
        XCTAssertEqual(decoded.provider, ProviderSelection.system.rawValue)
    }

    func testResetAllClearsProviderAndPerProviderModelDefaults() {
        AppSettings.store.set(ProviderSelection.codex.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set(ClaudeModel.haiku.rawValue, forKey: AppSettings.defaultClaudeModelKey)
        AppSettings.store.set(CodexModel.gpt5Codex.rawValue, forKey: AppSettings.defaultCodexModelKey)

        AppSettings.resetAll()

        XCTAssertNil(AppSettings.store.string(forKey: AppSettings.defaultProviderKey))
        XCTAssertNil(AppSettings.store.string(forKey: AppSettings.defaultClaudeModelKey))
        XCTAssertNil(AppSettings.store.string(forKey: AppSettings.defaultCodexModelKey))
    }
}
