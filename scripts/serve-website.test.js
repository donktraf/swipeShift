'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const s = require('./serve-website');

test('parseRedirects + matchRedirect mit Splat', () => {
  const rules = s.parseRedirects('# c\n/jobs/* /jobs/index.html 200\n/old /new 301\n/x /y\n');
  assert.strictEqual(rules.length, 3);
  assert.deepStrictEqual(s.matchRedirect(rules, '/jobs/abc'), { status: 200, target: '/jobs/index.html' });
  assert.deepStrictEqual(s.matchRedirect(rules, '/old'), { status: 301, target: '/new' });
  assert.strictEqual(s.matchRedirect(rules, '/x').status, 302);
  assert.strictEqual(s.matchRedirect(rules, '/none'), null);
  assert.strictEqual(s.matchRedirect(s.parseRedirects('/a/* /b/:splat 301'), '/a/c/d').target, '/b/c/d');
});

test('parseHeaders + headersFor', () => {
  const b = s.parseHeaders('/*\n  X-A: 1\n\n/.well-known/aasa\n  Content-Type: application/json\n  X-A: 2\n/assets/*\n  Cache-Control: x\n');
  assert.strictEqual(b.length, 3);
  assert.deepStrictEqual(s.headersFor(b, '/privacy'), { 'x-a': '1' });
  assert.deepStrictEqual(s.headersFor(b, '/.well-known/aasa'), { 'x-a': '1, 2', 'content-type': 'application/json' });
  assert.strictEqual(s.headersFor(b, '/assets/a/b.css')['cache-control'], 'x');
});

test('safeResolve blockt Traversal', () => {
  const root = path.join(os.tmpdir(), 'ssroot');
  assert.strictEqual(s.safeResolve(root, '/../etc/passwd'), path.join(root, 'etc/passwd'));
  assert.strictEqual(s.safeResolve(root, '/%2e%2e/%2e%2e/etc/passwd'), path.join(root, 'etc/passwd'));
  assert.strictEqual(s.safeResolve(root, '/a%00b'), null);
  assert.strictEqual(s.safeResolve(root, '/%E0%A4%A'), null);
});

test('resolveRequest: saubere URLs', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ssw-'));
  fs.writeFileSync(path.join(root, 'index.html'), 'i');
  fs.writeFileSync(path.join(root, 'privacy.html'), 'p');
  fs.mkdirSync(path.join(root, 'jobs'));
  fs.writeFileSync(path.join(root, 'jobs', 'index.html'), 'j');
  assert.strictEqual(s.resolveRequest(root, '/').file, path.join(root, 'index.html'));
  assert.strictEqual(s.resolveRequest(root, '/privacy').file, path.join(root, 'privacy.html'));
  assert.deepStrictEqual(s.resolveRequest(root, '/privacy.html'), { redirect: '/privacy' });
  assert.deepStrictEqual(s.resolveRequest(root, '/jobs/index.html'), { redirect: '/jobs/' });
  assert.deepStrictEqual(s.resolveRequest(root, '/jobs'), { redirect: '/jobs/' });
  assert.strictEqual(s.resolveRequest(root, '/jobs/').file, path.join(root, 'jobs', 'index.html'));
  assert.strictEqual(s.resolveRequest(root, '/nope'), null);
});

test('contentType', () => {
  assert.match(s.contentType('a.svg'), /svg/);
  assert.strictEqual(s.contentType('/x/apple-app-site-association'), 'application/json');
});
