# drag-lint IDE pass -- DataCopy edition

**Engine `1.9.0-alpha`, plugin `v1.1.0-alpha`, extractor `1.10.0-alpha`,
resolver `1.1.0-alpha`, schema `21`.**

Everything here is DataCopy-only. No step needs ORM3. Every file, line number
and count below was **measured on this machine on 2026-09-01** against the
engine you are about to test, so a mismatch is a real result, not a guess.

> **One caveat that is yours, not the tool's:** you are editing DataCopy in
> another window. Total counts move when you edit. The per-rule and per-file
> numbers are what matter; if a TOTAL is off by a few, check whether you changed
> the file before reporting it. (Measured twice 30 minutes apart today: 130 then
> 132, from your edits, on identical binaries.)

## The two DataCopy databases -- both verified `current`

| what | path |
|---|---|
| app index | `C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite` |
| tests index | `C:\Projects\DataCopy\Tests\_D-RAG\DataCopyTests.sqlite` |
| app project | `C:\Projects\DataCopy\DataCopy.dproj` |
| tests project | `C:\Projects\DataCopy\Tests\DataCopyTests.dproj` |
| engine | `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe` |

**Never type a bare `drag-lint`.** This machine sets
`NoDefaultCurrentDirectoryInExePath`, so a bare name runs a different, older
binary off PATH. Always the full path above.

---

## Part 0 -- Preconditions

- [ ] **0.1** Engine version:
      ```
      C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe --version
      ```
      Must read **`drag-lint 1.9.0-alpha`**.

- [ ] **0.2** *Component > Install Packages* lists `dclDragLintWizard`. If you
      rebuilt the BPL: **uncheck, rebuild, re-check** -- a BPL rebuilt while
      loaded does not take effect.

- [ ] **0.3** Open `C:\Projects\DataCopy\DataCopy.dproj` and a unit with real
      code -- use `uFileUtils.pas`, it is the one section 3 needs.

---

## 1. About window -- is this the right build, and are the indexes fresh?

- [ ] **1.1** *drag-lint > About* renders five groups: **Versions**,
      **Connections**, **Indexes in use**, **Configuration**, **Process**.

- [ ] **1.2** Versions: plugin `v1.1.0-alpha`, engine `1.9.0-alpha`, platform
      `Win64`. **Plugin 1.1.0 beside engine 1.9.0 is CORRECT** -- two
      independent constants, not a mismatch.

- [ ] **1.3** *Indexes in use* names
      `C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite` and
      `C:\Projects\.drag-lint\library-Win64.sqlite`. Anything under a shared
      `C:\Projects\.drag-lint\<Repo>-<Project>.sqlite` is a **stale config**;
      that layout was retired.

