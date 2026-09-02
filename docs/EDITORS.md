# drag-lint in VS Code and Zed

drag-lint ships a stdio language server (`drag-lint lsp`) that any LSP-capable
editor can talk to. It answers **hover, go-to-definition, find-references,
workspace symbols, completion and signature help** from the index -- no compiler,
no project open, and it works across every project in your manifest at once.

Verified capability set, captured from a live `initialize` handshake:

```
completionProvider, definitionProvider, hoverProvider,
referencesProvider, signatureHelpProvider, workspaceSymbolProvider
```

> **Worth knowing if you also use the Delphi IDE:** Embarcadero's `DelphiLSP`
> implements *neither* `referencesProvider` nor `workspaceSymbolProvider` (nor
> rename). For find-references and workspace symbols, drag-lint is the only
> provider -- these are not duplicated features.

---

## Support matrix

| | Highlighting | Language server | Status |
|---|---|---|---|
| **VS Code** | **TextMate grammar -- shipped, v1.5** | **yes** | **ready -- extension included** |
| **Zed** | tree-sitter (shipped separately) | yes | **needs a small Rust extension -- not built; see below** |
| Neovim / Helix | tree-sitter (shipped separately) | yes | configure `drag-lint lsp` as an LSP command |

**VS Code cannot use tree-sitter for highlighting.** VS Code highlights with
TextMate grammars and does not expose tree-sitter to extensions, so the
tree-sitter grammars do nothing there. This is stated plainly because it is easy
to assume otherwise.

