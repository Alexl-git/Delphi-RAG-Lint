# v0.21 OTAPI IDE Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development

**Goal:** Ship `dclDragLintWizard.bpl` design-time package that wraps v0.20 LSP into RAD Studio 13 editor surfaces.

**Architecture:** Persistent drag-lint.exe subprocess managed by a wizard; IDE features wired through OTAPI.

**Spec:** [docs/superpowers/specs/2026-05-28-v021-otapi-plugin-design.md](../specs/2026-05-28-v021-otapi-plugin-design.md)

---

## Task 1: Package + Wizard skeleton

**Files:**
- Create: `src/delphi-plugin/dclDragLintWizard.dpk`
- Create: `src/delphi-plugin/dclDragLintWizard.dproj`
- Create: `src/delphi-plugin/DragLint.Plugin.Wizard.pas`
- Create: `src/delphi-plugin/README.md`

### Wizard.pas content

```pascal
unit DragLint.Plugin.Wizard;

interface

uses
  System.SysUtils, System.Classes, ToolsAPI;

type
  TDragLintWizard = class(TInterfacedObject, IOTAWizard)
  public
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
  end;

procedure Register;

implementation

uses
  Vcl.Dialogs;

function TDragLintWizard.GetIDString: string;
begin
  Result := 'drag-lint.wizard.v021';
end;

function TDragLintWizard.GetName: string;
begin
  Result := 'drag-lint';
end;

function TDragLintWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TDragLintWizard.Execute;
begin
  ShowMessage('drag-lint wizard v0.21.0-alpha. Hover/completion/signatureHelp/diagnostics bindings will register on IDE startup.');
end;

procedure Register;
begin
  RegisterPackageWizard(TDragLintWizard.Create);
end;

end.
```

### .dpk content

```pascal
package dclDragLintWizard;

{$R *.res}
{$IFDEF IMPLICITBUILDING This IFDEF should not be used by users}
{$ALIGN 8}
{$ASSERTIONS ON}
{$BOOLEVAL OFF}
{$DEBUGINFO OFF}
{$EXTENDEDSYNTAX ON}
{$IMPORTEDDATA ON}
{$IOCHECKS ON}
{$LOCALSYMBOLS OFF}
{$LONGSTRINGS ON}
{$OPENSTRINGS ON}
{$OPTIMIZATION ON}
{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}
{$REFERENCEINFO OFF}
{$SAFEDIVIDE OFF}
{$STACKFRAMES OFF}
{$TYPEDADDRESS OFF}
{$VARSTRINGCHECKS ON}
{$WRITEABLECONST OFF}
{$MINENUMSIZE 1}
{$IMAGEBASE $400000}
{$DEFINE DEBUG}
{$ENDIF IMPLICITBUILDING}
{$DESIGNONLY}
{$IMPLICITBUILD ON}

requires
  rtl,
  vcl,
  designide;

contains
  DragLint.Plugin.Wizard in 'DragLint.Plugin.Wizard.pas';

end.
```

### .dproj — minimal Delphi 13 package descriptor

Use existing project .dproj as a template (drag-lint.dproj) but change:
- `<ProjectType>Package</ProjectType>` (vs Application)
- `<DCC_Define>DESIGNONLY;DEBUG;$(DCC_Define)</DCC_Define>`
- `<DCC_DependencyCheckOutputName>$(BDS)\bin64\dclDragLintWizard.bpl</DCC_DependencyCheckOutputName>`
- Add `designide.dcp` to required packages
- Configurations Win64-only

### README.md content

Install steps:
1. Build via `msbuild dclDragLintWizard.dproj /p:Platform=Win64 /p:Config=Debug`.
2. In RAD Studio, **Component → Install Packages...**, click Add, browse to `<RAD>/bin64/dclDragLintWizard.bpl`.
3. Verify under Component → Configure Components that "drag-lint" appears.
4. Restart IDE; on first start a wizard message-box should appear.

Verification:

1. Build via msbuild.
2. Run from `<repo>/src/delphi-plugin`:
   ```
   cmd.exe /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" && msbuild dclDragLintWizard.dproj /p:Platform=Win64 /p:Config=Debug /v:minimal"
   ```
3. Expect `dclDragLintWizard.bpl` produced in `<RAD>/bin64/`.

Commit: `feat(v0.21): wizard package skeleton (Register + IOTAWizard)`.

---

## Task 2: TDragLintLspClient

**Files:**
- Create: `src/delphi-plugin/DragLint.Plugin.LspClient.pas`
- New: `tests/fixtures/T27_lsp_client.dpr`

LSP client wrapping a CreateProcess subprocess with redirected stdin/stdout
pipes. Supports:
- `Start(const AExePath: string)` — spawn drag-lint.exe lsp
- `Initialize: Boolean` — handshake
- `Request(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Integer = 5000): TJSONValue`
- `Notify(const AMethod: string; AParams: TJSONValue)`
- `Stop` — clean shutdown
- `OnNotification: TProc<string, TJSONValue>` — async server notifications

Internals:
- `TThread` descendant reading framed JSON from stdout
- `TDictionary<Integer, TEvent>` for pending requests
- `TDictionary<Integer, TJSONValue>` for results
- Synchronous Lock on writes

