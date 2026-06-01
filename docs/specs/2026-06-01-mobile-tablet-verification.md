# Mobile / tablet verification checklist

Run through this on a real Android tablet (and on the desktop too, since the responsive code now affects both). Each box should pass; flag anything that doesn't.

## On desktop (≥1100px)

- [ ] Sidebar (230px) renders as before; no icon rail, no bottom nav.
- [ ] All existing pages look identical to before the mobile work.
- [ ] Modals open as centered cards (NOT full-screen).
- [ ] Work Orders kanban still scrolls horizontally; columns are 260px min (was 200).
- [ ] DOT inspection components now show OK/Repair/N/A as colored segmented buttons instead of dropdowns — looks fine and still saves.

## On tablet landscape (~900–1099px)

- [ ] Sidebar collapses to a 64px **icon rail** on the left.
- [ ] Hover over an icon → tooltip with the page name (`title` attribute).
- [ ] Top bar appears at the top of the content area with the current page name.
- [ ] If logged in as `role=mechanic`: 🔧 Shop view / 🖥 Full view toggle shows in top bar. Tap it; nav switches between trimmed (Work Orders / Reminders / Inventory / Dashboard) and full.
- [ ] WO modal tabs (📷 / 🔧 Jobs / 🔩 Parts / 🧴 Supply / 📝 Notes / 🛡️ DOT / 🔔 Reminders) scroll horizontally instead of wrapping.

## On tablet portrait or phone (<900px)

- [ ] Sidebar/icon rail gone; **bottom nav** appears with 5 items (4 page icons + ⋯ More).
- [ ] Tap ⋯ More → drawer slides up showing the overflow pages.
- [ ] Any modal (WO, customer, equipment, reminder) opens **full-screen** instead of a centered card.
- [ ] Reminders page: table replaced with stacked **cards** (no horizontal scroll). Tap targets ≥44px.
- [ ] Inputs in any form are at least 46px tall, 15px font.

## Mechanic mode (`role=mechanic` + viewport <1100px)

- [ ] Default = Shop view: nav has only Dashboard / Work Orders / Reminders / Inventory.
- [ ] Dashboard title reads "**My Work**"; tiles show My open WOs / In progress / Waiting for parts / Overdue reminders.
- [ ] Work Orders: amber banner reads "Showing work orders assigned to <your name>". Only WOs whose `mechanic` matches show.
- [ ] Tap 🖥 Full view → full nav returns, banner disappears.

## Photo capture (every entity)

For each of these, tap "📷 Add Photo" → camera opens → take/pick photo → it appears within ~2s as a thumbnail. Tap thumbnail → lightbox. Tap × in lightbox to close. Tap × on thumbnail → confirm → photo deletes.

- [ ] Work Order → 📷 Photos tab.
- [ ] Work Order → 🔧 Jobs tab → inside any job card → compact photo strip.
- [ ] Work Order → 🔩 Parts tab → inside any part card → compact photo strip.
- [ ] Work Order → 🛡️ DOT Inspection tab → next to any component row → compact photo button.
- [ ] Customers page → any customer card → compact photo strip at the bottom.
- [ ] Customer card → 🚛 Equipment → any equipment row → compact photo strip at the bottom.

Verify on Supabase that each upload shows in:
- `public.photos` table — one row per upload with the right `entity_type`/`entity_id`.
- `tms-photos` storage bucket — one file under the matching path.
- `public.audit_log` — entry with `action=create`, `entity_type=photo`.

## Known limitations to remember

- Mechanic mode requires a user with `role=mechanic` in the `users` table to test. If you don't have one, create one in Settings.
- "Shop view" only kicks in when viewport <1100px. On a real desktop, mechanics see the full nav by default — that's intentional.
- The Reminders page reverts to a full sortable table at ≥900px. Column header sorts only work on the table view.
- Photo bucket is publicly readable. Anyone with a URL can view the image. RLS / auth work is the planned next undertaking after this lands.
