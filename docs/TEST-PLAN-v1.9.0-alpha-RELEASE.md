# drag-lint v1.9.0-alpha -- IDE verification pass

**Engine `1.9.0-alpha`, plugin `v1.1.0-alpha`, extractor `1.10.0-alpha`,
resolver `1.1.0-alpha`, schema `21`.**

**Purpose.** Confirm in a live RAD Studio 13 Florence (Studio 37.0) that this
engine behaves in the IDE the way 433 headless tests say it does. This is the
last gate before the release is tagged.

**Refreshed 2026-09-01 (session 57) to cover what session 56 shipped.** What
moved: **the [NOW]/[AFTER] split**, the path table, **0.3**, **1.5**, **all of
section 4**, **6**, **11** (two rules added), the Part Two gate and the sign-off.

**Three of those would have produced a FALSE BUG REPORT if run as previously
written** -- 0.3 (the `serverPath` pin is now deliberately unset), 1.5 (it told
you to report `current` as the defect), and 4.1 (its "deliberately malformed"
example is now a valid marker). **Do not work from an older printed copy.**

Every behavioural claim below was re-measured against the deployed
`1.9.0-alpha` binary while writing this refresh, not copied forward.

---

## >>> READ THIS FIRST: THE REINDEX IS DONE. BOTH HALVES ARE UNBLOCKED.

The earlier version of this plan split into **[NOW]** and **[AFTER]** because
`DRAGLINT_EXTRACTOR_VERSION` had moved to **1.10.0-alpha** and every index on
this machine was one re-parse behind, with the reindex scheduled for the evening.

**That reindex has completed:** 33/33 sections, 17,825 files, 5.8 h, and **all 32
databases verified `current`** (`indexer_stale=False`, `resolver_stale=False`).
Re-verified at the top of this refresh; the three indexes this plan touches --
`DataCopy`, `library-Win64` and ORM3 `Micronite2027` -- each read `current`.

**So the gate on Part Two is already satisfied and the whole plan runs in one
pass.** The `[NOW]` / `[AFTER]` tags are retained below only as a reading aid for
what each half exercises; neither is blocked any more.

> **The gate has INVERTED, and this is the important consequence.** Under the old
> plan a stale index was expected, so a thin or wrong index answer meant "stale
> data, not a defect". That excuse is gone. **Every index is current, so an index
> answer that is thin, wrong, or off by a consistent line offset is now a REAL
> DEFECT and should be reported.**

