#!/usr/bin/env node
'use strict';
// Lokaler Dev-Server fuer website/ (emuliert Cloudflare Pages: _redirects, _headers, saubere URLs).
// Start: node scripts/serve-website.js  -> http://localhost:8788
const http = require('http');
const fs = require('fs');
const path = require('path');

const MIME = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8', '.mjs': 'application/javascript; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.webp': 'image/webp', '.ico': 'image/x-icon', '.json': 'application/json; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8', '.woff2': 'font/woff2', '.xml': 'application/xml',
};

function globToRegExp(pattern, withSplat) {
  let re = '';
  for (const ch of pattern) {
    if (ch === '*') re += withSplat ? '(.*)' : '.*';
    else re += ch.replace(/[.+?^${}()|[\]\\]/g, '\\$&');
  }
  return new RegExp('^' + re + '$');
}

/** Parst _redirects: `quelle ziel [status]`, Kommentare mit #. Default-Status 302. */
function parseRedirects(text) {
  const rules = [];
  for (const raw of String(text || '').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const [from, to, st] = line.split(/\s+/);
    if (!from || !to) continue;
    const status = st ? parseInt(st, 10) : 302;
    if (![200, 301, 302, 303, 307, 308].includes(status)) continue;
    rules.push({ from, to, status, re: globToRegExp(from, true) });
  }
  return rules;
}

/** Erste passende Regel -> { status, target } oder null. `*` wird in `:splat` eingesetzt. */
function matchRedirect(rules, pathname) {
  for (const r of rules) {
    const m = r.re.exec(pathname);
    if (m) return { status: r.status, target: r.to.replace(/:splat/g, m[1] || '') };
  }
  return null;
}

/** Parst _headers: Pfadzeile (nicht eingerueckt), darunter eingerueckte `Name: Wert`. */
function parseHeaders(text) {
  const blocks = [];
  let cur = null;
  for (const raw of String(text || '').split(/\r?\n/)) {
    if (!raw.trim() || raw.trim().startsWith('#')) continue;
    if (/^\s/.test(raw)) {
      const i = raw.indexOf(':');
      if (cur && i > 0) cur.headers.push([raw.slice(0, i).trim(), raw.slice(i + 1).trim()]);
    } else {
      cur = { pattern: raw.trim(), re: globToRegExp(raw.trim(), false), headers: [] };
      blocks.push(cur);
    }
  }
  return blocks;
}

/** Alle passenden Blocks; gleiche Header werden (wie Pages) mit ", " verkettet. */
function headersFor(blocks, pathname) {
  const out = {};
  for (const b of blocks) {
    if (!b.re.test(pathname)) continue;
    for (const [k, v] of b.headers) {
      const key = k.toLowerCase();
      out[key] = key in out ? `${out[key]}, ${v}` : v;
    }
  }
  return out;
}

/** Sicher innerhalb von root aufloesen (kein Traversal), sonst null. */
function safeResolve(root, pathname) {
  let decoded;
  try { decoded = decodeURIComponent(pathname); } catch { return null; }
  if (decoded.includes('\0')) return null;
  const base = path.resolve(root);
  const full = path.resolve(base, '.' + path.posix.normalize('/' + decoded));
  if (full !== base && !full.startsWith(base + path.sep)) return null;
  return full;
}

function isFile(p) { try { return fs.statSync(p).isFile(); } catch { return false; } }
function isDir(p) { try { return fs.statSync(p).isDirectory(); } catch { return false; } }

/**
 * Pfad -> { file } | { redirect } | null. Saubere URLs wie Pages:
 * /x.html -> 308 /x, /x/index.html -> 308 /x/, /x -> x.html | x/index.html, Verzeichnis -> index.html.
 */
