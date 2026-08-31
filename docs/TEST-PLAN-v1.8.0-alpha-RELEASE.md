# drag-lint v1.8.0-alpha -- IDE release-verification pass

**Purpose.** Confirm, in a live RAD Studio 13 Florence (Studio 37.0), that the
v1.8.0-alpha engine and the plugin that drives it behave in the IDE the way 428
headless tests say they behave. This is the last gate before the release is
tagged and published.

**This is NOT `TEST-PLAN-IDE-FULL.md`.** That document is a 484-step sweep last
touched 2026-06-17, targets **v0.45.0-alpha**, and its setup section names
databases that no longer exist (`C:\Projects\DB\ORM3\drag-lint.sqlite`,
`C:\Projects\drag-lint-all.sqlite` -- both deleted when the per-project `_D-RAG`
layout landed). Do not use it as-is. This pass is scoped to **what changed in
v1.8.0-alpha** plus a short core sweep that would catch a plugin that failed to
load at all.

**Time budget:** Part 0 ~20 min (mostly waiting on a re-resolve), Part 1 ~5 min,
Part 2 ~40 min, Part 3 ~15 min.

**If anything misbehaves:** *drag-lint > About > Open Plugin Log*, and copy the
tail. The log records what was actually invoked, which is almost always the
answer. Note the step number here so the report is unambiguous.

---

## Part 0 -- Preconditions

Work through these in order. Steps 0.1 and 0.2 collide with each other, which is
the point of doing them in this order.

