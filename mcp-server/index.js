#!/usr/bin/env node
// Local MCP server for InkList (see ~/inklist, the Flutter/Android app).
// Bridges MCP tool calls to InkList's in-app HTTP bridge (see
// lib/services/mcp_bridge_service.dart) over the local Wi-Fi network — the
// phone must have "Enable Local API for Claude" on in Settings, on the same
// network as whatever runs this. See README.md for setup.

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';

const HOST = process.env.INKLIST_HOST;
const PORT = process.env.INKLIST_PORT || '8787';
const TOKEN = process.env.INKLIST_TOKEN;

if (!HOST || !TOKEN) {
  console.error(
    'INKLIST_HOST and INKLIST_TOKEN environment variables are required. ' +
      'Find both in the InkList app: Settings -> Claude Connector.',
  );
  process.exit(1);
}

const BASE_URL = `http://${HOST}:${PORT}`;

async function bridgeFetch(path, options = {}) {
  const resp = await fetch(`${BASE_URL}${path}`, {
    ...options,
    headers: {
      authorization: `Bearer ${TOKEN}`,
      'content-type': 'application/json',
      ...options.headers,
    },
    signal: AbortSignal.timeout(10_000),
  });
  const text = await resp.text();
  let body;
  try {
    body = text ? JSON.parse(text) : {};
  } catch {
    body = { raw: text };
  }
  if (!resp.ok) {
    throw new Error(body?.error || `InkList bridge returned HTTP ${resp.status}`);
  }
  return body;
}

// A single unreachable call (phone off, wrong IP, bridge disabled) must
// never crash this process -- every tool catches and reports instead.
function toolError(err) {
  return {
    content: [
      {
        type: 'text',
        text:
          `InkList connector error: ${err.message}. Check that InkList is ` +
          'open on the phone, "Enable Local API for Claude" is on in ' +
          'Settings, and INKLIST_HOST/INKLIST_TOKEN are current.',
      },
    ],
    isError: true,
  };
}

function toolOk(data) {
  return { content: [{ type: 'text', text: JSON.stringify(data, null, 2) }] };
}

const server = new McpServer({ name: 'inklist', version: '1.0.0' });

server.registerTool(
  'inklist_list_tasks',
  {
    title: 'List InkList tasks',
    description:
      'Lists tasks from InkList. scope "today" (default) returns today\'s ' +
      'and overdue tasks, "overdue" returns only overdue tasks, "all" ' +
      'returns every task.',
    inputSchema: {
      scope: z.enum(['today', 'overdue', 'all']).optional(),
    },
  },
  async ({ scope }) => {
    try {
      const data = await bridgeFetch(`/tasks?scope=${scope ?? 'today'}`);
      return toolOk(data.tasks);
    } catch (err) {
      return toolError(err);
    }
  },
);

server.registerTool(
  'inklist_create_task',
  {
    title: 'Create an InkList task',
    description:
      'Creates a new task in InkList. dueDate is an ISO date (yyyy-MM-dd), ' +
      'defaults to today. time is 24-hour "HH:mm"; if given, a real alarm ' +
      "is scheduled on the phone. recurrence follows InkList's grammar: " +
      '"none" (default), "daily", "weekly:MON,WED,FRI", "monthly:15", or ' +
      '"monthly:last".',
    inputSchema: {
      title: z.string().min(1),
      description: z.string().optional(),
      dueDate: z.string().optional(),
      time: z.string().optional(),
      priority: z.enum(['low', 'medium', 'high']).optional(),
      recurrence: z.string().optional(),
    },
  },
  async (args) => {
    try {
      const data = await bridgeFetch('/tasks', {
        method: 'POST',
        body: JSON.stringify(args),
      });
      return toolOk(data.task);
    } catch (err) {
      return toolError(err);
    }
  },
);

server.registerTool(
  'inklist_complete_task',
  {
    title: 'Complete an InkList task',
    description:
      'Marks a task done for a given day (defaults to today). Idempotent ' +
      '-- calling it again on an already-completed task is a no-op, it ' +
      'never un-completes.',
    inputSchema: {
      id: z.string().min(1),
      day: z.string().optional(),
    },
  },
  async ({ id, day }) => {
    try {
      const data = await bridgeFetch(`/tasks/${encodeURIComponent(id)}/complete`, {
        method: 'POST',
        body: JSON.stringify(day ? { day } : {}),
      });
      return toolOk(data);
    } catch (err) {
      return toolError(err);
    }
  },
);

server.registerTool(
  'inklist_list_habits',
  {
    title: 'List InkList habits',
    description:
      "Lists tracked habits with each one's current streak and whether " +
      "it's done today.",
    inputSchema: {},
  },
  async () => {
    try {
      const data = await bridgeFetch('/habits');
      return toolOk(data.habits);
    } catch (err) {
      return toolError(err);
    }
  },
);

server.registerTool(
  'inklist_behavior_snapshot',
  {
    title: 'InkList behavior snapshot',
    description:
      "The same 14-day behavioral summary InkList's own AI features use: " +
      'completion rates by weekday/priority, recurring tasks that keep ' +
      'getting missed, habit streaks, and Pomodoro focus patterns.',
    inputSchema: {},
  },
  async () => {
    try {
      const data = await bridgeFetch('/behavior');
      return toolOk(data);
    } catch (err) {
      return toolError(err);
    }
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
console.error(`InkList MCP server connected (bridge at ${BASE_URL}).`);
