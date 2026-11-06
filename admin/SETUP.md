# FiberBro admin portal setup

The portal is at [https://fiberbro.pages.dev/admin/](https://fiberbro.pages.dev/admin/). It uses the free Supabase tier and Google sign-in. Nothing here needs a paid plan.

The Supabase project already exists (`https://lrzfaxhaujrrxivvphls.supabase.co`) and `admin/config.js` already has its URL and anon key. Start at step 2 and run `supabase/schema.sql`. Until that script has been applied, sign-in cannot load records. The public inquiry form keeps sending to the Google Sheet either way.

## 1. Create a Supabase project

1. Sign in at [supabase.com](https://supabase.com/) with the company Google account.
2. New project. Pick the free plan, a name such as `fiberbro`, and a database password. Save the password somewhere safe.
3. Wait until the project status is healthy.

## 2. Run the database script

1. In the Supabase dashboard open **SQL Editor**.
2. New query. Paste the full contents of `supabase/schema.sql` from this repository.
3. Run it. You should see success, and **Table Editor** should list `admins`, `investors`, `technicians`, `customers`, `tickets`, and `customer_stage_events`.
4. Open `admins`. It should already contain `fiberbropayatas@gmail.com`.

The script turns on row level security. A signed-in Google user can read or change rows only when their email is in `admins`. The public site can insert an inquiry and cannot read any customer.

## 3. Turn on Google sign-in

### Google Cloud OAuth client

1. Open [Google Cloud Console](https://console.cloud.google.com/) and create a project (or use an existing one). The free OAuth client is enough.
2. **APIs & Services → OAuth consent screen**. User type **External**. App name `FiberBro`. Add `fiberbropayatas@gmail.com` as a test user while the app stays in Testing. You do not need to submit the app for verification if every admin is a test user.
3. **APIs & Services → Credentials → Create credentials → OAuth client ID → Web application**.
4. Authorized JavaScript origins:
   - `https://fiberbro.pages.dev`
   - `https://lrzfaxhaujrrxivvphls.supabase.co`
5. Authorized redirect URI (this exact path):
   - `https://lrzfaxhaujrrxivvphls.supabase.co/auth/v1/callback`
6. Copy the client ID and client secret.

### Supabase provider

1. **Authentication → Sign In / Providers → Google**. Enable it and paste the client ID and secret.
2. **Authentication → URL Configuration**:
   - Site URL: `https://fiberbro.pages.dev/admin/`
   - Redirect URLs, add both:
     - `https://fiberbro.pages.dev/admin/`
     - `https://fiberbro.pages.dev/admin`

## 4. Config

`admin/config.js` already has this project:

- URL: `https://lrzfaxhaujrrxivvphls.supabase.co`
- Key: the anon public key (not the service_role key)

Do not replace it with the service_role key. That key bypasses row level security. Cloudflare Pages deploys `fiberbro.pages.dev` from `main`. Bump the `?v=` on script and stylesheet links when you change JavaScript or CSS.

## 5. Sign in and add admins

1. Open `https://fiberbro.pages.dev/admin/`.
2. Choose **Sign in with Google** and use `fiberbropayatas@gmail.com`.
3. To let someone else in, add their Gmail address under **Admins** in the portal. They must also be a test user on the Google OAuth consent screen while that app is in Testing. Signing in with any other Gmail shows an access-denied message and the database still returns no rows.

## What the portal does

- **Customers** lists inquiries and accounts. Search and filter them, then open a record to edit every master-list field.
- Stage order is Inquiry → Encoded in Microtech → Activated → Ticket assigned. The database rejects a skip.
- On Inquiry, choose an **Investor**. Investors whose areas include the customer’s area are listed first. Any active investor can still be chosen. The old Referral column is this dropdown.
- **Encoded in Microtech** and **Activated** are manual buttons. Activation creates the technician ticket. Assigning that ticket moves the customer to Ticket assigned.
- **Investors** and **Technicians** can be added, edited, and deactivated.
- Each stage change stores the time and the admin’s email.

Website inquiries still go to the Google Sheet through Apps Script. When `config.js` is filled in, the form also inserts the inquiry fields into `customers` at stage Inquiry. A Supabase error does not stop the Sheet submission. The ID photo is not sent to Supabase. It stays on the Sheet / Google Drive path.
