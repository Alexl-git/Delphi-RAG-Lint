# drag-lint - manual IDE test checklist

Quick-reference checklist for spot-checking specific features after a build.
For the full end-to-end pass see `TEST-PLAN-IDE-FULL.md`.

---

## C4. Dockable Panel -- Search (no grep) tab

Tools > drag-lint > Dockable Panel (or dock it from a previous session).

- [ ] S1. Tools > drag-lint dockable panel -> a "Search (no grep)" tab appears (2nd, after Structure).
- [ ] S2. Kind=Symbol, type a known type/method name -> grid lists Kind|Name|Location; double-click jumps to the .pas at the right line.
- [ ] S3. Kind=Text, type a known message/caption phrase -> grid lists Source|Text|Location; double-click jumps. Toggle Advanced -> Substring/Any-word + Source filter appear and change results.
- [ ] S4. Kind=Usages, type a known symbol -> grid lists Category|Detail|Location (Decl/Read/Write/Call...); double-click jumps. Advanced -> Width changes the snippet width.
- [ ] S5. Search something not indexed (a local variable) -> a single clean "No matches ... drag-lint indexes ..." status line. NO JSON, NO == DEBUG == anywhere.
- [ ] S6. Find Usages tab on a not-found symbol -> a single "(no usages found)" hint line, NO == DEBUG == block.
