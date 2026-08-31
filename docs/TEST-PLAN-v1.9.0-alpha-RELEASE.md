# drag-lint v1.9.0-alpha -- IDE verification pass

**Engine `1.9.0-alpha`, plugin `v1.1.0-alpha`, extractor `1.10.0-alpha`,
resolver `1.1.0-alpha`, schema `21`.**

**Purpose.** Confirm in a live RAD Studio 13 Florence (Studio 37.0) that this
engine behaves in the IDE the way 430 headless tests say it does. This is the
last gate before the release is tagged.

---

## >>> READ THIS FIRST: THE PLAN IS SPLIT IN TWO, AND THE SPLIT IS LOAD-BEARING

`DRAGLINT_EXTRACTOR_VERSION` moved to **1.10.0-alpha** in this build, so **every
index on this machine is one re-parse behind.** The reindex is scheduled for the
evening.

That does **not** block most of this plan, but it changes what a failure MEANS,
so each section is tagged:

| tag | meaning |
|---|---|
| **[NOW]** | Valid before the reindex. Tests plumbing, rendering, menus, process behaviour -- things a stale index cannot fake. |
| **[AFTER]** | **Do not run before the reindex.** These read the index, so a thin or wrong answer would be the STALE DATA, not a defect. Running them early produces false bug reports. |

**If you only have time for one half today, do [NOW].** It is the half that
finds plugin defects, and it is the half a reindex cannot help with.

> **A [AFTER] step run early is not a pass and not a fail -- it is noise.** Mark
> it "not run", not "broken".

---

## EVERY PATH IN THIS PLAN IS ABSOLUTE, ON PURPOSE

No step assumes a working directory, and no step uses a bare `drag-lint`. This
machine sets `NoDefaultCurrentDirectoryInExePath`, so a bare name resolves off
PATH to a **different, older binary** -- that once reported 33,626 findings
against a real 14,764 and read as a catastrophic regression.

Copy these once; every command below uses them verbatim.

| what | full path |
|---|---|
| engine | `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe` |
| engine build script | `C:\Projects\Delphi-RAG-lint\build\build_draglint_win64.bat` |
| VS Code engine refresh | `C:\Projects\Delphi-RAG-lint\tools\refresh-vscode-engine.ps1` |
| VS Code private engine | `C:\Users\alexanderl\AppData\Local\drag-lint-vscode-engine\drag-lint.exe` |
| plugin BPL | `C:\Projects\Delphi-RAG-lint\third_party\dll-win32\dclDragLintWizard.bpl` |
| engine config | `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.json` |
| plugin log | `C:\Users\alexanderl\AppData\Local\Temp\drag-lint-plugin.log` |
| library index (Win64) | `C:\Projects\.drag-lint\library-Win64.sqlite` |
| DataCopy index | `C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite` |
| ORM3 CLIENT index | `C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite` |
| ORM3 CLIENT project | `C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj` |
| DataCopy project | `C:\Projects\DataCopy\DataCopy.dproj` |

**Never guess an index path.** Ask:

```
C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe resolve-dbs --project C:\Projects\DataCopy\DataCopy.dproj
```

---

## Part 0 -- Preconditions

- [ ] **0.1 Engine version.** Full path -- this machine has
      `NoDefaultCurrentDirectoryInExePath`, so a bare `drag-lint` runs something
      else entirely.
      ```
      C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe --version
      ```
      Must read **`drag-lint 1.9.0-alpha`**.

- [ ] **0.2 The plugin BPL is the current one.** *Component > Install Packages*
      shows `dclDragLintWizard`. If you rebuilt it, **uncheck, rebuild, re-check**
      -- a BPL rebuilt under a loaded package does not take effect.

