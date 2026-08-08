const token = new URL(import.meta.url).searchParams.get('token') ?? globalThis.__MARKDOWN_PREVIEW_TOKEN__ ?? 'test-token';
const app = typeof document !== 'undefined' ? document.getElementById('app') : null;
const mermaidCache = new Map();
const MERMAID_CACHE_LIMIT = 32;
export const MERMAID_SELECTOR = 'pre[lang="mermaid"] > code, code.language-mermaid';
let renderVersion = 0;
let theme = typeof window !== 'undefined' ? currentTheme() : 'light';
let latestPayload = null;
let pendingCursorLine = null;
let cursorFrame = null;
let mermaidPromise = null;

function currentTheme() {
  return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

export function assetUrl(sourcePath, relativePath) {
  const url = new URL('/asset', window.location.origin);
  url.searchParams.set('token', token);
  url.searchParams.set('sourcePath', sourcePath);
  url.searchParams.set('path', relativePath);
  return url.toString();
}

export function parseSourcepos(value) {
  const match = String(value || '').match(/^(\d+):(\d+)-(\d+):(\d+)$/);
  if (!match) {
    return null;
  }
  return {
    startLine: Number(match[1]),
    startColumn: Number(match[2]),
    endLine: Number(match[3]),
    endColumn: Number(match[4]),
  };
}

export function isExternalLink(href) {
  try {
    return new URL(href, window.location.href).origin !== window.location.origin;
  } catch {
    return false;
  }
}

function applyTheme(nextTheme = currentTheme()) {
  if (!app || typeof document === 'undefined' || typeof window === 'undefined') {
    return;
  }
  theme = nextTheme;
  document.documentElement.dataset.theme = theme;
  configureMermaid();
}

function configureMermaid() {
  if (!window.mermaid) return;
  window.mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    theme: theme === 'dark' ? 'dark' : 'default',
  });
}

function loadMermaid() {
  if (window.mermaid) return Promise.resolve(window.mermaid);
  if (mermaidPromise) return mermaidPromise;
  mermaidPromise = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = `/vendor/mermaid.min.js?token=${encodeURIComponent(token)}`;
    script.addEventListener('load', () => {
      if (!window.mermaid) {
        reject(new Error('Mermaid bundle did not initialize'));
        return;
      }
      configureMermaid();
      resolve(window.mermaid);
    }, { once: true });
    script.addEventListener('error', () => reject(new Error('Failed to load Mermaid bundle')), { once: true });
    document.head.appendChild(script);
  });
  return mermaidPromise;
}

