# drag-lint - manual IDE test checklist

Quick-reference checklist for spot-checking specific features after a build.
For the full end-to-end pass see `TEST-PLAN-IDE-FULL.md`.

---

## C4. Dockable Panel -- tabs and navigation

Tools > drag-lint > drag-lint Panel (dockable) (or dock it from a previous session).

- [ ] B1. Click any form-unit result (from any tab) -> opens the .pas code editor, NOT the form designer.
- [ ] B2. Blast Radius tab shows direct usages by category (Reads, Writes, Calls, etc.) and a unit-impact count roll-up; each row is clickable and jumps to source.
- [ ] B3. No "Symbol Search" tab appears (it was folded into Search / Blast Radius tabs).

### C4.1. Search (no grep) tab

- [ ] S1. Tools > drag-lint dockable panel -> tabs are: Structure | Search (no grep) | Blast Radius (in that order, 2nd and 3rd).
- [ ] S2. Kind=Symbol, type a known type/method name -> grid lists Kind|Name|Location; double-click jumps to the .pas at the right line.
- [ ] S3. Kind=Text, type a known message/caption phrase -> grid lists Source|Text|Location; double-click jumps. Toggle Advanced -> Substring/Any-word + Source filter appear and change results.
- [ ] S4. Kind=Usages, type a known symbol -> grid lists Category|Detail|Location (Decl/Read/Write/Call...); double-click jumps. Advanced -> Width changes the snippet width.
- [ ] S5. Search something not indexed (a local variable) -> a single clean "No matches ... drag-lint indexes ..." status line. NO JSON, NO == DEBUG == anywhere.
- [ ] S6. Blast Radius tab on a symbol -> shows direct usages grouped by category (Decl/Read/Write/Call/Type-use/Event), with a unit-impact count summary. Each row is clickable.

### C4.2. Blast Radius tab

- [ ] B4. Open the Blast Radius tab, type a known symbol (e.g., a public method), and verify the tab label says "Blast radius of: <symbol>".
- [ ] B5. Results show a flat list of direct usages by category (Reads, Writes, Calls, etc.) with a unit-impact count summary; no multi-level tree (transitive drill-down is a deferred follow-up).

---

## Y1. YADF false positive #6 -- try-except-swallowed marker (needs the IDE index)

From the retired INBOX `yadf-false-positives-2026-11-03` (#6). Not reproducible in a fixture: the case needs a ToolsAPI-backed index
(`DECLARED(IOTACodeFormatter)`). Run it once against the real YADF project in the IDE, with the current engine.

- [ ] Y1.1. Open YADF.Options.pas in the IDE with the YADF project indexed (ToolsAPI units resolved), lint the unit.
- [ ] Y1.2. A `dl:ok` marker over a `try ... except` that swallows must NOT be reported `review-marker-unused` while the finding it suppresses still fires without the marker.
- [ ] Y1.3. Same unit, same DB copy, engine 1.41 and the current engine: the verdict must be identical. Record both; a difference is the open defect.
