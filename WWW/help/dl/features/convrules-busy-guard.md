---
id: convrules-busy-guard
title: Progress window and busy guard
summary: ConvRulesEditor shows a cancellable progress window for long engine calls and refuses Save, Add, Convert and Delete while one runs
product: DL
group: component-conversion
order: 60005
since: 1.35.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# Progress window and busy guard

ConvRulesEditor shows a cancellable progress window for long engine calls and refuses Save, Add, Convert and Delete while one runs.

Know why the editor shows a progress window and why a click was refused while it runs.

## Details

Long engine calls in ConvRulesEditor (opening a book that needs the engine, Reindex project,
a Convert run, the first classification of the Unit Rules tab) run behind a progress window
with a Cancel button, so the editor stays responsive and the call can be stopped.

### What you see
* A progress window names the call and the elapsed time; Cancel stops it. After a cancel the
  result may be partial (a reindex says the index may be partly refreshed: run it again).
* The Unit Rules tab classifies its rows only when the tab is first shown, so the editor
  starts without waiting for it.

### What is refused while it runs
While a long call or a Convert run is busy, clicks that would start more work are refused and
reported in the status line instead of running: File > Save, Add..., Convert and Delete on the
Convert tab, and menu commands posted to the window. The refusal changes nothing in the book.
Wait for the window to close (or press Cancel) and repeat the action.

### Reaching it
There is nothing to open: the window appears by itself. Menus involved: Conversion > Reindex
project, Conversion > Convert..., File > Open....

### Where to click

**Progress window (appears by itself)**
1. Start a long action (Conversion > Reindex project, Conversion > Convert... > Convert)
2. Watch the progress window; press Cancel to stop
3. A click on Save, Add..., Convert or Delete meanwhile is refused and reported in the status line

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
