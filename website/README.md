# SwipeShift website

Static site for https://swipeshift.app. Plain HTML/CSS, no build tool, no external scripts, fonts, or trackers.

## Structure

| Path | Purpose |
| --- | --- |
| `index.html` | `/` landing page |
| `guide.html`, `privacy.html`, `terms.html` | `/guide`, `/privacy`, `/terms` (Cloudflare Pages serves them without `.html`) |
| `jobs/index.html` | Fallback page for every `/jobs/<id>` link ("Open in the app" button) |
| `404.html` | Not-found page (used automatically by Cloudflare Pages) |
| `assets/style.css` | Shared CSS (light/dark via `prefers-color-scheme`) |
| `assets/store-badge.js` | App Store button configuration (see below) |
| `assets/job-link.js` | Reads the job id from the path (`[A-Za-z0-9-]` only) and sets `swipeshift://job/<id>` |
| `_headers` | Security headers (CSP allows only same-origin scripts/styles) and AASA content type |
| `_redirects` | `/jobs/*` rewrites to `/jobs/index.html` (status 200) |
| `.well-known/apple-app-site-association` | Universal Links for app ID `988DGAA7W2.com.swipeShift`, path `/jobs/*` |

Header and footer are repeated in each HTML file (no build step). Change them in every page.

## View locally

```sh
cd website
python3 -m http.server 8000
```

Open http://localhost:8000. Note: `_redirects` and `_headers` are Cloudflare features and do not apply locally. Use `/guide.html`, `/privacy.html`, `/terms.html` locally, and open `/jobs/index.html` directly (a local link such as `/jobs/abc` gives 404; the id is only read on Cloudflare, where the rewrite keeps the original path). Absolute links like `/privacy` will 404 on the Python server for the same reason.

## Deploy on Cloudflare Pages

1. Cloudflare dashboard, Workers & Pages, Create, Pages, connect the Git repository.
2. Framework preset: None. Build command: leave empty. Build output directory: `website`.
3. Add the custom domain `swipeshift.app` under the project's Custom domains.
4. After deploy, check: `curl -i https://swipeshift.app/.well-known/apple-app-site-association` returns `200` with `Content-Type: application/json` and no redirect.

Universal Links additionally need the Associated Domains entitlement `applinks:swipeshift.app` in the app (not part of this folder).

## Switching the App Store button to the real link

The button exists in `index.html` and `jobs/index.html` as `<div data-store-badge ...>Coming soon to the App Store</div>`. Both are controlled from ONE place: `assets/store-badge.js`. Set

```js
var APP_STORE_URL = "https://apps.apple.com/app/idXXXXXXXXXX";
```

(must start with `https://apps.apple.com/`). Leave it empty for the "Coming soon" state.

## Placeholders to fill in before launch

Search the HTML files for `class="placeholder"` (highlighted in the browser):

- `[COMPANY LEGAL NAME]` (footer on every page, privacy, terms)
- `[ADDRESS]` (privacy, terms)
- `[STATE]` (terms, governing law)
- `[EMAIL PROVIDER]`, `[HOSTING PROVIDER]` (privacy)
- `[CONFIRM LOG CONTENT AND RETENTION]`, `[CONFIRM RETENTION PERIOD]` (privacy)
- `[CONFIRM RESPONSE TARGET ...]`, `[WORKER STATUS / CONTRACTOR NOTICE ...]`, `[ANY COMPENSATION RULES ...]`, `[AMOUNT ...]`, `[DISPUTE RESOLUTION ...]` (terms)
- The "Draft - pending legal review" banners and the "Requires legal/engineering confirmation" notes must be removed only after legal review.
- Update the "Last updated" dates when texts change.
