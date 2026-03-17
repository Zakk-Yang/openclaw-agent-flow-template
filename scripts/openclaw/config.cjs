#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const rootDir = path.resolve(__dirname, "../..");
const configPath = path.join(rootDir, ".openclaw", "project.json");

if (!fs.existsSync(configPath)) {
  console.error(`Missing config: ${configPath}`);
  process.exit(1);
}

const config = JSON.parse(fs.readFileSync(configPath, "utf8"));

function fail(message) {
  console.error(message);
  process.exit(1);
}

function print(value) {
  if (value === undefined || value === null) {
    process.exit(1);
  }
  if (typeof value === "object") {
    process.stdout.write(JSON.stringify(value, null, 2));
    return;
  }
  process.stdout.write(String(value));
}

function findAgent(key) {
  const agent = (config.agents || []).find((entry) => entry.key === key);
  if (!agent) fail(`Unknown agent key: ${key}`);
  return agent;
}

const [command, ...args] = process.argv.slice(2);

switch (command) {
  case "project":
    print(config.project?.[args[0]]);
    break;
  case "agent":
    print(findAgent(args[0])?.[args[1]]);
    break;
  case "agent-keys":
    for (const agent of config.agents || []) {
      process.stdout.write(`${agent.key}\n`);
    }
    break;
  case "agent-paths":
    for (const entry of findAgent(args[0]).focus_paths || []) {
      process.stdout.write(`${entry}\n`);
    }
    break;
  case "agent-id":
    print(`${config.project.slug}-${findAgent(args[0]).agent_id_suffix}`);
    break;
  case "root":
    print(rootDir);
    break;
  default:
    fail("Usage: node scripts/openclaw/config.cjs <project|agent|agent-keys|agent-paths|agent-id|root> ...");
}
