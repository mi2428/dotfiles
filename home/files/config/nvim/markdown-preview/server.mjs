import { createServer } from 'node:http';
import { createReadStream, promises as fs } from 'node:fs';
import { dirname, extname, join, resolve, relative, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';

const here = dirname(fileURLToPath(import.meta.url));
const COMRAK_BIN = process.env.COMRAK_BIN || 'comrak';
const MERMAID_JS = process.env.MERMAID_JS || join(here, 'vendor', 'mermaid.min.js');
const DEFAULT_MAX_MARKDOWN_INPUT_BYTES = 1024 * 1024;
const configuredMaxMarkdownBytes = Number(process.env.MARKDOWN_PREVIEW_MAX_BYTES);
const MAX_MARKDOWN_INPUT_BYTES = Number.isSafeInteger(configuredMaxMarkdownBytes) && configuredMaxMarkdownBytes > 0
  ? configuredMaxMarkdownBytes
  : DEFAULT_MAX_MARKDOWN_INPUT_BYTES;
const MAX_RENDER_OUTPUT_BYTES = 16 * 1024 * 1024;

export const COMRAK_ARGS = [
  '--config-file',
  'none',
  '--gfm',
  '-e',
  'alerts',
  '--sourcepos',
  '--github-pre-lang',
  '--syntax-highlighting',
  'css',
  '--front-matter-delimiter=---',
];

export const ledger = { comrakArgs: [...COMRAK_ARGS] };

const token = randomBytes(16).toString('hex');
const clients = new Set();
const state = {
  current: null,
  published: null,
  currentRootReal: null,
  currentSourcePath: null,
  currentHtml: '',
  currentCursorLine: null,
  latestSeq: 0,
  active: null,
  abortController: null,
  queued: null,
  shuttingDown: false,
  shutdownPromise: null,
};

const server = createServer(handleRequest);

server.listen(0, '127.0.0.1', () => {
  const { port } = server.address();
  process.stdout.write(JSON.stringify({ type: 'ready', url: `http://127.0.0.1:${port}/page?token=${token}` }) + '\n');
});

process.stdin.setEncoding('utf8');
const stdin = createInterface({ input: process.stdin, crlfDelay: Infinity });
stdin.on('line', (line) => {
  if (!line.trim()) {
    return;
  }
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    process.stderr.write(`bad json (${Buffer.byteLength(line)} bytes)\n`);
    return;
  }
  if (message.type === 'render') {
    queueRender(message);
    return;
  }
  if (message.type === 'cursor') {
    if (Number.isInteger(message.line)) {
      state.currentCursorLine = message.line;
      broadcast('cursor', { line: message.line });
    }
    return;
  }
  if (message.type === 'shutdown') {
    void shutdown();
  }
});
stdin.on('close', () => void shutdown());

process.on('SIGINT', () => void shutdown());
process.on('SIGTERM', () => void shutdown());

function tokenOk(url) {
  return url.searchParams.get('token') === token;
}

function sendJson(res, status, body, contentType = 'application/json; charset=utf-8') {
  res.writeHead(status, {
    'content-type': contentType,
    'cache-control': 'no-store',
  });
  res.end(body);
}

function mimeFor(filePath) {
  switch (extname(filePath)) {
    case '.css': return 'text/css; charset=utf-8';
    case '.html': return 'text/html; charset=utf-8';
    case '.js':
    case '.mjs': return 'text/javascript; charset=utf-8';
    case '.json': return 'application/json; charset=utf-8';
    case '.svg': return 'image/svg+xml';
    case '.png': return 'image/png';
    case '.jpg':
    case '.jpeg': return 'image/jpeg';
    case '.gif': return 'image/gif';
    case '.webp': return 'image/webp';
    case '.ico': return 'image/x-icon';
    case '.md':
    case '.txt': return 'text/plain; charset=utf-8';
    default: return 'application/octet-stream';
  }
}

function rootHtml() {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Markdown Preview</title>
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'self' 'unsafe-inline'; script-src 'self'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; form-action 'none'">
  <link rel="stylesheet" href="/style.css?token=${token}">
  <script type="module" src="/client.mjs?token=${token}"></script>
</head>
<body>
  <main id="app" class="markdown-body" aria-live="polite"></main>
</body>
</html>`;
}

function sseWrite(res, event, data) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(data)}\n\n`);
}

function broadcast(event, data) {
  for (const res of clients) {
    sseWrite(res, event, data);
  }
}

function latestRenderPayload() {
  return {
    html: state.currentHtml,
    sourcePath: state.currentSourcePath,
    root: state.published?.root,
    cursorLine: state.currentCursorLine,
    seq: state.published?.seq,
  };
}

