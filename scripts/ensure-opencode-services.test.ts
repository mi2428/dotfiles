import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { it } from "bun:test";

it("preserves live service credentials, including when validation fails", () => {
  const root = mkdtempSync(path.join(tmpdir(), "opencode-services-"));
  const run = () => spawnSync("sh", [path.join(import.meta.dir, "ensure-opencode-services.sh"), root]);
  try {
    assert.equal(run().status, 0);
    const file = path.join(root, "herdr/opencode/service.json");
    assert.equal(statSync(file).mode & 0o777, 0o600);
    for (const port of [4098, 4100]) {
      const contents = JSON.stringify({ port, password: "test-only" });
      writeFileSync(file, contents);
      const before = statSync(file);
      assert.equal(run().status, port === 4098 ? 0 : 78);
      assert.equal(readFileSync(file, "utf8"), contents);
      assert.equal(statSync(file).ino, before.ino);
      assert.equal(statSync(file).mtimeMs, before.mtimeMs);
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
