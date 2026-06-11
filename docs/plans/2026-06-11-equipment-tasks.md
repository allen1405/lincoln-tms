# Equipment Future Tasks + WO Surfacing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Undated "next visit" tasks per piece of equipment, a durable WO→equipment link, and surfacing of the equipment's open tasks/reminders in the new-WO form and the WO details modal (with one-tap "Add as job").

**Architecture:** Tasks are rows in the existing `reminders` table with a new `kind` column (`'reminder'` default | `'task'`). `work_orders` gains a nullable `equipment_id`. All UI lives in `index.html` (single-file React, babel-in-browser); writes go through the existing `must()` helper and `audit()` calls. Spec: `docs/specs/2026-06-11-equipment-tasks-design.md`.

**Tech stack:** React 18 via babel-standalone, supabase-js v2 (pinned), Supabase Postgres. No test framework (project decision) — verification is `python3 scripts/build.py` (esbuild parse) + manual UAT.

**Line numbers below are as of commit `7fbd346`** — re-locate by the quoted code, not the number, if the file has shifted.

---

### Task 1: Schema migration

**Files:** none (Supabase migration via MCP `apply_migration`)

- [ ] **Step 1: Verify `equipment.id` type** — run `select data_type from information_schema.columns where table_name='equipment' and column_name='id'` via `execute_sql`. Expect `bigint`. If it's `integer`, use `integer` in the FK below.

- [ ] **Step 2: Apply migration** named `equipment_tasks_and_wo_link`:

```sql
alter table reminders add column if not exists kind text not null default 'reminder';
alter table work_orders add column if not exists equipment_id bigint references equipment(id) on delete set null;
```

- [ ] **Step 3: Verify** — `select kind from reminders limit 1;` returns `'reminder'` for existing rows; `select equipment_id from work_orders limit 1;` returns null. No commit (no repo files changed).

---

### Task 2: Future Tasks tab in EquipmentModal

**Files:** Modify `index.html` — EquipmentModal (lines ~607–778)

- [ ] **Step 1: Split loaded rows and add task state.** After `const [reminders,setReminders]=useState([]);` (line 618) add:

```js
const [taskNote,setTaskNote]=useState("");
const [addingTask,setAddingTask]=useState(false);
```

After the `label` helper (line 682) add derived lists:

```js
const eqReminders=reminders.filter(r=>r.kind!=='task');
const eqTasks=reminders.filter(r=>r.kind==='task');
```

- [ ] **Step 2: Add `addTask`** next to `addReminder` (line 668):

```js
const addTask=async()=>{
  if(!taskNote.trim()) return;
  const eqLabel=`${viewEquip.year} ${viewEquip.make} ${viewEquip.model||viewEquip.type} (${viewEquip.vin||'no VIN'})`;
  const {data:inserted,error}=await sb.from('reminders').insert([{kind:'task',equipment_id:viewEquip.id,customer_name:customerName,equipment_label:eqLabel,note:taskNote.trim(),created_by:user.name}]).select().single();
  if(error){alert("Could not save task: "+error.message);return;}
  audit(user,"create","reminder",inserted?.id,`${customerName} — ${eqLabel}`,`task: ${taskNote.trim().slice(0,110)}`);
  setTaskNote(""); setAddingTask(false); loadReminders(viewEquip.id);
};
```

`completeRem` (line 669) is reused as-is for tasks — `rescheduleAutoReminder` already no-ops when `auto_days` is null (line 272).

- [ ] **Step 3: Tab bar.** Change the Reminders tab count to `eqReminders` and add a Tasks tab (line 688):

```jsx
<button className={`tab-btn${activeTab==="reminders"?" active":""}`} onClick={()=>setActiveTab("reminders")}>🔔 Reminders ({eqReminders.filter(r=>!r.completed).length})</button>
<button className={`tab-btn${activeTab==="tasks"?" active":""}`} onClick={()=>setActiveTab("tasks")}>📋 Future Tasks ({eqTasks.filter(r=>!r.completed).length})</button>
```

In the reminders tab body, change `reminders.length===0` / `reminders.map` to `eqReminders` (lines 711–712).

- [ ] **Step 4: Tasks tab body.** After the reminders tab block (closing at line 728) add:

