unit DragLint.Plugin.AboutForm;

{ Session 27 (2026-08-17): the drag-lint About / status window.

  Why a new unit rather than an extension of DragLint.Plugin.About: that unit
  registers the IDE's own Help > About entry through
  IOTAAboutBoxServices.AddPluginInfo, whose only payload is a description
  STRING. It cannot host a button, colour a failing component red, or refresh.
  Those are the whole point here, so this is a real VCL form and the two units
  stay separate -- About.pas keeps owning the IDE splash/About entry.

  Every fact shown here comes from DragLint.Plugin.Diagnose. That separation is
  deliberate and load-bearing: an earlier draft of this window computed its own
  version/connection/index strings, which meant the same questions had two
  answers that could drift apart -- the exact failure DbResolver's own header
  was written about in v0.40.3. One data layer, two renderers (this form and
  the copyable text report).

  Built entirely in code via CreateNew (no .dfm), matching every other form in
  this plugin. A design-time package that ships a form WITH a .dfm must also
  ship the resource or it fails at runtime with EResNotFound -- see
  Delphi_IDE_OptionsPage_HOWTO.md. CreateNew sidesteps that class of failure. }

interface

uses
  System.Classes
  , Vcl.Controls
  , Vcl.Forms
  , Vcl.StdCtrls
  , Vcl.ExtCtrls
  ;

type
  /// <summary>Modeless status window: versions, connection health, indexes in
  /// use, configuration warnings, process footprint, and the diagnostic actions
  /// moved off the main menu.</summary>
  /// <remarks>Singleton -- use ShowAboutDialog. Freed from this unit's
  /// finalization so nothing survives a package unload.</remarks>
  TDragLintAboutForm = class(TForm)
    strict private
      FScroll   : TScrollBox;
      FButtons  : TPanel    ;
      FStatusBar: TLabel    ;
      FNextTop  : Integer   ;
      FWrappers : TList     ;
      procedure BuildContent;
      procedure ClearContent;
      procedure DoRefresh   (Sender: TObject);
      procedure DoDiagnose  (Sender: TObject);
      procedure DoCopyReport(Sender: TObject);
      procedure DoCloseClick(Sender: TObject);
      procedure AddButton(const ACaption: string; AHandler: TNotifyEvent;
                          var ALeft: Integer; var ATop: Integer);
      procedure AddProcButton(const ACaption: string; AProc: Pointer;
                              var ALeft: Integer; var ATop: Integer);
      procedure BuildButtons;
    public
      constructor Create(AOwner: TComponent); override;
      destructor Destroy; override;
      /// <summary>Re-reads every diagnostic group and repaints.</summary>
      procedure Rebuild;
  end;

/// <summary>Shows (creating if needed) the About / status window.</summary>
/// <remarks>Main thread only. Cheap: no database is opened -- see the
/// performance contract in DragLint.Plugin.Diagnose.</remarks>
procedure ShowAboutDialog;

/// <summary>Closes and frees the About window if it is open.</summary>
procedure CloseAboutDialog;

implementation

uses
  System.SysUtils
  , Winapi.Windows
  , Vcl.Graphics
  , Vcl.Clipbrd
  , Vcl.Dialogs
  , DragLint.Plugin.Diagnose
  , DragLint.Plugin.Editor
  ;

type
  { Editor.pas's Invoke* actions are UNIT-LEVEL procedures, and TNotifyEvent is a
    method POINTER -- the two are not assignment-compatible, which is why a
    direct assignment fails with E2009 "method pointer and regular procedure".
    Editor.pas solves this for menus with TMenuActionWrapper; this is the same
    trick for buttons. Wrappers are owned by the form and freed with it, so
    nothing is left pointing into an unloaded BPL. }
  TDLPlainProc = procedure(Sender: TObject);

  TDLActionWrapper = class
    strict private
      FProc: TDLPlainProc;
    public
      constructor Create(AProc: TDLPlainProc);
      procedure Click(Sender: TObject);
  end;

  { Same problem for the report dialog's Copy button, which must capture the
    report text: an anonymous method cannot be assigned to OnClick either. }
  TDLTextCopier = class
    strict private
      FText: string;
    public
      constructor Create(const AText: string);
      procedure Click(Sender: TObject);
  end;