15 files failed to parse in that reindex, all third-party and all expected: 6
`.inc` fragments, fibplus, Raize/Indy, OmniThreadLibrary, Spring.Comparers,
FireDAC.Phys.MongoDBCli, and 2 `.dfm`. Do not report these.

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
| VS Code engine refresh | the extension command **`drag-lint: Update Engine Copy Now`** (the old `tools\refresh-vscode-engine.ps1` targets the retired copy -- see 0.3) |
| VS Code managed engine | `C:\Users\alexanderl\AppData\Roaming\Code\User\globalStorage\drag-lint.drag-lint\engine\drag-lint.exe` |
| ~~VS Code private engine~~ | ~~`C:\Users\alexanderl\AppData\Local\drag-lint-vscode-engine\`~~ -- **RETIRED, still on disk, an orphan** |
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

- [ ] **0.3 VS Code no longer holds the engine -- AND THE PIN IS NOW GONE.**

      **CHANGED 2026-09-01.** This step previously told you `dragLint.serverPath`
      was *set* to a hand-made copy at
      `C:\Users\alexanderl\AppData\Local\drag-lint-vscode-engine\`, and to verify
      the LSP pointed there. **That is now backwards and would fail the step on
      correct behaviour.**

      Extension **v1.4.0 is installed** and manages its own private engine copy,
      refreshing it on activation. An explicit `serverPath` **disables** that
      managed copy and would freeze VS Code on one engine build forever, so the
      pin was deliberately **removed**.

      - [ ] `dragLint.serverPath` is **unset** in VS Code settings. (Set = the
            defect.)
      - [ ] After VS Code has opened a Pascal file at least once, verify:
      ```powershell
      Get-CimInstance Win32_Process -Filter "Name='drag-lint.exe'" |
        Select-Object ProcessId, ExecutablePath
      ```
      Any `lsp --stdio` whose parent is `Code` must resolve under the extension's
      global storage --
      `C:\Users\alexanderl\AppData\Roaming\Code\User\globalStorage\drag-lint.drag-lint\engine\drag-lint.exe`
      -- and **not** `C:\Projects\Delphi-RAG-lint\third_party\dll-win64`.

      > That folder is created on first activation, so its absence before you have
      > opened a Pascal file is normal, not a failure.

      > **`C:\Users\alexanderl\AppData\Local\drag-lint-vscode-engine\` still
      > exists and is now an ORPHAN** -- the retired hand-made copy, left on disk.
      > It is no longer refreshed by anything. If you ever see the LSP running
      > from there, `serverPath` has been re-pinned. An engine that merely EXISTS
      > answers confidently while being months behind; that has bitten this
      > project twice.

      > To force the managed copy to refresh after an engine build, use the
      > extension's own **"Update Engine Copy Now"** command. The old
      > `tools\refresh-vscode-engine.ps1 -Kill` targeted the orphan above and is
      > no longer the right instrument.

- [ ] **0.4 Open ORM3** `CLIENT\Micronite2027.dproj` and a unit with real code.

---

# PART ONE -- [NOW]: plumbing, rendering, menus, process behaviour

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

      **What you should see -- THE REINDEX HAS RUN, so this expectation is the
      OPPOSITE of what this step said before.** Re-measured 2026-09-01, so this
      is a recorded expectation, not a guess:

      | index | verdict |
      |---|---|
      | `C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite` | `current` |
      | `C:\Projects\.drag-lint\library-Win64.sqlite` | `current` |
      | `C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite` | `current` |

      > **DO NOT USE THE OLDER VERSION OF THIS STEP.** It expected
      > `library-Win64` to read `reparse-owed` and told you that `current` was
      > "the defect worth reporting". Before the reindex that was right; now it
      > would have you file a **false bug report** against correct behaviour. All
      > 32 databases were verified `current` after the evening pass.

      - [ ] **Record the verdict for each index.**
      - [ ] **Every row must read `current`.** Anything still `reparse-owed`
            means a section failed; anything `resolve-owed` means the resolve
            half did not run. Either one is now a real finding -- and it also
            invalidates Part Two, so stop and say so rather than testing on.

      > The verdicts distinguish **`reparse-owed`** (hours) from
      > **`resolve-owed`** (minutes) on purpose. Treating the cheap one as the
      > expensive one is how a re-resolve gets deferred indefinitely.

      > The original worry behind this step still stands and is worth restating:
      > a stamp claiming freshness that the pass never earned is **self-concealing
      > once written**. That is why the check asks the engine rather than trusting
      > the About window.

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

## 4. `dl:ok` markers -- REWRITTEN 2026-09-01. The old example is now VALID.

> **READ BEFORE RUNNING.** The previous version of this step used
> `// dl:ok sleep-in-vcl: because reasons` as its **deliberately malformed**
> marker. **The colon form is now ACCEPTED** (it is literally test case 10 in
> `ReviewMarkerTests.dpr`), so that line now suppresses correctly and emits no
> malformed hint. Running the old step would have you report a false defect.

**Run all of section 4 through *Code Quality > Run Lint All*.** This is
load-bearing, not a preference: `review-marker-malformed` and
`review-marker-unused` are **structurally unreachable from the per-file `lint`
verb**, which passes no scanned-file set. Per-file, you would see nothing and
file a false bug. (Filed as `INBOX-lint-verb-cannot-report-unused-markers.md`.)

- [ ] **4.1 The colon form is accepted.** In a scratch unit, put a real finding
      on a line and mark it with the colon form, comma in the prose included:
      ```pascal
      Sleep(100); // dl:ok sleep-in-vcl: headless test, no UI
      ```
      Expect the finding **suppressed**, and **no** `review-marker-malformed`.
      The comma is part of the test -- it used to split the tail into two bogus
      rule ids.

      > **EXPECTED, NOT A DEFECT:** that line also raises a separate
      > **`review-marker-stale`** hint -- *"carries no @hash, so it cannot be
      > checked against the code -- re-mark it as `sleep-in-vcl@f48a`"*. That is
      > a different rule doing its own job, and it appears on **every** hash-less
      > marker including the correct ones below. Add the `@hash` it suggests and
      > it goes away. Measured on this build 2026-09-01.

      > This is the fix's whole point. A real project had 11 such markers, 11
      > findings still firing, and **no warning of any kind**: the marker
      > suppressed nothing while the source read as reviewed. A marker that fails
      > loudly is a nuisance; one that fails silently is a lie the file tells
      > every future reader.

- [ ] **4.2 The dash form still works.**
      `// dl:ok sleep-in-vcl -- headless test` suppresses, as before.

- [ ] **4.3 Whichever separator comes FIRST wins.** Both of these are one valid
      marker whose reason keeps the other separator as ordinary prose:
      ```pascal
      // dl:ok bare-except -- see note: it is rethrown
      // dl:ok bare-except: rethrown -- by the caller
      ```