```jsx
{activeTab==="tasks"&&(
  <div>
    <p style={{color:"#888",fontSize:13,marginTop:0}}>Deferred work to do next time this unit is in the shop. Shows on any work order for this equipment.</p>
    {!addingTask&&<button onClick={()=>setAddingTask(true)} style={{marginBottom:16,padding:"9px 16px",background:"#c0392b",color:"#fff",border:"none",borderRadius:8,cursor:"pointer",fontWeight:600,fontSize:13}}>+ Add Task</button>}
    {addingTask&&(
      <div style={{background:"#f8f9fa",borderRadius:10,padding:16,marginBottom:16}}>
        <Field label="Task" value={taskNote} onChange={setTaskNote} placeholder="e.g. Replace air dryer next visit" required type="textarea"/>
        <div style={{display:"flex",gap:8}}>
          <button onClick={()=>guard(addTask)} style={{padding:"9px 16px",background:"#c0392b",color:"#fff",border:"none",borderRadius:8,cursor:"pointer",fontWeight:600,fontSize:13}}>Save Task</button>
          <button onClick={()=>setAddingTask(false)} style={{padding:"9px 16px",background:"#f0f0f0",border:"none",borderRadius:8,cursor:"pointer",fontSize:13}}>Cancel</button>
        </div>
      </div>
    )}
    {eqTasks.length===0&&<p style={{color:"#aaa",fontSize:13}}>No future tasks yet.</p>}
    {eqTasks.map(r=>(
      <div key={r.id} style={{border:`1px solid ${r.completed?"#a9dfbf":"#eee"}`,borderRadius:10,padding:14,marginBottom:10,background:r.completed?"#f9fff9":"#fff"}}>
        <div style={{display:"flex",justifyContent:"space-between",alignItems:"flex-start"}}>
          <div>
            <div style={{fontWeight:600,fontSize:14,color:r.completed?"#888":"#1a1a2e",textDecoration:r.completed?"line-through":""}}>📋 {r.note}</div>
            <div style={{fontSize:12,color:"#888",marginTop:4}}><span>👤 {r.created_by} · {fmtDate(r.created_at)}</span></div>
          </div>
          {!r.completed&&<button onClick={()=>completeRem(r.id)} style={{padding:"6px 12px",background:"#27ae60",color:"#fff",border:"none",borderRadius:6,cursor:"pointer",fontSize:12,fontWeight:600}}>✓ Done</button>}
        </div>
      </div>
    ))}
  </div>
)}
```

Note: EquipmentModal has no `guard` yet — add `const guard=useOnce();` next to its other hooks if absent (check line ~609; the reminder form at 706 already calls `guard`, so it exists — reuse it).

- [ ] **Step 5: Parse check** — `python3 scripts/build.py` → exits 0.

- [ ] **Step 6: Commit** — `git add index.html && git commit -m "Equipment Future Tasks tab (kind='task' rows in reminders)"`

---

### Task 3: WO form — equipment link + open-items panel

**Files:** Modify `index.html` — WorkOrders component (form state 815, insert 870, openEdit 876, update 882, selEquip 1178, form JSX ~1346)

- [ ] **Step 1: Form state.** Add `equipment_id:null` to `empty` (line 815). In `openEdit` (876) add `equipment_id:w.equipment_id??null` to the `setForm` object. In the update payload (882) add `equipment_id:form.equipment_id||null`. (The insert at 870 spreads `...form`, so it picks the field up automatically.)

- [ ] **Step 2: Picker sets the link.** `selEquip` (1178) becomes:

```js
const selEquip=(e)=>{
  setForm(p=>({...p,equipment_id:e.id,unit_number:e.unit_number||e.vin||e.license_plate||`${e.type}-${e.id}`,vin:e.vin||""}));
  setEquipModal(null);
};
```

- [ ] **Step 3: Debounced resolver + panel state.** Near the other WO modal state add:

```js
const [formEquipItems,setFormEquipItems]=useState(null); // {equipment, items} → amber panel in the WO form
// Resolve typed equipment so deferred work surfaces even without the picker:
// exact VIN, else customer+unit number, else whatever the picker set.
useEffect(()=>{
  if(!modal){setFormEquipItems(null);return;}
  const t=setTimeout(async()=>{
    let eq=null;
    const vin=(form.vin||"").trim(), unit=(form.unit_number||"").trim();
    if(vin){const{data}=await sb.from('equipment').select('*').eq('vin',vin).limit(1);eq=(data&&data[0])||null;}
    if(!eq&&unit&&form.customer){
      const c=customers.find(x=>x.name===form.customer);
      if(c){const{data}=await sb.from('equipment').select('*').eq('customer_id',c.id).eq('unit_number',unit).limit(1);eq=(data&&data[0])||null;}
    }
    if(!eq&&form.equipment_id){const{data}=await sb.from('equipment').select('*').eq('id',form.equipment_id).maybeSingle();eq=data||null;}
    if((eq?eq.id:null)!==form.equipment_id) setForm(p=>({...p,equipment_id:eq?eq.id:null}));
    if(!eq){setFormEquipItems(null);return;}
    const{data:items}=await sb.from('reminders').select('*').eq('equipment_id',eq.id).eq('completed',false).order('created_at',{ascending:false});
    setFormEquipItems(items&&items.length?{equipment:eq,items}:null);
  },500);
  return()=>clearTimeout(t);
},[modal,form.vin,form.unit_number,form.customer,form.equipment_id]);
```

