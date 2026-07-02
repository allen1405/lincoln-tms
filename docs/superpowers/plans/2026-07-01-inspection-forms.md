# Inspection Forms Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two fillable-saved-printable inspection forms to Lincoln TMS — the full **Outbound/Inbound Inspection** (A2C fleet only, on the work order) and the **Inspection Results** page (any truck, on non-A2C work orders + a standalone Inspections page).

**Architecture:** Follows the existing DOT-inspection pattern exactly (state object in the `WorkOrders` component → `upsert` to Supabase keyed by `work_order_id` → print via `window.open` with LTTR letterhead + auto-signature). Two new tables (`outbound_inspections`, `inspections`). Shared, top-level `FindingsEditor` component and two top-level print builders keep the three surfaces DRY. A new top-level `Inspections` page component hosts standalone results.

**Tech Stack:** Single-file React 18 + babel-standalone in `index.html`; supabase-js v2 (global `sb`); Supabase MCP for the migration; GitHub Pages deploy on push to `main`.

**Verification model:** This repo has **no unit-test framework**. The established gate (used by every prior feature) is `python3 scripts/build.py` — an esbuild **parse-check** (syntax only, not runtime). Each task's "test" step runs that plus explicit manual/live checks. A render-time exception blanks the screen, so manual load-checks matter.

**Key domain fact:** A2C is customer **"A2C Logistics CO"** (id 1). A truck is "A2C's" when `work_order.customer === "A2C Logistics CO"`.

---

## File Structure

Everything lives in `index.html` (single-file app — do not restructure). New code is added at these anchors:

- **Constants block** (near `SHOP`, `index.html:169`): `A2C_NAME`, `CHECKLIST_LABELS`, `PARTS_VENDORS`.
- **Top-level helpers/components** (near other top-level components, e.g. before `const WorkOrders`, ~`index.html:920`): `FindingsEditor`, `printInspectionResults`, `printOutboundInspection`.
- **Inside `WorkOrders`** (the component that owns `jobsModal`/`jobTab`, ~`index.html:920`–`2090`): outbound + results state, load/save handlers, two new job-modal tabs.
- **`AUDIT_ENTITIES`** (`index.html:166`): add `"outbound_inspection"`, `"inspection"`.
- **`Inspections` page component** (new top-level component, add near `const Estimates`, ~`index.html:2914`).
- **`NAV`** (`index.html:538`) and the **`pages` map** (`index.html:3422`): register the Inspections page.

---

## Task 1: Database tables, constants, audit entities

**Files:**
- Migration: Supabase MCP `apply_migration`
- Modify: `index.html:166` (AUDIT_ENTITIES), `index.html:169` (constants)

- [ ] **Step 1: Create the two tables via Supabase MCP `apply_migration`**

Name: `inspection_forms`. SQL:

```sql
create table if not exists public.outbound_inspections (
  id bigint generated always as identity primary key,
  work_order_id bigint unique,
  inspection_date date,
  done_by text,
  unit_number text,
  vehicle_kind text,
  came_with text,
  truck_trailer_service boolean default false,
  apu_service boolean default false,
  reason_here text,
  mileage text,
  apu_hours text,
  reefer_hours text,
  last_annual_date date,
  do_new_annual boolean,
  checklist jsonb default '[]'::jsonb,
  parts_ordered jsonb default '{}'::jsonb,
  findings jsonb default '[]'::jsonb,
  created_by text,
  updated_at timestamptz default now()
);

create table if not exists public.inspections (
  id bigint generated always as identity primary key,
  work_order_id bigint unique,
  customer text,
  unit_number text,
  vin text,
  inspection_date date,
  inspector text,
  findings jsonb default '[]'::jsonb,
  created_by text,
  updated_at timestamptz default now()
);
```

Note: `work_order_id` is `unique` (nullable) on both so `upsert(..., {onConflict:'work_order_id'})` works for WO-linked records; standalone `inspections` rows have `work_order_id = null` (Postgres allows many NULLs under a UNIQUE constraint). RLS is intentionally left off (app-wide posture; tracked separately).

- [ ] **Step 2: Verify tables exist**

Run (Bash):
```bash
curl -s -o /dev/null -w "%{http_code}\n" "https://paytgvlfkqpyyxoqvaqn.supabase.co/rest/v1/outbound_inspections?select=id&limit=1" -H "apikey: sb_publishable_8U6IiUfM6Q9QaJ5tP0uhMQ_cN-rUNrv"
curl -s -o /dev/null -w "%{http_code}\n" "https://paytgvlfkqpyyxoqvaqn.supabase.co/rest/v1/inspections?select=id&limit=1" -H "apikey: sb_publishable_8U6IiUfM6Q9QaJ5tP0uhMQ_cN-rUNrv"
```
Expected: `200` on both lines.

- [ ] **Step 3: Add audit entity types**

In `index.html:166`, change:
```js
const AUDIT_ENTITIES = ["work_order","customer","equipment","reminder","job","part","note","appointment","user","shop_supply","dot_inspection","photo"];
```
to append the two new entities:
```js
const AUDIT_ENTITIES = ["work_order","customer","equipment","reminder","job","part","note","appointment","user","shop_supply","dot_inspection","photo","outbound_inspection","inspection"];
```

- [ ] **Step 4: Add form constants**

Immediately AFTER `const SHOP = {...};` (`index.html:169`), add:
```js
const A2C_NAME = "A2C Logistics CO";
// Fixed checklist rows on the Outbound/Inbound form (left column then right column, per the paper form).
const CHECKLIST_LABELS = ["NY Sticker on truck","Fridge","Microwave","ELD","Tablet","BestPass","Truck Keys","Straps","Chains","Oil","Coolant","Windshield Washer","Windshield Wipers","Fire Extinguisher","Reflective Triangles","Fridge Empty","Cabin Empty","Cabinets Empty"];
const PARTS_VENDORS = ["International","Freightliner","Kenworth","Peterbilt","Volvo"];
```

- [ ] **Step 5: Parse-check**

