// agent_bridge/index.mjs — Node.js bridge invoked by ClaudeAgentSdkClient
// (aion/lib/core/agent/claude_agent_sdk_client.dart). Not part of the
// Flutter build — a plain Node/ESM script.
//
// Reads one JSON request line ({prompt, model, toolsEnabled, tools}) from
// stdin and runs it through the Claude Agent SDK's query(). Tool access
// (file edits, git, bash, MCP) is disabled unless the request sets
// toolsEnabled: true — set only by TicketsCubit's coding-execution path
// (aion-arch/changes/task-to-coding-execution-trigger/design.md §1.3); every
// other caller keeps today's text-only behavior. Independently, a non-empty
// `tools` array (AgentToolDefinition[] — see
// aion/lib/core/contracts/agent_tool_definition.dart) registers app-defined
// tools the model may call mid-run, regardless of toolsEnabled — see
// aion-arch/changes/mid-task-chat-branching/design.md §3. Writes one NDJSON
// line per resulting event to stdout:
//   {"type":"text","text":"..."}
//   {"type":"tool_use","name":"...","summary":"..."}
//   {"type":"tool_call_request","toolCallId":"...","name":"...","arguments":{...}}
//   {"type":"done","inputTokens":123,"outputTokens":456}
//   {"type":"error","message":"..."}
//   {"type":"overage","message":"..."}
// When `tools` is non-empty, stdin is kept open for the process's whole
// lifetime (rather than closed after the initial request line) so Dart can
// reply to a "tool_call_request" line with a matching
// {"toolCallId":"...","result":{...}} line — one reply per request, matched
// by toolCallId. Exactly one request per process invocation —
// ClaudeAgentSdkClient spawns a fresh process per AgentModelClient.run()
// call.

import { createSdkMcpServer, query } from '@anthropic-ai/claude-agent-sdk';
import { randomUUID } from 'node:crypto';
import { createInterface } from 'node:readline';
import { z } from 'zod';

// The MCP server name app-defined tools are registered under. The Agent
// SDK exposes MCP-server tools to the model as `mcp__<server>__<tool>` —
// used both to build the tool-enabled-off allowlist below and (implicitly)
// by the SDK's own tool-use reporting.
const AION_TOOLS_SERVER_NAME = 'aion_tools';

function emit(event) {
  process.stdout.write(`${JSON.stringify(event)}\n`);
}

// Derives a short, human-readable one-liner from a tool_use content
// block's input, for the live progress indicator (coding-execution-
// reliability-and-safety). Returns undefined for an unrecognized tool —
// ClaudeAgentSdkClient._parseLine passes that through as `null`.
// Truncated to ~120 chars: this is a live status hint, not a transcript.
function summarizeToolInput(name, input) {
  const raw =
    name === 'Read' || name === 'Write' || name === 'Edit'
      ? input?.file_path
      : name === 'Bash'
        ? input?.command
        : name === 'Grep' || name === 'Glob'
          ? input?.pattern
          : undefined;
  if (typeof raw !== 'string') return undefined;
  return raw.length > 120 ? `${raw.slice(0, 120)}…` : raw;
}

// Converts one JSON-Schema property node to its Zod equivalent. Handles
// the scalar/array/object shapes an AgentToolDefinition.inputSchema
// actually uses (see jsonSchemaToZodShape below); anything unrecognized
// falls back to z.any() rather than throwing, so an unusual property type
// degrades to unvalidated-but-still-callable instead of breaking tool
// registration entirely.
function jsonSchemaPropertyToZod(propSchema) {
  let zodType;
  switch (propSchema?.type) {
    case 'string':
      zodType = z.string();
      break;
    case 'number':
      zodType = z.number();
      break;
    case 'integer':
      zodType = z.number().int();
      break;
    case 'boolean':
      zodType = z.boolean();
      break;
    case 'array':
      zodType = z.array(
        propSchema.items ? jsonSchemaPropertyToZod(propSchema.items) : z.any(),
      );
      break;
    case 'object':
      zodType = z.object(jsonSchemaToZodShape(propSchema));
      break;
    default:
      zodType = z.any();
  }
  return propSchema?.description
    ? zodType.describe(propSchema.description)
    : zodType;
}

