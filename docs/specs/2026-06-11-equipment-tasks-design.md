# Equipment Future Tasks + WO Surfacing — Design

**Date:** 2026-06-11
**Status:** Approved (Alexander, 2026-06-11)

## Problem

Equipment already has dated reminders (Customer → Equipment → "History & Reminders"),
but there is no way to record undated deferred work ("replace air dryer next time it's
in"), and nothing connects equipment reminders to work orders. A WO stores the unit
number and VIN as plain text, so when a truck with known deferred work comes into the
shop, the writer and mechanic never see it.

## What we're building

1. **Future Tasks** — undated, non-recurring "do this next visit" items per piece of
   equipment, alongside the existing reminders.
2. **A durable WO → equipment link**, set by the equipment picker or inferred by
   VIN / customer+unit match.
3. **Surfacing in both WO moments**: a read-only panel in the new-WO form when
   equipment is selected/matched, and a "From this equipment" section in the WO
   details Reminders tab with one-tap **Add as job** for tasks.

## Decisions (with rationale)

- **Tasks live in the `reminders` table** with a new `kind` column
  (`'reminder'` default | `'task'`). One table = tasks inherit audit logging, the
  race-safe complete pattern, the Reminders page, and — critically — the staged
  `sql/rls-migration.sql` already covers `reminders`, so the unapplied security
  migration needs no edits. (Alternatives considered: separate `equipment_tasks`
  table — duplicates ~80% of CRUD and needs new RLS policies; undated-reminders-as-
  tasks — no way to distinguish deferred work from undated reminders.)
- **Tasks are undated and non-recurring.** No `reminder_date`, no `auto_days`.
- **Conversion is explicit.** "Add as job" is a tap; tasks never auto-complete when a
  similar job finishes.
- **Equipment resolution order for a WO:** `equipment_id` → exact VIN match →
  customer + unit number match. Old WOs created before this feature still resolve.
- **Lookup failures degrade silently** — the panel just doesn't render; equipment
  matching never blocks WO creation.

## Schema (nullable, backward-compatible)

```sql
alter table reminders add column kind text not null default 'reminder';
alter table work_orders add column equipment_id bigint references equipment(id) on delete set null;
```

Existing rows are all `kind='reminder'`; no backfill needed.

## UI changes (index.html)

**EquipmentModal equipment view:** tab bar becomes
🔧 Repair History | 🔔 Reminders (n) | 📋 Future Tasks (n).
Tasks tab mirrors the reminder card pattern: add form is a single note textarea;
open tasks listed with ✓ Done; completed shown struck-through. All writes via
`must()`, audited as entity `reminder` with kind noted in details.

**New-WO form:** `selEquip` additionally stores `equipment_id` on the form. An
on-blur lookup on the VIN/unit fields matches hand-typed equipment (VIN exact, else
customer + unit number) and sets `equipment_id` quietly. When equipment is known and
has open items, an amber panel under the unit field lists them read-only:
"⚠ This unit has 2 open tasks · 1 reminder".

**WO details modal, Reminders tab:** above the existing WO reminders, a
"From this equipment" section shows the resolved equipment's open tasks and
reminders. Tasks get **➕ Add as job** — inserts a job on this WO via the existing
`addJob` path (audit + error handling for free), then marks the task completed with
an audit entry naming the WO. Reminders get the existing ✓ Done (auto-reschedules
recurring ones).

**Reminders page:** task rows show a 📋 badge; existing filters unchanged (same table).

## Testing (manual UAT — no test framework by project decision)

1. Create task on equipment → start WO via picker → panel shows → open WO →
   Add as job → job exists, task completed, audit rows correct.
2. Same flow with hand-typed unit number (fallback match).
3. Old WOs and existing reminders unaffected; recurring reminder complete still
   reschedules; CI esbuild parse check passes.