Run: `python3 scripts/build.py`
Expected: `Wrote dist/index.html (... KB, babel-standalone removed)` and exit 0.

- [ ] **Step 6: Commit**

```bash
git add index.html && git commit -m "Inspection forms: tables + constants + audit entities

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Shared FindingsEditor component + two print builders

These are top-level (module-scope) so all three surfaces reuse them. Add them just BEFORE `const WorkOrders` (~`index.html:920`; find the line `const WorkOrders = () => {` and insert above it).

**Files:**
- Modify: `index.html` (~920, insert above `const WorkOrders`)

- [ ] **Step 1: Add the `FindingsEditor` component**

`findings` is an array of `{checked:boolean, text:string}`. `onChange` receives the new array.

```jsx
// Reusable page-2 "Inspection Results" editor: a dynamic checkbox + free-text finding list.
const FindingsEditor = ({findings, onChange}) => {
  const rows = findings && findings.length ? findings : [];
  const set = (i, patch) => onChange(rows.map((r, idx) => idx === i ? {...r, ...patch} : r));
  const add = () => onChange([...rows, {checked:false, text:""}]);
  const del = (i) => onChange(rows.filter((_, idx) => idx !== i));
  return (
    <div>
      {rows.length === 0 && <p style={{color:"#aaa",fontSize:13,margin:"6px 0"}}>No findings yet — add the first result below.</p>}
      {rows.map((r, i) => (
        <div key={i} style={{display:"flex",alignItems:"center",gap:8,marginBottom:6}}>
          <input type="checkbox" checked={!!r.checked} onChange={e=>set(i,{checked:e.target.checked})} style={{width:18,height:18,flex:"0 0 auto",cursor:"pointer"}}/>
          <input value={r.text||""} onChange={e=>set(i,{text:e.target.value})} placeholder="Result / finding…" style={{flex:1,padding:"8px 10px",border:"1px solid #ddd",borderRadius:8,fontSize:13}}/>
          <button onClick={()=>del(i)} title="Remove" style={{padding:"6px 10px",background:"#f0f0f0",border:"none",borderRadius:8,cursor:"pointer",flex:"0 0 auto"}}>🗑</button>
        </div>
      ))}
      <button onClick={add} style={{marginTop:4,padding:"8px 14px",background:"#1a1a2e",color:"#fff",border:"none",borderRadius:8,cursor:"pointer",fontSize:13,fontWeight:600}}>＋ Add finding</button>
    </div>
  );
};
```

- [ ] **Step 2: Add the `printInspectionResults` builder**

Mirrors `printDot` (`index.html:1210`): opens window synchronously, fetches signature, writes an LTTR-letterhead page. `rec` is an `inspections`-shaped object (or the findings section of an outbound record). `user` gives the signer.

```jsx
// Print the page-2 "Inspection Results" sheet alone. rec: {unit_number, customer, inspection_date, inspector, findings[]}.
async function printInspectionResults(rec, user) {
  const w = window.open("", "_blank");
  if (!w) { alert("Pop-up blocked — allow pop-ups to print."); return; }
  const esc = s => String(s || "").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
  let sigImg = ""; try { const {data} = await sb.from('users').select('signature').eq('id', user.id).maybeSingle(); sigImg = (data && data.signature) || ""; } catch(_) {}
  const findings = (rec.findings || []);
  const rowsHtml = findings.map(f => `<tr><td class="chk">${f.checked ? "☑" : "☐"}</td><td class="txt">${esc(f.text)}</td></tr>`).join("")
    // pad to a full-looking sheet like the paper form
    + Array.from({length: Math.max(0, 24 - findings.length)}).map(() => `<tr><td class="chk">☐</td><td class="txt">&nbsp;</td></tr>`).join("");
  const html = `<!DOCTYPE html><html><head><title></title><style>
    @page{size:letter;margin:10mm}
    *{box-sizing:border-box;-webkit-print-color-adjust:exact;print-color-adjust:exact}
    body{font-family:Arial,Helvetica,sans-serif;color:#000;margin:0;font-size:11px}
    .shop{display:flex;justify-content:space-between;align-items:flex-end;border-bottom:1px solid #555;padding-bottom:4px;margin-bottom:8px}
    .shop .name{font-weight:bold;font-size:14px}.shop .addr{font-size:10px;color:#333}
    h1{text-align:center;font-size:15px;letter-spacing:1px;margin:6px 0 10px}
    .hdr{display:flex;gap:20px;font-size:11px;margin-bottom:8px}.hdr b{font-size:8px;text-transform:uppercase;color:#333;display:block}
    table.res{width:100%;border-collapse:collapse}
    table.res td{border:1px solid #555;padding:5px 7px}
    table.res td.chk{width:22px;text-align:center;font-size:14px}
    .sig{display:flex;justify-content:flex-end;gap:14px;margin-top:14px}
    .sig .sigcell{text-align:center}.sig .sigcontent{height:34px;display:flex;align-items:flex-end;justify-content:center}
    .sig .sigimg{max-height:34px;max-width:150px}.sig .line{border-top:1px solid #000;width:150px;padding-top:2px;font-size:8px}
  </style></head><body>
    <div class="shop"><div><div class="name">${esc(SHOP.name)}</div><div class="addr">${esc(SHOP.address)}</div></div></div>
    <h1>INSPECTION RESULTS</h1>
    <div class="hdr">
      <div><b>Unit #</b>${esc(rec.unit_number)}</div>
      <div><b>Customer</b>${esc(rec.customer) || "—"}</div>
      <div><b>Date</b>${esc(rec.inspection_date)}</div>
      <div><b>Done by</b>${esc(rec.inspector)}</div>
    </div>
    <table class="res"><tbody>${rowsHtml}</tbody></table>
    <div class="sig"><div class="sigcell"><div class="sigcontent">${sigImg ? `<img class="sigimg" src="${sigImg}"/>` : ""}</div><div class="line">Signature</div></div></div>
  </body></html>`;
  w.document.write(html); w.document.close(); w.focus(); setTimeout(() => w.print(), 250);
}
```

- [ ] **Step 3: Add the `printOutboundInspection` builder**

Prints page 1 (header + details + two-column checklist + Parts Ordered) then the findings sheet. `rec` is an `outbound_inspections`-shaped object.

```jsx
// Print the full A2C Outbound/Inbound form: page 1 (fields, checklist, parts) + page 2 (findings).
async function printOutboundInspection(rec, user) {
  const w = window.open("", "_blank");
  if (!w) { alert("Pop-up blocked — allow pop-ups to print."); return; }
  const esc = s => String(s || "").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
  const chk = b => b ? "☑" : "☐";
  const ynYes = rec.do_new_annual === true, ynNo = rec.do_new_annual === false;
  let sigImg = ""; try { const {data} = await sb.from('users').select('signature').eq('id', user.id).maybeSingle(); sigImg = (data && data.signature) || ""; } catch(_) {}
  const items = rec.checklist || [];
  const half = Math.ceil(items.length / 2);
  const colRows = arr => arr.map(it => `<tr><td class="c">${chk(it.checked)}</td><td class="l">${esc(it.label)}</td><td class="q">${esc(it.note)}</td></tr>`).join("");
  const po = rec.parts_ordered || {vendors:[],other:"",lines:[]};
  const vendorHtml = PARTS_VENDORS.map(v => `<span>${(po.vendors||[]).includes(v) ? "☑" : "☐"} ${v}</span>`).join("")
    + `<span>${(po.other||"").trim() ? "☑" : "☐"} Other ${esc(po.other)}</span>`;
  const partLines = (po.lines || []).map(ln => `<tr><td>${esc(ln.text)}</td></tr>`).join("")
    + Array.from({length: Math.max(0, 6 - (po.lines || []).length)}).map(() => `<tr><td>&nbsp;</td></tr>`).join("");
  const findings = (rec.findings || []);
  const findingRows = findings.map(f => `<tr><td class="chk">${chk(f.checked)}</td><td>${esc(f.text)}</td></tr>`).join("")
    + Array.from({length: Math.max(0, 24 - findings.length)}).map(() => `<tr><td class="chk">☐</td><td>&nbsp;</td></tr>`).join("");
  const html = `<!DOCTYPE html><html><head><title></title><style>
    @page{size:letter;margin:8mm}
    *{box-sizing:border-box;-webkit-print-color-adjust:exact;print-color-adjust:exact}
    body{font-family:Arial,Helvetica,sans-serif;color:#000;margin:0;font-size:10px}
    .shop{display:flex;justify-content:space-between;align-items:flex-end;border-bottom:1px solid #555;padding-bottom:4px;margin-bottom:6px}
    .shop .name{font-weight:bold;font-size:13px}.shop .addr{font-size:9px;color:#333}.shop .title{font-weight:bold;font-size:14px}
    .row{display:flex;gap:16px;margin-bottom:4px;flex-wrap:wrap}
    .fld{font-size:10px}.fld b{font-size:7.5px;text-transform:uppercase;color:#333;display:block}
    .fld .v{border-bottom:1px solid #888;min-width:120px;min-height:13px;font-weight:bold;padding:1px 2px}
    .checks{display:grid;grid-template-columns:1fr 1fr;gap:0 10px;margin-top:6px}
    table.ck{width:100%;border-collapse:collapse}
    table.ck td{border-bottom:1px solid #ccc;padding:3px 4px;font-size:9.5px}
    table.ck td.c{width:16px;text-align:center;font-size:12px}table.ck td.q{color:#333;border-left:1px solid #eee}
    .ck-hd{background:#1a1a2e;color:#fff;font-weight:bold;font-size:8.5px;padding:2px 5px;display:flex;justify-content:space-between}
    .parts{border:1px solid #555;margin-top:8px}
    .parts-hd{background:#1a1a2e;color:#fff;font-weight:bold;text-align:center;padding:3px;font-size:11px}
    .parts .from{font-size:9.5px;padding:4px 6px;border-bottom:1px solid #555}.parts .from span{margin-right:10px}
    table.pl{width:100%;border-collapse:collapse}table.pl td{border-bottom:1px solid #ccc;padding:4px 6px;min-height:16px}
    .pagebreak{page-break-before:always}
    h2{text-align:center;font-size:13px;letter-spacing:1px;margin:6px 0}
    table.res{width:100%;border-collapse:collapse}table.res td{border:1px solid #555;padding:5px 7px;font-size:11px}table.res td.chk{width:22px;text-align:center;font-size:14px}
    .sig{display:flex;justify-content:flex-end;gap:14px;margin-top:12px}.sig .sigcontent{height:34px;display:flex;align-items:flex-end;justify-content:center}.sig .sigimg{max-height:34px;max-width:150px}.sig .line{border-top:1px solid #000;width:150px;padding-top:2px;font-size:8px;text-align:center}
  </style></head><body>
    <div class="shop"><div><div class="name">${esc(SHOP.name)}</div><div class="addr">${esc(SHOP.address)}</div></div><div class="title">Outbound / Inbound Inspection</div></div>
    <div class="row">
      <div class="fld"><b>Date</b><div class="v">${esc(rec.inspection_date)}</div></div>
      <div class="fld"><b>Done by</b><div class="v">${esc(rec.done_by)}</div></div>
      <div class="fld"><b>Unit</b><div class="v">${esc(rec.unit_number)}</div></div>
      <div class="fld"><b>Type</b><div class="v">${esc(rec.vehicle_kind)}</div></div>
      <div class="fld"><b>Came with</b><div class="v">${esc(rec.came_with)}</div></div>
    </div>
    <div class="row">
      <div class="fld">${chk(rec.truck_trailer_service)} Truck / Trailer Service</div>
      <div class="fld">${chk(rec.apu_service)} APU Service</div>
      <div class="fld">Do a new annual inspection? ${ynYes ? "☑" : "☐"} Yes &nbsp; ${ynNo ? "☑" : "☐"} No</div>
    </div>
    <div class="row">
      <div class="fld"><b>Reason why here</b><div class="v" style="min-width:260px">${esc(rec.reason_here)}</div></div>
    </div>
    <div class="row">
      <div class="fld"><b>Mileage</b><div class="v">${esc(rec.mileage)}</div></div>
      <div class="fld"><b>APU hours</b><div class="v">${esc(rec.apu_hours)}</div></div>
      <div class="fld"><b>Reefer hours</b><div class="v">${esc(rec.reefer_hours)}</div></div>
      <div class="fld"><b>Last annual inspection</b><div class="v">${esc(rec.last_annual_date)}</div></div>
    </div>
    <div class="checks">
      <div><div class="ck-hd"><span></span><span>Quantity / Comments</span></div><table class="ck"><tbody>${colRows(items.slice(0, half))}</tbody></table></div>
      <div><div class="ck-hd"><span></span><span>Quantity / Comments</span></div><table class="ck"><tbody>${colRows(items.slice(half))}</tbody></table></div>
    </div>
    <div class="parts"><div class="parts-hd">PARTS ORDERED</div><div class="from">From: ${vendorHtml}</div><table class="pl"><tbody>${partLines}</tbody></table></div>
    <div class="pagebreak"></div>
    <div class="shop"><div><div class="name">${esc(SHOP.name)}</div><div class="addr">${esc(SHOP.address)}</div></div></div>
    <h2>INSPECTION RESULTS</h2>
    <table class="res"><tbody>${findingRows}</tbody></table>
    <div class="sig"><div class="sigcell"><div class="sigcontent">${sigImg ? `<img class="sigimg" src="${sigImg}"/>` : ""}</div><div class="line">Signature</div></div></div>
  </body></html>`;
  w.document.write(html); w.document.close(); w.focus(); setTimeout(() => w.print(), 250);
}
```

- [ ] **Step 4: Parse-check**

Run: `python3 scripts/build.py`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add index.html && git commit -m "Inspection forms: shared FindingsEditor + print builders

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Outbound/Inbound tab on A2C work orders

All edits are inside the `WorkOrders` component. It already owns `jobsModal` (`index.html:924`), `jobTab` (`index.html:925`), `customers`, `openJobs` (`index.html:1155`), the combined-modal opener (`index.html:1164`), the tab buttons (`index.html:1715`–`1721`), and the tab-content blocks (`index.html:1723`+). `user` is in scope.

**Files:**
- Modify: `index.html` (WorkOrders component)

- [ ] **Step 1: Add outbound state**

Right after `const [jobsList,setJobsList]=useState([]); const [jobTab,setJobTab]=useState("jobs");` (`index.html:925`), add:
```js
  const [outb,setOutb]=useState(null);
```

- [ ] **Step 2: Add blank + load + field helpers**

Add these just AFTER `setDotField`/`setDotComp` (i.e. after `index.html:1201`, before `saveDot`):
```js
  const blankOutbound=(wo)=>({
    inspection_date:todayLocal(), done_by:user.name||"", unit_number:wo.unit_number||"",
    vehicle_kind:wo.vehicle_type||"", came_with:"", truck_trailer_service:false, apu_service:false,
    reason_here:"", mileage:wo.truck_mileage??"", apu_hours:wo.apu_hours??"", reefer_hours:wo.reefer_hours??"",
    last_annual_date:null, do_new_annual:null,
    checklist:CHECKLIST_LABELS.map(l=>({label:l,checked:false,note:""})),
    parts_ordered:{vendors:[],other:"",lines:[]}, findings:[]
  });
  const loadOutbound=async(wo)=>{
    const{data}=await sb.from('outbound_inspections').select('*').eq('work_order_id',wo.id).maybeSingle();
    setOutb(data?{...blankOutbound(wo),...data,checklist:(data.checklist&&data.checklist.length)?data.checklist:blankOutbound(wo).checklist,parts_ordered:data.parts_ordered||{vendors:[],other:"",lines:[]},findings:data.findings||[]}:blankOutbound(wo));
  };
  const setOutbField=(k,v)=>setOutb(p=>({...p,[k]:v}));
  const setOutbCheck=(i,patch)=>setOutb(p=>({...p,checklist:p.checklist.map((it,idx)=>idx===i?{...it,...patch}:it)}));
  const addOutbRow=()=>setOutb(p=>({...p,checklist:[...p.checklist,{label:"",checked:false,note:""}]}));
  const setOutbVendor=(v,on)=>setOutb(p=>({...p,parts_ordered:{...p.parts_ordered,vendors:on?[...(p.parts_ordered.vendors||[]),v]:(p.parts_ordered.vendors||[]).filter(x=>x!==v)}}));
  const addPartLine=()=>setOutb(p=>({...p,parts_ordered:{...p.parts_ordered,lines:[...(p.parts_ordered.lines||[]),{text:""}]}}));
  const setPartLine=(i,text)=>setOutb(p=>({...p,parts_ordered:{...p.parts_ordered,lines:p.parts_ordered.lines.map((ln,idx)=>idx===i?{text}:ln)}}));
```

- [ ] **Step 3: Add save handler**

Add just AFTER `saveDot` (after `index.html:1209`):
```js
  const saveOutbound=async()=>{
    const payload={work_order_id:jobsModal.id,inspection_date:outb.inspection_date||null,done_by:outb.done_by,unit_number:outb.unit_number,vehicle_kind:outb.vehicle_kind,came_with:outb.came_with,truck_trailer_service:!!outb.truck_trailer_service,apu_service:!!outb.apu_service,reason_here:outb.reason_here,mileage:outb.mileage,apu_hours:outb.apu_hours,reefer_hours:outb.reefer_hours,last_annual_date:outb.last_annual_date||null,do_new_annual:outb.do_new_annual,checklist:outb.checklist,parts_ordered:outb.parts_ordered,findings:outb.findings,created_by:user.name,updated_at:new Date().toISOString()};
    const res=await sb.from('outbound_inspections').upsert(payload,{onConflict:'work_order_id'}).select().single();
    if(res.error){alert("Could not save inspection: "+res.error.message);return;}
    setOutb({...blankOutbound(jobsModal),...res.data});
    audit(user,"update","outbound_inspection",jobsModal.id,`${jobsModal.id} — ${jobsModal.customer}`,`unit ${outb.unit_number||"—"}`);
    alert("Outbound/Inbound inspection saved.");
  };
```

- [ ] **Step 4: Load it when the modal opens**

In `openJobs` (`index.html:1155`), add `loadOutbound(wo)` to the `Promise.all`:
```js
  const openJobs=async(wo)=>{setJobsModal(wo);setJobTab("jobs");setShopSupply(wo.shop_supply||"");shopSupplySaved.current=wo.shop_supply||"";setRemForm({id:null,reminder_date:"",note:""});await Promise.all([loadJobs(wo.id),loadNotes(wo.id),loadParts(wo.id),loadDot(wo),loadDotPhotos(wo.id),loadWoReminders(wo.id),loadEqItems(wo),loadOutbound(wo)]);};
```
And in the combined-modal opener (`index.html:1164`), append `,loadOutbound(w)` to its `Promise.all` the same way.

- [ ] **Step 5: Add the tab button (A2C only)**

After the DOT tab button (`index.html:1719`), add:
```jsx
            {jobsModal.customer===A2C_NAME&&<button className={`tab-btn${jobTab==="outbound"?" active":""}`} onClick={()=>setJobTab("outbound")}>🚚 Outbound/Inbound</button>}
```

- [ ] **Step 6: Add the tab content**

After the DOT tab content block (find `{jobTab==="dot"&&(` … its closing `)}`, then insert after it). If `outb` is null render nothing. Use existing `Field`:
```jsx
          {jobTab==="outbound"&&outb&&(
            <div style={{padding:"4px 2px"}}>
              <div style={{display:"grid",gridTemplateColumns:"1fr 1fr 1fr",gap:12}}>
                <Field label="Date" type="date" value={outb.inspection_date||""} onChange={v=>setOutbField("inspection_date",v)}/>
                <Field label="Done by" value={outb.done_by||""} onChange={v=>setOutbField("done_by",v)}/>
                <Field label="Unit #" value={outb.unit_number||""} onChange={v=>setOutbField("unit_number",v)}/>
                <Field label="Type" value={outb.vehicle_kind||""} onChange={v=>setOutbField("vehicle_kind",v)} options={["","Truck","Trailer"]}/>
                <Field label="Came with" value={outb.came_with||""} onChange={v=>setOutbField("came_with",v)}/>
                <Field label="Last annual inspection date" type="date" value={outb.last_annual_date||""} onChange={v=>setOutbField("last_annual_date",v)}/>
                <Field label="Mileage" value={outb.mileage||""} onChange={v=>setOutbField("mileage",v)}/>
                <Field label="APU hours" value={outb.apu_hours||""} onChange={v=>setOutbField("apu_hours",v)}/>
                <Field label="Reefer hours" value={outb.reefer_hours||""} onChange={v=>setOutbField("reefer_hours",v)}/>
              </div>
              <Field label="Reason why here" type="textarea" value={outb.reason_here||""} onChange={v=>setOutbField("reason_here",v)}/>
              <div style={{display:"flex",gap:20,margin:"8px 0",flexWrap:"wrap",fontSize:13}}>
                <label style={{cursor:"pointer"}}><input type="checkbox" checked={!!outb.truck_trailer_service} onChange={e=>setOutbField("truck_trailer_service",e.target.checked)}/> Truck / Trailer Service</label>
                <label style={{cursor:"pointer"}}><input type="checkbox" checked={!!outb.apu_service} onChange={e=>setOutbField("apu_service",e.target.checked)}/> APU Service</label>
                <span>Do a new annual inspection?
                  <label style={{cursor:"pointer",marginLeft:8}}><input type="radio" name="dna" checked={outb.do_new_annual===true} onChange={()=>setOutbField("do_new_annual",true)}/> Yes</label>
                  <label style={{cursor:"pointer",marginLeft:8}}><input type="radio" name="dna" checked={outb.do_new_annual===false} onChange={()=>setOutbField("do_new_annual",false)}/> No</label>
                </span>
              </div>
              <h4 style={{margin:"14px 0 6px"}}>Checklist</h4>
              <div style={{display:"grid",gridTemplateColumns:"1fr",gap:6}}>
                {outb.checklist.map((it,i)=>(
                  <div key={i} style={{display:"flex",alignItems:"center",gap:8}}>
                    <input type="checkbox" checked={!!it.checked} onChange={e=>setOutbCheck(i,{checked:e.target.checked})} style={{width:18,height:18,cursor:"pointer"}}/>
                    <input value={it.label} onChange={e=>setOutbCheck(i,{label:e.target.value})} placeholder="Item" style={{width:180,padding:"6px 8px",border:"1px solid #ddd",borderRadius:6,fontSize:13}}/>
                    <input value={it.note} onChange={e=>setOutbCheck(i,{note:e.target.value})} placeholder="Quantity / comments" style={{flex:1,padding:"6px 8px",border:"1px solid #ddd",borderRadius:6,fontSize:13}}/>
                  </div>
                ))}
              </div>
              <button onClick={addOutbRow} style={{marginTop:6,padding:"6px 12px",background:"#eee",border:"none",borderRadius:8,cursor:"pointer",fontSize:12}}>＋ Add item</button>
              <h4 style={{margin:"14px 0 6px"}}>Parts Ordered</h4>
              <div style={{display:"flex",gap:14,flexWrap:"wrap",fontSize:13,marginBottom:6}}>
                {PARTS_VENDORS.map(v=>(<label key={v} style={{cursor:"pointer"}}><input type="checkbox" checked={(outb.parts_ordered.vendors||[]).includes(v)} onChange={e=>setOutbVendor(v,e.target.checked)}/> {v}</label>))}
                <label style={{cursor:"pointer",display:"flex",alignItems:"center",gap:4}}>Other <input value={outb.parts_ordered.other||""} onChange={e=>setOutbField("parts_ordered",{...outb.parts_ordered,other:e.target.value})} style={{padding:"4px 6px",border:"1px solid #ddd",borderRadius:6,fontSize:13,width:120}}/></label>
              </div>
              {(outb.parts_ordered.lines||[]).map((ln,i)=>(<input key={i} value={ln.text} onChange={e=>setPartLine(i,e.target.value)} placeholder="Part…" style={{display:"block",width:"100%",padding:"6px 8px",border:"1px solid #ddd",borderRadius:6,fontSize:13,marginBottom:4}}/>))}
              <button onClick={addPartLine} style={{padding:"6px 12px",background:"#eee",border:"none",borderRadius:8,cursor:"pointer",fontSize:12}}>＋ Add part</button>
              <h4 style={{margin:"14px 0 6px"}}>Inspection Results</h4>
              <FindingsEditor findings={outb.findings} onChange={f=>setOutbField("findings",f)}/>
              <div style={{display:"flex",justifyContent:"flex-end",gap:10,marginTop:14}}>
                <button onClick={()=>printOutboundInspection({...outb,inspector:outb.done_by,customer:jobsModal.customer},user)} style={{padding:"10px 18px",background:"#1a1a2e",color:"#fff",border:"none",borderRadius:8,cursor:"pointer",fontWeight:600,fontSize:13}}>🖨 Print</button>
                <button onClick={saveOutbound} style={{padding:"10px 18px",background:"#27ae60",color:"#fff",border:"none",borderRadius:8,cursor:"pointer",fontWeight:600,fontSize:13}}>Save</button>
              </div>
            </div>
          )}
```

- [ ] **Step 7: Parse-check + manual check**

Run: `python3 scripts/build.py` → exit 0.
Manual (after deploy in Task 6, or local file open): open an A2C work order → the **🚚 Outbound/Inbound** tab appears; open a non-A2C WO → it does NOT appear. Fill fields, Save, reopen → data persists. Print → 2-page PDF with letterhead.

- [ ] **Step 8: Commit**

```bash
git add index.html && git commit -m "Inspection forms: Outbound/Inbound tab on A2C work orders

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Inspection Results tab on non-A2C work orders

Also inside `WorkOrders`. Writes to `inspections` (upsert by `work_order_id`).

**Files:**
- Modify: `index.html` (WorkOrders component)

- [ ] **Step 1: Add results state**

After the `const [outb,setOutb]=useState(null);` line from Task 3, add:
```js
  const [wores,setWores]=useState(null);
```

- [ ] **Step 2: Add blank + load helpers**

After `loadOutbound` (from Task 3 Step 2), add:
```js
  const blankResults=(wo)=>({work_order_id:wo.id,customer:wo.customer||"",unit_number:wo.unit_number||"",vin:wo.vin||"",inspection_date:todayLocal(),inspector:user.name||"",findings:[]});
  const loadResults=async(wo)=>{
    const{data}=await sb.from('inspections').select('*').eq('work_order_id',wo.id).maybeSingle();
    setWores(data?{...blankResults(wo),...data,findings:data.findings||[]}:blankResults(wo));
  };
```

- [ ] **Step 3: Add save handler**

After `saveOutbound` (Task 3 Step 3), add:
```js
  const saveResults=async()=>{
    const payload={work_order_id:jobsModal.id,customer:wores.customer,unit_number:wores.unit_number,vin:wores.vin,inspection_date:wores.inspection_date||null,inspector:wores.inspector,findings:wores.findings,created_by:user.name,updated_at:new Date().toISOString()};
    const res=await sb.from('inspections').upsert(payload,{onConflict:'work_order_id'}).select().single();
    if(res.error){alert("Could not save results: "+res.error.message);return;}
    setWores({...blankResults(jobsModal),...res.data});
    audit(user,"update","inspection",jobsModal.id,`${jobsModal.id} — ${jobsModal.customer}`,`${(wores.findings||[]).length} findings`);
    alert("Inspection results saved.");
  };
```

- [ ] **Step 4: Load when modal opens**

Append `,loadResults(wo)` to `openJobs`'s `Promise.all` and `,loadResults(w)` to the combined opener's `Promise.all` (same lines edited in Task 3 Step 4).

- [ ] **Step 5: Tab button (non-A2C only)**

Right after the Outbound tab button added in Task 3 Step 5, add:
```jsx
            {jobsModal.customer!==A2C_NAME&&<button className={`tab-btn${jobTab==="results"?" active":""}`} onClick={()=>setJobTab("results")}>📋 Inspection Results</button>}
```

- [ ] **Step 6: Tab content**

After the outbound tab content block (Task 3 Step 6), add:
```jsx
          {jobTab==="results"&&wores&&(
            <div style={{padding:"4px 2px"}}>
              <div style={{display:"grid",gridTemplateColumns:"1fr 1fr 1fr",gap:12,marginBottom:10}}>
                <Field label="Unit #" value={wores.unit_number||""} onChange={v=>setWores(p=>({...p,unit_number:v}))}/>
                <Field label="Date" type="date" value={wores.inspection_date||""} onChange={v=>setWores(p=>({...p,inspection_date:v}))}/>
                <Field label="Done by" value={wores.inspector||""} onChange={v=>setWores(p=>({...p,inspector:v}))}/>
              </div>
              <FindingsEditor findings={wores.findings} onChange={f=>setWores(p=>({...p,findings:f}))}/>
              <div style={{display:"flex",justifyContent:"flex-end",gap:10,marginTop:14}}>
                <button onClick={()=>printInspectionResults(wores,user)} style={{padding:"10px 18px",background:"#1a1a2e",color:"#fff",border:"none",borderRadius:8,cursor:"pointer",fontWeight:600,fontSize:13}}>🖨 Print</button>
                <button onClick={saveResults} style={{padding:"10px 18px",background:"#27ae60",color:"#fff",border:"none",borderRadius:8,cursor:"pointer",fontWeight:600,fontSize:13}}>Save</button>
              </div>
            </div>
          )}
```

- [ ] **Step 7: Parse-check + manual check**

`python3 scripts/build.py` → exit 0. Non-A2C WO shows **📋 Inspection Results** tab (and no Outbound tab); add findings, Save, reopen persists; Print → results sheet.

- [ ] **Step 8: Commit**

```bash
git add index.html && git commit -m "Inspection forms: Inspection Results tab on non-A2C work orders

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Standalone Inspections page + nav wiring

**Files:**
- Modify: `index.html` — add `Inspections` component (~`index.html:2914`, near `const Estimates`), NAV (`index.html:538`), pages map (`index.html:3422`).

- [ ] **Step 1: Add the `Inspections` page component**

Insert immediately BEFORE `const Estimates = () => {` (`index.html:2914`):
```jsx
const Inspections = () => {
  const user = useContext(UserCtx);
  const guard = useOnce();
  const [list,setList]=useState([]); const [loading,setLoading]=useState(true);
  const [customers,setCustomers]=useState([]);
  const [modal,setModal]=useState(false); const [rec,setRec]=useState(null); const [search,setSearch]=useState("");
  const blank=()=>({customer:"",unit_number:"",vin:"",inspection_date:todayLocal(),inspector:user.name||"",findings:[]});
  const load=async()=>{const{data}=await sb.from('inspections').select('*').order('updated_at',{ascending:false});setList(data||[]);setLoading(false);};
  const loadCustomers=async()=>{const{data}=await sb.from('customers').select('name').order('name');setCustomers((data||[]).map(c=>c.name));};
  useEffect(()=>{load();loadCustomers();},[]);
  const openNew=()=>{setRec(blank());setModal(true);};
  const openEdit=(r)=>{setRec({...blank(),...r,findings:r.findings||[]});setModal(true);};
  const close=()=>{setModal(false);setRec(null);};
  const save=async()=>{
    const payload={work_order_id:rec.work_order_id||null,customer:rec.customer||null,unit_number:rec.unit_number,vin:rec.vin||null,inspection_date:rec.inspection_date||null,inspector:rec.inspector,findings:rec.findings,created_by:user.name,updated_at:new Date().toISOString()};
    let res;
    if(rec.id){res=await sb.from('inspections').update(payload).eq('id',rec.id).select().single();}
    else{res=await sb.from('inspections').insert([payload]).select().single();}
    if(res.error){alert("Could not save: "+res.error.message);return;}
    audit(user,rec.id?"update":"create","inspection",res.data?.id,`${rec.unit_number||"—"}`,`${(rec.findings||[]).length} findings`);
    close();load();
  };
  const del=async(id)=>{if(!confirm("Delete this inspection?"))return;const r=await must(sb.from('inspections').delete().eq('id',id),"Could not delete");if(!r)return;audit(user,"delete","inspection",id,"");load();};
  if(loading) return <Loading/>;
  const q=search.toLowerCase();
  const filtered=list.filter(r=>(r.unit_number||"").toLowerCase().includes(q)||(r.customer||"").toLowerCase().includes(q));
  return (
    <div>
      <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginBottom:20}}>
        <h1 style={{margin:0,fontSize:26,fontWeight:800,color:"#1a1a2e"}}>Inspections</h1>
        <Btn label="＋ New Inspection" onClick={openNew} color="#c0392b"/>
      </div>
      <div style={{background:"#fff",borderRadius:12,padding:24,boxShadow:"0 2px 12px rgba(0,0,0,0.06)"}}>
        <div style={{display:"flex",justifyContent:"flex-end",marginBottom:14}}>
          <div style={{position:"relative"}}><span style={{position:"absolute",left:10,top:"50%",transform:"translateY(-50%)",color:"#aaa"}}>🔍</span><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search unit / customer…" style={{padding:"8px 12px 8px 32px",border:"1px solid #ddd",borderRadius:8,fontSize:13}}/></div>
        </div>
        <table style={{width:"100%",borderCollapse:"collapse"}}>
          <thead><tr><TH c="Date"/><TH c="Unit #"/><TH c="Customer"/><TH c="Done by"/><TH c="Findings"/><TH c=""/></tr></thead>
          <tbody>{filtered.length===0?<tr><td colSpan={6} style={{textAlign:"center",padding:36,color:"#aaa"}}>No inspections yet.</td></tr>:filtered.map((r,i)=>(
            <tr key={r.id} style={{background:i%2?"#fafafa":"#fff",cursor:"pointer"}} onClick={()=>openEdit(r)}>
              <td style={{padding:"10px 14px",fontSize:13,borderBottom:"1px solid #f5f5f5"}}>{fmtDay(r.inspection_date)}</td>
              <td style={{padding:"10px 14px",fontSize:13,borderBottom:"1px solid #f5f5f5",fontWeight:600}}>{r.unit_number||"—"}{r.work_order_id?<span style={{color:"#888",fontWeight:400}}> · WO {r.work_order_id}</span>:""}</td>
              <td style={{padding:"10px 14px",fontSize:13,borderBottom:"1px solid #f5f5f5"}}>{r.customer||"—"}</td>
              <td style={{padding:"10px 14px",fontSize:13,borderBottom:"1px solid #f5f5f5"}}>{r.inspector||"—"}</td>
              <td style={{padding:"10px 14px",fontSize:13,borderBottom:"1px solid #f5f5f5"}}>{(r.findings||[]).length}</td>
              <td style={{padding:"10px 14px",fontSize:13,borderBottom:"1px solid #f5f5f5"}} onClick={e=>e.stopPropagation()}><button onClick={()=>del(r.id)} style={{padding:"6px 10px",background:"#f0f0f0",border:"none",borderRadius:8,cursor:"pointer"}}>🗑</button></td>
            </tr>
          ))}</tbody>
        </table>
      </div>
      {modal&&rec&&(
        <Modal title={rec.id?"Edit Inspection":"New Inspection"} onClose={close} wide>
          <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:12}}>
            <Field label="Unit #" value={rec.unit_number||""} onChange={v=>setRec(p=>({...p,unit_number:v}))} required/>
            <div><label style={{fontSize:12,fontWeight:600,color:"#555",display:"block",marginBottom:4}}>Customer (optional)</label><Combobox value={rec.customer||""} onChange={v=>setRec(p=>({...p,customer:v}))} options={customers} placeholder="Search customer…"/></div>
            <Field label="Date" type="date" value={rec.inspection_date||""} onChange={v=>setRec(p=>({...p,inspection_date:v}))}/>
            <Field label="Done by" value={rec.inspector||""} onChange={v=>setRec(p=>({...p,inspector:v}))}/>
          </div>
          <h4 style={{margin:"14px 0 6px"}}>Inspection Results</h4>
          <FindingsEditor findings={rec.findings} onChange={f=>setRec(p=>({...p,findings:f}))}/>
          <div style={{display:"flex",justifyContent:"flex-end",gap:10,marginTop:16}}>
            <button onClick={()=>printInspectionResults(rec,user)} style={{padding:"10px 18px",background:"#1a1a2e",color:"#fff",border:"none",borderRadius:8,cursor:"pointer",fontWeight:600}}>🖨 Print</button>
            <button onClick={close} style={{padding:"10px 18px",background:"#f0f0f0",border:"none",borderRadius:8,cursor:"pointer"}}>Cancel</button>
            <button onClick={()=>guard(save)} style={{padding:"10px 18px",background:"#c0392b",color:"#fff",border:"none",borderRadius:8,cursor:"pointer",fontWeight:600}}>{rec.id?"Save Changes":"Save"}</button>
          </div>
        </Modal>
      )}
    </div>
  );
};
```

Note: `Btn`, `TH`, `Modal`, `Combobox`, `Field`, `Loading`, `UserCtx`, `useOnce`, `audit`, `must`, `fmtDay`, `todayLocal` are all existing top-level helpers already used elsewhere in the file. `Modal` supports a `wide` prop (see the reminders modal, `index.html:2271`).

- [ ] **Step 2: Add the NAV entry**

In `NAV` (`index.html:538`), add after the `orderparts`/`partsref` lines (`index.html:548`):
```js
  {id:"inspections",label:"Inspections",icon:"🔎",s:"SUPPORT",shop:true},
