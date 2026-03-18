#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const os = require("os");
const { execFileSync } = require("child_process");

function fail(message) {
  console.error(message);
  process.exit(1);
}

function expandHome(value) {
  if (!value) return value;
  if (value === "~") return os.homedir();
  if (value.startsWith("~/")) return path.join(os.homedir(), value.slice(2));
  return value;
}

function parseArgs(argv) {
  const options = {
    repo: null,
    activeRoot: null,
    startDate: "2025-01-01",
    endDate: new Date().toISOString().slice(0, 10),
    json: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    switch (arg) {
      case "--repo":
        options.repo = argv[++i];
        break;
      case "--active-root":
        options.activeRoot = argv[++i];
        break;
      case "--start":
        options.startDate = argv[++i];
        break;
      case "--end":
        options.endDate = argv[++i];
        break;
      case "--json":
        options.json = true;
        break;
      case "-h":
      case "--help":
        printHelp();
        process.exit(0);
        break;
      default:
        fail(`Unknown argument: ${arg}`);
    }
  }

  return options;
}

function printHelp() {
  console.log(`Usage:
  node scripts/openclaw/session-costs.cjs [--repo <path>] [--start YYYY-MM-DD] [--end YYYY-MM-DD] [--json]
  node scripts/openclaw/session-costs.cjs --active-root <path> [--start YYYY-MM-DD] [--end YYYY-MM-DD] [--json]

Examples:
  npm run agents:costs
  npm run agents:costs -- --start 2026-03-01 --end 2026-03-31
  npm run agents:costs:active -- --active-root ~/projects/_active
`);
}

function isDateString(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value);
}

function resolveRepoRoot(inputPath) {
  let current = path.resolve(expandHome(inputPath || process.cwd()));
  try {
    const stat = fs.statSync(current);
    if (stat.isFile()) current = path.dirname(current);
  } catch {
    fail(`Path does not exist: ${current}`);
  }

  while (true) {
    if (fs.existsSync(path.join(current, ".openclaw", "project.json"))) {
      return current;
    }
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }

  fail(`Could not find .openclaw/project.json from: ${inputPath || process.cwd()}`);
}

function loadProject(repoRoot) {
  const configPath = path.join(repoRoot, ".openclaw", "project.json");
  if (!fs.existsSync(configPath)) return null;
  const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
  const agents = Array.isArray(config.agents) ? config.agents : [];
  const slug = config.project?.slug;
  if (!slug) {
    fail(`Missing project.slug in ${configPath}`);
  }

  const normalizedAgents = agents.map((agent) => {
    const agentId = `${slug}-${agent.agent_id_suffix}`;
    return {
      key: agent.key,
      roleLabel: agent.role_label || null,
      identityName: agent.identity_name || null,
      agentId,
      sessionKey: `agent:${agentId}:main`,
    };
  });

  return {
    repoRoot,
    slug,
    name: config.project?.name || slug,
    agents: normalizedAgents,
  };
}

function scanActiveRoot(activeRootInput) {
  const activeRoot = path.resolve(expandHome(activeRootInput));
  if (!fs.existsSync(activeRoot)) {
    fail(`Active root does not exist: ${activeRoot}`);
  }

  const entries = fs.readdirSync(activeRoot, { withFileTypes: true });
  const projects = [];
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const repoRoot = path.join(activeRoot, entry.name);
    const project = loadProject(repoRoot);
    if (project) projects.push(project);
  }

  if (projects.length === 0) {
    fail(`No agent-flow projects found under: ${activeRoot}`);
  }

  return projects.sort((a, b) => a.repoRoot.localeCompare(b.repoRoot));
}

function parseGatewayJson(raw) {
  const trimmed = raw.trim();
  const lines = trimmed.split(/\r?\n/);
  if (lines[0] && lines[0].startsWith("Gateway call:")) {
    return JSON.parse(lines.slice(1).join("\n"));
  }
  return JSON.parse(trimmed);
}

function fetchUsage(startDate, endDate) {
  let stdout;
  try {
    stdout = execFileSync(
      "openclaw",
      [
        "gateway",
        "call",
        "sessions.usage",
        "--params",
        JSON.stringify({
          startDate,
          endDate,
          limit: 5000,
          includeContextWeight: true,
        }),
      ],
      { encoding: "utf8" },
    );
  } catch (error) {
    fail(`Failed to query OpenClaw usage: ${error.message}`);
  }
  return parseGatewayJson(stdout);
}