async function handleRequest(req, res) {
  const url = new URL(req.url, 'http://127.0.0.1');
  if (!tokenOk(url)) {
    res.writeHead(401, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });
    res.end('unauthorized');
    return;
  }

  if (req.method !== 'GET') {
    res.writeHead(405, { allow: 'GET', 'cache-control': 'no-store' });
    res.end();
    return;
  }

  if (url.pathname === '/page') {
    sendJson(res, 200, rootHtml(), 'text/html; charset=utf-8');
    return;
  }

  if (url.pathname === '/style.css') {
    streamLocalFile(res, join(here, 'style.css'));
    return;
  }

  if (url.pathname === '/client.mjs') {
    streamLocalFile(res, join(here, 'client.mjs'));
    return;
  }

  if (url.pathname === '/vendor/mermaid.min.js') {
    streamLocalFile(res, MERMAID_JS);
    return;
  }

  if (url.pathname === '/sse') {
    res.writeHead(200, {
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-cache, no-store, must-revalidate',
      connection: 'keep-alive',
      'x-accel-buffering': 'no',
    });
    res.write('\n');
    clients.add(res);
    req.on('close', () => clients.delete(res));
    if (state.currentHtml) {
      sseWrite(res, 'render', latestRenderPayload());
    }
    if (state.currentCursorLine != null) {
      sseWrite(res, 'cursor', { line: state.currentCursorLine });
    }
    return;
  }

  if (url.pathname === '/asset') {
    await handleAsset(url, res);
    return;
  }

  res.writeHead(404, { 'cache-control': 'no-store' });
  res.end('not found');
}

function streamLocalFile(res, filePath) {
  const stream = createReadStream(filePath);
  const fail = (status, body) => {
    if (res.headersSent) {
      res.destroy();
      return;
    }
    res.writeHead(status, {
      'content-type': 'text/plain; charset=utf-8',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
    });
    res.end(body);
  };
  stream.on('error', (error) => {
    fail(error?.code === 'ENOENT' ? 404 : 500, error?.code === 'ENOENT' ? 'not found' : 'failed to read file');
  });
  res.on('close', () => stream.destroy());
  stream.once('open', () => {
    if (res.destroyed) {
      stream.destroy();
      return;
    }
    res.writeHead(200, {
      'content-type': mimeFor(filePath),
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
    });
    stream.pipe(res);
  });
}

async function handleAsset(url, res) {
  if (!state.published?.root || !state.currentRootReal || !state.currentSourcePath) {
    res.writeHead(404, { 'cache-control': 'no-store' });
    res.end('no active render');
    return;
  }

  const sourcePath = url.searchParams.get('sourcePath');
  const assetPath = url.searchParams.get('path');
  if (!sourcePath || !assetPath || sourcePath !== state.currentSourcePath) {
    res.writeHead(404, { 'cache-control': 'no-store' });
    res.end('stale asset');
    return;
  }

  const baseDir = dirname(sourcePath);
  let decodedAssetPath;
  try {
    decodedAssetPath = decodeURIComponent(assetPath);
  } catch {
    res.writeHead(400, { 'cache-control': 'no-store' });
    res.end('invalid asset path');
    return;
  }
  const resolved = resolve(baseDir, decodedAssetPath);
  const resolvedReal = await fs.realpath(resolved).catch(() => null);
  if (!resolvedReal) {
    res.writeHead(404, { 'cache-control': 'no-store' });
    res.end('missing asset');
    return;
  }

  const rel = relative(state.currentRootReal, resolvedReal);
  if (rel.startsWith('..') || isAbsolute(rel)) {
    res.writeHead(403, { 'cache-control': 'no-store' });
    res.end('forbidden');
    return;
  }

  const stat = await fs.stat(resolvedReal).catch(() => null);
  if (!stat || !stat.isFile()) {
    res.writeHead(404, { 'cache-control': 'no-store' });
    res.end('missing asset');
    return;
  }

  streamLocalFile(res, resolvedReal);
}

function queueRender(message) {
  if (state.shuttingDown) {
    return;
  }
  const seq = Number(message.seq) || 0;
  const markdown = String(message.markdown ?? '');
  state.latestSeq = Math.max(state.latestSeq, seq);
  if (Buffer.byteLength(markdown) > MAX_MARKDOWN_INPUT_BYTES) {
    state.queued = null;
    process.stderr.write(`markdown input exceeded ${MAX_MARKDOWN_INPUT_BYTES} bytes\n`);
    return;
  }
  state.current = {
    seq: seq || state.latestSeq,
    markdown,
    cursorLine: Number.isInteger(message.cursorLine) ? message.cursorLine : null,
    sourcePath: String(message.sourcePath ?? ''),
    root: String(message.root ?? ''),
  };
  if (state.current.cursorLine != null) {
    state.currentCursorLine = state.current.cursorLine;
  }
  state.queued = state.current;
  if (!state.active) {
    void drainQueue();
  }
}