(The `setForm` inside re-fires the effect once; the second pass resolves to the same row and settles. Lookup failure just clears the panel — never blocks the form.)

- [ ] **Step 4: Amber panel JSX.** Immediately after the Equipment/Unit field's closing `</div>` (line ~1352, before the VIN grid):

```jsx
{formEquipItems&&(
  <div style={{background:"#fef9e7",border:"1px solid #f7dc6f",borderRadius:10,padding:"10px 14px",marginBottom:14}}>
    <div style={{fontSize:13,fontWeight:700,color:"#9a7d0a",marginBottom:6}}>⚠ This unit has {formEquipItems.items.filter(i=>i.kind==='task').length} open task(s) · {formEquipItems.items.filter(i=>i.kind!=='task').length} reminder(s)</div>
    {formEquipItems.items.map(i=>(
      <div key={i.id} style={{fontSize:13,color:"#7d6608",marginBottom:3}}>{i.kind==='task'?'📋':'🔔'} {i.note}{i.reminder_date?` (due ${fmtDay(i.reminder_date)})`:''}</div>
    ))}
  </div>
)}
```

- [ ] **Step 5: Parse check** — `python3 scripts/build.py` → exits 0.

- [ ] **Step 6: Commit** — `git commit -am "WO form: durable equipment link + open tasks/reminders panel"`

---

### Task 4: WO details — "From this equipment" section with Add-as-job

**Files:** Modify `index.html` — WorkOrders details modal (openJobs 950, handlers ~949–968, reminders tab JSX ~1735–1768)

- [ ] **Step 1: State + loader.** Next to `woReminders` state (813):

```js
const [eqItems,setEqItems]=useState(null); // {equipment, items} for the open WO's linked equipment
```

Next to `loadWoReminders` (949):

```js
const loadEqItems=async(wo)=>{
  setEqItems(null);
  let eq=null;
  if(wo.equipment_id){const{data}=await sb.from('equipment').select('*').eq('id',wo.equipment_id).maybeSingle();eq=data||null;}
  if(!eq&&(wo.vin||"").trim()){const{data}=await sb.from('equipment').select('*').eq('vin',wo.vin.trim()).limit(1);eq=(data&&data[0])||null;}
  if(!eq&&(wo.unit_number||"").trim()&&wo.customer){
    const c=customers.find(x=>x.name===wo.customer);
    if(c){const{data}=await sb.from('equipment').select('*').eq('customer_id',c.id).eq('unit_number',wo.unit_number.trim()).limit(1);eq=(data&&data[0])||null;}
  }
  if(!eq)return;
  const{data:items}=await sb.from('reminders').select('*').eq('equipment_id',eq.id).eq('completed',false).order('created_at',{ascending:false});
  // Rows already attached to THIS WO render in the list below — don't show them twice.
  setEqItems({equipment:eq,items:(items||[]).filter(r=>r.work_order_id!==wo.id)});
};
```

- [ ] **Step 2: Load on open.** Add `loadEqItems(wo)` to the `Promise.all` in `openJobs` (950).

- [ ] **Step 3: Handlers.** Next to `completeWoReminder` (967):

```js
const addTaskAsJob=async(t)=>{
  const {data:inserted,error}=await sb.from('jobs').insert([{work_order_id:jobsModal.id,name:t.note,status:"Pending",created_by:user.name}]).select().single();
  if(error){alert("Could not add job: "+error.message);return;}
  audit(user,"create","job",inserted?.id,`${jobsModal.id} — ${t.note}`);
  const r=await must(sb.from('reminders').update({completed:true}).eq('id',t.id).eq('completed',false).select(),"Job added, but could not mark the task done");
  if(r&&r.data&&r.data.length) audit(user,"status_change","reminder",t.id,`${t.customer_name||""} — ${t.equipment_label||""}`,`task completed — added as job on WO ${jobsModal.id}`);
  loadJobs(jobsModal.id); loadEqItems(jobsModal);
};
const completeEqItem=async(r0)=>{
  const r=await must(sb.from('reminders').update({completed:true}).eq('id',r0.id).eq('completed',false).select(),"Could not complete");
  if(!r)return;
  if(r.data&&r.data.length){
    audit(user,"status_change","reminder",r0.id,`${r0.customer_name||""} — ${r0.equipment_label||""}`,`completed: false → true`);
    await rescheduleAutoReminder(user,r0);
  }
  loadEqItems(jobsModal);
};
```

