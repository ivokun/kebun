import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { CheckpointStore } from "./checkpoint-store.js";
/**
 * Registers all Excalidraw tools and resources on the given McpServer.
 * Shared between local (main.ts) and Vercel (api/mcp.ts) entry points.
 */
export declare function registerTools(server: McpServer, distDir: string, store: CheckpointStore): void;
/**
 * Creates a new MCP server instance with Excalidraw drawing tools.
 * Used by local entry point (main.ts) and Docker deployments.
 */
export declare function createServer(store: CheckpointStore): McpServer;
