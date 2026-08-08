import assert from 'node:assert/strict';
import { test } from 'node:test';
import { assetUrl, parseSourcepos, isExternalLink, MERMAID_SELECTOR } from '../client.mjs';

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