- [ ] **0.3 VS Code no longer holds the engine.**
      `dragLint.serverPath` is now set to a private copy at
      `C:\Users\alexanderl\AppData\Local\drag-lint-vscode-engine\`. **This takes effect only after a
      VS Code restart.** Verify after restarting it:
      ```powershell
      Get-CimInstance Win32_Process -Filter "Name='drag-lint.exe'" |
        Select-Object ProcessId, ExecutablePath
      ```
      Any `lsp --stdio` whose parent is `Code` must point at
      `C:\Users\alexanderl\AppData\Local\drag-lint-vscode-engine`, **not** at `C:\Projects\Delphi-RAG-lint\third_party\dll-win64`.

      > That private copy is a SECOND DEPLOYMENT and goes stale. After any engine
      > build you want VS Code to reflect:
      > `pwsh -File C:\Projects\Delphi-RAG-lint\tools\refresh-vscode-engine.ps1 -Kill`

- [ ] **0.4 Open ORM3** `CLIENT\Micronite2027.dproj` and a unit with real code.

---

# PART ONE -- [NOW]: valid before the reindex

## 1. Is the right build loaded?

- [ ] **1.1** *drag-lint > About* renders five groups: **Versions**,
      **Connections**, **Indexes in use**, **Configuration**, **Process**.

- [ ] **1.2 Versions.**

      | Row | Expected |
      |---|---|
      | Plugin (BPL) | `v1.1.0-alpha` + today's build time |
      | Engine | `1.9.0-alpha`, today, platform `Win64` |
      | Engine exe | `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe` |
      | tree-sitter | `delphi13 <v> / dfm <v>` |
      | Graph viewer | `present, built <date>` |

      **Plugin `v1.1.0-alpha` beside engine `1.9.0-alpha` is CORRECT** -- two
      independent constants, not a mismatch.

- [ ] **1.3 Connections.** *"not started yet"* on a cold IDE is correct. Hover a
      symbol, reopen About, and it should report a live server. A menu caption
      reading **`drag-lint (!)`** means the LSP is down; About says why.

- [ ] **1.4 Indexes in use.** Paths must be the per-project `_D-RAG` ones
      (`C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite`, or for DataCopy
      `C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite`) plus
      `C:\Projects\.drag-lint\library-Win64.sqlite`. Anything under a shared
      `C:\Projects\.drag-lint\<Repo>-<Project>.sqlite` is a **stale config** -- that layout
      was retired.

- [ ] **1.5 DO NOT EXPECT THE ABOUT WINDOW TO SHOW STALENESS. IT CANNOT.**

      This step said the opposite when first written, and that was wrong -- it
      would have had you file a false bug report. Corrected 2026-08-31 16:20
      after reading `C:\Projects\Delphi-RAG-lint\src\delphi-plugin\DragLint.Plugin.Diagnose.pas`, whose header states a
      load-bearing performance contract: *"nothing here may COUNT rows or open a
      database ... Index facts below come from the FILE"*.

      So **`[ok]` on an index row means PRESENT, not FRESH.** Size and write time
      are read from the filesystem; the fingerprints inside the database are
      never consulted. An index a whole extractor version behind still shows
      `[ok]`, which is exactly what it did on this machine today: `library-Win64`
      is at `v=1.9.0-alpha` against a current `1.10.0-alpha`, with no resolver
      stamp at all, and the window called it `[ok]`.

      **ASK THE ENGINE INSTEAD -- it answers this directly as of v1.9.0-alpha.**
      Copy this line exactly; it names both of DataCopy's indexes and needs no
      working directory:

      ```
      C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe info --json --db C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite --db C:\Projects\.drag-lint\library-Win64.sqlite
      ```

      For the ORM3 client instead, swap the first `--db` for
      `C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite`.

      **Prefer PowerShell, which will format it for you:**

      ```powershell
      $exe = "C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe"
      $r = & $exe info --json `
             --db "C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite" `
             --db "C:\Projects\.drag-lint\library-Win64.sqlite" 2>$null | ConvertFrom-Json
      "engine {0}   extractor {1}   resolver {2}" -f $r.version, $r.extractor_version, $r.resolver_version
      $r.indexes | Format-Table path, verdict, indexer_stale, resolver_stale -AutoSize
      ```

      **What you should see BEFORE the evening reindex** -- measured on this
      machine at 17:05 today, so this is a recorded expectation, not a guess:

      | index | verdict |
      |---|---|
      | `C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite` | `current` |
      | `C:\Projects\.drag-lint\library-Win64.sqlite` | `reparse-owed` |

      `DataCopy` is already current because it was re-indexed at 15:34, after the
      extractor bump. The library index is one extractor version behind and
      carries **no resolver stamp at all**.

      - [ ] **Record the verdict for each index.**
      - [ ] **The library index must NOT say `current` before the reindex.** If it
            does, that is the defect worth reporting -- a stamp claiming
            freshness the pass never earned is exactly what went wrong earlier
            today, and it is self-concealing once written.
      - [ ] **AFTER the evening reindex, re-run the same line.** Every row must
            read `current`. Anything still `reparse-owed` means a section failed;
            anything `resolve-owed` means the resolve half did not run.

      > The verdicts distinguish **`reparse-owed`** (hours) from
      > **`resolve-owed`** (minutes) on purpose. Treating the cheap one as the
      > expensive one is how a re-resolve gets deferred indefinitely.

      > Filed as a gap: the About window is the one screen built to stop a stale
      > index answering confidently -- its own header says so -- and it is blind
      > to the staleness that matters most. Reading two `schema_meta` rows is an
      > indexed lookup, not a COUNT, so the performance contract does not
      > actually forbid it.

## 2. The engine can be rebuilt with the IDE open

- [ ] **2.1** Leave the IDE open with a project loaded. Run
      `C:\Projects\Delphi-RAG-lint\build\build_draglint_win64.bat`.
- [ ] **2.2** It must **succeed, including staging**. The status strip shows
      `drag-lint: engine released for a rebuild (Ns left)`.
- [ ] **2.3** Afterwards, hover a symbol and confirm the LSP came back.

> Verified working headlessly today: the build staged cleanly with RAD Studio
> open. The failure this replaces was `ERROR: failed to stage ...` one line after
> a successful compile.

## 3. Per-severity gutter icons

- [ ] **3.1** Open a unit with findings. *About > Run Diagnostics (didSave)* if
      the gutter is empty.
- [ ] **3.2** Each severity shows a **distinct drawn glyph** -- not a uniform
      filled square, and not the old `[E] ` text tag on Diagnostics rows.
- [ ] **3.3 Look hard at the glyphs at YOUR font size, and change the size.**
      Two defects in this family were invisible in review and obvious only once
      the arithmetic was replayed: an info "i" that drew solid and read as a
      warning, and an error "X" that sat off-centre and escaped its circle. Zoom
      up and down several steps; each glyph must stay centred, inside its circle,
      and distinguishable.
- [ ] **3.4** Toggle a severity off; only those rows lose their mark.

## 4. `dl:ok` markers -- NEW, and the reason is a silent failure

- [ ] **4.1** In a scratch unit, put a real finding on a line and mark it with a
      **deliberately malformed** marker:
      ```pascal
      Sleep(100); // dl:ok sleep-in-vcl: because reasons
      ```
- [ ] **4.2** Run *Code Quality > Run Lint All*. Expect **two** things on that
      line: the original finding **still reported**, and a new
      **`review-marker-malformed`** hint saying the marker suppresses NOTHING and
      listing the accepted forms.
- [ ] **4.3** Now write it correctly -- `// dl:ok sleep-in-vcl -- because reasons`
      -- and confirm the finding IS suppressed and the malformed hint is gone.