```

- [ ] **Step 3: Register in the pages map**

In the `pages` object (`index.html:3422`), add `inspections:<Inspections/>` — e.g. change the line containing `orderparts:<OrderParts/>,partsref:<PartsReference/>` to append:
```js
    salaries:<Salaries/>,inventory:<Inventory/>,orderparts:<OrderParts/>,partsref:<PartsReference/>,inspections:<Inspections/>,mysig:<MySignature/>,reports:<Reports/>,
```

- [ ] **Step 4: Parse-check + manual check**

`python3 scripts/build.py` → exit 0. **Inspections** appears in the sidebar; **＋ New Inspection** opens the modal; enter a unit # for a truck not in the system, add findings, Save → row appears in the list; reopen → persists; Print → results sheet with letterhead.

- [ ] **Step 5: Commit**

```bash
git add index.html && git commit -m "Inspection forms: standalone Inspections page + nav

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Deploy + live verification

**Files:** none (deploy only)

- [ ] **Step 1: Final parse-check**

Run: `python3 scripts/build.py` → exit 0.

- [ ] **Step 2: Push (foreground — never background git; it left a stale lock last time)**

```bash
find .git -name "*.lock" -delete 2>/dev/null; git push origin main; git rev-parse --short HEAD; git rev-parse --short origin/main
```
Expected: local and `origin/main` short hashes match.

