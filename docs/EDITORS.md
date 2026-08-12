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
| **VS Code** | TextMate grammar (not shipped) | **yes** | **ready -- extension included** |
| **Zed** | tree-sitter (shipped separately) | yes | **needs a small Rust extension -- not built; see below** |
| Neovim / Helix | tree-sitter (shipped separately) | yes | configure `drag-lint lsp` as an LSP command |

**VS Code cannot use tree-sitter for highlighting.** VS Code highlights with
TextMate grammars and does not expose tree-sitter to extensions, so the
tree-sitter grammars do nothing there. VS Code gets the *language server*;
syntax highlighting comes from whatever Pascal TextMate extension you already
use. This is stated plainly because it is easy to assume otherwise.

---

## VS Code

### Install

The extension lives in this repo at `editors/vscode/drag-lint/`.

```bat
cd editors\vscode\drag-lint
npm install --omit=dev
xcopy /E /I . "%USERPROFILE%\.vscode\extensions\drag-lint-1.2.2"
```

Restart VS Code, open any `.pas`, and hover a symbol.

`node_modules` is not tracked; `npm install` restores exactly what
`package-lock.json` pins.

### Settings

| setting | default | meaning |
|---|---|---|
| `dragLint.serverPath` | `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe` | Path to `drag-lint.exe`. |
| `dragLint.databases` | `[]` (empty) | Optional explicit `--db` paths. |
| `dragLint.trace.server` | `off` | Log the LSP conversation to the *drag-lint* output channel. |

**Both defaults are deliberate.**

*The server path points at the same deployed binary the Delphi IDE loads.*
Redeploying the engine therefore updates VS Code with no extension change, and
the editor and the IDE can never disagree about which build answered a query.
Point it elsewhere only if you keep a separate build.

*Leaving `databases` empty is the recommended setup.* drag-lint then resolves
databases from the `drag-lint.json` sitting beside the exe -- the same manifest
the IDE reads -- so VS Code follows your project layout automatically. Pinning an
explicit list here means adding or renaming a project index silently stops
working in the editor until someone remembers to update this setting.

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