> Why this matters: a marker that fails loudly is a nuisance; one that fails
> silently is a lie the source tells every future reader. A real project had 11
> such markers, 11 findings still firing, and no warning of any kind.

## 5. Autofix from the panel

- [ ] **5.1** Open the dockable panel (*View > Tool Windows > drag-lint*). Tabs
      read **Structure | Search (no grep) | Blast Radius**.
- [ ] **5.2** Right-click a fixable finding -> **Fix it**. The buffer is
      rewritten and reloaded.
- [ ] **5.3** From the Diagnostics **root** node: **Fix all in unit** and **Fix
      all in project** are enabled there and disabled on a leaf (that is correct).
- [ ] **5.4** **Allow this message** on a finding writes a properly formatted
      `dl:ok` -- cross-check it does NOT produce the malformed hint from 4.2.

## 6. A directory walk stays inside the project

- [ ] **6.1** Point a lint run at a folder containing units the project does not
      compile (ORM3 CLIENT qualifies -- it holds `- Copy.pas` files).
- [ ] **6.2** **No finding may name a file the project does not compile.** Read
      the file column, not the summary count.
- [ ] **6.3** On a **scratch copy**, repeat with `--fix --apply`, then check by
      timestamp/hash which files changed.

> Verify what was TOUCHED, not whether a skip message appeared. The first version
> of this filter was a complete no-op that still printed plausibly.