- [ ] **Step 3: Verify the Pages build + live markers**

```bash
gh api repos/allen1405/lincoln-tms/pages/builds/latest --jq '{status,commit,error:.error.message}'
for i in $(seq 1 20); do b=$(curl -s "https://allen1405.github.io/lincoln-tms/index.html?cb=$RANDOM"); echo "$b" | grep -q "Outbound/Inbound" && echo "LIVE $i" && break; sleep 6; done
```
Expected: build `status:"built"`, `error:null`; `LIVE` prints.

- [ ] **Step 4: Live smoke test (manual, in the browser)**

1. Open an **A2C** work order → **🚚 Outbound/Inbound** tab present; fill, Save, reopen (persists), Print (2 pages, letterhead + signature).
2. Open a **non-A2C** work order → **📋 Inspection Results** tab present, **no** Outbound tab; add findings, Save, Print.
3. **Inspections** page → **＋ New Inspection** for a truck not in the system, no WO → Save, row appears, reopen, Print.
4. Confirm the DOT tab and the rest of the job modal are unchanged.

---

## Self-Review

**Spec coverage:**
- Full A2C form fillable/saved/printable → Task 1 (table) + Task 2 (print) + Task 3 (tab). ✓
- Results form for any truck, WO + standalone → Task 4 (non-A2C WO tab) + Task 5 (standalone page). ✓
- A2C gating by customer #1 → `jobsModal.customer===A2C_NAME` (Task 3/4 tab buttons). ✓
- Faithful fields/checklist/parts → Task 1 constants + Task 3 content + Task 2 print. ✓
- Pre-fill mileage/APU/reefer/unit# from WO → `blankOutbound` (Task 3 Step 2). ✓
- LTTR letterhead + auto-signature print → Task 2 builders (fetch `signature` by `user.id`, `SHOP` header). ✓
- Inspections list + New/edit/delete → Task 5. ✓
- Audit entities → Task 1 Step 3. ✓
- Out-of-scope (Parts Ordered not wired to Order Parts queue; A2C forms not in the Inspections list; RLS off) → respected. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step is complete. ✓

**Type/name consistency:** State names (`outb`/`setOutb`, `wores`/`setWores`, `rec`), handlers (`loadOutbound`/`saveOutbound`/`loadResults`/`saveResults`), print fns (`printOutboundInspection`/`printInspectionResults`), findings shape `{checked,text}`, constants (`A2C_NAME`, `CHECKLIST_LABELS`, `PARTS_VENDORS`) are consistent across tasks. `printOutboundInspection` is called with `{...outb,inspector,customer}`; the builder only reads outbound fields + findings, so the extras are harmless. ✓
