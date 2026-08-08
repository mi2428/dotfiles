import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  ALERT_ICON_PATHS,
  MERMAID_SELECTOR,
  assetUrl,
  decorateAlerts,
  isExternalLink,
  parseSourcepos,
} from '../client.mjs';

test('client helpers', () => {
  globalThis.window = {
    location: { origin: 'http://127.0.0.1:1234', href: 'http://127.0.0.1:1234/page' },
  };
  assert.equal(parseSourcepos('3:1-8:4').startLine, 3);
  assert.equal(parseSourcepos('bad'), null);
  assert.equal(isExternalLink('https://example.com'), true);
  assert.equal(isExternalLink('/doc.png'), false);
  assert.match(assetUrl('/tmp/doc.md', 'img/pic.png'), /token=/);
  assert.match(MERMAID_SELECTOR, /pre\[lang="mermaid"\] > code/);
  assert.match(MERMAID_SELECTOR, /code\.language-mermaid/);
});

test('GitHub alert decoration inserts the matching Octicon once', () => {
  const prepended = [];
  const makeNode = (tag) => ({
    tag,
    attributes: {},
    children: [],
    classList: { values: [], add(...values) { this.values.push(...values); } },
    setAttribute(name, value) { this.attributes[name] = value; },
    appendChild(child) { this.children.push(child); },
  });
  const ownerDocument = { createElementNS: (_, tag) => makeNode(tag) };
  const title = {
    ownerDocument,
    querySelector: () => null,
    prepend: (node) => prepended.push(node),
  };
  const alert = {
    classList: { contains: (name) => name === 'markdown-alert-tip' },
    querySelector: (selector) => selector === '.markdown-alert-title' ? title : null,
  };

  decorateAlerts({ querySelectorAll: () => [alert] });

  assert.equal(prepended.length, 1);
  assert.deepEqual(prepended[0].classList.values, ['octicon', 'octicon-light-bulb', 'mr-2']);
  assert.equal(prepended[0].children[0].attributes.d, ALERT_ICON_PATHS.tip);
  assert.equal(prepended[0].attributes['aria-hidden'], 'true');
});
