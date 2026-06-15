# drag-lint Visual Configurator - Manual Test Plan

Standalone Win64 app `drag-lint-config.exe`. It edits the unified
`.drag-lint.json` (sections + settings), shows per-folder coverage, previews the
resolved plan, and runs build/drift by shelling to `drag-lint.exe`.

**Automated coverage already passing** (you don't need to run these; for
reference): `run_coverage.ps1` (coverage classifier), `run_config_build.ps1`
(app compiles + `--version`), plus `run_manifest/reconcile/drift/formsmap`. This
plan covers the GUI runtime, which is not automated.

## Setup
- The app is deployed beside the engine + config:
  `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint-config.exe`
  (next to `drag-lint.exe` and `drag-lint.json`).
- **Launch it** by double-clicking that exe, or from a prompt:
  `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint-config.exe`
  It auto-loads `drag-lint.json` from its own folder. (To load a different
  manifest: `drag-lint-config.exe --config <path>\.drag-lint.json`.)
- Report per failing step: the step number, what you saw vs expected, and any
  text in the Build log / a message box.

## A. Load + section editor (Indexes tab)
- [ ] **A1 Launch + load.** App opens on the **Indexes** tab. The **Sections**
      list (left) shows your sections: ORM3, SQL, Loader, TableTools, DragLint,
      DragLintGraph, OCRPDF, Library, AllProjects.
- [ ] **A2 Select a section.** Click **ORM3** -> the right editor fills: Name
      `ORM3`, Db the ORM3 sqlite path, Source = folders/dproj, Include lists
      `C:\Projects\DB\ORM3`, useIgnoreFiles checked.
- [ ] **A3 Library section.** Click **Library** -> Source = registry-libraries,
      Platforms shows `*` (or the list), Db `library-{platform}.sqlite`.
- [ ] **A4 Edit Include.** Select **TableTools**, click **+Folder**, pick any
      folder -> it appears in the Include list. Click **Remove** -> it's gone.
- [ ] **A5 Edit fields.** Change an Exclude / toggle useIgnoreFiles on a scratch
      section -> values stay as you set them when you reselect the section.
- [ ] **A6 Add / Delete.** **Add** -> a new "NewDB" section appears + is
      selected. **Delete** it -> it's removed from the list.

## B. Settings tab
- [ ] **B1 Open Settings tab.** Shows: currentProjectsIndexing (combo:
      perProject/perGroup/single), defaultPlatform (combo listing your registry
      platforms - Win32/Win64/...), sizeGuardMB (1500), maxJobs (0),
      maxParseFileKB (2048), enginePath (auto).
- [ ] **B2 Round-trip.** Change defaultPlatform to Win64 and maxJobs to 4 ->
      click **Save** -> click **Reload** -> the Settings tab still shows Win64 / 4
      (persisted to the JSON). (Set them back if you like.)

## C. Plan preview tab (Indexes -> bottom "Plan preview")
- [ ] **C1 Refresh.** Click the **Plan preview** tab (or **Refresh**) -> a grid
      lists every section: Section, Mode (folderTree / closure / library), Db,
      Platform, Roots count, Dedup count.
- [ ] **C2 Platform expansion.** The Library section appears once **per platform**
      (library-Win32, library-Win64, ...), each Mode = library.
- [ ] **C3 Closure + dedup.** Loader shows Mode = closure. AllProjects shows a
      non-zero Dedup count.
- [ ] **C4 Live.** Edit a section's Include (tab A), return to Plan preview,
      Refresh -> the change is reflected.

## D. Coverage tree (Indexes -> bottom "Coverage") - the headline view
- [ ] **D1 Set root.** On the **Coverage** tab, set the root to `C:\Projects`
      (browse or type) -> click **Refresh**.
- [ ] **D2 Colors.** Child folders are color-coded:
      - **green** = indexed by a section (e.g. `DB` path under ORM3, `TableTools`,
        `OCRPDF`, `Loader2019`).
      - **gray** = excluded by a rule (e.g. a `... - Copy` folder, `*BACKUP*`).
      - **red** = unassigned (a project folder not in any section).
      - **navy** = under a library path; **olive/amber** = overlap (>1 section).
      The caption shows `<leaf> [<kind>] <detail>` (detail = section name or the
      matching rule).
- [ ] **D3 Expand.** Click the [+] on a folder -> its children are classified the
      same way (lazy-loaded).
- [ ] **D4 Assign.** Right-click a **red (unassigned)** folder -> **Assign to ->**
      -> pick a section -> the folder is added to that section's Include and the
      node recolors **green**. (Check tab A: the section's Include now lists it.)
- [ ] **D5 New DB.** Right-click another folder -> **New DB from folder...** ->
      accept/edit the name -> a new section appears in the Sections list (tab A)
      with that folder as its Include; the node recolors green.
- [ ] **D6 Persist.** Click **Save**. Reopen the app -> your D4/D5 changes are
      still there.

## E. Build / drift (Indexes -> bottom "Build log")
- [ ] **E1 Build Selected.** Select a SMALL section (e.g. OCRPDF or TableTools)
      in the Sections list, open the **Build log** tab, click **Build Selected**
      -> the log streams `=== <name> -> ...sqlite : files=.. ===` and ends with
      `=== exit 0 ===`; the buttons re-enable when done.
- [ ] **E2 Library Drift.** Click **Library Drift** -> the log reports
      `library-drift: N platforms checked, 0 roots missing from index` (0 after the
      recent full reindex), `=== exit 0 ===`.
- [ ] **E3 Build All (optional, long).** Click **Build All** only if you have time
      (Library + AllProjects take a while). Expect per-section lines, some
      `SKIP ... exceeds parse limit` for huge generated files, and a final
      `parallel build: N/N sections OK` / `=== exit 0 ===`.

## F. Save integrity
- [ ] **F1 Valid JSON.** After any edits + **Save**, run in a prompt:
      `drag-lint.exe index --all --dry-run --config third_party\dll-win64\drag-lint.json`
      -> it parses and prints the plan (proves the configurator wrote valid JSON).
- [ ] **F2 Invalid guard.** (Optional) Make two sections share the same Name,
      Save -> a validation error message appears and the file is NOT written.

## Notes / known limits (by design)
- Coverage classifies one folder level at a time (expand to go deeper) for speed.
- Plugin settings (auto-index, hover) are NOT here yet - they come when the
  configurator moves into the IDE.
- The app reads the engine from beside itself (`drag-lint.exe`), or
  `settings.enginePath` if set; if Build buttons say "engine not found", set
  enginePath on the Settings tab.