var
  GAboutForm: TDragLintAboutForm = nil;

const
  MARGIN    = 12;
  LABEL_W   = 200;
  ROW_H     = 18;
  GROUP_GAP = 14;
  BTN_W     = 232;
  BTN_H     = 27;
  BTN_GAP   = 6;

constructor TDLActionWrapper.Create(AProc: TDLPlainProc);
begin
  inherited Create;
  FProc:= AProc;
end;

procedure TDLActionWrapper.Click(Sender: TObject);
begin
  if Assigned(FProc) then FProc(Sender);
end;

constructor TDLTextCopier.Create(const AText: string);
begin
  inherited Create;
  FText:= AText;
end;

procedure TDLTextCopier.Click(Sender: TObject);
begin
  Clipboard.AsText:= FText;
end;

{ ---- a read-only viewer for the diagnose report ---- }

{ Shown modally so the report cannot be lost behind the IDE while the user is
  copying it into an issue. }
procedure ShowTextReport(const ACaption, AText: string);
var
  Dlg   : TForm       ;
  Memo  : TMemo       ;
  Bar   : TPanel      ;
  BtnCp : TButton     ;
  BtnCl : TButton     ;
  Copier: TDLTextCopier;
begin
  Copier:= TDLTextCopier.Create(AText);
  try
    Dlg:= TForm.CreateNew(nil);
    try
      Dlg.Caption    := ACaption;
      Dlg.Width      := 1000;
      Dlg.Height     := 660;
      Dlg.Position   := poScreenCenter;
      Dlg.BorderStyle:= bsSizeable;

      Bar:= TPanel.Create(Dlg);
      Bar.Parent    := Dlg;
      Bar.Align     := alBottom;
      Bar.Height    := 40;
      Bar.BevelOuter:= bvNone;

      Memo:= TMemo.Create(Dlg);
      Memo.Parent    := Dlg;
      Memo.Align     := alClient;
      Memo.ScrollBars:= ssBoth;
      Memo.WordWrap  := False;
      Memo.ReadOnly  := True;
      Memo.Font.Name := 'Consolas';
      Memo.Font.Size := 9;
      Memo.Text      := AText;

      BtnCp:= TButton.Create(Dlg);
      BtnCp.Parent := Bar;
      BtnCp.Caption:= 'Copy to clipboard';
      BtnCp.Left   := MARGIN;
      BtnCp.Top    := 7;
      BtnCp.Width  := 150;
      BtnCp.OnClick:= Copier.Click;

      BtnCl:= TButton.Create(Dlg);
      BtnCl.Parent     := Bar;
      BtnCl.Caption    := 'Close';
      BtnCl.ModalResult:= mrOk;
      BtnCl.Cancel     := True;
      BtnCl.Default    := True;
      BtnCl.Left       := MARGIN + 160;
      BtnCl.Top        := 7;
      BtnCl.Width      := 90;

      Dlg.ShowModal;
    finally
      Dlg.Free;
    end;
  finally
    Copier.Free;
  end;
end;

{ ---- TDragLintAboutForm ---- }

constructor TDragLintAboutForm.Create(AOwner: TComponent);
begin
  { CreateNew, not Create: no .dfm exists for this form and none should. }
  inherited CreateNew(AOwner);
  Caption    := 'drag-lint -- About and Status';
  Width      := 1000;
  Height     := 720;
  Position   := poScreenCenter;
  BorderStyle:= bsSizeable;
  Constraints.MinWidth := 660;
  Constraints.MinHeight:= 440;

  FWrappers:= TList.Create;

  FButtons:= TPanel.Create(Self);
  FButtons.Parent    := Self;
  FButtons.Align     := alBottom;
  FButtons.Height    := 106;
  FButtons.BevelOuter:= bvNone;

  FStatusBar:= TLabel.Create(Self);
  FStatusBar.Parent := Self;
  FStatusBar.Align  := alBottom;
  FStatusBar.Layout := tlCenter;
  FStatusBar.Height := 22;

  FScroll:= TScrollBox.Create(Self);
  FScroll.Parent     := Self;
  FScroll.Align      := alClient;
  FScroll.BorderStyle:= bsNone;
  FScroll.ParentColor:= False;
  FScroll.Color      := clWindow;

  BuildButtons;
  BuildContent;
