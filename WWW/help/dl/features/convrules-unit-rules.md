---
id: convrules-unit-rules
title: "Unit rules (#use, #unuse, #useswap)"
summary: "ConvRulesEditor Uses Units menu and Unit Rules tab: add, remove and swap units in the converted unit's uses clause"
product: DL
group: component-conversion
order: 60021
since: 1.31.0-alpha
status: shipped
updated: 1.46.0-alpha
---

# Unit rules (#use, #unuse, #useswap)

ConvRulesEditor Uses Units menu and Unit Rules tab: add, remove and swap units in the converted unit's uses clause.

Manage the uses-clause changes a conversion makes.

## Details

Unit rules say which units to ADD to (`#use`), REMOVE from (`#unuse`) or SWAP in
(`#useswap Old -> New`) a converted unit's uses clause. ConvRulesEditor writes them
from the **Uses Units** menu and lists them on the **Unit Rules** tab.

### Where it shows
* **Uses Units > Swap...** adds `#useswap Old -> New1[, New2 ...]` for the selected
  Old unit; **Add unit...** adds `#use`; **Remove unit** adds `#unuse`;
  **Delete unit rule** removes the rule (or dismisses the candidate / harvested row)
  selected on the Unit Rules tab.
* **Derive units** adds `#use` / `#unuse` from every `#convert` To / From type, deduped;
  **Check units** reports `#use` / `#unuse` conflicts (ADD wins);
  **Accept scope renames** adds `#useswap Name -> Scope.Name` for each selected
  "via scope" row.

### What to know
Unit names are compared without regard to case. The Unit Rules tab classifies each unit
against the project and the platform library from the engine's index.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
