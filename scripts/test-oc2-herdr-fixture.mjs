import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { once } from "node:events";
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { setTimeout as delay } from "node:timers/promises";

const script = path.join(import.meta.dirname, "experiment-oc2-herdr-pane.mjs");
const parent = await mkdtemp(path.join(tmpdir(), "oc2-herdr-fixture-"));
const binary = path.join(parent, "fake-server");
const run = (...args) => spawnSync(process.execPath, [script, ...args], { encoding: "utf8" });
function startOwner() {
  const child = spawn(process.execPath, [script, "--serve"], {
    env: { ...process.env, OPENCODE_V2_BIN: binary, OPENCODE_EXPERIMENT_ROOT: parent,
      OPENCODE_EXPERIMENT_WORKTREE: path.dirname(import.meta.dirname), OPENCODE_EXPERIMENT_HERDR_PLUGIN: "none" },
    stdio: ["ignore", "pipe", "inherit"],
  });
  const root = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Fixture did not register")), 5000);
    child.stdout.on("data", (chunk) => {
      const match = chunk.toString().match(/EXPERIMENT_DIR=(.+)\n/);
      if (match) { clearTimeout(timer); resolve(match[1]); }
    });
    child.once("exit", () => reject(new Error("Fixture exited before registration")));
  });
  return { child, root };
}
let unrelated;
let owner;
let serverPid;
let serverDead = false;
let other;
let otherPid;
let otherDead = false;

try {
  unrelated = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)", "experiment-oc2-herdr-pane.mjs --serve"]);
  await once(unrelated, "spawn");
  await delay(50);
  const ps = spawnSync("ps", ["-o", "lstart=", "-o", "command=", "-p", String(unrelated.pid)], { encoding: "utf8" });
  assert.equal(ps.status, 0);
  const fake = path.join(parent, "registration.json");
  await writeFile(fake, JSON.stringify({ owner: unrelated.pid, ownerIdentity: ps.stdout.trim(), root: parent }));
  assert.notEqual(run("--stop", parent).status, 0);
  process.kill(unrelated.pid, 0);
  await rm(fake);

  await writeFile(binary, `#!/usr/bin/env node
import { writeFileSync } from "node:fs";
import path from "node:path";
writeFileSync(path.join(process.env.HOME, "server.pid"), String(process.pid));
process.on("SIGTERM", () => {});
process.stdin.resume();
console.log(JSON.stringify({ url: "http://127.0.0.1:1" }));
`, { mode: 0o700 });
  const first = startOwner();
  owner = first.child;
  const root = await first.root;
  serverPid = Number(await readFile(path.join(root, "server.pid"), "utf8"));
  const forgedRoot = path.join(parent, "forged-root");
  await mkdir(forgedRoot);
  const registration = JSON.parse(await readFile(path.join(root, "registration.json"), "utf8"));
  await writeFile(path.join(forgedRoot, "registration.json"), JSON.stringify({ ...registration, root: forgedRoot }));
  assert.notEqual(run("--stop", forgedRoot).status, 0);
  process.kill(owner.pid, 0);
  await rm(forgedRoot, { recursive: true });

  const second = startOwner();
  other = second.child;
  const otherRoot = await second.root;
  otherPid = Number(await readFile(path.join(otherRoot, "server.pid"), "utf8"));
  const otherState = JSON.parse(await readFile(path.join(otherRoot, "registration.json"), "utf8"));
  const forgedConfig = JSON.parse(registration.config);
  forgedConfig.providers.probe.settings.baseURL = JSON.parse(otherState.config).providers.probe.settings.baseURL;
  await writeFile(path.join(root, "registration.json"), JSON.stringify({ ...registration,
    config: JSON.stringify(forgedConfig), password: otherState.password }));
  assert.notEqual(run("--stop", root).status, 0);
  process.kill(owner.pid, 0);
  process.kill(other.pid, 0);
  await writeFile(path.join(root, "registration.json"), JSON.stringify(registration));
  await writeFile(path.join(otherRoot, "registration.json"), JSON.stringify({ ...otherState,
    owner: registration.owner, ownerIdentity: registration.ownerIdentity }));
  const otherExited = once(other, "exit");
  assert.equal(run("--stop", otherRoot).status, 0);
  assert.equal((await otherExited)[0], 0);
  assert.throws(() => process.kill(otherPid, 0), { code: "ESRCH" });
  otherDead = true;
  process.kill(owner.pid, 0);

  const ownerExited = once(owner, "exit");
  assert.equal(run("--stop", root).status, 0);
  assert.equal((await ownerExited)[0], 0);
  assert.throws(() => process.kill(serverPid, 0), { code: "ESRCH" });
  serverDead = true;
  assert.deepEqual((await readdir(parent)).sort(), ["fake-server"]);

  const failed = spawnSync(process.execPath, [script, "--serve"], {
    env: { ...process.env, OPENCODE_V2_BIN: path.join(parent, "missing"), OPENCODE_EXPERIMENT_ROOT: parent,
      OPENCODE_EXPERIMENT_WORKTREE: path.dirname(import.meta.dirname), OPENCODE_EXPERIMENT_HERDR_PLUGIN: "none" },
    encoding: "utf8", timeout: 5000,
  });
  assert.notEqual(failed.status, 0);
  assert.deepEqual(await readdir(parent), ["fake-server"]);
  console.log("OC2 Herdr fixture stop and cleanup: ok");
} finally {
  if (owner && owner.exitCode === null && owner.signalCode === null) owner.kill("SIGKILL");
  if (other && other.exitCode === null && other.signalCode === null) other.kill("SIGKILL");
  if (serverPid && !serverDead) {
    const command = spawnSync("ps", ["-o", "command=", "-p", String(serverPid)], { encoding: "utf8" });
    if (command.status === 0 && command.stdout.includes(binary)) process.kill(serverPid, "SIGKILL");
  }
  if (otherPid && !otherDead) {
    const command = spawnSync("ps", ["-o", "command=", "-p", String(otherPid)], { encoding: "utf8" });
    if (command.status === 0 && command.stdout.includes(binary)) process.kill(otherPid, "SIGKILL");
  }
  if (unrelated && unrelated.exitCode === null && unrelated.signalCode === null) unrelated.kill("SIGKILL");
  await rm(parent, { recursive: true, force: true });
}