- [ ] **0.1 Close the IDE, then build the engine.**

      A running IDE holds `third_party\dll-win64\drag-lint.exe` through the
      long-lived `lsp --stdio` child, and a build fails at the STAGING step with
      a message that names the file but not the holder. Building with the IDE
      shut is the simple path.

      ```
      build\build_draglint_win64.bat
      ```

      Expect `BUILD_EXITCODE=0` and no `[dcc] Error` in the log. This produces
      Win64 **Debug**, stages the tree-sitter companions beside the linked exe,
      syncs `rules\` to both exe directories, and deploys to
      `third_party\dll-win64\`.

- [ ] **0.2 Build the plugin BPL, then install it.**

      Build `dclDragLintWizard.dproj`. In the IDE:
      *Component > Install Packages* -- if `dclDragLintWizard` is already listed,
      **uncheck it, rebuild, then re-check it**; a BPL that is merely rebuilt
      under a loaded package does not take effect.

      On load the IDE confirms `drag-lint`.

- [ ] **0.2b VS CODE WILL BLOCK YOUR BUILDS IF ITS EXTENSION IS OLD. Check
      this before you lose a build to it.**

      Measured on this machine 2026-08-31: with the Delphi IDE **closed**, a
      build still failed at staging, and the holder was **VS Code**:

      ```
      PID 57928  ...\third_party\dll-win64\drag-lint.exe lsp --stdio
      parent: Code(24384)
      ```

      Cause: the **installed** extension is **v1.2.2**. The private-engine-copy
      fix -- which is what stops VS Code holding the deployed binary -- shipped
      in extension **v1.4.0**, and `editors\vscode\drag-lint\package.json` in
      this repo is already at 1.4.0. The fix exists and is guarded by
      `tests\vscode\run_vscode_engine_copy.ps1`; it simply is not installed.

      Either **package and install the current extension**, or close VS Code for
      the duration of the build. If you hit it anyway, the workaround is good and
      loses nothing: `msbuild` writes `src\cli\Win64\Debug\drag-lint.exe`, which
      nothing holds, and **every runner takes `-Exe`** -- so test against that
      path and defer only the deploy. Treat `ERROR: failed to stage` as expected
      in that window; the compile line above it is what matters.

- [ ] **0.3 Confirm the engine version the plugin will actually run.**

      ```
      third_party\dll-win64\drag-lint.exe --version
      ```

      Must read **1.8.0-alpha**. Use the full path -- this machine has
      `NoDefaultCurrentDirectoryInExePath` set, so a bare `drag-lint` resolves
      off PATH to an older build. A session once reported 33,626 findings
      against a real 14,764 for exactly this reason.

- [ ] **0.4 Re-resolve the indexes. THIS RELEASE OWES ONE.**

      `DRAGLINT_RESOLVER_VERSION` is new and stands at `1.1.0-alpha`. Every
      existing index is stamped `r=1.0.0-alpha`, so each one re-derives its
      edges **once**. This is minutes per section, not the ~5 hours a re-parse
      costs, and it is the difference the second stamp exists to make.

      ```
      third_party\dll-win64\drag-lint.exe index --all --jobs 0
      ```

      A section that needs it prints, before the resolve:

      ```
      Resolver changed since this DB was resolved
        (r=1.0.0-alpha;schema=21 -> r=1.1.0-alpha;schema=21): re-deriving every edge.
      resolve: calls  starting WHOLE-DB pass over all N indexed file(s)
      ```

      **If you see no such line for any section, stop and report it** -- that is
      the stamp failing to detect exactly the staleness it was built for, and
      every result below would be measured against old edges.

      To re-derive without walking a single file (useful for the big library
      indexes): `index <dir> --db <db> --resolve-only`.

- [ ] **0.5 Open a real project.** ORM3 `CLIENT\Micronite2027.dproj` is the
      reference corpus for this pass -- most measurements in the CHANGELOG are
      taken on it. Open a unit with real code so the index-backed items have
      something to answer about.

---

## Part 1 -- Is the right build loaded?

Everything in Part 2 is meaningless if the IDE is driving a stale engine.

- [ ] **1.1 Open *drag-lint > About*.** The window renders five groups:
      **Versions**, **Connections**, **Indexes in use**, **Configuration**,
      **Process**.

- [ ] **1.2 Versions group.**

      | Row | Expected |
      |---|---|
      | Plugin (BPL) | `v1.1.0-alpha` + today's build time |
      | BPL path | the BPL you just installed, not an older copy elsewhere |
      | Engine | `1.8.0-alpha`, today's build date, platform `Win64` |
      | Engine exe | `...\third_party\dll-win64\drag-lint.exe` |
      | tree-sitter | `delphi13 <v> / dfm <v>`, both present |
      | Graph viewer | `present, built <date>` |

      **The plugin and engine versions differ on purpose** -- `PLUGIN_VERSION`
      and `DRAGLINT_VERSION` are separate constants. `v1.1.0-alpha` beside
      `1.8.0-alpha` is correct, not a mismatch.

      A red **`Engine -- UNAVAILABLE`** row means the plugin cannot run the exe
      at all; nothing below will work. Fix that first.

- [ ] **1.3 Connections group.** The LSP server may read *"not started yet
      (starts on first hover / completion)"* -- that is correct on a cold IDE,
      not a fault. Hover over a symbol, reopen About, and it should now report a
      live server.

      If the `drag-lint` menu's own caption reads **`drag-lint (!)`**, the LSP is
      down and the Connections group states why.

- [ ] **1.4 Indexes in use.** Confirm the paths are the per-project `_D-RAG`
      ones -- `C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite`, plus
      `C:\Projects\.drag-lint\library-Win32.sqlite` or `-Win64`. Any path under
      a shared `C:\Projects\.drag-lint\<Repo>-<Project>.sqlite` is a **stale
      config** -- that layout was retired.

      **An index that exists is not an index that is populated.** If results come
      back thin, cross-check with *drag-lint > Index && Maintenance > Show
      Resolved DBs (debug)*, which is the first thing to look at when answers
      arrive from somewhere unexpected.

---

## Part 2 -- New in v1.8.0-alpha

The pass that matters. Each item states what to do, what to expect, and **what
it proves** -- so a partial result can still be reported usefully.

### 2.1 The engine can be rebuilt with the IDE open

Previously a merely-open IDE blocked every engine build.

- [ ] **A.** Leave the IDE open with the project loaded. From a shell, run
      `build\build_draglint_win64.bat`.
- [ ] **B.** Expect the build to **succeed**, including the staging step. While
      the hold is active the plugin's status strip reads
      `drag-lint: engine released for a rebuild (Ns left)`.
- [ ] **C.** After the build, the plugin recovers on its own -- hover over a
      symbol and confirm the LSP answers again.

> *Proves:* `ide-release` writes the hold, `stage-engine.ps1` kills the holder
> and retries, and the hold makes the kill stick. The failure mode this replaces
> was `ERROR: failed to stage ...drag-lint.exe` one line after a successful
> compile.

### 2.2 Per-severity gutter icons

- [ ] **A.** Open a unit with findings of more than one severity. Run
      *drag-lint > About > Run Diagnostics (didSave)* if the gutter is empty.
- [ ] **B.** The editor gutter shows a **drawn glyph per severity**, not a
      uniform filled square (which is what shipped before 2026-08-25), and not
      the old `[E] ` text tag on the Diagnostics rows.
- [ ] **C.** **Look closely at the glyphs at your actual gutter size.** Two
      rendering defects in this family were invisible in review and obvious only
      when the integer arithmetic was replayed: an info "i" that read as a
      warning because it drew solid at one diameter, and an error "X" that sat
      off-centre and escaped its circle at another. Zoom the editor font up and
      down a few steps and confirm each glyph stays centred, inside its circle,
      and distinguishable.
- [ ] **D.** Toggle a severity off in the options and confirm those rows lose
      their gutter mark while the others keep theirs.

### 2.3 A directory walk stays inside the project

The owner's ruling, verbatim: *"they are completely unrelated and might belong
to some other project and reading or modifying those might break something
else."*

- [ ] **A.** Pick a folder that contains units the active project does **not**
      compile -- ORM3 CLIENT qualifies; it holds `- Copy.pas` files and units
      belonging to other projects.
- [ ] **B.** Run a report over the folder (*Code Quality > Run Lint All (Full
      Report)*, or `lint <folder> --db <db>` from a shell).
- [ ] **C.** **No finding may name a file the project does not compile.** Read
      the report's file column, not the summary count.
- [ ] **D.** Repeat with `--fix --apply` on a **scratch copy of the folder**, and
      afterwards check which files changed by timestamp or hash.

> *Proves:* both halves of the ruling. **Verify which files were TOUCHED, not
> whether a skip message appeared** -- the first version of this filter read the
> wrong argument, was a complete no-op, still printed plausibly, and was caught
> only by noticing that a foreign file had received an edit.

### 2.4 `exceptions-sync` and the bare-raise rewrite

The verb writes the unit; the call-site rewrite is a fix-it.

- [ ] **A. Dry run first -- it is the default.**
      ```
      drag-lint exceptions-sync --db <project db>
      ```
      Expect a report of the classes it *would* add, and **no file written**.
      Confirm nothing changed on disk before going further.
- [ ] **B.** `--apply` against a **project whose exceptions unit is committed or
      backed up by hash**. On ORM3 the target is
      `COMMON\CommonExceptions.pas`, which already declares `EMicroniteError`.
- [ ] **C. Run `--apply` a second time.** It must report `0 class(es) added`
      **and leave the file byte-identical**. This is the exact kill condition
      that caught a shipped defect: 11 of ORM3's 78 real messages end in a
      space, the `//` map comment was written verbatim and read back trimmed, so
      the second run silently rewrote the unit while correctly reporting zero
      additions. Compare sizes or hashes -- the report alone cannot tell you.
