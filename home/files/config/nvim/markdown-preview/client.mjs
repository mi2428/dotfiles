const token = new URL(import.meta.url).searchParams.get('token') ?? globalThis.__MARKDOWN_PREVIEW_TOKEN__ ?? 'test-token';
const app = typeof document !== 'undefined' ? document.getElementById('app') : null;
const mermaidCache = new Map();
const MERMAID_CACHE_LIMIT = 32;
export const MERMAID_SELECTOR = 'pre[lang="mermaid"] > code, code.language-mermaid';
export const ALERT_ICON_PATHS = Object.freeze({
  note: 'M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-6.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13ZM6.5 7.75A.75.75 0 0 1 7.25 7h1a.75.75 0 0 1 .75.75v2.75h.25a.75.75 0 0 1 0 1.5h-2a.75.75 0 0 1 0-1.5h.25v-2h-.25a.75.75 0 0 1-.75-.75ZM8 6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z',
  tip: 'M8 1.5c-2.363 0-4 1.69-4 3.75 0 .984.424 1.625.984 2.304l.214.253c.223.264.47.556.673.848.284.411.537.896.621 1.49a.75.75 0 0 1-1.484.211c-.04-.282-.163-.547-.37-.847a8.456 8.456 0 0 0-.542-.68c-.084-.1-.173-.205-.268-.32C3.201 7.75 2.5 6.766 2.5 5.25 2.5 2.31 4.863 0 8 0s5.5 2.31 5.5 5.25c0 1.516-.701 2.5-1.328 3.259-.095.115-.184.22-.268.319-.207.245-.383.453-.541.681-.208.3-.33.565-.37.847a.751.751 0 0 1-1.485-.212c.084-.593.337-1.078.621-1.489.203-.292.45-.584.673-.848.075-.088.147-.173.213-.253.561-.679.985-1.32.985-2.304 0-2.06-1.637-3.75-4-3.75ZM5.75 12h4.5a.75.75 0 0 1 0 1.5h-4.5a.75.75 0 0 1 0-1.5ZM6 15.25a.75.75 0 0 1 .75-.75h2.5a.75.75 0 0 1 0 1.5h-2.5a.75.75 0 0 1-.75-.75Z',
  important: 'M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v9.5A1.75 1.75 0 0 1 14.25 13H8.06l-2.573 2.573A1.458 1.458 0 0 1 3 14.543V13H1.75A1.75 1.75 0 0 1 0 11.25Zm1.75-.25a.25.25 0 0 0-.25.25v9.5c0 .138.112.25.25.25h2a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h6.5a.25.25 0 0 0 .25-.25v-9.5a.25.25 0 0 0-.25-.25Zm7 2.25v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 9a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z',
  warning: 'M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0 1 14.082 15H1.918a1.75 1.75 0 0 1-1.543-2.575Zm1.763.707a.25.25 0 0 0-.44 0L1.698 13.132a.25.25 0 0 0 .22.368h12.164a.25.25 0 0 0 .22-.368Zm.53 3.996v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z',
  caution: 'M4.47.22A.749.749 0 0 1 5 0h6c.199 0 .389.079.53.22l4.25 4.25c.141.14.22.331.22.53v6a.749.749 0 0 1-.22.53l-4.25 4.25A.749.749 0 0 1 11 16H5a.749.749 0 0 1-.53-.22L.22 11.53A.749.749 0 0 1 0 11V5c0-.199.079-.389.22-.53Zm.84 1.28L1.5 5.31v5.38l3.81 3.81h5.38l3.81-3.81V5.31L10.69 1.5ZM8 4a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 8 4Zm0 8a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z',
});
const ALERT_ICON_NAMES = Object.freeze({
  note: 'info',
  tip: 'light-bulb',
  important: 'report',
  warning: 'alert',
  caution: 'stop',
});
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

export function decorateAlerts(root) {
  for (const alert of root.querySelectorAll('.markdown-alert')) {
    const kind = Object.keys(ALERT_ICON_PATHS).find((name) => alert.classList.contains(`markdown-alert-${name}`));
    const title = kind && alert.querySelector('.markdown-alert-title');
    if (!title || title.querySelector('.octicon')) continue;
    const svg = title.ownerDocument.createElementNS('http://www.w3.org/2000/svg', 'svg');
    const path = title.ownerDocument.createElementNS('http://www.w3.org/2000/svg', 'path');
    svg.setAttribute('viewBox', '0 0 16 16');
    svg.setAttribute('width', '16');
    svg.setAttribute('height', '16');
    svg.setAttribute('aria-hidden', 'true');
    svg.classList.add('octicon', `octicon-${ALERT_ICON_NAMES[kind]}`, 'mr-2');
    path.setAttribute('d', ALERT_ICON_PATHS[kind]);
    svg.appendChild(path);
    title.prepend(svg);
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
  decorateAlerts(app);
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
