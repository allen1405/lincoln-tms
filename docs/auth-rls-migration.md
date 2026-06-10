# Auth + RLS Migration Plan

**Status: PREPARED, NOT APPLIED.** Do not run `sql/rls-migration.sql` until the app-side
auth changes (Phase A) are deployed — enabling RLS first locks the current app out of its
own database mid-shift.

## Why this is urgent

Supabase's security linter (checked 2026-06-10) confirms:
- RLS disabled on all 12 public tables (`users`, `work_orders`, `jobs`, `parts`, `notes`,
  `customers`, `reminders`, `appointments`, `equipment`, `dot_inspections`, `audit_log`, `photos`)
- `users.password` (plaintext) exposed via the API with no RLS
- `tms-photos` bucket publicly listable

The publishable key in `index.html` is in a **public GitHub repo**. Anyone who finds it can
read every employee's plaintext password, dump customer PII, and delete the database.
Until this migration lands, every permission check in the app is client-side decoration.

## Phase A — App-side auth (deploy first, RLS still off)

1. **Create Supabase Auth users** (Dashboard → Authentication → Add user, or admin API)
   for each row in `users`, with NEW passwords. Treat all current passwords as compromised.
2. **Link them**: add `auth_id uuid` to `users` (the SQL file does this) and set it for
   each employee.
3. **App changes** in `index.html`:
   - `Login.go()` → `sb.auth.signInWithPassword({email, password})`, then fetch the
     profile: `sb.from('users').select('id,name,email,role,active').eq('auth_id', session.user.id).single()`
   - Replace the localStorage session with supabase-js's own session
     (`sb.auth.getSession()` / `onAuthStateChange`) — it's a signed JWT, not forgeable.
   - `Settings.add` → `sb.auth.admin` won't work client-side; create users from the
     Supabase dashboard, or add a small edge function later. Password reset →
     `sb.auth.resetPasswordForEmail`.
4. **Deploy.** Everyone logs in once with their new password. RLS is still off, so nothing
   else breaks while this settles.

## Phase B — Lock down (run `sql/rls-migration.sql`)

5. Run the SQL: drops `users.password`, enables RLS everywhere, adds policies
   (authenticated staff = full access to operational tables; `users` writes and
   `audit_log` reads admin-only; `audit_log` is insert-only — no update/delete for anyone).
6. **Storage**: flip `tms-photos` to private (the SQL adds the policies). App change:
   replace `getPublicUrl` with `createSignedUrl(path, 60*60)` in `PhotoSection` and render
   from `storage_path` instead of the stored `public_url` column.
7. Re-run the linter: `get_advisors(security)` should come back clean.

## Phase C — Cleanup

8. Verify a mechanic login can't read `audit_log` or write `users` (try from the browser console).
9. Consider moving hosting to Cloudflare Pages so the GitHub repo can go private
   (`wrangler pages deploy` — same tooling as the Shingle sites). Pages-on-public-repo is
   how the key got indexed.

## Coordination notes

- Do Phase A → B on the same day, ideally after hours: between them the DB is still open,
  and after B every tablet must be on the new app version.
- The shop tablets hold old localStorage sessions; the new app version invalidates them
  automatically (different session mechanism), forcing the one-time re-login.