function zeroUsage() {
  return {
    totalTokens: 0,
    totalCost: 0,
    messageCounts: { total: 0, user: 0, assistant: 0, toolCalls: 0, toolResults: 0, errors: 0 },
    toolUsage: { totalCalls: 0, uniqueTools: 0, tools: [] },
    durationMs: 0,
    firstActivity: null,
    lastActivity: null,
    input: 0,
    output: 0,
    cacheRead: 0,
    cacheWrite: 0,
    inputCost: 0,
    outputCost: 0,
    cacheReadCost: 0,
    cacheWriteCost: 0,
    missingCostEntries: 0,
  };
}

function normalizeUsage(usage) {
  if (!usage) return zeroUsage();
  return {
    totalTokens: usage.totalTokens || 0,
    totalCost: usage.totalCost || 0,
    messageCounts: usage.messageCounts || zeroUsage().messageCounts,
    toolUsage: usage.toolUsage || zeroUsage().toolUsage,
    durationMs: usage.durationMs || 0,
    firstActivity: usage.firstActivity || null,
    lastActivity: usage.lastActivity || null,
    input: usage.input || 0,
    output: usage.output || 0,
    cacheRead: usage.cacheRead || 0,
    cacheWrite: usage.cacheWrite || 0,
    inputCost: usage.inputCost || 0,
    outputCost: usage.outputCost || 0,
    cacheReadCost: usage.cacheReadCost || 0,
    cacheWriteCost: usage.cacheWriteCost || 0,
    missingCostEntries: usage.missingCostEntries || 0,
  };
}

function getWorkspaceDir(session) {
  return session?.contextWeight?.workspaceDir || null;
}

function isProjectAgentSessionKey(project, key) {
  return typeof key === "string" && key.startsWith(`agent:${project.slug}-`) && key.endsWith(":main");
}

function buildProjectReport(project, sessionsByKey) {
  const configuredKeyToAgent = new Map(project.agents.map((agent) => [agent.sessionKey, agent]));

  const matchedSessions = [];
  for (const session of sessionsByKey.values()) {
    const workspaceDir = getWorkspaceDir(session);
    if (workspaceDir === project.repoRoot || configuredKeyToAgent.has(session.key) || isProjectAgentSessionKey(project, session.key)) {
      matchedSessions.push(session);
    }
  }

  const seenKeys = new Set();
  const rows = [];

  for (const agent of project.agents) {
    const session = matchedSessions.find((entry) => entry.key === agent.sessionKey) || null;
    seenKeys.add(agent.sessionKey);
    rows.push({
      type: "configured",
      agentKey: agent.key,
      agentId: agent.agentId,
      sessionKey: agent.sessionKey,
      label: agent.roleLabel || agent.key,
      usage: normalizeUsage(session?.usage),
    });
  }

  for (const session of matchedSessions) {
    if (seenKeys.has(session.key)) continue;
    seenKeys.add(session.key);

    if (isProjectAgentSessionKey(project, session.key)) {
      const agentId = session.key.slice("agent:".length, -":main".length);
      rows.push({
        type: "discovered",
        agentKey: null,
        agentId,
        sessionKey: session.key,
        label: "unconfigured",
        usage: normalizeUsage(session?.usage),
      });
      continue;
    }

    rows.push({
      type: "shared",
      agentKey: null,
      agentId: session.agentId || "shared-session",
      sessionKey: session.key,
      label: session.label || session.key,
      usage: normalizeUsage(session?.usage),
    });
  }

  rows.sort((a, b) => {
    if (b.usage.totalCost !== a.usage.totalCost) return b.usage.totalCost - a.usage.totalCost;
    return a.agentId.localeCompare(b.agentId);
  });

  const totals = rows.reduce(
    (acc, row) => {
      acc.totalTokens += row.usage.totalTokens;
      acc.totalCost += row.usage.totalCost;
      acc.totalMessages += row.usage.messageCounts.total || 0;
      acc.totalToolCalls += row.usage.toolUsage.totalCalls || 0;
      const last = row.usage.lastActivity || 0;
      const first = row.usage.firstActivity || 0;
      acc.lastActivity = Math.max(acc.lastActivity, last);
      if (first > 0) {
        acc.firstActivity = acc.firstActivity === 0 ? first : Math.min(acc.firstActivity, first);
      }
      return acc;
    },
    {
      totalTokens: 0,
      totalCost: 0,
      totalMessages: 0,
      totalToolCalls: 0,
      firstActivity: 0,
      lastActivity: 0,
    },
  );

  return {
    project: {
      name: project.name,
      slug: project.slug,
      repoRoot: project.repoRoot,
    },
    totals,
    rows,
    matchedSessionCount: matchedSessions.length,
  };
}