Since **v1.5** the extension therefore ships its own Pascal TextMate grammar,
plus a colour theme generated from your RAD Studio editor scheme -- see
[Syntax colouring](#syntax-colouring----and-matching-the-ide-exactly). Before
v1.5 nothing coloured Pascal in VS Code at all: no third-party extension was
required, because none was installed and none of VS Code's built-ins covers
Pascal.

---

## VS Code

### Install

The extension lives in this repo at `editors/vscode/drag-lint/`. Package it as a
`.vsix` and install that -- do not copy the folder into `.vscode\extensions` by
hand:

```bat
cd editors\vscode\drag-lint
npm install
npm run package
```

That writes `dist\drag-lint-<version>.vsix`. Install it with
*Extensions > ... > Install from VSIX...*, or:

```bat
code --install-extension dist\drag-lint-1.5.0.vsix
```

`node_modules` is not tracked; `npm install` restores exactly what
`package-lock.json` pins. `@vscode/vsce` is a devDependency, so it is not
shipped inside the package (vsce bundles production deps only).

> **The hand-copy recipe this replaces is a trap, and it bit this project.** A
> copied folder is not registered as an installed extension version, so a newer
> copy can sit beside an older one and VS Code keeps loading the old one. The
> repo carried extension v1.4.0 while the machine ran v1.2.2 for weeks -- the
> private-engine fix, which is the entire point of 1.4.0, never reached the
> editor and engine builds kept failing at staging.

### Activation: it does nothing until a Pascal file is open

The extension declares `"activationEvents": ["onLanguage:pascal"]`. Until a
`.pas` file is **open in that window**, it has not run: no language server, and
no private engine copy.

This matters because it makes a correct fix look like a failed one. Reloading
the window is not enough on its own -- **reload, then open a `.pas` file**, and
do it **per window**, because activation is per extension host. On a machine with
two VS Code windows open, doing one and checking
`%APPDATA%\Code\User\globalStorage\drag-lint.drag-lint\engine` still shows
nothing, which reads as "the reload did not help".

### Settings

| setting | default | meaning |
|---|---|---|
| `dragLint.engineSource` | `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe` | The deployed engine the extension **mirrors from** -- the same binary the Delphi IDE loads. VS Code does not run it directly. |
| `dragLint.engineUpdate` | `onActivate` | When the private copy is refreshed: `onActivate` (VS Code start / window reload / first Pascal file), `manual` (only the command), or `off` (run the deployed engine directly). |
| `dragLint.serverPath` | `""` (empty) | Explicit override -- run this exact exe, make no copy. Leave empty to use the managed copy. |
| `dragLint.databases` | `[]` (empty) | Optional explicit `--db` paths. |
| `dragLint.colors.bdsVersion` | `auto` | Which RAD Studio install the colour commands read their editor scheme from, e.g. `37.0`. `auto` picks the newest under `HKCU\Software\Embarcadero\BDS`. See [Syntax colouring](#syntax-colouring----and-matching-the-ide-exactly). |
| `dragLint.trace.server` | `off` | Log the LSP conversation to the *drag-lint* output channel. |

**The defaults are deliberate.**

*VS Code runs a PRIVATE COPY of the engine; the Delphi IDE runs the deployed
one.* This is the one place the two editors are deliberately NOT identical, and
the reason is a Windows fact: a running process holds an execute lock on its own
image. The VS Code language server **is** `drag-lint.exe`, so while VS Code is
open it locks whatever binary it was started from.

Until extension v1.4 that binary was the deployed one, shared with the IDE --
and the result was that an idle VS Code window made
`build\build_draglint_win64.bat` fail:

```
ERROR: failed to stage C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe
```

The compile succeeded; only the deploy failed. Killing the server did not help,
because VS Code respawns it within a second and the build lost the race again.

So the extension now mirrors the engine into its own `globalStorage` folder and
runs that. The consequences are worth stating plainly:

* **the Delphi IDE always has the current engine** -- it is the one that must,
  and nothing about it changed;
* **VS Code can sit several builds behind, on purpose.** The copy is refreshed
  only when the extension activates: VS Code start, window reload, or the first
  Pascal file opened. It is never swapped underneath a live session;
* **engine rebuilds are no longer blocked** by a VS Code window;
* run **drag-lint: Update Engine Copy Now** from the command palette when you
  do want the copy current immediately. It stops the server, re-copies, and
  restarts.

The copy is the exe plus what the language server actually needs beside it:
`drag-lint.json` (the DB manifest -- every path in it is absolute, so a
relocated copy resolves to exactly the same databases), the three tree-sitter
DLLs, and `rules\`. The BPL, `drag_lint_graph.exe` and `ConvRulesEditor.exe`
are not copied; the server never opens them.

*Setting `dragLint.serverPath`* bypasses all of this and runs the exact path you
give, with no copy. If you point it at the deployed binary you get the pre-v1.4
behaviour back -- including the blocked builds.

*The Delphi IDE still locks the deployed engine while it is open.* That is by
design, and it is why the standing rule is to build with the IDE closed. Only
the VS Code half of the problem is solved here.

*Leaving `databases` empty is the recommended setup.* drag-lint then resolves
databases from the `drag-lint.json` sitting beside the exe -- the same manifest
the IDE reads -- so VS Code follows your project layout automatically. Pinning an
explicit list here means adding or renaming a project index silently stops
working in the editor until someone remembers to update this setting.

### Syntax colouring -- and matching the IDE exactly

Extension **v1.5** ships a Pascal TextMate grammar and a colour theme
**generated from your own RAD Studio editor scheme**. Before it, nothing
coloured Pascal in VS Code at all.

#### What you were actually seeing before v1.5

Not "poor highlighting" -- *no* highlighting. Measured:

| source | result |
|---|---|
| our extension | contributed `languages` but **no `grammars`** |
| VS Code's 97 built-in extensions | **none** for Pascal or Delphi; none claiming `.pas` |
| our LSP | no `semanticTokens` |

The `begin`/`end` and bracket colours were VS Code's **bracket-pair
colourization** reading the pairs in `language-configuration.json`. That is a
bracket feature, not highlighting -- which is why keywords, strings, comments
and numbers were all one colour.

#### Two ways to get the IDE's colours

Both read `HKCU\Software\Embarcadero\BDS\<ver>\Editor\Highlight` -- your actual
IDE scheme, all 42 elements -- so "exactly like the IDE" is literal rather than
approximate, and it follows you if you change your scheme. Both go through the
same converter, so they cannot disagree about a colour.

**1. Pascal only, applied instantly** -- command palette:
**drag-lint: Apply RAD Studio Colours (Pascal only)**

Writes `editor.tokenColorCustomizations` into your `settings.json`. Takes effect
immediately with no reload, and touches **only Pascal files** -- every scope the
grammar emits ends in `.pascal`, which is what confines the rules. Your own VS
Code theme keeps everything else. It cannot set the editor background: that is
global in VS Code with no per-language form.

Re-running it replaces the rules it wrote before and leaves any rule of your own
alone (it recognises its own by that `.pascal` suffix), so it will not
accumulate duplicates.

**2. The full IDE look** -- `Ctrl+K Ctrl+T` -> **Delphi IDE (drag-lint)**

A real theme, so it carries the editor background too. It recolours *every*
language, not just Pascal. To rebuild it after changing your IDE scheme, run
**drag-lint: Generate Theme From RAD Studio Colours**; VS Code reads a theme file
once, so it will offer a window reload.

#### For pure IDE fidelity, turn bracket-pair colourization off

It is on by default and paints `begin`/`end` and brackets in rotating colours
that override the theme, which is the one visible way the result still differs
from the IDE:

```json
"editor.bracketPairColorization.enabled": false
```

Leave it on if you like it -- nothing else depends on it.

#### Regenerating the shipped theme from a checkout

```
cd editors\vscode\drag-lint
node scripts\gen-theme.js                 # newest install
node scripts\gen-theme.js --version 37.0  # a specific one
```

The generator is deliberately **not** wired into `npm run package`: packaging
must not depend on a registry that exists only on a developer's machine, or a
build elsewhere would emit a colourless theme rather than failing.

#### The colour format, because getting it wrong is silent

Values are stored as `$00BBGGRR` -- a Delphi `TColor`, so the bytes are **BGR,
not RGB**. `$00FFAA7F` is `#7FAAFF` (light blue), not `#FFAA7F` (salmon). Both
readings produce a plausible dark palette and the **wrong** one looks *more*
conventional (blue keywords, salmon strings -- close to Dark+), so a mistake
here never looks like a mistake. Three further traps live in the same data:
the value name is `Foreground Color New` (the old name reads back **empty**);
`Default Foreground`/`Default Background` are booleans that **override** the
stored colour; and a value may be a VCL colour *name* (`clWhite`, `clRed`)
rather than hex. `tests\vscode\run_pascal_grammar_and_theme.ps1` pins all four.

#### Known limits

A TextMate grammar is a regex cascade with no parser behind it, so it disagrees
with drag-lint's own tree-sitter parse in the corners -- generics versus
comparison (`AreEqual<Integer>` vs `A < B`), nested `{$IFDEF}` regions, `asm`
bodies. That is inherent to the mechanism, not a defect to chase. The version
that cannot drift from the analysis is `textDocument/semanticTokens` fed by the
real parse; VS Code layers semantic tokens **over** a grammar, so it is a
complement to this, not a replacement.

**Do not also install a third-party Pascal extension.** A second extension
declaring `source.pascal` conflicts with this grammar, and some start their own
language server, which double-publishes into the Problems panel.

### The Problems panel

Lint findings and syntax errors appear in VS Code's **Problems** panel, one row
per finding, each tagged with the **source** `drag-lint`. That label is how you
tell whose finding it is, and it is set on every diagnostic the server emits.

**Everything Pascal in that panel is drag-lint's, unless you have installed
another Pascal extension.** RAD Studio's `DelphiLSP.exe` is *not* involved: it is
spawned by `bds.exe` for the IDE's own Code Insight and publishes nothing to VS
Code. Seeing `DelphiLSP.exe` in Task Manager while VS Code is open is therefore
expected and means nothing about the Problems panel.

Diagnostics are published on **didSave**, not per keystroke.

#### Merging with compiler diagnostics is free here -- unlike in RAD Studio

If you also want DelphiLSP's compiler errors in VS Code, install an extension
that runs `DelphiLSP.exe`. Nothing else is needed: **the two sets merge
automatically**, and neither can overwrite the other.

That is worth stating explicitly because the opposite is true in the Delphi IDE,
and the difference is structural:

| | RAD Studio plugin | VS Code |
|---|---|---|
| diagnostic channel | ONE, shared | one `DiagnosticCollection` **per extension** |
| effect of a second publisher | `publishDiagnostics` REPLACES the set for that URI, so whoever publishes last wins | both collections coexist; the panel shows the UNION |
| merging requires | appending into DelphiLSP's own frame -- the `lsp --proxy` work | nothing |

So `lsp --proxy` and the diagnostics-merge design exist to solve a **RAD Studio**
problem. In VS Code they buy nothing: two language servers cannot clobber each
other's diagnostics, because each client owns its own collection and the panel
aggregates them.

### Reading a unit while something else edits it

A common use is keeping VS Code open purely to *read* units -- including ones an
agent or another tool is actively rewriting -- while the IDE is busy or closed.
That works, and the private engine copy is what makes it safe: VS Code never
holds the deployed `drag-lint.exe`, so it cannot block an engine rebuild, and
whatever is editing the source is unaffected by VS Code having the file open.

Two consequences to expect rather than report:

* diagnostics refresh on **save**, so a file being rewritten by another process
  updates its Problems rows when that process saves, not while it types;
* the answers come from the **index**, so a symbol added seconds ago is not
  there until that project is re-indexed -- the Problems rows are still correct
  about the file's own text, since linting parses the file, but hover and
  go-to-definition can lag.

### Checking it works

Set `dragLint.trace.server` to `verbose`, open the *drag-lint* output channel,
and look for the `initialize` response. `serverInfo.version` must match
`drag-lint --version`; if it does not, VS Code is talking to a different binary
than you think.

If the extension cannot find the exe it says so with an error notification
naming the path it tried -- a language client that fails silently just produces
no hovers, which reads as *"the index is empty"* rather than *"the binary is
missing"*.

---

## Zed

Zed can already **highlight** Delphi: the tree-sitter grammars
(`tree-sitter-delphi13`, `tree-sitter-dfm`) ship `queries/highlights.scm` and
`queries/outline.scm`, and the Zed extension scaffold lives in
`tree-sitter-delphi13/editors/zed/`.

**What is missing is the language-server registration, and it cannot be done in
JSON.** Zed has no settings path that points at an arbitrary LSP binary; a custom
server must be registered by an extension compiled to `wasm32-wasip1`. That
requires a Rust toolchain.

**We have not built this**, and the honest reason is that no Rust toolchain is
installed on the machine where drag-lint is developed. The work is small and
fully specified below, so anyone with `rustup` can finish it. Contributions
welcome.

### What has to be written

**1. `extension.toml`** -- add a `[lib]` section to the existing scaffold:

```toml
id = "delphi"
name = "Delphi"
version = "0.1.0"
schema_version = 1

[lib]
kind = "rust"

[grammars.delphi13]
repository = "https://github.com/<org>/tree-sitter-delphi13"
commit = "<pin a commit SHA>"

[grammars.dfm]
repository = "https://github.com/<org>/tree-sitter-dfm"
commit = "<pin a commit SHA>"

[language_servers.drag-lint]
name = "drag-lint"
languages = ["Delphi"]
```

**2. `Cargo.toml`**

```toml
[package]
name = "zed_delphi"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
zed_extension_api = "0.1"
```

**3. `src/lib.rs`** -- the whole extension is one trait method. It must return
the command Zed should spawn:

```rust
use zed_extension_api::{self as zed, Command, LanguageServerId, Result, Worktree};

struct DelphiExtension;

impl zed::Extension for DelphiExtension {
    fn new() -> Self { DelphiExtension }

    fn language_server_command(
        &mut self,
        _id: &LanguageServerId,
        worktree: &Worktree,
    ) -> Result<Command> {
        // Prefer an explicit setting, else fall back to PATH.
        // Pass NO --db: drag-lint resolves databases from the drag-lint.json
        // beside the exe, which keeps Zed following the project layout.
        let path = worktree
            .which("drag-lint")
            .ok_or_else(|| "drag-lint not found on PATH".to_string())?;
        Ok(Command {
            command: path,
            args: vec!["lsp".to_string()],
            env: Default::default(),
        })
    }
}

zed::register_extension!(DelphiExtension);
```

**4. Build and install**

```bash
rustup target add wasm32-wasip1
cargo build --release --target wasm32-wasip1
# then: Zed -> Extensions -> Install Dev Extension -> pick the folder
```

### Notes for whoever builds it

* **`drag-lint lsp` needs no engine changes.** It was driven directly with an
  `initialize` request and answers correctly as a stock stdio LSP server. Nothing
  is blocked on drag-lint itself.
* **Do not pass `--db` unless you must.** Manifest auto-resolution is what makes
  the editor track the project layout; a hardcoded list rots.
* **Validate any `.scm` you touch** with `tree-sitter query`. Exit 0 means the
  query compiles *and* matches real source. It has already caught an impossible
  DFM pattern (`object` exposes `class:`/`name:` fields, not a bare
  `qualified_identifier` child) that would have silently killed DFM highlighting
  outright. Broken queries are invisible in-editor -- highlighting simply stops.
* **32-bit vs 64-bit does not matter.** stdio is bitness-agnostic; the two
  DelphiLSP builds are byte-identical at `initialize`, and drag-lint's win32 and
  win64 exes serve the same protocol.

---

## Any other LSP editor

Point it at `drag-lint lsp` over stdio. Neovim example:

```lua
vim.lsp.start({
  name = 'drag-lint',
  cmd = { 'C:/Projects/Delphi-RAG-lint/third_party/dll-win64/drag-lint.exe', 'lsp' },
  root_dir = vim.fs.dirname(vim.fs.find({'.git'}, { upward = true })[1]),
})
```

The index must exist first -- see `INSTALL.md` step 2. An editor pointed at an
empty or missing database answers every request with nothing, which is
indistinguishable from "no such symbol".
