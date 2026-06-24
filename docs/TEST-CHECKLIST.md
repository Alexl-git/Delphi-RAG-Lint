# drag-lint - manual IDE test checklist

Quick-reference checklist for spot-checking specific features after a build.
For the full end-to-end pass see `TEST-PLAN-IDE-FULL.md`.

---

## C4. Dockable Panel -- tabs and navigation

Tools > drag-lint > Dockable Panel (or dock it from a previous session).

- [ ] B1. Click any form-unit result (from any tab) -> opens the .pas code editor, NOT the form designer.
- [ ] B2. Blast Radius tab shows clickable callers + impact roll-up (transitive call depth, unit count per depth).
- [ ] B3. No "Symbol Search" tab appears (it was folded into Search / Blast Radius tabs).

### C4.1. Search (no grep) tab

- [ ] S1. Tools > drag-lint dockable panel -> tabs are: Structure | Search (no grep) | Blast Radius (in that order, 2nd and 3rd).
- [ ] S2. Kind=Symbol, type a known type/method name -> grid lists Kind|Name|Location; double-click jumps to the .pas at the right line.
- [ ] S3. Kind=Text, type a known message/caption phrase -> grid lists Source|Text|Location; double-click jumps. Toggle Advanced -> Substring/Any-word + Source filter appear and change results.
- [ ] S4. Kind=Usages, type a known symbol -> grid lists Category|Detail|Location (Decl/Read/Write/Call...); double-click jumps. Advanced -> Width changes the snippet width.
- [ ] S5. Search something not indexed (a local variable) -> a single clean "No matches ... drag-lint indexes ..." status line. NO JSON, NO == DEBUG == anywhere.
- [ ] S6. Blast Radius tab on a symbol -> shows transitive callers grouped by depth, with unit count per depth. Each caller is clickable.

### C4.2. Blast Radius tab

- [ ] B4. Open the Blast Radius tab, type a known symbol (e.g., a public method), and verify the tab label says "Blast radius of: <symbol>".
- [ ] B5. Results show a tree-like drill-down (or flat list with depth indicator) of callers at each transitive level, with unit counts per depth.
