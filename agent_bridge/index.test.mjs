// agent_bridge/index.test.mjs — regression coverage for buildQueryOptions
// (index.mjs). Run via `npm test` (node --test). Added for AIO-2954: a
// `toolsEnabled: false` request must actually restrict the SDK's available
// tool set via `options.tools`, not merely skip the permission prompt for an
// otherwise-unrestricted default toolset via `options.allowedTools` — the
// bug this file exists to catch before it reaches a live run again. Extended
// for AIO-2962: a `toolsEnabled: false, readOnlyTools: true` request (SDD-
// stage chats) must get Read/Grep/Glob back on top of that restriction, not
// stay fully text-only.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildQueryOptions } from './index.mjs';

test('toolsEnabled: false restricts the built-in tool set via `tools`, not `allowedTools`', () => {
  const options = buildQueryOptions({
    model: 'claude-sonnet-5',
    resume: undefined,
    forkSession: undefined,
    toolsServer: {},
    toolsEnabled: false,
    aionToolNames: new Set([
      'mcp__aion_tools__create_ticket',
      'mcp__aion_tools__add_link',
    ]),
  });

  assert.deepEqual(options.tools, [
    'mcp__aion_tools__create_ticket',
    'mcp__aion_tools__add_link',
  ]);
  assert.equal('allowedTools' in options, false);
  assert.equal('permissionMode' in options, false);
  assert.equal('allowDangerouslySkipPermissions' in options, false);
});

test('toolsEnabled: false with no app-defined tools fully disables the built-in tool set', () => {
  const options = buildQueryOptions({
    model: 'claude-sonnet-5',
    resume: undefined,
    forkSession: undefined,
    toolsServer: null,
    toolsEnabled: false,
    aionToolNames: new Set(),
  });

  assert.deepEqual(options.tools, []);
  assert.equal('mcpServers' in options, false);
});

test('toolsEnabled: true grants the SDK default tool set via bypassPermissions, not `tools`', () => {
  const options = buildQueryOptions({
    model: 'claude-sonnet-5',
    resume: undefined,
    forkSession: undefined,
    toolsServer: null,
    toolsEnabled: true,
    aionToolNames: new Set(),
  });

  assert.equal(options.permissionMode, 'bypassPermissions');
  assert.equal(options.allowDangerouslySkipPermissions, true);
  assert.equal('tools' in options, false);
  assert.equal('allowedTools' in options, false);
});

test('toolsEnabled: false, readOnlyTools: true grants Read/Grep/Glob on top of the app-defined tools', () => {
  const options = buildQueryOptions({
    model: 'claude-sonnet-5',
    resume: undefined,
    forkSession: undefined,
    toolsServer: {},
    toolsEnabled: false,
    readOnlyTools: true,
    aionToolNames: new Set(['mcp__aion_tools__create_ticket']),
  });

  assert.deepEqual(options.tools, [
    'Read',
    'Grep',
    'Glob',
    'mcp__aion_tools__create_ticket',
  ]);
  assert.equal('allowedTools' in options, false);
  assert.equal('permissionMode' in options, false);
});

test('toolsEnabled: false, readOnlyTools: true with no app-defined tools still grants only Read/Grep/Glob', () => {
  const options = buildQueryOptions({
    model: 'claude-sonnet-5',
    resume: undefined,
    forkSession: undefined,
    toolsServer: null,
    toolsEnabled: false,
    readOnlyTools: true,
    aionToolNames: new Set(),
  });

  assert.deepEqual(options.tools, ['Read', 'Grep', 'Glob']);
});

test('toolsEnabled: true ignores readOnlyTools — the bypassPermissions grant is already a superset', () => {
  const options = buildQueryOptions({
    model: 'claude-sonnet-5',
    resume: undefined,
    forkSession: undefined,
    toolsServer: null,
    toolsEnabled: true,
    readOnlyTools: true,
    aionToolNames: new Set(),
  });

  assert.equal(options.permissionMode, 'bypassPermissions');
  assert.equal('tools' in options, false);
});

test('resume/forkSession and mcpServers are threaded through unchanged regardless of toolsEnabled', () => {
  const toolsServer = { name: 'aion_tools' };
  const options = buildQueryOptions({
    model: 'claude-sonnet-5',
    resume: 'session-123',
    forkSession: true,
    toolsServer,
    toolsEnabled: false,
    aionToolNames: new Set(['mcp__aion_tools__branch_ticket']),
  });

  assert.equal(options.resume, 'session-123');
  assert.equal(options.forkSession, true);
  assert.equal(options.mcpServers.aion_tools, toolsServer);
});