T27_lsp_client.dpr is a console test program:
```pascal
program T27_lsp_client;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.JSON,
  DragLint.Plugin.LspClient;
var
  Client: TDragLintLspClient;
  Resp: TJSONValue;
begin
  Client := TDragLintLspClient.Create;
  try
    if not Client.Start(ExtractFilePath(ParamStr(0)) + '..\..\third_party\dll\drag-lint.exe') then
    begin
      Writeln('FAIL: could not spawn drag-lint.exe');
      Halt(1);
    end;
    if not Client.Initialize then
    begin
      Writeln('FAIL: initialize did not respond');
      Halt(1);
    end;
    Resp := Client.Request('shutdown', nil, 2000);
    if Resp = nil then
    begin
      Writeln('FAIL: shutdown timed out');
      Halt(1);
    end;
    Resp.Free;
    Client.Notify('exit', nil);
    Client.Stop;
    Writeln('OK');
  finally
    Client.Free;
  end;
end.
```

T27 .bat fixture: build the .dpr (dcc64), run it, verify output `OK`.

Commit: `feat(v0.21): TDragLintLspClient subprocess + JSON-RPC over pipes`.

---

## Task 3: Hover popup

**Files:**
- Create: `src/delphi-plugin/DragLint.Plugin.Hover.pas`
- Create: `src/delphi-plugin/DragLint.Plugin.Editor.pas`
- Modify: `src/delphi-plugin/dclDragLintWizard.dpk` — add new units

`TDragLintHoverPopup` — borderless TForm with a TMemo. Method `ShowAt(X, Y: Integer; const AMarkdown: string)`.

`TDragLintEditor` — implements `IOTAEditViewNotifier`; registers keystroke binding for `Ctrl+Alt+H`; on trigger:
1. Get caret position from `IOTAEditView.GetEditWindow.View.Buffer.CurrentLine` etc.
2. Build LSP `textDocument/hover` request.
3. Send via TDragLintLspClient (held by the wizard singleton).
4. Receive hover content, ShowAt(caret pos).

Wire in Wizard.Execute or in the wizard's `AfterCreate`.

(Verification: compile only — hover UX needs IDE testing.)

Commit: `feat(v0.21): hover popup + editor notifier + Ctrl+Alt+H binding`.

---

## Task 4: Completion popup

**Files:**
- Create: `src/delphi-plugin/DragLint.Plugin.Completion.pas`
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas`

`TDragLintCompletionPopup` — TForm with TListView; positioned at caret;
populated from LSP `textDocument/completion` response.

Bind to `Ctrl+J` (drag-lint completion) since `Ctrl+Space` is IDE's default
Code Insight trigger.

Insert on Enter via `IOTAEditWriter.Insert(InsertText)`.

Commit: `feat(v0.21): completion popup + Ctrl+J binding`.

---

## Task 5: signatureHelp popup

**Files:**
- Create: `src/delphi-plugin/DragLint.Plugin.Signature.pas`
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas`

`TDragLintSignaturePopup` — small TForm with one TLabel; bold active param.

Trigger: detect `(` in `IOTAEditViewNotifier.BeginEdit/EndEdit` or via
keyboard hook. Hide on `)` or ESC.

Commit: `feat(v0.21): signatureHelp popup`.

---

## Task 6: Diagnostics → Messages pane

**Files:**
- Create: `src/delphi-plugin/DragLint.Plugin.Diagnostics.pas`
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas` — wire didOpen/didSave

`TDragLintDiagnostics.PublishToMessagesPane(URI, Diagnostics: TJSONArray)`:
- For each diagnostic, call `(BorlandIDEServices as IOTAMessageServices)
  .AddToolMessage(FileName, Message, RuleCode, Line, Col)`.
- Clear previous tool messages for same FileName first.

Wire from LspClient's notification dispatcher: when
`textDocument/publishDiagnostics` arrives, route here.

Editor notifier hooks:
- `BufferLoaded` → send `textDocument/didOpen`.
- `BufferSaved` → send `textDocument/didSave`.

Commit: `feat(v0.21): diagnostics into Messages pane`.

---

## Task 7: README + stitcher + tag v0.21.0-alpha

**Files:**
- Modify: `src/delphi-plugin/README.md` — full install + verify steps
- Modify: `tests/run_v021_doctests.bat` — copy v0.20 + add T27
- Modify: `CHANGELOG.md`
- Modify: `README.md` (top-level) — link to plugin
- Modify: `src/cli/DRagLint.CLI.pas` — VERSION bump to '0.21.0-alpha'

### Auto-verified stop criteria (must pass)

1. `dclDragLintWizard.bpl` builds clean.
2. `T27_lsp_client.exe` round-trips initialize + shutdown.
3. v0.16-v0.20 tests all pass.

### Manual stop criteria (user, after install)

4. BPL installs in RAD Studio without error.
5. Tools menu shows drag-lint entry; clicking shows the v0.21.0-alpha message.
6. Ctrl+Alt+H on an identifier in an indexed project shows the hover popup.

Commit + tag locally:
```
git tag -a v0.21.0-alpha -m "v0.21.0-alpha - OTAPI Delphi IDE plugin (the headline destination)"
```

DO NOT push.

---

## Stop criteria summary

1. BPL builds.
2. LSP client standalone test passes.
3. All prior tests pass.
4. User-side manual verification documented in plugin README.
