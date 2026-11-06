# FiberBro website

Static marketing site for **FiberBro Internet Communication Services Corp.** — fiber internet exclusive to **Payatas, Quezon City, Philippines**.

Built for **Cloudflare Pages** (free): plain HTML, CSS, and vanilla JS. No build step.

## Live URL (placeholder)

- Planned: `https://fiberbro.pages.dev`
- Custom domain: add later in Cloudflare (e.g. `.ph` or `.com`)

## Plans (current)

| Plan  | Speed        | Monthly   | Installation      |
|-------|--------------|-----------|-------------------|
| Basic | 75–150 Mbps  | ₱1,000/mo | ₱1,000 one-time   |
| Plus  | 150–200 Mbps | ₱1,200/mo | ₱1,000 one-time   |
| Max   | 200–300 Mbps | ₱1,400/mo | ₱1,000 one-time   |

- Plus is marked **Most Popular**.
- Installation fee is shown on every plan card, under the plans section, and on the inquiry form (also sent as a hidden form field `installation_fee`).
- All three plans include **unlimited data** (no caps). Feature bullets live in `assets/js/main.js` → `PLANS`.

## Deploy to Cloudflare Pages

1. Create a GitHub repo and push this folder (repo root = site root).
2. In Cloudflare Dashboard → **Workers & Pages** → **Create** → **Pages** → Connect GitHub.
3. Build settings:
   - **Framework preset:** None
   - **Build command:** *(leave empty)*
   - **Build output directory:** `/` (or leave as `.` / empty — site files are at the repo root)
4. Save and deploy. You’ll get a `*.pages.dev` URL.
5. (Optional) Attach a custom domain under the Pages project → Custom domains.

CSS and JS are linked with a `?v=` query (`styles.css?v=20261106o`, `main.js?v=20261106o`) in `index.html`, `privacy.html`, and `404.html`. Bump that `v=` value on every CSS or JS change so returning visitors pick up the new files. Images stay long-cached; `/assets/css/*` and `/assets/js/*` use a short `Cache-Control` in `_headers`.

## Inquiry form

Submissions are posted as JSON to a Google Apps Script web app, which appends each inquiry to a Google Sheet under the company's Google account:

`https://script.google.com/macros/s/AKfycbwY9a5oRCCG_ztClnLn6Ku4N1fawzALZQV2_Q4sDhUvzRsw-Ha6EFGnObvB1Zu9SpQLBA/exec`

The handler is in `assets/js/main.js`. The form `action` points at the same endpoint so a no-JavaScript submit still POSTs somewhere useful.

When `admin/config.js` has a real Supabase URL and anon key, the same submission also inserts an Inquiry-stage customer. A Supabase failure does not affect the Sheet. Setup is in `admin/SETUP.md`. The internal portal is `/admin/` and is disallowed in `robots.txt`.

## What to configure after deploy

### 1. Plans / prices / features

Edit the single `PLANS` array and `INSTALLATION_FEE` at the top of:

`assets/js/main.js`

Plan cards are generated from that block. The registration form lists the same three speeds and monthly prices.

### 2. Logo assets

The real logo PNG is already in place:

- `assets/img/fiberbro-logo.png` / `.webp` — hero / full
- `assets/img/fiberbro-logo-header.png` / `.webp` — sticky header
- `assets/img/favicon*.png`, `favicon.svg`, `apple-touch-icon.png`
- `assets/img/og-image.png` / `.webp`
- `assets/img/fiberbro-logo.svg` — SVG wordmark fallback only

HTML uses `<picture>` with WebP + PNG fallback.

### 3. Coverage list

Replace the TODO items in the Coverage section of `index.html` with confirmed sitios / streets.

### 4. Privacy Notice

`privacy.html` is a short RA 10173 draft. Have it reviewed before treating it as final. No NPC registration numbers are invented.

## Local preview

Any static server from the site root, for example:

```bash
cd /path/to/fiberbro-site
python3 -m http.server 8080
```

Open `http://localhost:8080`.

## Contact

- Email: fiberbropayatas@gmail.com
- Facebook: https://www.facebook.com/721922910999905
- Messenger: https://m.me/721922910999905
- Area: Payatas, Quezon City only
