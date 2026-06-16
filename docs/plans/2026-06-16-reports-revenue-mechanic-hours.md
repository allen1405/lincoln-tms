# Reports: rate×hours revenue + mechanic hours + admin-only

**Date:** 2026-06-16

## Decisions (from operator)
- `work_orders.labor` is reinterpreted as an **hourly rate** ($/hr).
- **Revenue per WO = rate × (sum of that WO's `jobs.labor` hours) + parts.** Applied **everywhere**: Dashboard tile, Reports, Invoices, Estimates, Salaries.
- **Backfill:** one-time set rate-less WOs (labor 0/null) to **$160**; the 15 WOs that already have a rate keep it.
- **New WOs:** labor field starts **blank**, filled manually; relabel it clearly as the hourly rate.
- **Mechanic hours:** sum `jobs.labor` grouped by `jobs.mechanic`, filtered by the **WO service date** (`work_orders.date`), presets Today / This week / This month / All time.
- **Admin only:** the Reports tab (nav hidden + component guard) and the Dashboard Revenue tile are visible only to `role==='admin'` (Catalin).

## Tasks

### 1. Backfill (one-time, Supabase)
`update work_orders set labor=160 where coalesce(labor,0)=0;` — verify count ≈ 42, then spot-check.

### 2. Shared helpers (module level, near `todayLocal` ~269)
```
const woHoursMap = jobs => { const m={}; (jobs||[]).forEach(j=>{ if(j.work_order_id!=null) m[j.work_order_id]=(m[j.work_order_id]||0)+Number(j.labor||0); }); return m; };
const woRevenue  = (w,hours) => (Number(w.labor)||0)*(hours||0) + (Number(w.parts)||0);
```

### 3. WO form (renderWoForm + `empty`)
- `empty`: `labor:0` → `labor:""`.
- Field: `label="Labor ($)"` → `label="Labor rate ($/hr)"`, add `placeholder="e.g. 160"`.

### 4. Dashboard (~519)
- jobs select → `('work_order_id,mechanic,labor')`.
- `const hrs=woHoursMap(jobs); const revenue=wos.reduce((s,w)=>s+woRevenue(w,hrs[w.id]),0);`
- Revenue tile only for admin: in the non-shop tiles array, `...(user.role==="admin"?[{l:"Revenue",...}]:[])`.

### 5. Reports (~2609) — admin gate + revenue + mechanic hours
- `const user=useContext(UserCtx); ... if(user.role!=="admin") return <⛔ Admin access only>;`
- Load WOs (non-voided) + jobs(`work_order_id,mechanic,labor`).
- Revenue: `hrs=woHoursMap(jobs); labor=Σ woRevenue minus parts → compute labor=Σ rate*hrs[w.id]; parts=Σ parts; total=labor+parts.`
- New card: **Hours by Mechanic** with period segmented control (Today/This week/This month/All). Build `woById`, `inPeriod(date)`, sum job hours per mechanic where the job's WO date is in period; sort desc; show total. Mobile: stack the grid (already `1fr` on mobile).

### 6. Invoices (~2637) & Estimates (~2656)
Load jobs too; Total cell = `woRevenue(w, hrs[w.id])`.

### 7. Salaries (~2580)
Load jobs; `woById`; per mechanic Labor Revenue = Σ over their jobs of `rate(WO)×job.labor`. Replace `myWos.reduce(...labor)`.

### 8. NAV / routing (~466, ~2890)
- Add `admin:true` to the `reports` NAV entry.
- `activeNav = (shopActive?NAV.filter(n=>n.shop):NAV).filter(n=>!n.admin||user.role==="admin");`

### 9. Verify
`python3 scripts/build.py`; review agent on diff; manual: admin sees Reports + revenue, mechanic does not; revenue = rate×hours+parts; mechanic-hours periods filter correctly. Push.