- [ ] **Step 4: Section JSX.** In the details modal, immediately inside the `{jobTab==="reminders"&&(<div>` block, before the add-reminder form:

```jsx
{eqItems&&eqItems.items.length>0&&(
  <div style={{background:"#fef9e7",border:"1px solid #f7dc6f",borderRadius:10,padding:14,marginBottom:14}}>
    <div style={{fontSize:12,fontWeight:700,color:"#9a7d0a",textTransform:"uppercase",letterSpacing:0.5,marginBottom:8}}>From this equipment — open items</div>
    {eqItems.items.map(r=>(
      <div key={r.id} style={{display:"flex",justifyContent:"space-between",alignItems:"flex-start",gap:10,padding:"8px 0",borderBottom:"1px solid rgba(247,220,111,0.35)"}}>
        <div style={{flex:1}}>
          <div style={{fontSize:14,fontWeight:600,color:"#1a1a2e"}}>{r.kind==='task'?'📋':'🔔'} {r.note}</div>
          <div style={{fontSize:12,color:"#888",marginTop:2}}>
            {r.reminder_date&&<span>📅 {fmtDay(r.reminder_date)} &nbsp;</span>}
            {r.auto_days&&<span>🔄 Every {r.auto_days} days &nbsp;</span>}
            <span>👤 {r.created_by||"—"}</span>
          </div>
        </div>
        <div style={{display:"flex",gap:6}}>
          {r.kind==='task'&&<button onClick={()=>guard(()=>addTaskAsJob(r))} style={{padding:"6px 12px",background:"#c0392b",color:"#fff",border:"none",borderRadius:6,cursor:"pointer",fontSize:12,fontWeight:600,whiteSpace:"nowrap"}}>➕ Add as job</button>}
          <button onClick={()=>completeEqItem(r)} title="Mark done" style={{padding:"6px 12px",background:"#27ae60",color:"#fff",border:"none",borderRadius:6,cursor:"pointer",fontSize:12,fontWeight:600}}>✓</button>
        </div>
      </div>
    ))}
  </div>
)}
```

(Confirm `guard(()=>addTaskAsJob(r))` matches `useOnce`'s call signature — `guard(addReminder)` at 706 takes a function, so a closure is fine.)

- [ ] **Step 5: Parse check** — `python3 scripts/build.py` → exits 0.

- [ ] **Step 6: Commit** — `git commit -am "WO details: equipment open items section with one-tap Add as job"`

---

### Task 5: Task badge on the Reminders page

**Files:** Modify `index.html` — RemindersPage rows (mobile card ~2209, desktop source cell ~2241)

- [ ] **Step 1: Mobile card.** In the meta row (line 2209–2213) add before the source span:

```jsx
{r.kind==='task'&&<span style={{padding:"2px 8px",borderRadius:10,fontSize:10,fontWeight:700,background:"#fef9e7",color:"#9a7d0a"}}>📋 TASK</span>}
```

- [ ] **Step 2: Desktop table.** Change the `source` computation (2241) to prefix tasks:

```js
const source=(r.kind==='task'?'📋 TASK · ':'')+(r.work_order_id?`WO ${r.work_order_id}`:(r.equipment_label||"—"));
```

Apply the same change to the mobile `source` (2201), minus the badge duplication — there, keep `source` unchanged and rely on the badge from Step 1.

- [ ] **Step 3: Parse check** — `python3 scripts/build.py` → exits 0.

- [ ] **Step 4: Commit** — `git commit -am "Reminders page: badge task rows"`

---

### Task 6: Verify, push, UAT notes

- [ ] **Step 1:** `python3 scripts/build.py` one final time; `git log --oneline` shows the four commits.
- [ ] **Step 2:** Push to `main` (GitHub Pages auto-deploys; columns added in Task 1 are backward-compatible so old cached clients keep working).
- [ ] **Step 3:** Report UAT script to Alexander: create task on a unit → new WO via picker (panel) → hand-typed WO (panel via fallback) → open WO → Add as job → job exists, task struck through, audit log has both rows; recurring reminder ✓ from the WO section reschedules.

---

## Self-review notes

- Spec coverage: tasks tab (T2), WO link + picker + fallback (T3), create-form panel (T3), details section + Add as job (T4), Reminders page badge (T5), schema (T1), silent degradation (resolver catch-free `.maybeSingle()`/empty results → panel hidden). Dashboard needs no change: its query filters `lt('reminder_date', today)`, which excludes null-dated tasks.
- Dedup rule: equipment items already attached to the open WO are filtered out (T4 Step 1).
- `rescheduleAutoReminder` no-ops for tasks (guard at line 272) and doesn't copy `kind` — recurrence stays reminder-only. Correct per spec.