end;

destructor TDragLintAboutForm.Destroy;
var
  I: Integer;
begin
  if FWrappers <> nil then
  begin
    for I:= 0 to FWrappers.Count - 1 do
      TObject(FWrappers[I]).Free;
    FWrappers.Free;
  end;
  GAboutForm:= nil;
  inherited Destroy;
end;

procedure TDragLintAboutForm.ClearContent;
var
  I: Integer;
begin
  for I:= FScroll.ControlCount - 1 downto 0 do
    FScroll.Controls[I].Free;
  FNextTop:= MARGIN;
end;

procedure TDragLintAboutForm.BuildContent;

  procedure RenderGroup(const ATitle: string; const ALines: TDiagLines);
  var
    Head: TLabel   ;
    Cap : TLabel   ;
    Val : TLabel   ;
    Rule: TShape   ;
    L   : TDiagLine;
  begin
    Head:= TLabel.Create(Self);
    Head.Parent    := FScroll;
    Head.Left      := MARGIN;
    Head.Top       := FNextTop;
    Head.Caption   := ATitle;
    Head.Font.Style:= [fsBold];
    Head.Font.Size := 10;
    Inc(FNextTop, 20);

    Rule:= TShape.Create(Self);
    Rule.Parent   := FScroll;
    Rule.Left     := MARGIN;
    Rule.Top      := FNextTop;
    Rule.Width    := 880;
    Rule.Height   := 1;
    Rule.Pen.Color:= clSilver;
    Inc(FNextTop, 8);

    for L in ALines do
    begin
      Cap:= TLabel.Create(Self);
      Cap.Parent    := FScroll;
      Cap.Left      := MARGIN + 8;
      Cap.Top       := FNextTop;
      Cap.Width     := LABEL_W;
      Cap.Caption   := L.Caption;
      Cap.Font.Color:= clGrayText;

      Val:= TLabel.Create(Self);
      Val.Parent  := FScroll;
      Val.Left    := MARGIN + 8 + LABEL_W;
      Val.Top     := FNextTop;
      Val.Caption := L.Value;
      { The colour IS the message. A status screen that renders a broken
        component in the same ink as a healthy one is a screen nobody reads --
        which is how a stale library index survived months of daily use. }
      case L.Severity of
        dsBad : begin Val.Font.Color:= clRed; Val.Font.Style:= [fsBold]; end;
        dsWarn:       Val.Font.Color:= clMaroon;
        dsOk  :       Val.Font.Color:= clGreen;
      else
        Val.Font.Color:= clWindowText;
      end;

      Inc(FNextTop, ROW_H);
    end;
    Inc(FNextTop, GROUP_GAP);
  end;

var
  Conn: TDiagLines;
  Idx : TDiagLines;
begin
  ClearContent;
  Screen.Cursor:= crHourGlass;
  try
    RenderGroup('Versions', DiagVersions);

    Conn:= DiagConnections;
    RenderGroup('Connections', Conn);

    Idx:= DiagIndexes;
    RenderGroup('Indexes in use', Idx);

    RenderGroup('Configuration', DiagConfiguration);
    RenderGroup('Process'      , DiagProcess      );

    if HasProblem(Conn) or HasProblem(Idx) then
    begin
      FStatusBar.Caption   := '  Problems detected -- the red lines above are the ones that matter.';
      FStatusBar.Font.Color:= clRed;
      FStatusBar.Font.Style:= [fsBold];
    end
    else
    begin
      FStatusBar.Caption   := '  All resolved components look healthy.';
      FStatusBar.Font.Color:= clGreen;
      FStatusBar.Font.Style:= [];
    end;
  finally
    Screen.Cursor:= crDefault;
  end;
end;

procedure TDragLintAboutForm.Rebuild;
begin
  BuildContent;
end;

procedure TDragLintAboutForm.AddButton(const ACaption: string; AHandler: TNotifyEvent;
  var ALeft: Integer; var ATop: Integer);
var
  Btn: TButton;