async function drainQueue() {
  if (state.active || !state.queued || state.shuttingDown) {
    return;
  }
  const job = state.queued;
  state.queued = null;
  state.active = job;
  const controller = new AbortController();
  state.abortController = controller;
  try {
    const rootReal = await fs.realpath(job.root);
    const html = await renderMarkdown(job.markdown, controller.signal);
    if (state.latestSeq !== job.seq) {
      return;
    }
    state.published = job;
    state.currentRootReal = rootReal;
    state.currentSourcePath = job.sourcePath;
    state.currentHtml = html;
    if (job.cursorLine != null) {
      state.currentCursorLine = job.cursorLine;
    }
    broadcast('render', latestRenderPayload());
    if (state.currentCursorLine != null) {
      broadcast('cursor', { line: state.currentCursorLine });
    }
  } catch (error) {
    if (error?.name !== 'AbortError') {
      process.stderr.write(`comrak failed: ${error.message}\n`);
    }
  } finally {
    state.active = null;
    state.abortController = null;
    if (state.queued) {
      void drainQueue();
    } else if (state.shuttingDown) {
      await finishShutdown();
    }
  }
}

function renderMarkdown(markdown, signal) {
  return new Promise((resolvePromise, rejectPromise) => {
    if (signal.aborted) {
      rejectPromise(abortError());
      return;
    }
    const child = spawn(COMRAK_BIN, COMRAK_ARGS, { shell: false, stdio: ['pipe', 'pipe', 'pipe'] });
    const stdoutChunks = [];
    const stderrChunks = [];
    let stdoutBytes = 0;
    let stderrBytes = 0;
    let pendingError = null;
    let settled = false;

    const finish = (callback) => {
      if (settled) {
        return;
      }
      settled = true;
      signal.removeEventListener('abort', onAbort);
      callback();
    };

    const stopChild = (error) => {
      pendingError ??= error;
      child.kill('SIGTERM');
    };

    const collect = (chunk, chunks, currentBytes) => {
      const nextBytes = currentBytes + Buffer.byteLength(chunk);
      if (nextBytes > MAX_RENDER_OUTPUT_BYTES) {
        stopChild(new Error(`comrak output exceeded ${MAX_RENDER_OUTPUT_BYTES} bytes`));
        return currentBytes;
      }
      chunks.push(chunk);
      return nextBytes;
    };

    function onAbort() {
      stopChild(abortError());
    }

    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', (chunk) => {
      stdoutBytes = collect(chunk, stdoutChunks, stdoutBytes);
    });
    child.stderr.on('data', (chunk) => {
      stderrBytes = collect(chunk, stderrChunks, stderrBytes);
    });
    child.on('error', (error) => {
      finish(() => rejectPromise(pendingError ?? error));
    });
    child.on('close', (code, closeSignal) => {
      const stdout = stdoutChunks.join('');
      const stderr = stderrChunks.join('');
      if (pendingError) {
        finish(() => rejectPromise(pendingError));
        return;
      }
      if (code === 0) {
        finish(() => resolvePromise(stdout));
        return;
      }
      const suffix = closeSignal ? ` (${closeSignal})` : '';
      const detail = stderr.trim();
      const error = new Error(detail ? `comrak exited with code ${code}${suffix}: ${detail}` : `comrak exited with code ${code}${suffix}`);
      error.code = code;
      error.signal = closeSignal;
      error.stderr = stderr;
      finish(() => rejectPromise(error));
    });
    child.stdin.on('error', (error) => {
      if (error?.code !== 'EPIPE') {
        stopChild(error);
      }
    });
    signal.addEventListener('abort', onAbort, { once: true });
    child.stdin.end(normalizeCompactAlerts(markdown));
  });
}

function normalizeCompactAlerts(markdown) {
  let fence;
  return markdown.split('\n').map((line) => {
    const marker = line.match(/^ {0,3}(`{3,}|~{3,})/);
    if (marker) {
      const next = { character: marker[1][0], length: marker[1].length };
      if (!fence) {
        fence = next;
      } else if (
        next.character === fence.character
        && next.length >= fence.length
        && line.slice(marker[0].length).trim() === ''
      ) {
        fence = undefined;
      }
      return line;
    }
    return fence ? line : line.replace(/^( {0,3})>(\[!(?:NOTE|TIP|IMPORTANT|WARNING|CAUTION)\])([ \t]*)$/i, '$1> $2$3');
  }).join('\n');
}

async function shutdown() {
  if (state.shuttingDown) {
    if (!state.active) {
      await finishShutdown();
    }
    return;
  }
  state.shuttingDown = true;
  stdin.close();
  state.abortController?.abort();
  if (state.active) {
    state.queued = null;
    return;
  }
  await finishShutdown();
}

function finishShutdown() {
  if (state.shutdownPromise) {
    return state.shutdownPromise;
  }
  state.shutdownPromise = (async () => {
    for (const res of clients) {
      res.end();
    }
    clients.clear();
    server.closeAllConnections?.();
    await new Promise((resolvePromise) => server.close(resolvePromise));
    process.exit(0);
  })();
  return state.shutdownPromise;
}

function abortError() {
  const error = new Error('render aborted');
  error.name = 'AbortError';
  return error;
}
