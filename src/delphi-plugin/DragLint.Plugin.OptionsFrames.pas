unit DragLint.Plugin.OptionsFrames;

{ Four Tools->Options page frames that together replace the single
  TDragLintOptionsFrame (DragLint.Plugin.OptionsFrame.pas) with a
  General / Indexer / Linter / Editor split (Batch B, Task 1).

  Each page shows a SUBSET of TDragLintSettings. TDLPageFrame.Save
  re-reads the whole record via LoadSettings before applying this
  page's controls, so saving one page never clobbers fields owned
  by another page -- that read-modify-write contract is the entire
  point of the split.

  Controls are code-built (no .dfm), matching the idiom in
  DragLint.Plugin.OptionsFrame.pas. Registration as IDE Options
  sub-pages happens in Task 2; this unit only establishes the frames
  and proves they compile. }

interface

uses
  System.Classes
  , System.SysUtils
  , System.IOUtils
  , System.JSON
  , Vcl.Forms
  , Vcl.Controls
  , Vcl.StdCtrls
  , Vcl.ExtCtrls
  , Vcl.Dialogs
  , Vcl.Samples.Spin
  , ToolsAPI
  , DragLint.Plugin.Settings
  ;

type
  /// <summary>Base for the four drag-lint Tools->Options page frames. Each page
  /// shows a SUBSET of TDragLintSettings; Load/Save re-read the whole record so a
  /// page only writes its own fields and never clobbers another page's.</summary>
  TDLPageFrame = class(TFrame)
  protected
    FSettings: TDragLintSettings;
    /// <summary>Create this page's controls (code-built, no .dfm). Called once.</summary>
    procedure BuildControls; virtual; abstract;
    /// <summary>Copy FSettings -> this page's controls.</summary>
    procedure LoadControls; virtual; abstract;
    /// <summary>Copy this page's controls -> ASettings (only this page's fields).</summary>
    procedure SaveControls(var ASettings: TDragLintSettings); virtual; abstract;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Read the registry into FSettings and populate this page.</summary>
    procedure Load; virtual;
    /// <summary>Re-read the registry, apply this page's controls, write back.</summary>
    procedure Save; virtual;
  end;

  /// <summary>Tools->Options "General" page: exe/db paths, workspace mode, and the
  /// auto-compile family of toggles (8 fields: ExePath, DbPathTemplate,
  /// EnableWorkspaceMode, AutoCompileOnSave, AutoCompileBuffer, AutoCompileOnStartup,
  /// AutoCompileOnSwitch, AutoJumpToDiagnostics).</summary>
  TDLGeneralOptionsFrame = class(TDLPageFrame)
  private
    FGrpPaths    : TGroupBox;
    FEdExe       : TEdit    ;
    FBtnBrowse   : TButton  ;
    FEdDb        : TEdit    ;
    FOpenDlg     : TOpenDialog;
    FGrpWorkspace: TGroupBox;
    FCbWorkspace : TCheckBox;
    FGrpCompile  : TGroupBox;
    FCbCompileOnSave    : TCheckBox;
    FCbCompileBuffer    : TCheckBox;
    FCbCompileOnStartup : TCheckBox;
    FCbCompileOnSwitch  : TCheckBox;
    FCbJumpToDiagnostics: TCheckBox;
    procedure BtnBrowseClick(Sender: TObject);
  protected
    procedure BuildControls; override;
    procedure LoadControls; override;
    procedure SaveControls(var ASettings: TDragLintSettings); override;
  end;

  /// <summary>Tools->Options "Indexer" page: what/when/where to index (6 fields:
  /// AutoIndex, AutoReindexOnSave, ScanLibraries, IndexDbs, AutoDiscoverDbs,
  /// IncludeLibraryDb).</summary>
  TDLIndexerOptionsFrame = class(TDLPageFrame)
  private
    FGrpAutoIndex   : TGroupBox;
    FCbAutoIndex    : TCheckBox;
    FCbAutoReindex  : TCheckBox;
    FCbScanLibraries: TCheckBox;
    FGrpDbs         : TGroupBox;
    FCbAutoDiscover : TCheckBox;
    FCbIncludeLib   : TCheckBox;
    FMemoIndexDbs   : TMemo;
  protected
    procedure BuildControls; override;
    procedure LoadControls; override;
    procedure SaveControls(var ASettings: TDragLintSettings); override;
  end;

  /// <summary>Tools->Options "Linter" page: diagnostics + inline-marker toggles
  /// (7 fields: EnableDiagnostics, AutoDiagnosticsOnSave, EnableInlineMarkers,
  /// ShowErrorsInline, ShowWarningsInline, ShowHintsInline, ShowInfoInline),
  /// plus one manifest-backed field: max_return_cases (docs.max_return_cases in
  /// drag-lint.json -- NOT a registry setting; see ManifestPathForWrite).</summary>
  TDLLinterOptionsFrame = class(TDLPageFrame)
  private
    FGrpDiag     : TGroupBox;
    FCbDiag      : TCheckBox;
    FCbAutoDiag  : TCheckBox;
    FGrpMarkers  : TGroupBox;
    FCbInline    : TCheckBox;
    FCbErrInline : TCheckBox;
    FCbWarnInline: TCheckBox;
    FCbHintInline: TCheckBox;
    FCbInfoInline: TCheckBox;
    FGrpDocs     : TGroupBox;
    FEdMaxReturnCases: TSpinEdit;
    /// <summary>Resolves the manifest file to read/write for max_return_cases.
    /// The field is PROJECT-scoped: if a project is open, targets that
    /// project's directory + ".drag-lint.json" (DOTTED -- matching the LOCAL
    /// override the CLI/AutoDoc walk up from the start dir to find);
    /// otherwise falls back to the directory of the configured drag-lint.exe
    /// + "drag-lint.json" (UNDOTTED -- the global/exe-dir manifest). This is
    /// deliberately NOT the merged-effective-manifest path used by
    /// TManifestIO.Load -- writes here only ever touch ONE file in place.</summary>
    function ManifestPathForWrite: string;
    /// <summary>Reads docs.max_return_cases from ManifestPathForWrite via a
    /// direct System.JSON parse (not TManifestIO, to avoid a merge-then-emit
    /// round-trip clobbering unrelated keys). Returns 20 (the documented
    /// default) if the file or key is absent.</summary>
    function ReadMaxReturnCases: Integer;
    /// <summary>Read-modify-writes ONLY docs.max_return_cases into
    /// ManifestPathForWrite, preserving every other key already in the file
    /// (including an existing "docs" object's other fields, and top-level
    /// keys like "settings"). Never emits a fresh minimal manifest.</summary>
    procedure WriteMaxReturnCases(AValue: Integer);
  protected
    procedure BuildControls; override;
    procedure LoadControls; override;
    procedure SaveControls(var ASettings: TDragLintSettings); override;
  public
    procedure Load; override;
    procedure Save; override;
  end;

  /// <summary>Tools->Options "Editor" page: hover/completion/signature/code-lens
  /// feature toggles (5 fields: EnableHover, EnableHoverTooltip, EnableCompletion,
  /// EnableSignature, EnableCodeLens).</summary>
  TDLEditorOptionsFrame = class(TDLPageFrame)
  private
    FGrpFeatures   : TGroupBox;
    FCbHover       : TCheckBox;
    FCbHoverTooltip: TCheckBox;
    FCbCompletion  : TCheckBox;
    FCbSignature   : TCheckBox;
    FCbCodeLens    : TCheckBox;
  protected
    procedure BuildControls; override;
    procedure LoadControls; override;
    procedure SaveControls(var ASettings: TDragLintSettings); override;
  end;