function resolveRequest(root, pathname) {
  const full = safeResolve(root, pathname);
  if (!full) return null;
  if (/\/index\.html$/.test(pathname)) return { redirect: pathname.slice(0, -'index.html'.length) };
  if (/\.html$/.test(pathname) && isFile(full)) return { redirect: pathname.slice(0, -5) };
  if (pathname.endsWith('/')) {
    const idx = path.join(full, 'index.html');
    return isFile(idx) ? { file: idx } : null;
  }
  if (isFile(full)) return { file: full };
  if (isFile(full + '.html')) return { file: full + '.html' };
  if (isDir(full) && isFile(path.join(full, 'index.html'))) return { redirect: pathname + '/' };
  return null;
}

function contentType(file) {
  const ext = path.extname(file).toLowerCase();
  if (MIME[ext]) return MIME[ext];
  if (path.basename(file) === 'apple-app-site-association') return 'application/json';
  return 'application/octet-stream';
}

function readOptional(p) { try { return fs.readFileSync(p, 'utf8'); } catch { return ''; } }

function createServer(root) {
  const redirects = () => parseRedirects(readOptional(path.join(root, '_redirects')));
  const headerBlocks = () => parseHeaders(readOptional(path.join(root, '_headers')));

  return http.createServer((req, res) => {
    const qi = req.url.indexOf('?');
    const reqPath = (qi < 0 ? req.url : req.url.slice(0, qi)) || '/';
    const reqSearch = qi < 0 ? '' : req.url.slice(qi);
    const send = (status, extra, body) => {
      const h = Object.assign({}, headersFor(headerBlocks(), reqPath), extra);
      res.writeHead(status, h);
      res.end(req.method === 'HEAD' ? undefined : body);
      console.log(`${req.method} ${req.url} -> ${status}`);
    };
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      return send(405, { Allow: 'GET, HEAD', 'content-type': 'text/plain' }, 'Method Not Allowed');
    }
    const pathname = reqPath;
    const search = reqSearch;
    if (!safeResolve(root, pathname)) return send(400, { 'content-type': 'text/plain' }, 'Bad Request');

    let servePath = pathname;
    const rule = matchRedirect(redirects(), pathname);
    if (rule) {
      if (rule.status !== 200) return send(rule.status, { location: rule.target + search }, '');
      // Rewrite: echte Dateien haben Vorrang (wie Pages)
      if (!resolveRequest(root, pathname)) {
        // Rewrite liefert die Zieldatei direkt aus (kein Clean-URL-Redirect)
        const t = safeResolve(root, rule.target);
        if (t && isFile(t)) return send(200, { 'content-type': contentType(t) }, fs.readFileSync(t));
        servePath = rule.target;
      }
    }

    const r = resolveRequest(root, servePath);
    if (r && r.redirect !== undefined) return send(308, { location: r.redirect + search }, '');
    if (r && r.file) {
      return send(200, { 'content-type': contentType(r.file) }, fs.readFileSync(r.file));
    }
    const nf = path.join(root, '404.html');
    if (isFile(nf)) return send(404, { 'content-type': MIME['.html'] }, fs.readFileSync(nf));
    return send(404, { 'content-type': 'text/plain' }, 'Not Found');
  });
}

if (require.main === module) {
  const root = path.resolve(process.env.WEBSITE_DIR || path.join(__dirname, '..', 'website'));
  const port = parseInt(process.env.PORT || '8788', 10);
  if (!isDir(root)) { console.error(`Ordner nicht gefunden: ${root}`); process.exit(1); }
  createServer(root).listen(port, '127.0.0.1', () => {
    console.log(`SwipeShift Website (lokal): http://localhost:${port}`);
    console.log(`Verzeichnis: ${root}`);
    for (const f of ['_redirects', '_headers', '404.html']) {
      if (!isFile(path.join(root, f))) console.log(`Hinweis: ${f} fehlt (wird ignoriert)`);
    }
  });
}

module.exports = { parseRedirects, matchRedirect, parseHeaders, headersFor, safeResolve, resolveRequest, contentType, createServer };
