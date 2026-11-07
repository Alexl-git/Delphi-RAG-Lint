# Installed layout v2 (E-INSTALLER-R2 E1-E4) -- design and phase 1

Status: phase 1 built on `lane/146-x5`, **NOT-FOR-MERGE until the owner reviews**. Nothing is
installed, moved or renamed by this branch. **A VM test is owed before the switch can flip**
(section 6).

Sources: CHARTS' approved proposal with the owner's rulings of 2026-10-13
(`docs\superpowers\specs\2026-10-13-installer-layout-v2-proposal.md` in worktree `archify-ir`,
gitignored there, so its rulings are restated below), the backlog row E-INSTALLER-R2, and the
tree at `5794670b`.

## 1. Owner rulings (binding, 2026-10-13)

1. Manifest order: **explicit (`DRAGLINT_MANIFEST` / `--manifest <path>`) > `%APPDATA%\drag-lint\drag-lint.json`
   > beside the exe.**
2. `drag-lint manifest migrate` is one-time and explicit. It RENAMES the exe-side file to
   `drag-lint.json.migrated-<date>`; it never deletes and never runs at startup.
3. Library DBs default to `%LOCALAPPDATA%\drag-lint\library` (needs E6, env-var expansion in `outDir`).
4. Logs ALWAYS go to `%LOCALAPPDATA%\drag-lint\logs`, dev box included.
5. The override lands BEFORE APPDATA-first, and tests must set `DRAGLINT_MANIFEST`: test scripts
   copy the engine beside a fixture manifest, and an APPDATA-first engine would otherwise read
   the real one.

## 2. Where the tree is today

| Item | State at `5794670b` |
|---|---|
| CHARTS P1, P3, C1, C2, E5-side lookups, installer R2 | shipped (`7e9887f0`, `6e5aad92`): plugin logs in `%LOCALAPPDATA%\drag-lint\logs`, Ask-Report `{app}\charts`, report pairs from `%APPDATA%` |
| E1 manifest read | exe dir only: `TManifestIO.Load`, ~25 CLI call sites through one function |
| E2 manifest write | exe dir: `FindManifestCopies` (exe dir + sibling folders), two CLI rewrite sites |
| E3 drag-lint-config | exe dir: `ConfigTargetPath` |
| E4 fatal log | beside the exe (CLI `Run`) |
| E6 env expansion in `outDir` | absent |
| `manifest migrate` | absent (`docs\SMOKE-TEST-1.37.0.html` line 29 lists it as a check; no such verb exists) |
| P2 plugin manifest lookup | exe/BPL dir: `DbResolver.pas` 120, 408, 725; `OptionsFrames.pas` 406, 1124 |
| Installer | starter manifest in `{app}\bin` with users-modify (`drag-lint.iss` 118-119) |