- [ ] **1.4 `[ok]` in that window means PRESENT, not FRESH -- it cannot tell you
      about staleness, by design.** Ask the engine instead:

      ```powershell
      $exe = "C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe"
      $r = & $exe info --json `
             --db "C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite" `
             --db "C:\Projects\DataCopy\Tests\_D-RAG\DataCopyTests.sqlite" `
             --db "C:\Projects\.drag-lint\library-Win64.sqlite" 2>$null | ConvertFrom-Json
      $r.indexes | Format-Table path, verdict, indexer_stale, resolver_stale -AutoSize
      ```

      **All three must read `current`.** Measured today: they do. Anything
      `reparse-owed` or `resolve-owed` means a section failed -- stop and say so,
      because it invalidates sections 9 and 10.

---

## 2. The engine can be rebuilt with the IDE open

- [ ] **2.1** Leave RAD Studio open with DataCopy loaded. Run
      `C:\Projects\Delphi-RAG-lint\build\build_draglint_win64.bat`.
- [ ] **2.2** It must **succeed, including staging** -- the last line reads
      `OK: staged Win64 drag-lint.exe + tree-sitter companions`. The status strip
      shows `drag-lint: engine released for a rebuild (Ns left)`.
- [ ] **2.3** Hover a symbol afterwards and confirm the LSP came back.

> Verified working headlessly today, three times, with RAD Studio open.
> **If it fails at staging, the holder is almost certainly VS Code, not the IDE**
> -- see the note at the end of this document.

---

## 3. Per-severity gutter icons -- use `uFileUtils.pas`

> **>>> CHECK YOUR FILTERS FIRST. An empty gutter is usually a SETTING, not a bug.**
>
> This step originally listed severity counts without saying that the plugin
> draws only the severities you have switched on -- and on this machine
> `ShowInfoInline` was **0**, so the whole info class was silently hidden. That
> cost a full round trip on 2026-09-01: a real finding list, a genuinely empty
> gutter, and no way to tell the two apart from the screen.
>
> **About > Configuration now states this** -- `severities drawn` plus a warning
> when info is off. Read it before reporting anything in this section.
> To change it: **drag-lint Options > Show info inline**.

`C:\Projects\DataCopy\uFileUtils.pas` carries all four classes. Measured today
with the per-file lint the LSP uses (45 findings):

| severity | count | drawn only if |
|---|---|---|
| warning | 1 (line 2208) | `ShowWarningsInline` |
| hint | 21 | `ShowHintsInline` |
| info | 23 | `ShowInfoInline` |

**The first non-info finding is at line 1036.** Everything above it -- lines 9,
63-79, 246, 349, 392, 958, 965, 1034 -- is info. So with info off, the top
thousand lines are CORRECTLY blank, and scrolling is not optional.

Good places to look with info off: hints at **1036, 1064, 1110, 1289, 1338,
1455, 1575-1589, 1732, 2028, 2055, 2492**, and the lone warning at **2208**.

- [ ] **3.0** *About > Configuration* -- record which severities are drawn.
      Every assertion below is relative to that.
- [ ] **3.1** Open it. If the gutter is empty, *About > Run Diagnostics (didSave)*.
- [ ] **3.2** Each severity draws a **distinct glyph** -- not a uniform filled
      square, and no `[E] ` text tag on Diagnostics rows.
- [ ] **3.3 Change the editor font size up and down several steps and look hard.**
      Two defects in this family were invisible in review and obvious only when
      the arithmetic was replayed: an info "i" that drew solid and read as a
      warning, and an error "X" that sat off-centre and escaped its circle. Each
      glyph must stay centred, inside its circle, and distinguishable at every
      size you use.
- [ ] **3.4** Toggle one severity off; only those rows lose their mark.

---

## 4. `dl:ok` markers -- DataCopy is the project that found this bug

**Open `C:\Projects\DataCopy\Tests\Test.FolderWatcher.pas`** and run
*Code Quality > **Run Lint All*** with the **tests** project active.

> **Run Lint All, not per-file lint. This is load-bearing.**
> `review-marker-unused` and `review-marker-malformed` are structurally
> unreachable from the per-file `lint` verb -- it passes no scanned-file set. On
> a per-file run you will see nothing and would file a false bug.

That file carries **11 markers in the colon form** you wrote:

```pascal
Sleep(100); // dl:ok sleep-in-vcl: headless test, no UI
```
at lines **73, 89, 103, 118, 121, 123, 143, 146, 170, 175, 180**.

- [ ] **4.1 The colon form is now ACCEPTED.** Measured on the tests project
      today: **`sleep-in-vcl` = 0** findings in that file. Previously all 11
      fired *and* the markers suppressed nothing, silently.

- [ ] **4.2 The markers now correctly report as REDUNDANT.** Expect exactly
      **11 `review-marker-unused` hints**, one per line above:
      *"dl:ok marker for "sleep-in-vcl" no longer matches any finding on this
      line -- remove it."*

      **This is the designed outcome, not a regression.** The findings vanished
      legitimately (the rule is now scoped to VCL units and that file is
      headless), so "remove it" is finally TRUE advice. You can delete all 11.

- [ ] **4.3 A genuinely malformed marker is still caught.** In a scratch copy,
      change one line to a name that is not a rule id:
      ```pascal
      Sleep(100); // dl:ok because reasons
      ```
      Expect a **`review-marker-malformed`** hint naming `"because reasons"` and
      saying the marker suppresses NOTHING. A misspelling
      (`// dl:ok slepe-in-vcl -- typo`) must behave the same way.

      > **Known, do not file:** that message lists three accepted forms and
      > **omits the colon form it now accepts**. Already filed as
      > `INBOX-malformed-marker-message-omits-the-colon-form.md`.

- [ ] **4.4 A hash-less marker also raises `review-marker-stale`** -- *"carries
      no @hash, so it cannot be checked against the code"*. That is a **different
      rule doing its own job**, expected on every hash-less marker, and not a
      defect. DataCopy's app units show 4 of these today. The `@hash` form in
      `CSVRoutines.pas:71` and `DPPRoutines.pas:409` is what a fully-formed
      marker looks like.