- [ ] **4.4 A genuinely malformed marker is still caught.** The check is now
      "does this name a **real rule id**", so use a name that is not one:
      ```pascal
      Sleep(100); // dl:ok because reasons
      ```
      Expect **two** things on that line: the original finding **still
      reported**, and a **`review-marker-malformed`** hint naming the bogus id,
      saying the marker suppresses NOTHING, and listing the accepted forms. A
      simple **misspelling** (`// dl:ok slepe-in-vcl -- typo`) must behave the
      same way -- that is the reason this was implemented as "unknown rule id"
      rather than as "unknown separator".

      Measured on this build 2026-09-01, both lines report:
      ```
      review-marker-malformed: dl:ok names "because reasons", which is not a
      rule id -- this marker suppresses NOTHING. ...
      review-marker-malformed: dl:ok names "slepe-in-vcl", which is not a
      rule id -- this marker suppresses NOTHING. ...
      ```

      > **KNOWN COSMETIC GAP, do not file:** the message lists
      > `dl:ok <rule-id>`, `dl:ok <rule-id>@<hash>` and
      > `dl:ok <rule-id> -- <reason>` but **omits the colon form it now
      > accepts**. The advice is correct, merely incomplete.

- [ ] **4.5 NEW (B3): a marker is honoured across the statement's whole SPAN.**
      A trailing `// dl:ok` can only be written where a statement **ends**, but a
      rule reports where it **begins**. On a wrapped multi-line statement, put
      the marker on the LAST line:
      ```pascal
      S := 'a very long string' +
           SomethingElse +
           TrailingBit;   // dl:ok <the-rule-id-that-fired> -- reviewed
      ```
      Expect **one** outcome, not two: the finding suppressed, and **no**
      `review-marker-unused` telling you to delete a legitimate review record.
      Before this fix a single reviewed site produced two messages, the second
      advising deletion of the very record that was doing the work.

- [ ] **4.6 Positive control -- do not skip.** An **unmarked** finding of the
      same rule in the same file must **still fire**. Without this, every
      assertion above passes with the rule simply switched off.

## 5. Autofix from the panel

- [ ] **5.1** Open the dockable panel (*View > Tool Windows > drag-lint*). Tabs
      read **Structure | Search (no grep) | Blast Radius**.
- [ ] **5.2** Right-click a fixable finding -> **Fix it**. The buffer is
      rewritten and reloaded.
- [ ] **5.3** From the Diagnostics **root** node: **Fix all in unit** and **Fix
      all in project** are enabled there and disabled on a leaf (that is correct).
- [ ] **5.4** **Allow this message** on a finding writes a properly formatted
      `dl:ok` -- cross-check it does NOT produce the malformed hint from 4.2.

## 6. A directory walk stays inside the project -- UPDATED (B8)

**What changed:** the walk now scopes **before it parses**, not after. It used to
glob every `*.pas`/`*.dpr`/`*.dpk`, parse them all, and then discard the findings
of files no project compiles -- on ORM3 CLIENT that is **84 of 284 walked files**,
30% of the parse budget spent on output thrown away a moment later.

**The observable behaviour you are checking is the same; the reported NUMBER is
not.** Because a file that is never parsed produces no finding, the skipped names
are now carried out of the walk and merged into the report explicitly.

- [ ] **6.1** Point a lint run at a folder containing units the project does not
      compile (ORM3 CLIENT qualifies -- it holds `- Copy.pas` files).
- [ ] **6.2** **No finding may name a file the project does not compile.** Read
      the file column, not the summary count.
- [ ] **6.3 The skipped files are still NAMED, and the count now means SKIPPED.**
      Expect the skipped names listed, **capped at 10 followed by
      `... and N more`**. The count is files **skipped** -- previously it was
      files that happened to produce a discarded finding, so **a different number
      here is correct, not a regression.**
- [ ] **6.4 An explicitly named file is NEVER filtered.** `lint <file>` on a file
      no project compiles must still lint it. The user naming a file is a
      different act from the tool finding one, and the IDE depends on this path
      through `--stand-in-for`. This is the direction most likely to break
      silently.
- [ ] **6.5** On a **scratch copy**, repeat with `--fix --apply`, then check by
      timestamp/hash which files changed.

> Verify what was TOUCHED, not whether a skip message appeared. The first version
> of this filter was a complete no-op that still printed plausibly. "Named, never
> silent" is the property that makes a scope filter distinguishable from a
> genuinely clean codebase.

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

# PART TWO -- [AFTER]: THE GATE IS OPEN, run these too

