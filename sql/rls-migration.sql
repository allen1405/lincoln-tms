-- Lincoln TMS — RLS migration (Phase B of docs/auth-rls-migration.md)
-- DO NOT RUN until the app uses Supabase Auth (Phase A is deployed and everyone has
-- logged in with new credentials). Running this first locks the current app out.

-- ── 0. Link app users to auth users (run the ALTER in Phase A; backfill before Phase B) ──
alter table public.users add column if not exists auth_id uuid unique references auth.users(id);
-- Backfill per employee after creating their auth account:
--   update public.users set auth_id = '<auth uuid>' where email = '<email>';

-- ── 1. Plaintext passwords go away entirely ──────────────────────────────────────────
alter table public.users drop column if exists password;

-- ── 2. Admin helper (security definer so policies can check role without recursion) ──
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.users
    where auth_id = auth.uid() and role = 'admin' and active
  );
$$;
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- ── 3. Enable RLS on every table ─────────────────────────────────────────────────────
alter table public.users            enable row level security;
alter table public.work_orders      enable row level security;
alter table public.jobs             enable row level security;
alter table public.parts            enable row level security;
alter table public.notes            enable row level security;
alter table public.customers        enable row level security;
alter table public.reminders        enable row level security;
alter table public.appointments     enable row level security;
alter table public.equipment        enable row level security;
alter table public.dot_inspections  enable row level security;
alter table public.audit_log        enable row level security;
alter table public.photos           enable row level security;

-- ── 4. Operational tables: any active authenticated employee, full access ────────────
-- (Tighten per-role later if mechanics should lose deletes; start by matching today's app.)
do $$
declare t text;
begin
  foreach t in array array['work_orders','jobs','parts','notes','customers','reminders',
                           'appointments','equipment','dot_inspections','photos']
  loop
    execute format('drop policy if exists staff_all on public.%I', t);
    execute format(
      'create policy staff_all on public.%I for all to authenticated
         using (exists (select 1 from public.users u where u.auth_id = auth.uid() and u.active))
         with check (exists (select 1 from public.users u where u.auth_id = auth.uid() and u.active))', t);
  end loop;
end $$;

-- ── 5. users: everyone authenticated may read (mechanic dropdowns need names);
--             only admins may write ─────────────────────────────────────────────────
drop policy if exists users_read  on public.users;
drop policy if exists users_write on public.users;
create policy users_read  on public.users for select to authenticated using (true);
create policy users_write on public.users for all    to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ── 6. audit_log: insert-only for staff, readable by admins, immutable for everyone ──
drop policy if exists audit_insert on public.audit_log;
drop policy if exists audit_read   on public.audit_log;
create policy audit_insert on public.audit_log for insert to authenticated
  with check (exists (select 1 from public.users u where u.auth_id = auth.uid() and u.active));
create policy audit_read on public.audit_log for select to authenticated
  using (public.is_admin());
-- No UPDATE/DELETE policies → audit history cannot be rewritten via the API.

-- ── 7. Storage: private bucket, authenticated-only access ────────────────────────────
update storage.buckets set public = false where id = 'tms-photos';
drop policy if exists "tms-photos anon select" on storage.objects;
drop policy if exists tms_photos_staff on storage.objects;
create policy tms_photos_staff on storage.objects for all to authenticated
  using (bucket_id = 'tms-photos'
         and exists (select 1 from public.users u where u.auth_id = auth.uid() and u.active))
  with check (bucket_id = 'tms-photos'
         and exists (select 1 from public.users u where u.auth_id = auth.uid() and u.active));

-- After running: switch PhotoSection to createSignedUrl(storage_path) — the stored
-- public_url values stop working once the bucket is private.