- [ ] **4.5 Positive control -- do not skip.** Delete one marker entirely and
      confirm nothing new fires on that line (the rule really is out of scope
      there). Without this, 4.1 passes with the rule simply switched off.

---

## 5. Autofix from the panel

- [ ] **5.1** Open *View > Tool Windows > drag-lint*. Tabs read
      **Structure | Search (no grep) | Blast Radius**.
- [ ] **5.2** DataCopy's `overwrite-before-read` findings (7 today, incl.
      `uMahrRoutines.pas`) are a good target. Right-click one -> **Fix it**; the
      buffer is rewritten and reloaded.
- [ ] **5.3** From the Diagnostics **root** node, **Fix all in unit** and **Fix
      all in project** are enabled; on a leaf they are disabled (correct).
- [ ] **5.4 Allow this message** on a finding writes a properly formatted
      `dl:ok`. Cross-check it does NOT produce the malformed hint from 4.3 --
      and note it should include an `@hash`, or 4.4 will fire on it.

---

## 6. A directory walk stays inside the project -- DataCopy has a perfect case

`C:\Projects\DataCopy\BACKUP OLD PROJECTS\` holds six `.dproj` files
(`CMM2CPY`, `CMMACOPY`, `CMMDCPY`, `CopyCSVWithTag`, `DPP2CSV`, `ZeissConvert`)
that `DataCopy.dproj` does **not** compile. That is exactly what this step needs.

**What changed:** the walk now scopes **before it parses** rather than parsing
everything and discarding the findings afterwards.

- [ ] **6.1** Point a lint run at `C:\Projects\DataCopy\` as a folder.
- [ ] **6.2** **No finding may name a file under `BACKUP OLD PROJECTS\`.** Read
      the file column, not the summary count.
- [ ] **6.3** The skipped files must still be **NAMED**, capped at 10 with
      `... and N more`. The count now means files **SKIPPED** -- previously it
      counted files that happened to produce a discarded finding, so a different
      number here is correct, not a regression.
- [ ] **6.4 An explicitly named file is NEVER filtered.** Run lint on
      `BACKUP OLD PROJECTS\DPP2CSV.dpr` directly -- it must still be linted. You
      naming a file is a different act from the tool finding one, and the IDE
      depends on this path.

---

## 7. Rules that changed behaviour

- [ ] **7.1 `sleep-in-vcl` is now SCOPED.** It requires the file to contain
      `vcl.` or `{$r *.dfm}`.
      - In `Tests\Test.FolderWatcher.pas` (headless): **silent** -- 0 findings.
      - In a DataCopy **form unit**, a `Sleep(100)` in an event handler must
        still **fire**. Do both; the first alone passes with the rule off.
      - **Known and deliberate, do not report:** a `Sleep` on a background
        thread inside a VCL unit still fires. Excluding it needs to know the
        class descends from `TThread`, which a tree-sitter query cannot see.

- [ ] **7.2 `hardcoded-absolute-path` is rebuilt, and DataCopy is why.** It used
      to be "any literal starting with a drive letter", which gave **73 findings
      on DataCopy, 55% of your test report**, all of them literals that open
      nothing -- including an `IniFile.ReadString` DEFAULT that advised you to do
      exactly what the line already did.

      **Measured today: `hardcoded-absolute-path` = 0 on DataCopy.** To check it
      still works, paste this into a scratch unit:

      ```pascal
      procedure ProbeA;                                   // MUST fire, warning
      begin
        TFile.WriteAllText('C:\Temp\probe.txt', 'x');
      end;

      procedure ProbeB;                                   // MUST be SILENT
      var
        S: string;
      begin
        S := 'C:\Temp\never-opened.txt';                  // nothing opens it
        Writeln(S);
      end;

      procedure ProbeC;                                   // MUST be SILENT
      var
        SL: TStringList;
      begin
        SL := TStringList.Create;
        SL.LoadFromFile('subdir\data.csv');               // relative: allowed
        SL.Free;
      end;

      procedure ProbeD;                                   // MUST fire, warning
      var
        Dir: string;
      begin
        Dir := GetEnvironmentVariable('MYROOT');
        if Dir = '' then Dir := 'C:\Program Files\Fallback';
        if TDirectory.Exists(Dir) then Exit;
      end;
      ```

      - **ProbeA and ProbeD report at `[warning]`** with the wording *"COMPLETE
        hardcoded path reaches ..."*. ProbeD is the env-with-hardcoded-fallback
        idiom -- it fires because the default is a possible outcome.
      - **ProbeB and ProbeC are silent.** B reaches no filesystem sink; C is a
        relative path, which is allowed.

- [ ] **7.3 `unused-unit-in-uses` reports at `info`** and names three blind
      spots. DataCopy has **46 of these -- the single largest group in your
      report. DO NOT bulk-act on them:** measured wrong about 13% of the time,
      in the direction of breaking the build. Spot-check three by hand.

- [ ] **7.4** `uses-global-census` (22 findings) states a **ratio**;
      `duplicate-global-decl` caps site lists at six with "and N more".

---

## 8. Menu smoke -- does anything fail to open?

- [ ] Full Compile Sweep | Compile && Diagnose | Compile Buffer (unsaved)
- [ ] Circular Uses Report -- **must state its outcome, including "no cycles"**
- [ ] Show Structure | Symbol Search | drag-lint Graph opens and renders
- [ ] `Ctrl+Alt+U` Quick-Fix on a deliberately undeclared identifier

---

## 9. Index-backed navigation (both DataCopy indexes are `current`)

- [ ] Hover | Go to Definition | **Show Completion -- type a PREFIX, not just
      the dot at end of line** | Signature Help | Type at Cursor
- [ ] *Find Usages* on `TCSVTransfer.TransferFile` (`CSVRoutines.pas:71`) and on
      `TDPPTransfer.TransferFile` (`DPPRoutines.pas:409`)
- [ ] *Rename Symbol* -- **review the preview and CANCEL** unless on a scratch copy
- [ ] Panel Search: Symbol / Text / Usages navigate on double-click; an
      unindexed local gives ONE clean "No matches" -- **no raw JSON, no `== DEBUG ==`**
- [ ] A form-unit result opens the **`.pas`**, not the designer
- [ ] Hover in an **unindexed** file must NOT answer from the LIBRARY index

> Every index reads `current`, so "it was probably stale" is no longer an
> available explanation. A thin, wrong, or consistently line-offset answer here
> is a **real defect** -- report it.

---

## 10. DUnitX attributes -- `Tests\` is the place

- [ ] Put the caret on a `[Test]`-attributed method in `Tests\Test.FolderWatcher.pas`
      and run *Find Usages*.
- [ ] RTTI attributes are indexed now. Previously `[Test]` produced nothing and
      `[TestCase('a','1,2')]` produced a **fabricated call edge** -- the index
      believed the method called a routine named `TestCase`. That edge must be gone.
- [ ] `method-pascalcase` must **not** fire on `[Test]`/`[TestCase]`/`[Setup]`
      methods, and **must** still fire on an ordinary badly-named helper.

---

## Not exercised on purpose

**Auto-Document Whole Project** writes to source files -- commit DataCopy first.
**Rebuild Index for This Project** is destructive and would throw away a
verified-current index. Run either only deliberately.

---

## If a build fails at staging: it is VS Code, not the IDE

Measured on this machine today. A `drag-lint.exe lsp --stdio` whose parent is
`Code.exe` was holding the deployed engine and failed staging twice, respawning
within seconds of being killed.

```powershell
Get-CimInstance Win32_Process -Filter "Name='drag-lint.exe'" |
  Select-Object ProcessId, ExecutablePath
```

**You do not need to close VS Code.** In the VS Code window that has DataCopy
open, run **Command Palette > `Developer: Reload Window`**. That restarts only
that window's extension host. Extension v1.4.0 then makes its own private engine
copy under
`...\Code\User\globalStorage\drag-lint.drag-lint\engine\` and runs THAT, so it
stops holding the deployed file permanently.

---

## Reporting a failure

1. The **step number**.
2. What you did and what you saw, **separately** -- not a diagnosis.
3. Tail of *About > Open Plugin Log*.
4. The **Versions** group.
5. For anything index-shaped: *Show Resolved DBs (debug)* and the verdict from 1.4.

A step you could not run is **not** a pass. Mark it skipped and say why.

## Sign-off

- [ ] Part 0 complete
- [ ] Sections 1-8 complete
- [ ] Sections 9-10 complete
- [ ] **Verdict: release / hold**