function rewriteImages(root, sourcePath) {
  if (!sourcePath) return;
  for (const img of root.querySelectorAll('img[src]')) {
    const src = img.getAttribute('src') || '';
    if (!src || /^(?:[a-z][a-z0-9+.-]*:|\/|#)/i.test(src)) {
      continue;
    }
    img.src = assetUrl(sourcePath, src);
  }
}

function secureLinks(root) {
  for (const link of root.querySelectorAll('a[href]')) {
    const href = link.getAttribute('href') || '';
    if (!href || href.startsWith('#') || !isExternalLink(href)) {
      continue;
    }
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
    link.referrerPolicy = 'no-referrer';
  }
}

function scrollToSourcepos(root, line) {
  if (!Number.isFinite(line)) return;
  let best = null;
  for (const node of root.querySelectorAll('[data-sourcepos]')) {
    const range = parseSourcepos(node.getAttribute('data-sourcepos'));
    if (!range) continue;
    if (line >= range.startLine && line <= range.endLine) {
      best = node;
      break;
    }
    if (!best || range.startLine <= line) {
      best = node;
    }
  }
  if (best) {
    best.scrollIntoView({ block: 'center' });
  }
}

function scheduleScrollToSourcepos(root, line) {
  if (!Number.isFinite(line) || typeof window === 'undefined') return;
  pendingCursorLine = line;
  if (cursorFrame !== null) return;
  const schedule = window.requestAnimationFrame || ((fn) => window.setTimeout(fn, 16));
  cursorFrame = schedule(() => {
    cursorFrame = null;
    const nextLine = pendingCursorLine;
    pendingCursorLine = null;
    scrollToSourcepos(root, nextLine);
  });
}

function mermaidKey(code) {
  return `${theme}\0${code}`;
}

function cacheMermaid(key, svg) {
  mermaidCache.delete(key);
  mermaidCache.set(key, svg);
  if (mermaidCache.size > MERMAID_CACHE_LIMIT) {
    mermaidCache.delete(mermaidCache.keys().next().value);
  }
}

function makeMermaidHost(codeBlock) {
  const wrapper = codeBlock.closest('pre') || codeBlock.parentElement;
  if (!wrapper) return null;
  const host = document.createElement('div');
  host.className = 'mermaid-render';
  const sourcepos = wrapper.getAttribute('data-sourcepos');
  if (sourcepos) {
    host.setAttribute('data-sourcepos', sourcepos);
  }
  wrapper.replaceWith(host);
  return host;
}

function replaceMermaidBlock(codeBlock, svg) {
  const host = makeMermaidHost(codeBlock);
  if (!host) return;
  host.innerHTML = svg;
}

function showMermaidError(host, error) {
  host.classList.add('mermaid-render-error');
  host.textContent = error?.message ? `Mermaid render error: ${error.message}` : 'Mermaid render error';
}

async function renderMermaidBlock(codeBlock, version) {
  const code = codeBlock.textContent || '';
  const key = mermaidKey(code);
  const cached = mermaidCache.get(key);
  if (cached) {
    replaceMermaidBlock(codeBlock, cached);
    return;
  }
  const host = makeMermaidHost(codeBlock);
  if (!host) return;
  const id = `mermaid-${version}-${Math.random().toString(36).slice(2)}`;
  try {
    const mermaid = await loadMermaid();
    if (version !== renderVersion || !host.isConnected) {
      return;
    }
    const result = await mermaid.render(id, code);
    if (version !== renderVersion || !host.isConnected) {
      return;
    }
    cacheMermaid(key, result.svg);
    host.innerHTML = result.svg;
  } catch (error) {
    if (version !== renderVersion || !host.isConnected) {
      return;
    }
    showMermaidError(host, error);
  }
}

function renderMermaidIdle(version) {
  if (!app || typeof window === 'undefined') return;
  const blocks = [...app.querySelectorAll(MERMAID_SELECTOR)];
  if (!blocks.length) return;
  const schedule = window.requestIdleCallback
    ? (fn) => window.requestIdleCallback(fn, { timeout: 500 })
    : (fn) => window.setTimeout(() => fn({ didTimeout: false, timeRemaining: () => 0 }), 0);
  for (const block of blocks) {
    schedule(() => {
      if (version !== renderVersion) return;
      void renderMermaidBlock(block, version);
    });
  }
}

function renderMarkdown(payload) {
  if (!app) return;
  latestPayload = payload;
  renderVersion += 1;
  const version = renderVersion;
  if (payload.sourcePath) {
    document.title = payload.sourcePath.split(/[\\/]/).pop() || 'Markdown Preview';
  }
  app.innerHTML = payload.html || '';
  rewriteImages(app, payload.sourcePath || '');
  secureLinks(app);
  scheduleScrollToSourcepos(app, payload.cursorLine ?? 1);
  renderMermaidIdle(version);
}

function connect() {
  if (!app || typeof window === 'undefined' || typeof EventSource === 'undefined') {
    return;
  }
  applyTheme();
  const source = new EventSource(`/sse?token=${encodeURIComponent(token)}`);
  source.addEventListener('render', (event) => renderMarkdown(JSON.parse(event.data)));
  source.addEventListener('cursor', (event) => {
    const payload = JSON.parse(event.data);
    scheduleScrollToSourcepos(app, payload.line);
  });
  window.addEventListener('beforeunload', () => source.close(), { once: true });
  const media = window.matchMedia?.('(prefers-color-scheme: dark)');
  if (media) {
    media.addEventListener('change', () => {
      applyTheme(media.matches ? 'dark' : 'light');
      if (latestPayload) {
        renderMarkdown(latestPayload);
      }
    });
  }
}

if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  connect();
}