// Converts an AgentToolDefinition.inputSchema (draft-07-compatible JSON
// Schema — {type:'object', properties, required}, see
// aion/lib/core/contracts/agent_tool_definition.dart) into the ZodRawShape
// the Agent SDK's custom-tool mechanism expects: the SDK has no raw-
// JSON-Schema tool-input path, only Zod. A property not listed in
// `required` becomes `.optional()`.
function jsonSchemaToZodShape(schema) {
  const properties = schema?.properties ?? {};
  const required = new Set(schema?.required ?? []);
  const shape = {};
  for (const [key, propSchema] of Object.entries(properties)) {
    const zodType = jsonSchemaPropertyToZod(propSchema);
    shape[key] = required.has(key) ? zodType : zodType.optional();
  }
  return shape;
}

// Builds the in-process MCP server exposing `tools` (AgentToolDefinition[]
// as received on the request line) to query(). Each tool's handler doesn't
// resolve the call itself — it defers to `requestToolCall`, which emits a
// "tool_call_request" line and awaits the matching stdin reply (see
// startReplyListener below), per design.md §3.
function buildToolsServer(tools, requestToolCall) {
  return createSdkMcpServer({
    name: AION_TOOLS_SERVER_NAME,
    version: '1.0.0',
    tools: tools.map((toolDef) => ({
      name: toolDef.name,
      description: toolDef.description,
      inputSchema: jsonSchemaToZodShape(toolDef.inputSchema),
      handler: async (args) => {
        const result = await requestToolCall(toolDef.name, args ?? {});
        return { content: [{ type: 'text', text: JSON.stringify(result) }] };
      },
    })),
  });
}

async function readRequest() {
  const rl = createInterface({ input: process.stdin, terminal: false });
  for await (const line of rl) {
    if (line.trim().length === 0) continue;
    rl.close();
    return JSON.parse(line);
  }
  throw new Error('No request line received on stdin.');
}

// Starts a persistent stdin reader for the process's remaining lifetime,
// resolving pending tool-call promises as `{"toolCallId":...,"result":...}`
// reply lines arrive. Returns the `readline.Interface` so callers can
// `.close()` it once the run finishes — otherwise the open stdin listener
// keeps the process alive indefinitely.
function startReplyListener(pendingToolCalls) {
  const rl = createInterface({ input: process.stdin, terminal: false });
  rl.on('line', (line) => {
    if (line.trim().length === 0) return;
    let reply;
    try {
      reply = JSON.parse(line);
    } catch {
      return; // Malformed reply line — ignore rather than crash the run.
    }
    const resolve = pendingToolCalls.get(reply.toolCallId);
    if (resolve) {
      pendingToolCalls.delete(reply.toolCallId);
      resolve(reply.result ?? {});
    }
  });
  return rl;
}

