import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, writeFile, mkdir, rm, symlink, chmod, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { spawn } from 'node:child_process';
import { get } from 'node:http';

const serverFile = new URL('../server.mjs', import.meta.url);
const TEST_TIMEOUT = 7000;

function onceReady(child) {
  return new Promise((resolve, reject) => {
    let buffer = '';
    const onData = (chunk) => {
      buffer += chunk;
      const [line] = buffer.split('\n');
      if (!line) return;
      cleanup();
      try {
        resolve(JSON.parse(line));
      } catch (error) {
        reject(error);
      }
    };
    const onExit = (code) => {
      cleanup();
      reject(new Error(`server exited early with ${code}`));
    };
    const cleanup = () => {
      child.stdout.off('data', onData);
      child.off('exit', onExit);
    };
    child.stdout.on('data', onData);
    child.once('exit', onExit);
  });
}

function waitForExit(child) {
  if (child.exitCode !== null || child.signalCode !== null) {
    return Promise.resolve();
  }
  return new Promise((resolve) => child.once('exit', resolve));
}

async function startServer(options = {}) {
  const dir = await mkdtemp(join(tmpdir(), 'markdown-preview-'));
  const bin = join(dir, 'bin');
  await mkdir(bin);
  const log = join(dir, 'comrak.log');
  const html = join(dir, 'comrak.html');
  const fakeComrak = join(bin, 'comrak');
  await writeFile(fakeComrak, `#!/bin/sh
set -eu
printf '%s\n' "$@" > ${JSON.stringify(log)}
cat > ${JSON.stringify(join(dir, 'stdin.md'))}
stdin_contents=$(cat ${JSON.stringify(join(dir, 'stdin.md'))})
if [ -n "\${COMRAK_DELAY:-}" ]; then
  sleep "\${COMRAK_DELAY}"
fi
if [ -n "\${COMRAK_HTML:-}" ]; then
  printf '%s' "\${COMRAK_HTML}" > ${JSON.stringify(html)}
else
  printf '<article><p data-sourcepos="1:1-1:4">%s</p><img src="image.png"><pre data-sourcepos="3:1-5:4" lang="mermaid"><code>graph TD; A-->B;</code></pre><a href="https://example.com">x</a></article>' "$stdin_contents" > ${JSON.stringify(html)}
fi
cat ${JSON.stringify(html)}
`);
  await chmod(fakeComrak, 0o755);
  const sourceDir = join(dir, 'doc');
  await mkdir(sourceDir);
  await writeFile(join(sourceDir, 'note.md'), '# hi\n');
  await writeFile(join(sourceDir, 'image.png'), 'png');
  await writeFile(join(sourceDir, 'image space.png'), 'space-png');
  await writeFile(join(dir, 'outside.txt'), 'nope');
  await symlink(join(dir, 'outside.txt'), join(sourceDir, 'escape.png'));
  const mermaidJs = join(dir, 'mermaid.min.js');
  await writeFile(mermaidJs, 'globalThis.mermaid = {};');

  const child = spawn('node', [serverFile.pathname], {
    cwd: dirname(serverFile.pathname),
    env: {
      ...process.env,
      COMRAK_BIN: options.comrakBin ?? fakeComrak,
      COMRAK_DELAY: options.comrakDelay ?? '',
      MERMAID_JS: mermaidJs,
      MARKDOWN_PREVIEW_MAX_BYTES: options.maxBytes ?? '',
    },
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  let stderr = '';
  child.stderr.on('data', (chunk) => {
    stderr += chunk.toString();
  });
  const ready = await onceReady(child);
  const url = new URL(ready.url);
  const send = (message) => child.stdin.write(`${JSON.stringify(message)}\n`);
  const close = () => waitForExit(child);
  return { child, dir, url, send, log, sourceDir, close, get stderr() { return stderr; } };
}

async function fetchText(url, init) {
  const res = await fetch(url, init);
  return { res, text: await res.text() };
}

function openStream(url) {
  return new Promise((resolve, reject) => {
    const req = get(url, (res) => {
      resolve(res);
    });
    req.on('error', reject);
  });
}

function waitFor(promise, label, ms = 5000) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timeout after ${ms}ms`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

function createSseReader(res) {
  let buffer = '';
  const queue = [];
  const waiters = [];
  let doneError = null;
  const flush = () => {
    while (queue.length && waiters.length) {
      waiters.shift().resolve(queue.shift());
    }
  };
  const finish = (error) => {
    doneError = error;
    while (waiters.length) {
      waiters.shift().reject(error);
    }
  };
  res.on('data', (chunk) => {
    buffer += chunk;
    const parts = buffer.split('\n\n');
    buffer = parts.pop() || '';
    for (const part of parts) {
      const event = { type: 'message', data: '' };
      for (const line of part.split('\n')) {
        if (line.startsWith('event: ')) event.type = line.slice(7);
        if (line.startsWith('data: ')) event.data += line.slice(6);
      }
      queue.push(event);
    }
    flush();
  });
  res.once('end', () => finish(new Error('sse closed')));
  res.once('error', finish);
  return {
    nextEvent() {
      if (queue.length) {
        return Promise.resolve(queue.shift());
      }
      if (doneError) {
        return Promise.reject(doneError);
      }
      return new Promise((resolve, reject) => waiters.push({ resolve, reject }));
    },
  };
}

async function nextEventOfType(reader, type, predicate = () => true) {
  for (;;) {
    const event = await reader.nextEvent();
    if (event.type === type && predicate(event)) {
      return event;
    }
  }
}

async function shutdownServer(server) {
  if (server.child.exitCode === null && server.child.signalCode === null) {
    server.send({ type: 'shutdown' });
  }
  await waitFor(server.close(), 'server shutdown');
}

test('token rejection and ready loopback', { timeout: TEST_TIMEOUT }, async (t) => {
  const server = await startServer();
  t.after(async () => {
    await shutdownServer(server);
    await rm(server.dir, { recursive: true, force: true });
  });
  assert.equal(server.url.hostname, '127.0.0.1');
  const denied = await fetchText(new URL('/page', server.url));
  assert.equal(denied.res.status, 401);
  const ok = await fetchText(server.url);
  assert.equal(ok.res.status, 200);
  assert.match(ok.text, /client\.mjs/);
  assert.match(ok.text, /<title>Markdown Preview<\/title>/);
  assert.match(ok.text, /id="app" class="markdown-body"/);
  assert.doesNotMatch(ok.text, /<script src="\/vendor\/mermaid\.min\.js/);
  const style = await fetchText(new URL(`/style.css?token=${server.url.searchParams.get('token')}`, server.url));
  assert.equal(style.res.status, 200);
  assert.match(style.text, /\.markdown-body code/);
  assert.match(style.text, /\.markdown-alert-title/);
  assert.match(style.text, /\.syntax-highlighting \.comment/);
  assert.match(style.text, /border-left:\s*3px solid/);
  assert.doesNotMatch(style.text, /border-radius:\s*8px/);
  const mermaid = await fetchText(new URL(`/vendor/mermaid.min.js?token=${server.url.searchParams.get('token')}`, server.url));
  assert.equal(mermaid.res.status, 200);
  assert.equal(mermaid.text, 'globalThis.mermaid = {};');
});

test('stdin close shuts down the server', { timeout: TEST_TIMEOUT }, async (t) => {
  const server = await startServer();
  t.after(async () => {
    if (server.child.exitCode === null && server.child.signalCode === null) {
      server.child.kill('SIGKILL');
    }
    await server.close();
    await rm(server.dir, { recursive: true, force: true });
  });
  server.child.stdin.end();
  await waitFor(server.close(), 'stdin-close shutdown');
  assert.equal(server.child.exitCode, 0);
});

test('oversized Markdown is rejected before spawning Comrak', { timeout: TEST_TIMEOUT }, async (t) => {
  const server = await startServer();
  t.after(async () => {
    await shutdownServer(server);
    await rm(server.dir, { recursive: true, force: true });
  });
  server.send({
    type: 'render',
    seq: 1,
    markdown: 'x'.repeat(1024 * 1024 + 1),
    sourcePath: join(server.sourceDir, 'note.md'),
    root: server.sourceDir,
  });
  await new Promise((resolve) => setTimeout(resolve, 100));
  assert.match(server.stderr, /markdown input exceeded 1048576 bytes/);
  await assert.rejects(readFile(join(server.dir, 'stdin.md')), { code: 'ENOENT' });
});

test('configured Markdown limit accepts the exact boundary', { timeout: TEST_TIMEOUT }, async (t) => {
  const server = await startServer({ maxBytes: '32' });
  t.after(async () => {
    await shutdownServer(server);
    await rm(server.dir, { recursive: true, force: true });
  });
  const sse = await openStream(new URL(`/sse?token=${server.url.searchParams.get('token')}`, server.url));
  sse.setEncoding('utf8');
  const reader = createSseReader(sse);
  server.send({
    type: 'render',
    seq: 1,
    markdown: 'x'.repeat(32),
    sourcePath: join(server.sourceDir, 'note.md'),
    root: server.sourceDir,
  });
  await waitFor(nextEventOfType(reader, 'render'), 'configured-limit render');
  assert.equal(await readFile(join(server.dir, 'stdin.md'), 'utf8'), 'x'.repeat(32));
  sse.destroy();
});

test('render broadcast, cursor, asset checks, shutdown', { timeout: TEST_TIMEOUT }, async (t) => {
  const server = await startServer();
  t.after(async () => {
    await shutdownServer(server);
    await rm(server.dir, { recursive: true, force: true });
  });

  const sse = await openStream(new URL(`/sse?token=${server.url.searchParams.get('token')}`, server.url));
  assert.equal(sse.statusCode, 200);
  sse.setEncoding('utf8');
  const reader = createSseReader(sse);

  const markdown = '# hi\n\n![x](image.png)\n\n```mermaid\ngraph TD; A-->B;\n```\n';
  server.send({
    type: 'render',
    seq: 1,
    markdown,
    cursorLine: 1,
    sourcePath: join(server.sourceDir, 'note.md'),
    root: server.sourceDir,
  });

  const renderEvent = await waitFor(reader.nextEvent(), `render event; stderr=${JSON.stringify(server.stderr)}`).catch(async (error) => {
    const log = await readFile(server.log, 'utf8').catch(() => '');
    const stdin = await readFile(join(server.dir, 'stdin.md'), 'utf8').catch(() => '');
    throw new Error(`${error.message}; log=${JSON.stringify(log)}; stdin=${JSON.stringify(stdin)}`);
  });
  assert.equal(renderEvent.type, 'render');
  const payload = JSON.parse(renderEvent.data);
  assert.match(payload.html, /data-sourcepos/);
  assert.match(payload.html, /<pre data-sourcepos="3:1-5:4" lang="mermaid"><code>/);
  assert.equal(payload.cursorLine, 1);
  assert.equal(await readFile(join(server.dir, 'stdin.md'), 'utf8'), markdown);

  const page = await fetchText(new URL(`/page?token=${server.url.searchParams.get('token')}`, server.url));
  assert.equal(page.res.status, 200);

  const asset = await fetchText(new URL(`/asset?token=${server.url.searchParams.get('token')}&sourcePath=${encodeURIComponent(join(server.sourceDir, 'note.md'))}&path=${encodeURIComponent('image.png')}`, server.url));
  assert.equal(asset.res.status, 200);
  assert.equal(asset.text, 'png');

  const encodedAsset = await fetchText(new URL(`/asset?token=${server.url.searchParams.get('token')}&sourcePath=${encodeURIComponent(join(server.sourceDir, 'note.md'))}&path=${encodeURIComponent('image%20space.png')}`, server.url));
  assert.equal(encodedAsset.res.status, 200);
  assert.equal(encodedAsset.text, 'space-png');

  const traverse = await fetchText(new URL(`/asset?token=${server.url.searchParams.get('token')}&sourcePath=${encodeURIComponent(join(server.sourceDir, 'note.md'))}&path=${encodeURIComponent('../outside.txt')}`, server.url));
  assert.equal(traverse.res.status, 403);

  const escaped = await fetchText(new URL(`/asset?token=${server.url.searchParams.get('token')}&sourcePath=${encodeURIComponent(join(server.sourceDir, 'note.md'))}&path=${encodeURIComponent('escape.png')}`, server.url));
  assert.equal(escaped.res.status, 403);

  server.send({ type: 'cursor', line: 7 });
  const cursorEvent = await waitFor(nextEventOfType(reader, 'cursor', (event) => JSON.parse(event.data).line === 7), 'cursor event');
  assert.deepEqual(JSON.parse(cursorEvent.data), { line: 7 });

  sse.destroy();
  await shutdownServer(server);
});

test('real Comrak renders compact GitHub alerts without changing fenced examples', { timeout: TEST_TIMEOUT }, async (t) => {
  const server = await startServer({ comrakBin: process.env.COMRAK_BIN || 'comrak' });
  t.after(async () => {
    await shutdownServer(server);
    await rm(server.dir, { recursive: true, force: true });
  });
  const sse = await openStream(new URL(`/sse?token=${server.url.searchParams.get('token')}`, server.url));
  sse.setEncoding('utf8');
  const reader = createSseReader(sse);
  const markdown = [
    '>[!NOTE]', '> note', '',
    '>[!TIP]', '> tip', '',
    '>[!IMPORTANT]', '> important', '',
    '>[!WARNING]', '> warning', '',
    '>[!CAUTION]', '> caution', '',
    '```markdown', '```not-a-close', '>[!TIP]', '```',
  ].join('\n');
  server.send({
    type: 'render',
    seq: 1,
    markdown,
    sourcePath: join(server.sourceDir, 'note.md'),
    root: server.sourceDir,
  });
  const event = await waitFor(nextEventOfType(reader, 'render'), 'real Comrak alert render');
  const html = JSON.parse(event.data).html;
  for (const kind of ['note', 'tip', 'important', 'warning', 'caution']) {
    assert.match(html, new RegExp(`class="markdown-alert markdown-alert-${kind}"`));
  }
  assert.equal((html.match(/class="markdown-alert markdown-alert-/g) || []).length, 5);
  assert.match(html, /&gt;\[!TIP\]/);
  assert.match(html, /class="syntax-highlighting"/);
  sse.destroy();
});

test('latest wins', { timeout: TEST_TIMEOUT }, async (t) => {
  const delayed = await startServer({ comrakDelay: '0.2' });
  t.after(async () => {
    await shutdownServer(delayed);
    await rm(delayed.dir, { recursive: true, force: true });
  });
  const delayedSse = await openStream(new URL(`/sse?token=${delayed.url.searchParams.get('token')}`, delayed.url));
  delayedSse.setEncoding('utf8');
  const reader = createSseReader(delayedSse);
  const latestRoot = join(delayed.dir, 'latest');
  const latestSource = join(latestRoot, 'note.md');
  await mkdir(latestRoot);
  await writeFile(latestSource, '# latest\n');
  await writeFile(join(latestRoot, 'image.png'), 'latest-png');
  delayed.send({ type: 'render', seq: 1, markdown: 'first', sourcePath: join(delayed.sourceDir, 'note.md'), root: delayed.sourceDir });
  delayed.send({ type: 'render', seq: 2, markdown: 'second', sourcePath: latestSource, root: latestRoot });
  const event = await waitFor(reader.nextEvent(), 'latest-wins event');
  assert.equal(event.type, 'render');
  assert.match(event.data, /second/);
  const currentAsset = await fetchText(new URL(`/asset?token=${delayed.url.searchParams.get('token')}&sourcePath=${encodeURIComponent(latestSource)}&path=image.png`, delayed.url));
  assert.equal(currentAsset.res.status, 200);
  assert.equal(currentAsset.text, 'latest-png');
  const staleAsset = await fetchText(new URL(`/asset?token=${delayed.url.searchParams.get('token')}&sourcePath=${encodeURIComponent(join(delayed.sourceDir, 'note.md'))}&path=image.png`, delayed.url));
  assert.equal(staleAsset.res.status, 404);
  delayedSse.destroy();
});
