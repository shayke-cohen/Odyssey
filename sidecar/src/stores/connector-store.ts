import type {
  ConnectorCapability,
  ConnectorConfig,
  ConnectorCredentials,
  ConnectorProvider,
} from "../types.js";
import { providerCapabilitiesForConnection } from "../connectors/provider-catalog.js";

export interface RuntimeConnectorState {
  connection: ConnectorConfig;
  credentials?: ConnectorCredentials;
}

export class ConnectorStore {
  private readonly connections = new Map<string, RuntimeConnectorState>();

  list(): RuntimeConnectorState[] {
    return Array.from(this.connections.values()).sort((left, right) =>
      left.connection.displayName.localeCompare(right.connection.displayName),
    );
  }

  listConfigs(): ConnectorConfig[] {
    return this.list().map((entry) => ({ ...entry.connection }));
  }

  get(connectionId: string): RuntimeConnectorState | undefined {
    return this.connections.get(connectionId);
  }

  findByProvider(provider: ConnectorProvider): RuntimeConnectorState[] {
    return this.list().filter((entry) => entry.connection.provider === provider);
  }

  upsert(connection: ConnectorConfig, credentials?: ConnectorCredentials): RuntimeConnectorState {
    const current = this.connections.get(connection.id);
    const next: RuntimeConnectorState = {
      connection: { ...connection },
      credentials: credentials ?? current?.credentials,
    };
    this.connections.set(connection.id, next);
    return next;
  }

  markAuthorizing(connection: ConnectorConfig): RuntimeConnectorState {
    return this.upsert({
      ...connection,
      status: "authorizing",
      lastCheckedAt: connection.lastCheckedAt ?? new Date().toISOString(),
    });
  }

  revoke(connectionId: string): RuntimeConnectorState | undefined {
    const current = this.connections.get(connectionId);
    if (!current) {
      return undefined;
    }
    const next: RuntimeConnectorState = {
      connection: {
        ...current.connection,
        status: "revoked",
        statusMessage: "Credentials removed.",
        lastCheckedAt: new Date().toISOString(),
      },
    };
    this.connections.set(connectionId, next);
    return next;
  }

  capabilitiesForSession(): ConnectorCapability[] {
    return this.list()
      .flatMap((entry) => providerCapabilitiesForConnection(entry.connection))
      .sort((left, right) => left.toolName.localeCompare(right.toolName));
  }
}