- [ ] **D.** Confirm the generated unit **compiles**. A configured ancestor
      declared in another unit must have reached the `uses` clause.
- [ ] **E. In the IDE:** open a unit containing `raise Exception.Create('...')`,
      open the dockable panel, find the `raise-bare-exception` finding under
      Diagnostics, right-click it and choose **Fix it**. The call site should be
      rewritten to the generated class and the buffer reloaded.
- [ ] **F.** Also exercise **Fix all in unit** and **Fix all in project** from
      the Diagnostics *root* node (they are disabled on a leaf finding, which is
      correct), and **Allow this message** on a finding you want to keep.

> *Note:* the rewrite reads the class NAME out of the generated unit rather than
> re-deriving it, so renaming a generated class by hand must keep working. Rename
> one, re-run, and confirm no reference to a dead class appears.

### 2.5 Helper-method calls resolve

887 of 1,118 helper-member call refs now bind to a real target, up from **zero**.

- [ ] **A.** Find a record or class helper method in the project.
- [ ] **B.** *drag-lint > Find Usages...* on it, and *Reverse Call Tree
      (clickable, Messages window)*.
- [ ] **C.** Expect real callers, and each Messages line must navigate to the
      right place. Previously helpers were invisible to the call graph entirely.
- [ ] **D.** Same check on a method reached through an **enum-typed receiver**
      and through a **plain type alias** (`TFoo = TBar`) -- both newly resolve.