begin
  if ALeft + BTN_W > FButtons.Width - MARGIN then
  begin
    ALeft:= MARGIN;
    Inc(ATop, BTN_H + BTN_GAP);
  end;
  Btn:= TButton.Create(Self);
  Btn.Parent := FButtons;
  Btn.Caption:= ACaption;
  Btn.Left   := ALeft;
  Btn.Top    := ATop;
  Btn.Width  := BTN_W;
  Btn.Height := BTN_H;
  Btn.OnClick:= AHandler;
  Inc(ALeft, BTN_W + BTN_GAP);
end;

procedure TDragLintAboutForm.AddProcButton(const ACaption: string; AProc: Pointer;
  var ALeft: Integer; var ATop: Integer);
var
  Wrap: TDLActionWrapper;
begin
  Wrap:= TDLActionWrapper.Create(TDLPlainProc(AProc));
  FWrappers.Add(Wrap);
  AddButton(ACaption, Wrap.Click, ALeft, ATop);
end;

procedure TDragLintAboutForm.BuildButtons;
var
  L, T: Integer;
begin
  L:= MARGIN;
  T:= 8;
  { This window's own actions first, then the seven moved off the
    "Diagnostics && Tests" menu section. Compile && Diagnose and Compile Buffer
    stayed on the menu -- they are daily actions, not diagnostics. }
  AddButton('Diagnose Current State', DoDiagnose   , L, T);
  AddButton('Copy Report'           , DoCopyReport , L, T);
  AddButton('Refresh'               , DoRefresh    , L, T);

  { Captions match the MENU captions these actions had before the move, exactly.
    Shortening them ("Run Diagnostics" for "Run Diagnostics (didSave)") broke
    every doc that named the old path and made the action harder to recognise
    for anyone who had used it for a year. The docs-sync guard's menu-path check
    caught both renames. }
  AddProcButton('Open Plugin Log'                , @InvokeOpenLog        , L, T);
  AddProcButton('Run Diagnostics (didSave)'      , @InvokeDiagnostics    , L, T);
  AddProcButton('Run AST Checks'                 , @InvokeRunAstChecks   , L, T);
  AddProcButton('Lint Buffer (Unsaved)'          , @InvokeLintBuffer     , L, T);
  AddProcButton('Copy Diagnostics (Current File)', @InvokeCopyDiagnostics, L, T);
  AddProcButton('Recover Buffer-Compile Files'   , @InvokeGhostRecover   , L, T);
  AddProcButton('Import Build Log...'            , @InvokeImportLog      , L, T);

  AddButton('Close', DoCloseClick, L, T);
end;

procedure TDragLintAboutForm.DoRefresh(Sender: TObject);
begin
  BuildContent;
end;

procedure TDragLintAboutForm.DoDiagnose(Sender: TObject);
var
  Report: string;
begin
  Screen.Cursor:= crHourGlass;
  try
    Report:= BuildDiagnoseReport(60);
  finally
    Screen.Cursor:= crDefault;
  end;
  ShowTextReport('drag-lint -- diagnose current state', Report);
end;

procedure TDragLintAboutForm.DoCopyReport(Sender: TObject);
begin
  Screen.Cursor:= crHourGlass;
  try
    Clipboard.AsText:= BuildDiagnoseReport(60);
  finally
    Screen.Cursor:= crDefault;
  end;
  FStatusBar.Caption   := '  Diagnose report copied to the clipboard.';
  FStatusBar.Font.Color:= clWindowText;
  FStatusBar.Font.Style:= [];
end;

procedure TDragLintAboutForm.DoCloseClick(Sender: TObject);
begin
  Close;
end;

procedure ShowAboutDialog;
begin
  if GAboutForm = nil then GAboutForm:= TDragLintAboutForm.Create(nil)
  else GAboutForm.Rebuild;
  GAboutForm.Show;
  GAboutForm.BringToFront;
end;

procedure CloseAboutDialog;
begin
  if GAboutForm <> nil then
  begin
    GAboutForm.Hide;
    FreeAndNil(GAboutForm);
  end;
end;

initialization

finalization
  if GAboutForm <> nil then FreeAndNil(GAboutForm);

end.