implementation

uses
  DragLint.Plugin.ExeResolver
  ;

{ Minimal .dfm resource for the BASE frame class (TDLPageFrame). TCustomFrame.Create
  streams a per-class resource via InitInheritedComponent(Self, TFrame) and raises
  EResNotFound when none exists (frames, unlike forms, have no CreateNew to skip
  streaming). The ancestor walk succeeds as soon as ANY class in the chain has a
  resource, so a single TDLPageFrame resource covers all four concrete subclasses
  (TDLGeneralOptionsFrame etc.). Mirrors the working code-built TDragLintDockFrame,
  which ships the same minimal .dfm. The frame's real controls are still code-built
  in BuildControls; the .dfm only supplies the streamable root object. }
{$R *.dfm}

{ ==================== TDLPageFrame ==================== }

constructor TDLPageFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BuildControls;
end;

procedure TDLPageFrame.Load;
begin
  FSettings:= LoadSettings;
  LoadControls;
end;

procedure TDLPageFrame.Save;
var
  S: TDragLintSettings;
begin
  S:= LoadSettings; { re-read: do not clobber other pages' fields }
  SaveControls(S);
  SaveSettings(S);
end;

{ ==================== shared control-building helpers ==================== }

function DLNewGroup(AOwner: TWinControl; const ACaption: string; var Y: Integer; AHeight: Integer): TGroupBox;
const
  GM = 8;
begin
  Result:= TGroupBox.Create(AOwner);
  Result.Parent := AOwner;
  Result.Left   := GM;
  Result.Top    := Y;
  Result.Width  := AOwner.Width - GM * 2;
  Result.Height := AHeight;
  Result.Caption:= ACaption;
  Result.Anchors:= [akLeft, akTop, akRight];
  Inc(Y, AHeight + GM);
end;

function DLNewLabel(AParent: TWinControl; const ACap: string; AX, AY: Integer): TLabel;
begin
  Result:= TLabel.Create(AParent);
  Result.Parent  := AParent;
  Result.Caption := ACap;
  Result.Left    := AX;
  Result.Top     := AY;
  Result.AutoSize:= True;
end;

function DLNewEdit(AParent: TWinControl; AX, AY, AW: Integer; const ATxt: string): TEdit;
begin
  Result:= TEdit.Create(AParent);
  Result.Parent:= AParent;
  Result.Left  := AX;
  Result.Top   := AY;
  Result.Width := AW;
  Result.Text  := ATxt;
  Result.Anchors:= [akLeft, akTop, akRight];
end;

function DLNewCheck(AParent: TWinControl; AX, AY: Integer; const ACap: string; AChecked: Boolean): TCheckBox;
begin
  Result:= TCheckBox.Create(AParent);
  Result.Parent  := AParent;
  Result.Left    := AX;
  Result.Top     := AY;
  Result.Width   := AParent.Width - AX - 4;
  Result.Caption := ACap;
  Result.Checked := AChecked;
  Result.Anchors := [akLeft, akTop, akRight];
end;

{ ==================== TDLGeneralOptionsFrame ==================== }

procedure TDLGeneralOptionsFrame.BuildControls;
const
  LM = 8;
  GM = 8;
  GH = 28;
  CH = 22;
  EH = 24;
var
  Y : Integer;
  GY: Integer;
  GW: Integer;
begin
  Width := 460;
  Height:= 420;
  Y     := GM;

  { --- Paths --- }
  FGrpPaths:= DLNewGroup(Self, 'Paths', Y, GH + EH + 8 + EH + 28);
  GW:= FGrpPaths.Width - LM * 2;
  GY:= GH - 4;

  DLNewLabel(FGrpPaths, 'drag-lint.exe:', LM, GY);
  Inc(GY, 16);
  FEdExe:= DLNewEdit(FGrpPaths, LM, GY, GW - 72, '');

  FBtnBrowse:= TButton.Create(FGrpPaths);
  FBtnBrowse.Parent := FGrpPaths;
  FBtnBrowse.Caption:= 'Browse...';
  FBtnBrowse.Left   := FEdExe.Left + FEdExe.Width + 4;
  FBtnBrowse.Top    := GY;
  FBtnBrowse.Width  := 68;
  FBtnBrowse.Height := EH;
  FBtnBrowse.Anchors:= [akTop, akRight];
  FBtnBrowse.OnClick:= BtnBrowseClick;
  Inc(GY, EH + 6);

  DLNewLabel(FGrpPaths, 'Database template (use <projdir>):', LM, GY);
  Inc(GY, 16);
  FEdDb:= DLNewEdit(FGrpPaths, LM, GY, GW, '');

  FOpenDlg:= TOpenDialog.Create(Self);
  FOpenDlg.Filter:= 'drag-lint.exe|drag-lint.exe|All files|*.*';

  { --- Workspace --- }
  FGrpWorkspace:= DLNewGroup(Self, 'Workspace', Y, GH + CH + 4);
  GY:= GH - 4;
  FCbWorkspace:= DLNewCheck(FGrpWorkspace, LM, GY, 'Enable workspace mode (auto-detect .drag-lint-workspace.json)', False);

  { --- Auto-compile --- }
  FGrpCompile:= DLNewGroup(Self, 'Auto-compile', Y, GH + CH * 5 + 4);
  GY:= GH - 4;
  FCbCompileOnSave    := DLNewCheck(FGrpCompile, LM, GY, 'Compile-check on save (out-of-process)'      , False); Inc(GY, CH);
  FCbCompileBuffer    := DLNewCheck(FGrpCompile, LM, GY, 'Compile the unsaved buffer on idle (ghost-check)', False); Inc(GY, CH);
  FCbCompileOnStartup := DLNewCheck(FGrpCompile, LM, GY, 'Compile once when the project opens'          , False); Inc(GY, CH);
  FCbCompileOnSwitch  := DLNewCheck(FGrpCompile, LM, GY, 'Compile when switching to a .pas file'        , False); Inc(GY, CH);
  FCbJumpToDiagnostics:= DLNewCheck(FGrpCompile, LM, GY, 'Jump to Diagnostics in Structure tree after compile', False);
end; // procedure

procedure TDLGeneralOptionsFrame.LoadControls;
begin
  FEdExe              .Text   := FSettings.ExePath;
  FEdDb               .Text   := FSettings.DbPathTemplate;
  FCbWorkspace        .Checked:= FSettings.EnableWorkspaceMode;
  FCbCompileOnSave    .Checked:= FSettings.AutoCompileOnSave;
  FCbCompileBuffer    .Checked:= FSettings.AutoCompileBuffer;
  FCbCompileOnStartup .Checked:= FSettings.AutoCompileOnStartup;
  FCbCompileOnSwitch  .Checked:= FSettings.AutoCompileOnSwitch;
  FCbJumpToDiagnostics.Checked:= FSettings.AutoJumpToDiagnostics;
end; // procedure

procedure TDLGeneralOptionsFrame.SaveControls(var ASettings: TDragLintSettings);
begin
  ASettings.ExePath              := FEdExe              .Text;
  ASettings.DbPathTemplate       := FEdDb               .Text;
  ASettings.EnableWorkspaceMode  := FCbWorkspace         .Checked;
  ASettings.AutoCompileOnSave    := FCbCompileOnSave     .Checked;
  ASettings.AutoCompileBuffer    := FCbCompileBuffer     .Checked;
  ASettings.AutoCompileOnStartup := FCbCompileOnStartup  .Checked;
  ASettings.AutoCompileOnSwitch  := FCbCompileOnSwitch   .Checked;
  ASettings.AutoJumpToDiagnostics:= FCbJumpToDiagnostics .Checked;
end; // procedure

procedure TDLGeneralOptionsFrame.BtnBrowseClick(Sender: TObject);
begin
  if FOpenDlg.Execute then FEdExe.Text:= FOpenDlg.FileName;
end;

{ ==================== TDLIndexerOptionsFrame ==================== }

procedure TDLIndexerOptionsFrame.BuildControls;
const
  LM = 8;
  GM = 8;
  GH = 28;
  CH = 22;
  MH = 90; { memo height }
var
  Y : Integer;
  GY: Integer;
begin
  Width := 460;
  Height:= 320;
  Y     := GM;

  { --- Auto-index --- }
  FGrpAutoIndex:= DLNewGroup(Self, 'Auto-index', Y, GH + CH * 3 + 4);
  GY:= GH - 4;
  FCbAutoIndex    := DLNewCheck(FGrpAutoIndex, LM, GY, 'Auto-index project when .dproj opens', False); Inc(GY, CH);
  FCbAutoReindex  := DLNewCheck(FGrpAutoIndex, LM, GY, 'Auto-reindex on file save (.pas, .dpr, .dfm)', False); Inc(GY, CH);
  FCbScanLibraries:= DLNewCheck(FGrpAutoIndex, LM, GY, 'Scan libraries (RTL + DevExpress + browsing paths) on index', False);

  { --- Index databases --- }
  FGrpDbs:= DLNewGroup(Self, 'Index Databases', Y, GH + CH * 2 + MH + 12);
  GY:= GH - 4;
  FCbAutoDiscover:= DLNewCheck(FGrpDbs, LM, GY, 'Auto-discover sibling databases (walk project root)', False); Inc(GY, CH);
  FCbIncludeLib  := DLNewCheck(FGrpDbs, LM, GY, 'Include exe-relative library database', False); Inc(GY, CH);

  DLNewLabel(FGrpDbs, 'Additional index databases (one path per line):', LM, GY);
  Inc(GY, 16);
  FMemoIndexDbs:= TMemo.Create(FGrpDbs);
  FMemoIndexDbs.Parent    := FGrpDbs;
  FMemoIndexDbs.Left      := LM;
  FMemoIndexDbs.Top       := GY;
  FMemoIndexDbs.Width     := FGrpDbs.Width - LM * 2;
  FMemoIndexDbs.Height    := MH;
  FMemoIndexDbs.ScrollBars:= ssVertical;
  FMemoIndexDbs.WordWrap  := False;
  FMemoIndexDbs.Anchors   := [akLeft, akTop, akRight];
end; // procedure

procedure TDLIndexerOptionsFrame.LoadControls;
var
  I: Integer;
begin
  FCbAutoIndex    .Checked:= FSettings.AutoIndex;
  FCbAutoReindex  .Checked:= FSettings.AutoReindexOnSave;
  FCbScanLibraries.Checked:= FSettings.ScanLibraries;
  FCbAutoDiscover .Checked:= FSettings.AutoDiscoverDbs;
  FCbIncludeLib   .Checked:= FSettings.IncludeLibraryDb;
  FMemoIndexDbs.Lines.BeginUpdate;
  try
    FMemoIndexDbs.Lines.Clear;
    for I:= 0 to High(FSettings.IndexDbs) do FMemoIndexDbs.Lines.Add(FSettings.IndexDbs[I]);
  finally
    FMemoIndexDbs.Lines.EndUpdate;
  end; // try
end; // procedure

procedure TDLIndexerOptionsFrame.SaveControls(var ASettings: TDragLintSettings);
var
  I  : Integer;
  Line: string;
  N  : Integer;
begin
  ASettings.AutoIndex        := FCbAutoIndex    .Checked;
  ASettings.AutoReindexOnSave:= FCbAutoReindex  .Checked;
  ASettings.ScanLibraries    := FCbScanLibraries.Checked;
  ASettings.AutoDiscoverDbs  := FCbAutoDiscover .Checked;
  ASettings.IncludeLibraryDb := FCbIncludeLib   .Checked;

  SetLength(ASettings.IndexDbs, 0);
  N:= 0;
  for I:= 0 to FMemoIndexDbs.Lines.Count - 1 do
  begin
    Line:= Trim(FMemoIndexDbs.Lines[I]);
    if Line = '' then Continue;
    SetLength(ASettings.IndexDbs, N + 1);
    ASettings.IndexDbs[N]:= Line;
    Inc(N);
  end;
end; // procedure

{ ==================== TDLLinterOptionsFrame ==================== }

procedure TDLLinterOptionsFrame.BuildControls;
const
  LM = 8;
  GM = 8;
  GH = 28;
  CH = 22;
  EH = 24;
var
  Y : Integer;
  GY: Integer;
begin
  Width := 460;
  Height:= 320;
  Y     := GM;

  { --- Diagnostics --- }
  FGrpDiag:= DLNewGroup(Self, 'Diagnostics', Y, GH + CH * 2 + 4);
  GY:= GH - 4;
  FCbDiag    := DLNewCheck(FGrpDiag, LM, GY, 'Enable Run Diagnostics', False); Inc(GY, CH);
  FCbAutoDiag:= DLNewCheck(FGrpDiag, LM, GY, 'Run diagnostics automatically on save', False);

  { --- Inline Markers --- }
  FGrpMarkers:= DLNewGroup(Self, 'Inline Markers', Y, GH + CH * 5 + 4);
  GY:= GH - 4;
  FCbInline    := DLNewCheck(FGrpMarkers, LM, GY, 'Enable inline markers (gutter + underline)', False); Inc(GY, CH);
  FCbErrInline := DLNewCheck(FGrpMarkers, LM + 16, GY, 'Show errors inline'  , False); Inc(GY, CH);
  FCbWarnInline:= DLNewCheck(FGrpMarkers, LM + 16, GY, 'Show warnings inline', False); Inc(GY, CH);
  FCbHintInline:= DLNewCheck(FGrpMarkers, LM + 16, GY, 'Show hints inline'   , False); Inc(GY, CH);
  FCbInfoInline:= DLNewCheck(FGrpMarkers, LM + 16, GY, 'Show info inline'    , False);

  { --- Doc generation (drag-lint.json) --- }
  Height:= Height + GH + EH + GM;
  FGrpDocs:= DLNewGroup(Self, 'Doc generation (drag-lint.json -- project/manifest-scoped, NOT a registry setting)', Y, GH + EH + 4);
  GY:= GH - 4;
  DLNewLabel(FGrpDocs, 'Max return cases (docs.max_return_cases):', LM, GY);
  FEdMaxReturnCases:= TSpinEdit.Create(FGrpDocs);
  FEdMaxReturnCases.Parent  := FGrpDocs;
  FEdMaxReturnCases.Left    := FGrpDocs.Width - LM - 80;
  FEdMaxReturnCases.Top     := GY - 2;
  FEdMaxReturnCases.Width   := 80;
  FEdMaxReturnCases.MinValue:= 0;
  FEdMaxReturnCases.MaxValue:= 9999;
  FEdMaxReturnCases.Value   := 20;
  FEdMaxReturnCases.Anchors := [akTop, akRight];
end; // procedure

procedure TDLLinterOptionsFrame.LoadControls;
begin
  FCbDiag      .Checked:= FSettings.EnableDiagnostics;
  FCbAutoDiag  .Checked:= FSettings.AutoDiagnosticsOnSave;
  FCbInline    .Checked:= FSettings.EnableInlineMarkers;
  FCbErrInline .Checked:= FSettings.ShowErrorsInline;
  FCbWarnInline.Checked:= FSettings.ShowWarningsInline;
  FCbHintInline.Checked:= FSettings.ShowHintsInline;
  FCbInfoInline.Checked:= FSettings.ShowInfoInline;
end; // procedure

procedure TDLLinterOptionsFrame.SaveControls(var ASettings: TDragLintSettings);
begin
  ASettings.EnableDiagnostics    := FCbDiag      .Checked;
  ASettings.AutoDiagnosticsOnSave:= FCbAutoDiag  .Checked;
  ASettings.EnableInlineMarkers  := FCbInline    .Checked;
  ASettings.ShowErrorsInline     := FCbErrInline .Checked;
  ASettings.ShowWarningsInline   := FCbWarnInline.Checked;
  ASettings.ShowHintsInline      := FCbHintInline.Checked;
  ASettings.ShowInfoInline       := FCbInfoInline.Checked;
end; // procedure

{ ---- manifest-backed max_return_cases (docs.max_return_cases, NOT registry) ---- }

function TDLLinterOptionsFrame.ManifestPathForWrite: string;
var
  MS        : IOTAModuleServices;
  ProjGroup : IOTAProjectGroup  ;
  ActiveProj: IOTAProject       ;
  ProjDir   : string            ;
  ExeDir    : string            ;
begin
  { Project-scoped first: if a project is open, the manifest we read/write
    lives beside its .dproj as the DOTTED ".drag-lint.json" -- this matches
    the LOCAL override the CLI/AutoDoc walk up from the start dir to find
    (see TManifestIO.Load), and keeps the edit scoped to that project. The
    UNDOTTED "drag-lint.json" is read by the CLI ONLY as the global config
    beside drag-lint.exe (see the no-project branch below), so it must never
    be used for the per-project case. }
  ProjDir:= '';
  try
    if Supports(BorlandIDEServices, IOTAModuleServices, MS) and (MS <> nil) then
    begin
      ProjGroup:= MS.MainProjectGroup;
      if ProjGroup <> nil then
      begin
        ActiveProj:= ProjGroup.ActiveProject;
        if ActiveProj <> nil then ProjDir:= ExtractFilePath(ActiveProj.FileName);
      end;
    end;
  except
    ProjDir:= '';
  end; // try

  if ProjDir <> '' then Exit(ProjDir + '.drag-lint.json');

  { No project open: write the GLOBAL manifest beside the REAL drag-lint.exe --
    resolved via DragLintExe (the same resolver every plugin spawn site uses),
    NOT ParamStr(0) (which is the IDE's bds.exe dir and is not where the CLI
    reads its global config). FSettings.ExePath is blank by default. }
  ExeDir:= ExtractFilePath(FSettings.ExePath);
  if ExeDir = '' then ExeDir:= ExtractFilePath(DragLintExe);
  Result:= ExeDir + 'drag-lint.json';
end;

function TDLLinterOptionsFrame.ReadMaxReturnCases: Integer;
const
  DEFAULT_MAX_RETURN_CASES = 20;
var
  Path : string;
  Root : TJSONValue ;
  Docs : TJSONValue ;
  Num  : TJSONValue ;
begin
  Result:= DEFAULT_MAX_RETURN_CASES;
  Path:= ManifestPathForWrite;
  if (Path = '') or not TFile.Exists(Path) then Exit;
  Root:= nil;
  try
    try
      Root:= TJSONObject.ParseJSONValue(TFile.ReadAllText(Path));
    except
      Exit; { malformed manifest: show the default rather than raising in Options UI }
    end; // try
    if not (Root is TJSONObject) then Exit;
    Docs:= TJSONObject(Root).GetValue('docs');
    if not (Docs is TJSONObject) then Exit;
    Num:= TJSONObject(Docs).GetValue('max_return_cases');
    if Num is TJSONNumber then Result:= TJSONNumber(Num).AsInt;
  finally
    Root.Free;
  end; // try
end;

procedure TDLLinterOptionsFrame.WriteMaxReturnCases(AValue: Integer);
var
  Path    : string;
  Parsed  : TJSONValue ;
  Root    : TJSONObject;
  DocsVal : TJSONValue ;
  Docs    : TJSONObject;
  OldPair : TJSONPair  ;
begin
  Path:= ManifestPathForWrite;
  if Path = '' then Exit;

  Root:= nil;
  try
    if TFile.Exists(Path) then
    begin
      Parsed:= nil;
      try
        Parsed:= TJSONObject.ParseJSONValue(TFile.ReadAllText(Path));
      except
        Parsed:= nil; { malformed manifest text: fall through to a fresh object }
      end; // try
      if Parsed is TJSONObject then
        Root:= TJSONObject(Parsed)
      else
        Parsed.Free; { either nil (no-op) or a non-object JSON value we cannot use }
    end; // if
    if Root = nil then Root:= TJSONObject.Create; { no file yet, or unparsable: start fresh }

    { Ensure a "docs" object exists, reusing it if present so every OTHER
      docs.* key (and every other top-level key) survives untouched. }
    DocsVal:= Root.GetValue('docs');
    if DocsVal is TJSONObject then
      Docs:= TJSONObject(DocsVal)
    else
    begin
      Docs:= TJSONObject.Create;
      Root.AddPair('docs', Docs);
    end; // if

    { TJSONObject has no in-place "set" -- remove any existing pair first so a
      repeated Save never leaves two max_return_cases pairs behind. }
    OldPair:= Docs.RemovePair('max_return_cases');
    OldPair.Free; { RemovePair returns nil if absent; TObject(nil).Free is a no-op }
    Docs.AddPair('max_return_cases', TJSONNumber.Create(AValue));

    TFile.WriteAllText(Path, Root.ToJSON, TEncoding.ANSI);
  finally
    Root.Free;
  end; // try
end;

procedure TDLLinterOptionsFrame.Load;
begin
  inherited Load; { registry checkboxes via LoadControls }
  FEdMaxReturnCases.Value:= ReadMaxReturnCases;
end;

procedure TDLLinterOptionsFrame.Save;
begin
  inherited Save; { registry checkboxes via SaveControls }
  WriteMaxReturnCases(FEdMaxReturnCases.Value);
end;

{ ==================== TDLEditorOptionsFrame ==================== }

procedure TDLEditorOptionsFrame.BuildControls;
const
  LM = 8;
  GM = 8;
  GH = 28;
  CH = 22;
var
  Y : Integer;
  GY: Integer;
begin
  Width := 460;
  Height:= 220;
  Y     := GM;

  FGrpFeatures:= DLNewGroup(Self, 'Feature Toggles', Y, GH + CH * 5 + 4);
  GY:= GH - 4;
  FCbHover       := DLNewCheck(FGrpFeatures, LM, GY, 'Enable Hover at Cursor'                    , False); Inc(GY, CH);
  FCbHoverTooltip:= DLNewCheck(FGrpFeatures, LM, GY, 'Enable hover tooltip (caret-based, 600ms dwell)', False); Inc(GY, CH);
  FCbCompletion  := DLNewCheck(FGrpFeatures, LM, GY, 'Enable Show Completion'                    , False); Inc(GY, CH);
  FCbSignature   := DLNewCheck(FGrpFeatures, LM, GY, 'Enable Show Signature Help'                , False); Inc(GY, CH);
  FCbCodeLens    := DLNewCheck(FGrpFeatures, LM, GY, 'Enable inline code lens ([N callers] next to method declarations)', False);
end; // procedure

procedure TDLEditorOptionsFrame.LoadControls;
begin
  FCbHover       .Checked:= FSettings.EnableHover;
  FCbHoverTooltip.Checked:= FSettings.EnableHoverTooltip;
  FCbCompletion  .Checked:= FSettings.EnableCompletion;
  FCbSignature   .Checked:= FSettings.EnableSignature;
  FCbCodeLens    .Checked:= FSettings.EnableCodeLens;
end; // procedure

procedure TDLEditorOptionsFrame.SaveControls(var ASettings: TDragLintSettings);
begin
  ASettings.EnableHover        := FCbHover       .Checked;
  ASettings.EnableHoverTooltip := FCbHoverTooltip.Checked;
  ASettings.EnableCompletion   := FCbCompletion  .Checked;
  ASettings.EnableSignature    := FCbSignature   .Checked;
  ASettings.EnableCodeLens     := FCbCodeLens    .Checked;
end; // procedure

end.