> **A stale index can have a NEWER mtime than the source.** If callers look
> plausible but land a consistent number of lines off, the index is stale, not
> the feature broken. Re-run 0.4 before reporting.

### 2.6 The five new rules appear and are readable

- [ ] **A.** Run *Code Quality > Run Lint All (Full Report)*. Confirm findings
      exist for: `global-only-uses-edge`, `uses-global-census`,
      `duplicate-global-decl`, `with-hides-outer-symbol`,
      `stat-gated-destructive`.
- [ ] **B. `uses-global-census` must state a RATIO**, not a bare count -- how
      many globals the reader draws *out of* how many the used unit declares,
      plus its DFM object count. "7 of 9" and "7 of 206" are opposite advice.
- [ ] **C.** It must **skip plain forms** and report datamodules. On ORM3 CLIENT
      there are 61 DFM roots and exactly 2 datamodules; `uStyles` is one, so the
      canonical 26-edge case must survive while ~43 plain-form edges stay quiet.
- [ ] **D. `duplicate-global-decl` must not list more than six sites** -- it caps
      at six with an "and N more" tail. A report line nobody can read is the same
      defect as a rule that floods. Confirm `Register` is not reported (it is
      declared in 134 ORM3 units by design).
- [ ] **E.** Confirm the acknowledgement `// dl:unit <unit> accepted` silences a
      census finding, **and that the older `// dl:census-ok <unit>` still works**
      -- an acknowledgement someone already wrote must not break when the wording
      improves.

### 2.7 Findings that were reporting zero

- [ ] **A. `unused-unit-in-uses` must report a non-zero count** on a real
      project. It reported **zero everywhere** before this release, in both
      layers. A zero here is a regression, not a clean project.
- [ ] **B.** Cross-check one of its findings with *Uses Cleanup Preview
      (compiler-verified, this unit)* -- a unit needed only for an inline or a
      `{$IF}` branch must NOT be offered for removal.

### 2.8 Find Usages does not spawn a process

- [ ] **A.** Open *About > Open Plugin Log*, note the tail.
- [ ] **B.** Run *Find Usages...* several times on different symbols.
- [ ] **C.** Re-read the log: the requests should be answered over the warm LSP
      (`draglint/usages`), without a fresh `drag-lint.exe` spawn per call. The
      code-lens caller counts went from 137 process spawns to none by the same
      route.
- [ ] **D.** Confirm in Task Manager that the `drag-lint.exe` count is not
      climbing as you work.

### 2.9 Hover, scope and configuration

- [ ] **A.** Hover a symbol in a file that is **not indexed**. It must NOT answer
      from the LIBRARY index -- a name match against the RTL is not this file's
      symbol.
- [ ] **B.** Open *drag-lint > drag-lint Options...*, change any setting, close.
      Then open `third_party\dll-win64\drag-lint.json` in a text editor: it must
      be **readable, indented JSON with no BOM**. It was previously written
      minified and with a BOM.