**Gate: SATISFIED.** The `index --all` pass completed (33/33 sections, 17,825
files) and all 32 databases read `current`. Confirm with step 1.5 and carry on --
there is nothing left to wait for.

**And the meaning of a failure here has inverted.** These steps read the index.
Under the old plan a thin or wrong answer was presumed to be stale data; the
indexes are now current, so **a thin or wrong answer here is a real defect.**

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

**Rule counts for this build, measured 2026-09-01:** **179 total = 126 built-in +
53 external `.scm`**. `hardcoded-absolute-path` moved from external to built-in in
this build, which is what moved the split from 125/54.

- [ ] **11.0 `sleep-in-vcl` is now SCOPED (new).** It used to match any `Sleep(`
      call anywhere -- the word VCL appeared only in its message. It fired 11
      times in one headless DUnitX unit of DataCopy with no message loop and no
      VCL unit in its uses clause, and **those findings were never true**.

      It now requires the file to contain `vcl.` or `{$r *.dfm}` (the second so a
      legacy form unit saying `uses Forms` rather than `Vcl.Forms` stays in
      scope).

      - [ ] In a **VCL form unit**, a `Sleep(100)` in an event handler **fires**.
      - [ ] In a **headless unit** naming no VCL unit, the same line is
            **silent**.
      - [ ] Known and deliberate, **do not report it**: a `Sleep` on a background
            thread inside a VCL unit **still fires**. Suppressing it needs to know
            the enclosing class descends from `TThread`, which is ancestry a
            tree-sitter query cannot see. This is stated in the `.scm` rather than
            pretended.


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


- [ ] **11.5 `hardcoded-absolute-path` is now SINK-ANCHORED (B7 stage 1, new).**
      It was one predicate -- any string literal starting with a drive letter,
      anywhere, with no notion of what the program did with it. **73 findings on
      DataCopy, 55% of that report, all literals that open nothing**, including
      an `IniFile.ReadString` DEFAULT that advised the author to do exactly what
      the line already did. It now anchors on a filesystem sink (`AssignFile`,
      `TFile.*`, `TDirectory.*`, `LoadFromFile`/`SaveToFile`, `FileExists`,
      `CopyFile`, ...) and walks back up to 4 steps.

      - [ ] A literal reaching a real sink -- `TFile.ReadAllText('C:\in\x.txt')`
            -- **fires**.
      - [ ] A path-shaped literal reaching **no** sink -- a `Pos` needle, a
            domain helper's argument, an INI default -- is **silent**.
      - [ ] A UNC literal at a sink -- `'\\server\share\x'` -- **fires**. This
            was invisible before, being drive-letter anchored.
      - [ ] Measured expectation on DataCopy: **73 -> 0** for this rule, and the
            whole project report **259 -> 123**.

      > **THREE OWNER DECISIONS ARE RULED BUT NOT YET IMPLEMENTED. If you see
      > these, they are KNOWN -- do not file them:**
      >
      > 1. A hardcoded **relative** portion under a computed base -- e.g.
      >    `TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'rules\x.txt')` --
      >    **still fires today and should not.** Only an absolute root (drive
      >    letter or UNC) is to be flagged. Being fixed next.
      > 2. `src\cli\DRagLint.CLI.pas:16844` is a **genuine** hardcoded path that
      >    is **NOT flagged**: the env-var-with-hardcoded-fallback idiom assigns
      >    the local twice, and the walk currently refuses to reason about a name
      >    assigned more than once. Being relaxed next.
      > 3. A path literal reaching no sink will become **`info`** rather than
      >    silent, so a missing sink can no longer make a whole category
      >    invisible. Not yet in this build.
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
**5.8 hours** of completed reindex -- and would invalidate all of Part Two with
it. Run either only deliberately.

---

## Reporting a failure

1. The **step number**.
2. What you did and what you saw, **separately** -- not a diagnosis.
3. Tail of *About > Open Plugin Log* (it records what was actually invoked).
4. The **Versions** group, so the build under test is unambiguous.
5. For anything index-shaped: *Show Resolved DBs (debug)*, and **the verdict
   step 1.5 recorded for that index**. Every index reads `current` in this pass,
   so "it was probably stale" is no longer an available explanation -- if it is
   not `current`, that is itself the finding.

A step that could not be run is **not** a pass. Mark it skipped and say why.

## Sign-off

- [ ] Part 0 complete
- [ ] **PART ONE [NOW]** complete
- [x] Reindex finished -- 2026-08-31 evening, 33/33 sections, all 32 DBs `current`
- [ ] **PART TWO [AFTER]** complete
- [ ] **Verdict: release / hold**