## 7. Options page and process hygiene

- [ ] **7.1** *drag-lint Options...*, change a setting, close. Then open
      `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.json`: **indented, readable, no BOM.**
- [ ] **7.2** Work for a few minutes; the `drag-lint.exe` count in Task Manager
      must not climb.
- [ ] **7.3** *About > Open Plugin Log* -- Find Usages should be answered over
      the warm LSP without a fresh spawn per call.

## 8. Menu smoke -- does anything not open?

- [ ] Full Compile Sweep | Compile && Diagnose | Compile Buffer (unsaved)
- [ ] Circular Uses Report -- **states its outcome including "no cycles"**
- [ ] Show Structure | Symbol Search | drag-lint Graph opens and renders
- [ ] `Ctrl+Alt+U` Quick-Fix on a deliberately undeclared identifier

---

# PART TWO -- [AFTER]: only once the reindex has finished

**Gate:** the evening `index --all` has completed, and step 1.5's staleness
warning is **gone**.

## 9. Attribute indexing -- NEW in this build

- [ ] **9.1** In a DUnitX suite, put the caret on a `[Test]`-attributed method
      and run *Find Usages*.
- [ ] **9.2** RTTI attributes are now indexed. Previously `[Test]` produced
      nothing at all, and `[TestCase('a','1,2')]` produced a **fabricated call
      edge** -- the index believed the method called a routine named `TestCase`.
      That edge must be gone.

## 10. Helper-method resolution

- [ ] **10.1** *Find Usages* and *Reverse Call Tree (clickable)* on a record or
      class helper method. Real callers must appear; each Messages line must
      navigate correctly.
- [ ] **10.2** Same for a method reached through an **enum-typed receiver** and a
      **plain type alias**.

> If callers look plausible but land a consistent number of lines off, the index
> is stale, not the feature broken.

## 11. Rules that changed behaviour

- [ ] **11.1** `method-pascalcase` must **not** fire on DUnitX
      `[Test]`/`[TestCase]`/`[Setup]` methods, and **must** still fire on an
      ordinary badly-named helper in the same class.
- [ ] **11.2** `unused-unit-in-uses` now reports at **info**, and its message
      names three blind spots. **Do not act on it without checking** -- measured
      wrong ~13% of the time toward breaking the build.
- [ ] **11.3** `unsafe-shellexecute`: a `CreateProcess` with a non-nil
      `lpApplicationName` is silent; one routing through `cmd.exe` with a nil
      `lpApplicationName` still reports.
- [ ] **11.4** The five coupling rules appear in a full report:
      `global-only-uses-edge`, `uses-global-census` (states a **ratio**),
      `duplicate-global-decl` (caps site lists at six with "and N more"),
      `with-hides-outer-symbol`, `stat-gated-destructive`.

## 12. Index-backed navigation

- [ ] Hover | Go to Definition | Show Completion (**type a prefix, not just the
      dot at end of line**) | Signature Help | Type at Cursor
- [ ] *Rename Symbol* -- **review the preview and cancel** unless on a scratch copy
- [ ] Panel Search: Symbol / Text / Usages all navigate on double-click; an
      unindexed local gives ONE clean "No matches" line -- **no raw JSON, no
      `== DEBUG ==`**
- [ ] A form-unit result opens the **`.pas`**, not the designer
- [ ] Hover in an **unindexed** file must NOT answer from the LIBRARY index

---

## Not exercised on purpose

**Auto-Document Whole Project** writes to source files -- commit or stash first.
**Rebuild Index for This Project** is destructive by design and would throw away
the evening reindex. Run either only deliberately.

---

## Reporting a failure

1. The **step number**.
2. What you did and what you saw, **separately** -- not a diagnosis.
3. Tail of *About > Open Plugin Log* (it records what was actually invoked).
4. The **Versions** group, so the build under test is unambiguous.
5. For anything index-shaped: *Show Resolved DBs (debug)*, and **whether the
   reindex had finished**.

A step that could not be run is **not** a pass. Mark it skipped and say why.

## Sign-off

- [ ] Part 0 complete
- [ ] **PART ONE [NOW]** complete
- [ ] Reindex finished
- [ ] **PART TWO [AFTER]** complete
- [ ] **Verdict: release / hold**
