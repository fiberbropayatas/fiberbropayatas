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

## What to configure after deploy

### 1. Formspree form ID

1. Sign up at [formspree.io](https://formspree.io/) with `fiberbropayatas@gmail.com`.
2. Create a form; copy the ID (e.g. `abcdefg`).
3. In `index.html`, replace:

```html
action="https://formspree.io/f/YOUR_FORM_ID"
```

with your real ID. Until then, the form shows a friendly error and points visitors to email.

### 2. Plans / prices / features

Edit the single `PLANS` array and `INSTALLATION_FEE` at the top of:

`assets/js/main.js`

Plan cards and the form `<select>` options are generated from that block.

### 3. Logo assets

The real logo PNG is already in place:

- `assets/img/fiberbro-logo.png` / `.webp` — hero / full
- `assets/img/fiberbro-logo-header.png` / `.webp` — sticky header
- `assets/img/favicon*.png`, `favicon.svg`, `apple-touch-icon.png`
- `assets/img/og-image.png` / `.webp`
- `assets/img/fiberbro-logo.svg` — SVG wordmark fallback only

HTML uses `<picture>` with WebP + PNG fallback.

### 4. Coverage list

Replace the TODO items in the Coverage section of `index.html` with confirmed sitios / streets.

### 5. Privacy Notice

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