Measured: 37 of 901 `tests\autotest\*.ps1` both copy the engine and name a `drag-lint.json`
(a text match over-counts and can miss; the rulings' 57 was the 2026-10-13 count). That list has
to be re-derived and each script given `DRAGLINT_MANIFEST` before the flip.

## 3. Options

**A. Flip in one branch:** APPDATA-first, migrate, installer and plugin together. Rejected: it
moves every install's manifest in one step, and the 37-plus scripts and the plugin must all be
right the same day. No way back but a rebuild.

**B. Exe side first, APPDATA as fallback** (the proposal's section 3). Overruled by ruling 1.

**C. Phased, switch OFF until the VM test (chosen).** One resolver, wired everywhere the engine
looks, behind `DRAGLINT_LAYOUT=v2`. With the switch off and no explicit manifest every path equals
today's, and the guard's O cases pass on the OLD engine too, which proves it. The flip is a
one-line default change after phases 2-4.

**Switch form.** An environment variable: inherited by spawned children, testable from a script,
and needs no file that might itself live in the wrong place. A manifest key was rejected because
the manifest's location is what the switch decides.

## 4. Design

`TInstalledLayout` in `DRagLint.Index.Manifest.pas` (no new unit: the unit is already in the CLI,
the Config exe, the plugin package and two harnesses, so no project file changes):

* `ResolveManifest(explicit, appDataRoot, engineDir, layoutV2)` is the order itself, inputs passed in.
* `ManifestLocation(engineDir)` feeds it from the environment; the single question every reader
  and writer asks.
* `LogDir(engineDir)`, `LibraryDir`, `Enabled`, `OriginName`.

Rules:

* **A missing explicit file is the answer.** It never falls through: fail-open here would load the
  real manifest, the exact accident ruling 5 prevents. `Load` records it as a load error, so a
  read verb warns and carries on with nothing and a write verb refuses.
* **The explicit override works with the switch OFF.** Silently ignoring an explicit request would
  fail open the same way; and ruling 5 needs it to land first.
* **`--manifest` sets the environment variable** at the top of `Run`, so spawned index children
  inherit it. A flag read only by the parent would send each child to the real manifest.
* **APPDATA answers only when its file exists.** Otherwise the exe side answers, so an upgraded
  install that has not migrated still works.
* **Relative paths resolve against the folder the file was FOUND in.**
* **`--config` is unchanged**: it names one file for one verb and bypasses this lookup.
* **A local `.drag-lint.json` still merges** over whichever global answered. The rulings speak of
  the global file only.

## 5. Phases

| Phase | Content | Gate |
|---|---|---|
| **1 (this branch)** | Resolver; E1, E2 (existing files only), E3 (target path only), E4; explicit env + flag; read-only `manifest where`; guard on scratch folders | owner review |
| 2 | `manifest migrate` (rename only, `--dry-run` first); E6 + library default; writers create the APPDATA file when none exists; give the test scripts `DRAGLINT_MANIFEST` | guard + targeted scripts |
| 3 | Plugin P2 and the "no log folder" readers, in one plugin branch (double BPL rebuild) | owner IDE test |
| 4 | Installer: starter manifest to `{userappdata}\drag-lint`, `outDir` = `%LOCALAPPDATA%\drag-lint\library`, `[Run] manifest migrate` on upgrade from v1, checklist update | **VM test** |
| 5 | Flip: v2 default, `DRAGLINT_LAYOUT=v1` the way back; run migrate on the dev box | owner go + full battery + re-run of VM test |

**Do not set `DRAGLINT_LAYOUT=v2` on a box with the IDE plugin before phase 3:** the plugin still
reads the manifest beside the BPL or exe, so plugin and engine would disagree on the DB list.

## 6. VM test owed (phase 4; cannot be proved here)

On a clean Windows VM without Delphi, using `installer\VM-TEST-CHECKLIST.md` extended with:
a per-user and an all-users install where `{app}` is not writable; a fresh install (manifest in
`%APPDATA%`, no file in `{app}\bin`); an upgrade from a flat v1 install with projects registered
(the old file becomes `drag-lint.json.migrated-<date>`, its sections answer from `%APPDATA%`, DBs
stay where they were); fatal log in `%LOCALAPPDATA%\drag-lint\logs`; a second Windows user on an
all-users install (starts with no manifest, exit 0); uninstall keeps both data folders.

## 7. Assumptions the owner can reverse

1. Switch name and value: `DRAGLINT_LAYOUT=v2`; any other value is OFF.
2. `DRAGLINT_MANIFEST` and `--manifest` are honoured with the switch OFF (section 4). Reversing it
   means gating `ResolveManifest`'s first rung, and re-opens the silent fall-through.
3. Phase 1 writes only to a file that exists: with v2 on and no manifest, `register-project`
   answers "no drag-lint.json found" and creates nothing. E2's "create in `%APPDATA%`" is phase 2.
4. No probe for "is the exe dir writable", the proposal's E2 condition: under ruling 1 the order
   decides, so nothing depends on a probe.
5. `--manifest` on `ask`, `protocol`, `mcp-config`, `init` and `syntax-count` is refused: those parse
   their own flags and read no project manifest through this path.
6. The entry is `status: internal` until the flip, so the switch is not advertised.

## 8. Risks

* **Hot path:** `Load` runs on nearly every verb. With the switch off it adds two environment reads
  and one `TFile.Exists` it already did.
* **Plugin package:** compiles the same unit but calls neither `Load` nor the resolver; its own
  lookups stay on the BPL or exe side until phase 3, which is why section 5 warns.
* **Multi-user:** roaming `%APPDATA%` holds absolute project paths; a roamed profile on another
  machine would list paths that do not exist there. Not new in kind, and the rulings accept it.
