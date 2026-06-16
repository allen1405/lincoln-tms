# Consolidated WO Screen (Desktop) — Plan

**Date:** 2026-06-16
**Goal:** On desktop only, clicking a Work Order number opens ONE extra-wide modal with the editable WO form on the left and the existing tabbed details (Jobs/Parts/Shop Supply/Notes/DOT/Reminders/Photos) on the right. The ✏️ edit button is removed from desktop cards. Mobile and tablet are completely unchanged (two separate modals, both buttons present).

**Key technique:** Extract only the small form body into `renderWoForm(ctx)` and reuse it. Leave the large details JSX in place — just wrap it in a column div and, on desktop, prepend the form column inside the same Modal. No duplication of the 380-line details block.

All new behavior gated on `vp.isDesktop`. Verify with `python3 scripts/build.py` after each task. Commit per task.

---

### Task 1: `xwide` Modal variant
`index.html` Modal (~278). Add `xwide` to props; in the non-fullSheet `containerStyle`, width becomes `xwide?"min(1180px,96vw)":wide?"min(800px,98vw)":"min(600px,95vw)"`. fullSheet (mobile) path untouched.

### Task 2: Handlers in WorkOrders
Near the existing WO handlers (~945–995):
- `const closeWoDetails=()=>{setJobsModal(null);setNoteText("");loadWos();};` (the current details onClose, named).
- `const closeCombined=()=>{setModal(false);setEditId(null);setForm(empty);setWoErr("");setJobsModal(null);setNoteText("");loadWos();};`
- `const openCombined=async(w)=>{ openEdit-style setForm+setEditId (copy openEdit's body WITHOUT setModal(true)); then jobsModal load: setJobsModal(w);setJobTab("jobs");setShopSupply(w.shop_supply||"");shopSupplySaved.current=w.shop_supply||"";setRemForm({id:null,reminder_date:"",note:""});await Promise.all([loadJobs(w.id),loadNotes(w.id),loadParts(w.id),loadDot(w),loadDotPhotos(w.id),loadWoReminders(w.id),loadEqItems(w)]); };`
- `const openWoCard=(w)=>vp.isDesktop?openCombined(w):openJobs(w);`
- `saveEdit` → `saveEdit(combined)`: add `const renumbered=id!==editId;` (reuse for the cascade `if(renumbered){`). Replace tail `closeWoModal();loadWos();` with:
  ```
  if(!combined){closeWoModal();loadWos();}
  else if(renumbered){closeCombined();}
  else {loadWos();setJobsModal(prev=>prev?{...prev,id,customer:form.customer,unit_number:form.unit_number,vin:form.vin,description:form.description,status:form.status}:prev);}
  ```
- `voidWo(id,fromModal)` → `voidWo(id,ctx)`: tail `if(ctx==="combined")closeCombined();else if(ctx==="standalone")closeWoModal();loadWos();`
- `restoreWo(id,fromModal)` → `restoreWo(id,ctx)`: same close branching, then `loadWos();`
- Voided-table call (1342) `restoreWo(w.id,false)` → `restoreWo(w.id)` (no close).

### Task 3: Extract `renderWoForm(ctx)`
Define a `const renderWoForm=(ctx)=>{const isCombined=ctx==="combined";return(<> ...form inner 1447–1509... </>);}` right before the component's main `return (`. Parametrize:
- Cancel onClick → `isCombined?closeCombined():closeWoModal()`
- Void → `voidWo(editId, isCombined?"combined":"standalone")`; Restore → `restoreWo(editId, isCombined?"combined":"standalone")`
- Save → `guard(editId?()=>saveEdit(isCombined):add)`
Then replace the standalone edit Modal's inner (1447–1509) with `{renderWoForm("standalone")}`. Modal wrapper (title/onClose=closeWoModal) stays — still used for New WO on all tiers and Edit on mobile/tablet.

### Task 4: Tier-conditional details modal + desktop form column
Details block (1535). Change wrapper to:
`<Modal title={...} onClose={vp.isDesktop?closeCombined:closeWoDetails} wide={!vp.isDesktop} xwide={vp.isDesktop}>`
Immediately inside, open `<div style={vp.isDesktop?{display:"flex",gap:24,alignItems:"flex-start"}:undefined}>`; if desktop, a left column `<div style={{width:400,flexShrink:0,overflowY:"auto",maxHeight:"78vh",paddingRight:4}}>{renderWoForm("combined")}</div>`; then a right column `<div style={vp.isDesktop?{flex:1,minWidth:0,overflowY:"auto",maxHeight:"78vh"}:undefined}>` wrapping the EXISTING details inner (contact strip → tabs → tab content, untouched). Close both divs before `</Modal>`.

### Task 5: Card triggers
- WO number (1362 kanban, 1396 list): `onClick={()=>openJobs(w)}` → `onClick={()=>openWoCard(w)}`.
- ✏️ buttons (1364 kanban, 1398 list): wrap `{!vp.isDesktop&&<button ...>✏️</button>}`.
- Voided-table WO number (1335, openEdit) and the New-WO button: unchanged.

### Task 6: Verify + review + ship
`python3 scripts/build.py`; manual desktop check (open WO → form+tabs, save keeps open, renumber closes, void closes, no ✏️); shrink to tablet/mobile → two separate modals, ✏️ back. Code-review agent on the diff. Push.
