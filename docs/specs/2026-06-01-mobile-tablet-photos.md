# Mobile / tablet TMS + photo capture — design

**Goal:** Make the TMS usable on Android tablets in the shop (primary user: mechanics), with photo capture wired into every relevant entity.

**Approach:** Responsive single codebase (no fork). Same `index.html`. Add a viewport hook and tablet/mobile layouts. Mechanic-role users on tablet boot into a focused "Shop view" with a toggle back to "Full view."

## Layout modes

| Width | Mode | Layout |
|---|---|---|
| ≥ 1100px | Desktop | Current behavior. Untouched. |
| 900–1099px | Tablet landscape | Sidebar → 64px icon rail. |
| < 900px | Tablet portrait / mobile | Sidebar → bottom nav (5 items + More). |

**Mechanic mode** = `user.role === "mechanic"` AND viewport < 1100px → trimmed nav (Work Orders / Reminders / Inventory) + "Assigned to me" WO default + "My WOs" dashboard tiles. A top-bar **🔧 Shop view / 🖥 Full view** toggle lets anyone on a tablet switch to the complete nav. Toggle visible from either mode (one-tap switch, never trapped).

Touch-target pass: 44×44px min on every interactive, 8px tap spacing, font sizes bumped one tier on mobile (13→15 body, 11→13 small). Modals → full-screen `<Sheet>` at <700px.

## Photo system

**Storage:** new public-read Supabase bucket `tms-photos`. Path: `{entity_type}/{entity_id}/{timestamp}-{filename}`.

**DB:** new `photos` table.
```
id, entity_type (work_order|job|part|equipment|customer|dot_inspection),
entity_id (text), storage_path, public_url,
caption, uploaded_by, created_at
```

**Capture:** `<input type="file" accept="image/*" capture="environment">` — opens system camera directly on Android. Client-side resize to max 1600px wide @ JPEG 0.85 before upload (typical ~200–500KB).

**Display:** `<PhotoSection entityType entityId />` — reusable thumbnail grid + uploader + lightbox. Wired into:
- WO details modal → new "📷 Photos (N)" tab
- Jobs / Parts → compact icon strip under each row
- Equipment / Customer cards → small inline grid
- DOT inspection → camera icon per component row

**Audit:** photo create/delete logged with entity `photo`, parent entity in `entity_label`.

## Components to add

- `useViewport()` hook → `{ isMobile, isTabletLandscape, isDesktop, width }`
- `responsive(d, tl, m)` style helper
- `<Sheet>` — full-screen modal variant at <700px
- `<PhotoSection entityType entityId />`
- `<TouchSegment options value onChange />` — 3-button selector replacing dropdowns for DOT statuses
- `<BottomNav>` — 5-item nav for mobile mode
- `<IconRail>` — collapsed 64px sidebar for tablet landscape

## Page-by-page

| Page | Mechanic mode | Full mode |
|---|---|---|
| Login | Bigger inputs/buttons | Same |
| Work Orders | "Assigned to me" default. Pills collapsed → Filter button. Modal as full-screen sheet. New 📷 Photos tab. | Existing kanban scrolls horizontally as today. Modal becomes sheet under 700px. |
| Reminders | Defaults Pending. Table → card list under 900px. Sort headers → "Sort by..." dropdown. | Same responsive table. |
| DOT inspection | OK/Needs repair/N/A → big 3-button segmented control per item. Camera icon per row. | Same as desktop; falls back to segmented control at portrait. |
| Dashboard | "My WOs" tiles: Today / Overdue / Waiting for parts / DOT due. | Existing tiles, responsive grid 4→2→1. |
| Customers, Appointments, Employees, Salaries, Inventory, Reports, Invoices, Estimates, Settings, Audit Log | Hidden from mechanic nav. Reachable via 🖥 Full view toggle. | Tables responsive; horizontal scroll with sticky first column at narrow widths. |

## Future work

- **RLS / Supabase Auth** is the next major undertaking after this lands. All 10+ tables and the new `tms-photos` bucket are currently open under the anon key. The photo bucket especially makes data exposure more concrete (a leaked URL is a viewable image). Deferred deliberately to keep mobile shippable; raise immediately after mobile + photos lands.

## Estimated effort

5–7 focused days:
- 1 day: Storage bucket + photos table + `<PhotoSection>` backbone
- 1 day: `useViewport` + `<Sheet>` + `<BottomNav>` + `<IconRail>` + mode toggle
- 1 day: Touch-target pass across existing pages
- 1.5 days: Mechanic mode (default filter, "My WOs" dashboard, nav trim)
- 1 day: DOT inspection touch redesign + per-item camera
- 0.5–1 day: Verification + buffer
