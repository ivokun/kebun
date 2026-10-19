import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import { publicError } from "./errors.js";
import { callRequestSchema, localRequest } from "./http.js";
import { readOnlyTools, toolNames, toolSchemas, validateToolResult } from "./memory-service.js";

const descriptions: Record<string, string> = {
  create_entities: "Create scoped entities and initial observations. Existing names are complete no-ops. Provenance is required.",
  create_relations: "Add scoped directed relations with provenance; identical active relations are no-ops.",
  add_observations: "Add curated scoped observations to existing entities, with provenance.",
  delete_entities: "Retract only the currently observed assertions for scoped entities and their connected relations.",
  delete_relations: "Retract only currently observed matching scoped relation assertions.",
  delete_observations: "Retract only currently observed matching scoped observation assertions.",
  remember: "Atomically ensure a scoped entity and add one curated observation. Supersedes names active observation IDs for a correction; provenance is required.",
  read_graph: "Read a complete scoped graph, including active assertion IDs, provenance, and type conflicts. Prefer search_nodes or open_nodes for recall.",
  search_nodes: "Search entity names, types, and observations within one explicit scope; prefer this to full-graph recall.",
  open_nodes: "Read selected named entities and their internal relations within one explicit scope.",
};

/** Stateless stdio adapter. It never imports or opens LocalStore or the datadir. */
export async function startMcp(socket: string): Promise<McpServer> {
  const server = new McpServer({ name: "kebun-memory", version: "0.1.0" }, { maxToolInputElements: 25_000 });
  for (const name of toolNames) {
    const readOnly = readOnlyTools.has(name);
    server.registerTool(name, {
      description: descriptions[name] ?? name,
      inputSchema: toolSchemas[name],
      annotations: { readOnlyHint: readOnly, destructiveHint: !readOnly, idempotentHint: name !== "remember", openWorldHint: false },
    }, async (arguments_: unknown): Promise<CallToolResult> => {
      try {
        const call = callRequestSchema.parse({ tool: name, arguments: arguments_ });
        const result = validateToolResult(name, await localRequest(socket, "POST", "/v1/call", call));
        return { content: [{ type: "text", text: JSON.stringify(result) }] };
      } catch (error) {
        const safe = publicError(error);
        return { isError: true, content: [{ type: "text", text: JSON.stringify({ error: { code: safe.code, message: safe.message } }) }] };
      }
    });
  }
  await server.connect(new StdioServerTransport());
  return server;
}