function formatNumber(value) {
  return new Intl.NumberFormat("en-US").format(value || 0);
}

function formatMoney(value) {
  return `$${(value || 0).toFixed(2)}`;
}

function formatTime(timestamp) {
  if (!timestamp) return "-";
  return new Date(timestamp).toISOString().replace("T", " ").replace(/\.\d{3}Z$/, "Z");
}

function printTextReport(report, startDate, endDate) {
  const grandTotals = report.projects.reduce(
    (acc, project) => {
      acc.totalTokens += project.totals.totalTokens;
      acc.totalCost += project.totals.totalCost;
      acc.totalMessages += project.totals.totalMessages;
      acc.totalToolCalls += project.totals.totalToolCalls;
      acc.totalAgents += project.rows.length;
      return acc;
    },
    { totalTokens: 0, totalCost: 0, totalMessages: 0, totalToolCalls: 0, totalAgents: 0 },
  );

  console.log(`Window: ${startDate} -> ${endDate}`);
  console.log(`Projects: ${report.projects.length}`);
  console.log(
    `Overall: ${formatNumber(grandTotals.totalTokens)} tokens | ${formatMoney(grandTotals.totalCost)} | ${formatNumber(grandTotals.totalMessages)} msgs | ${formatNumber(grandTotals.totalToolCalls)} tool calls | ${grandTotals.totalAgents} rows`,
  );

  for (const project of report.projects) {
    console.log(`\nProject: ${project.project.name} (${project.project.slug})`);
    console.log(`Root: ${project.project.repoRoot}`);
    console.log(
      `Total: ${formatNumber(project.totals.totalTokens)} tokens | ${formatMoney(project.totals.totalCost)} | ${formatNumber(project.totals.totalMessages)} msgs | ${formatNumber(project.totals.totalToolCalls)} tool calls | ${project.matchedSessionCount} matched sessions`,
    );

    if (project.rows.length === 0) {
      console.log("- No matching project sessions found in sessions.usage for this window.");
      continue;
    }

    for (const row of project.rows) {
      const typeSuffix = row.type === "discovered"
        ? " [discovered-agent]"
        : row.type === "shared"
          ? " [shared-project-session]"
          : "";
      const label = row.agentKey && row.agentKey !== row.agentId
        ? `${row.agentKey} (${row.agentId})`
        : row.agentId;
      console.log(
        `- ${label}${typeSuffix}: ${formatNumber(row.usage.totalTokens)} tok | ${formatMoney(row.usage.totalCost)} | ${formatNumber(row.usage.messageCounts.total || 0)} msgs | last ${formatTime(row.usage.lastActivity)}`,
      );
      console.log(`  session: ${row.sessionKey}`);
    }
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (!isDateString(options.startDate) || !isDateString(options.endDate)) {
    fail("--start and --end must use YYYY-MM-DD");
  }

  const projects = options.activeRoot
    ? scanActiveRoot(options.activeRoot)
    : [loadProject(resolveRepoRoot(options.repo))];

  const usagePayload = fetchUsage(options.startDate, options.endDate);
  const sessions = Array.isArray(usagePayload.sessions) ? usagePayload.sessions : [];
  const sessionsByKey = new Map(sessions.map((session) => [session.key, session]));

  const projectReports = projects.map((project) => buildProjectReport(project, sessionsByKey));
  const finalReport = {
    startDate: options.startDate,
    endDate: options.endDate,
    generatedAt: new Date().toISOString(),
    projects: projectReports,
  };

  if (options.json) {
    process.stdout.write(`${JSON.stringify(finalReport, null, 2)}\n`);
    return;
  }

  printTextReport(finalReport, options.startDate, options.endDate);
}

main();