- [ ] **C.** Confirm the *Configuration* group in About reports no warnings.

### 2.10 `refs.symbol_id` is populated

Not directly visible in the IDE, but it underpins the delete-safety answers.

- [ ] **A.** Pick a public symbol you know is referenced. Run *Find Dead Code...*
      and confirm it is **not** listed.
- [ ] **B.** Sanity-check one const used only as an **array bound**
      (`array [1..CBound] of ...`). This exact shape emitted no ref before this
      release, and a "safe to delete" check cleared a const the build needed --
      breaking ORM3 with E2003 plus two cascades. It must now show usages.

---

## Part 3 -- Core regression sweep

Short. This is here to catch a plugin that loaded but is broadly broken, not to
re-test features that have not changed.

- [ ] **3.1** *Hover at Cursor* -- signature, documentation and callers render.
- [ ] **3.2** *Go to Definition* -- lands on the declaration.
- [ ] **3.3** *Show Completion* -- list appears, and **type a prefix first**
      rather than only invoking it at end of line. Every completion fixture used
      to put the dot at end of line and never type a prefix, which structurally
      hid both a caret off-by-one and a wrong global-search fallback.
- [ ] **3.4** *Show Signature Help* -- parameter help inside a call.
- [ ] **3.5** *Symbol Search...* and *Type at Cursor*.
- [ ] **3.6** *Rename Symbol...* -- **review the preview and cancel**, unless you
      are on a scratch copy. It is a source-wide edit.
- [ ] **3.7 Dockable panel** (*View > Tool Windows > drag-lint*): tabs read
      **Structure | Search (no grep) | Blast Radius**, in that order.
      - Kind=Symbol, Kind=Text and Kind=Usages each return rows that navigate on
        double-click.
      - Search something genuinely unindexed (a local variable): a single clean
        "No matches" status line. **No raw JSON, no `== DEBUG ==` anywhere.**
      - Clicking a form-unit result opens the `.pas` editor, **not the form
        designer**.
- [ ] **3.8 Graph** (*View > Tool Windows > drag-lint Graph*) opens and renders.
- [ ] **3.9** *Compile && Diagnose* and *Compile Buffer (unsaved)* both return.
- [ ] **3.10** *Full Compile Sweep* completes and refreshes the open file.
- [ ] **3.11** *Circular Uses Report* -- states its outcome **including the
      negative one** ("no cycles"), rather than rendering an empty section.
- [ ] **3.12** *Quick-Fix: Add Unit for Undeclared at Cursor* (`Ctrl+Alt+U`) on a
      deliberately undeclared identifier adds the right unit to `uses`.

> **Not exercised here, on purpose:** *Auto-Document Whole Project* and *Rebuild
> Index for This Project*. The first **writes to source files** -- commit or
> stash first. The second is **destructive by design**: it clears the project's
> index and re-parses its whole compile closure, which would throw away the
> re-resolve from step 0.4. Run either only deliberately.

---

## Part 4 -- Reporting

For each failure, capture:

1. **The step number** from this document.
2. **What you did** and **what you saw**, separately -- not a diagnosis.
3. **The tail of *About > Open Plugin Log***, which records what was actually
   invoked.
4. **The Versions group from About**, so the build under test is unambiguous.
5. For anything index-shaped, the output of *Show Resolved DBs (debug)* and
   whether step 0.4 printed a re-resolve line for that section.

A step that could not be run (no suitable code in the project, a prerequisite
failed) is **not** a pass. Mark it skipped and say why -- an unrun check
reported as green is worse than a known gap.

---

## Sign-off

- [ ] Part 0 complete, including the re-resolve at 0.4
- [ ] Part 1 confirms engine `1.8.0-alpha` / plugin `v1.1.0-alpha`
- [ ] Part 2 complete, with every failure written up per Part 4
- [ ] Part 3 complete
- [ ] **Verdict: release / hold**
