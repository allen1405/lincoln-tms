# Inspection Forms — Design Spec

**Date:** 2026-07-01
**App:** Lincoln TMS (`index.html`, single-file React 18 + babel-standalone, Supabase backend, GitHub Pages deploy)
**Status:** Approved design (Approach A). Next step: implementation plan.

## Goal

Add two paper-form-faithful, fillable-and-saved-and-printable inspection forms to the app:

1. **Outbound / Inbound Inspection** — the full 2-page in-house form, used **only for A2C's own trucks** (never outside clients).
2. **Inspection Results** — the back page (findings list) alone, usable for **any inspection on any truck**, including outside clients and trucks not tied to a work order.

Both follow the existing **DOT Inspection** pattern: fill fields on screen → save to Supabase → print with LTTR letterhead + the mechanic's auto-signature.

## Domain facts

- **A2C Logistics CO is customer `id = 1`.** An "A2C truck" is identified automatically: a work order whose `customer === "A2C Logistics CO"`. No manual flag, no toggle.
- The shop letterhead + auto-signature print machinery already exists (`printDot`, `MySignature`). New print views reuse it.
- Work orders already carry `truck_mileage`, `apu_hours`, `reefer_hours`, `unit_number`, `vin`, `customer` — used to pre-fill the full form.

## Where each form lives

| Form | Placement | Gating |
|---|---|---|
| Outbound/Inbound (full) | New tab in the work-order job modal (alongside `🛡️ DOT Inspection`, near `index.html:1719`) | Tab renders **only when** the WO's `customer === "A2C Logistics CO"` |
| Inspection Results (page 2) | (a) New tab in the job modal for **non-A2C** work orders; **and** (b) a new top-level **"Inspections"** nav page with a **"＋ New Inspection"** button | None — any truck |

Net effect: an A2C work order shows the full form; every other truck shows just the results page (via WO tab or standalone). The A2C form can never be opened for an outside client.

New nav entry (in `NAV`, `index.html:538`): `{id:"inspections",label:"Inspections",icon:"🔎",s:"SUPPORT",shop:true}` — exact icon/section to be finalized in the plan. Wired into the `pages` map (`index.html:3422`).

## Data model — two purpose-built tables (Approach A)

Each table maps to exactly one form; each is self-contained.

### `outbound_inspections` (full A2C form — 1 row per work order)

Upsert keyed by `work_order_id`, exactly like `dot_inspections`.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint PK | |
| `work_order_id` | bigint UNIQUE | FK-by-convention to `work_orders.id` |
| `inspection_date` | date | "Date" |
| `done_by` | text | "Done by" (defaults to current user's name) |
| `unit_number` | text | pre-filled from WO |
| `vehicle_kind` | text | "Truck" \| "Trailer" |
| `came_with` | text | |
| `truck_trailer_service` | bool | checkbox |
| `apu_service` | bool | checkbox |
| `reason_here` | text | "Reason Why Here" |
| `mileage` | text | pre-filled from WO `truck_mileage` |
| `apu_hours` | text | pre-filled from WO |
| `reefer_hours` | text | pre-filled from WO |
| `last_annual_date` | date | "Last Annual Inspection Date" |
| `do_new_annual` | bool \| null | Yes/No (null = unanswered) |
| `checklist` | jsonb | array of `{label, checked, note}` — fixed items + user-added rows (see below) |
| `parts_ordered` | jsonb | `{vendors:[...], other:"", lines:[{text}]}` — captured as form data only, NOT wired to Order Parts queue |
| `findings` | jsonb | page-2 results: array of `{checked, text}` |
| `created_by` | text | |
| `updated_at` | timestamptz | |

**Checklist fixed items** (reproduced faithfully; two-column layout is presentation-only, stored as one ordered array):
Left: NY Sticker on truck, Fridge, Microwave, ELD, Tablet, BestPass, Truck Keys, Straps, Chains.
Right: Oil, Coolant, Windshield Washer, Windshield Wipers, Fire Extinguisher, Reflective Triangles, Fridge Empty, Cabin Empty, Cabinets Empty.
Plus a "＋ add item" affordance for the blank rows on the paper form. Each item: checkbox + Qty/Comments text.

**Parts Ordered vendors:** International, Freightliner, Kenworth, Peterbilt, Volvo, Other (+ free text). Then repeatable part line rows.

### `inspections` (standalone / any-truck results — many rows)

| Column | Type | Notes |
|---|---|---|
| `id` | bigint PK | |
| `work_order_id` | bigint \| null | set when opened as a non-A2C WO tab; null when standalone |
| `customer` | text \| null | optional customer (picker) for standalone; outside trucks allowed |
| `unit_number` | text | free-text; pre-filled from WO when tab-opened |
| `vin` | text \| null | |
| `inspection_date` | date | |
| `inspector` | text | defaults to current user's name |
| `findings` | jsonb | array of `{checked, text}` — dynamic add-row list |
| `created_by` | text | |
| `updated_at` | timestamptz | |

When opened as a WO tab, upsert by `work_order_id` (1 results record per WO). Standalone records are independent rows listed on the Inspections page.

## Findings list (page 2) — behavior

The paper back page is ~40 fixed checkbox+line rows. Digitally this is a **dynamic list**: each finding is `{checked, text}`; a "＋ add finding" button appends rows. Prints as a bordered checkbox+text table matching the paper look. Same component used by the full form's page-2 section, the non-A2C WO tab, and the standalone form.

## Inspections nav page

- Lists all `inspections` rows (standalone + WO-linked), newest first: date, unit #, customer, inspector, # findings, and a link back to the WO if linked.
- **"＋ New Inspection"** opens a blank results form: enter unit # (free text) + optional customer picker → add findings → save → print.
- Records are re-openable/editable (findings tracked over time).
- Search/filter consistent with other list pages (by unit #, customer).

## Printing

Two print builders modeled on `printDot` (`index.html:1210`):

- **Outbound/Inbound print:** page 1 (header + details + two-column checklist + Parts Ordered) then page 2 (findings) — LTTR letterhead, auto-signature block at the bottom.
- **Inspection Results print:** the findings page alone — LTTR letterhead + unit #/date header + auto-signature.

Both reuse the existing dark-header→print-safe CSS notes and the `MySignature` auto-stamp used by `printDot`.

## Auditing

Log via the existing `audit()` helper. Add `"inspection"` and `"outbound_inspection"` to `AUDIT_ENTITIES` (`index.html:166`). Create/update/print events audited like DOT inspections.

## Explicitly out of scope (YAGNI, revisit later if wanted)

- Wiring the full form's "Parts Ordered" into the Order Parts queue (kept as form data).
- Surfacing A2C `outbound_inspections` in the Inspections list page (they live on their WO like DOT does).
- Fixed 40-row layout (replaced by dynamic add-row).
- RLS (tables created open, consistent with current app-wide posture; tracked separately).

## Success criteria

1. Opening an **A2C** work order shows an **Outbound/Inbound Inspection** tab with every field/checklist item from page 1 + a findings section; fills, saves, reopens with data intact, prints as a 2-page LTTR form with signature.
2. Opening a **non-A2C** work order shows an **Inspection Results** tab (no full form); fills, saves, prints page-2-only.
3. The **Inspections** nav page lists results and a **＋ New Inspection** flow works for a truck **not** in the system and **without** a work order.
4. Mileage/APU/Reefer/unit# pre-fill from the WO on the full form.
5. No regression to the existing DOT tab or job modal.