async function main() {
  const {
    prompt,
    model,
    toolsEnabled,
    tools: toolDefs = [],
  } = await readRequest();

  const pendingToolCalls = new Map(); // toolCallId -> resolve(result)
  const replyListener =
    toolDefs.length > 0 ? startReplyListener(pendingToolCalls) : null;

  function requestToolCall(name, arguments_) {
    const toolCallId = randomUUID();
    return new Promise((resolve) => {
      pendingToolCalls.set(toolCallId, resolve);
      emit({
        type: 'tool_call_request',
        toolCallId,
        name,
        arguments: arguments_,
      });
    });
  }

  const toolsServer =
    toolDefs.length > 0 ? buildToolsServer(toolDefs, requestToolCall) : null;
  const aionToolNames = new Set(
    toolDefs.map((t) => `mcp__${AION_TOOLS_SERVER_NAME}__${t.name}`),
  );

  try {
    for await (const message of query({
      prompt,
      options: {
        model,
        ...(toolsServer
          ? { mcpServers: { [AION_TOOLS_SERVER_NAME]: toolsServer } }
          : {}),
        // Tool-enabled runs (Task coding-execution) get the SDK's default
        // tool set; every other caller (Settings' "Test Connection",
        // SDD-stage chats) keeps today's text-only behavior — except that
        // a non-empty `tools` request still needs its own app-defined
        // tool(s) explicitly allowlisted, since `allowedTools: []` would
        // otherwise block the MCP-backed tool too.
        ...(toolsEnabled
          ? {
              // This process has no TTY (spawned via dart:io Process with
              // piped stdio, no interactive terminal), so the SDK's default
              // 'default' permissionMode — which prompts for dangerous
              // operations like file writes — has no one to answer its
              // prompts. Confirmed empirically: without this, a tool-enabled
              // run can Read but every Edit/Write/git-write attempt is
              // denied, and the model burns its run narrating workarounds
              // instead of ever touching a file. bypassPermissions requires
              // allowDangerouslySkipPermissions: true as a companion flag.
              permissionMode: 'bypassPermissions',
              allowDangerouslySkipPermissions: true,
            }
          : { allowedTools: [...aionToolNames] }),
      },
    })) {
      if (message.type === 'assistant') {
        const content = message.message?.content ?? [];
        const text = content
          .filter((block) => block.type === 'text')
          .map((block) => block.text)
          .join('');
        // App-defined (aion_tools-backed) calls are reported via their own
        // "tool_call_request" line from requestToolCall above, not here —
        // only the provider's own file/git/bash/MCP-other tool use is
        // surfaced as "tool_use".
        for (const block of content.filter(
          (b) => b.type === 'tool_use' && !aionToolNames.has(b.name),
        )) {
          emit({
            type: 'tool_use',
            name: block.name,
            summary: summarizeToolInput(block.name, block.input),
          });
        }
        if (message.error) {
          // A real failure — `authentication_failed`, `rate_limit`,
          // `billing_error`, `invalid_request`, `server_error`, or
          // `unknown` (SDKAssistantMessageError). Observed empirically: the
          // `result` message that follows can still report
          // `subtype: 'success'` with this same text as its `result` field
          // (an undocumented SDK quirk, confirmed while wiring this up) —
          // ClaudeAgentSdkClient only honors the first terminal event in a
          // stream, so emitting this error now takes precedence over that
          // misleading later "success".
          emit({
            type: 'error',
            message: text || `Claude Agent SDK reported: ${message.error}.`,
          });
        } else if (text.length > 0) {
          emit({ type: 'text', text });
        }
      } else if (message.type === 'result') {
        if (message.subtype === 'success') {
          const usage = message.usage ?? {};
          emit({
            type: 'done',
            inputTokens: usage.input_tokens ?? null,
            outputTokens: usage.output_tokens ?? null,
          });
        } else {
          const errorMessage =
            (message.errors ?? []).join('; ') ||
            `Agent run failed: ${message.subtype}`;
          // `error_max_budget_usd` is the SDK's own structured signal for
          // Claude Code's usage-window/overage limit — the one case this
          // MVP can actually detect reliably (see proposal.md's Non-goals:
          // there's no way to check remaining budget *before* hitting it).
          if (message.subtype === 'error_max_budget_usd') {
            emit({ type: 'overage', message: errorMessage });
          }
          emit({ type: 'error', message: errorMessage });
        }
      }
    }
  } finally {
    // The process only exits once query()'s async generator finishes (a
    // `result` message, same as today). If we kept stdin open for the
    // reply round trip, that open readline listener otherwise keeps the
    // event loop alive past this point.
    replyListener?.close();
  }
}

main().catch((error) => {
  emit({ type: 'error', message: error?.message ?? String(error) });
  process.exitCode = 1;
});
