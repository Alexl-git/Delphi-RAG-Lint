unit DragLint.Plugin.SettingsForm;

interface

uses
  System.Classes, System.SysUtils,
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, Vcl.ExtCtrls, Vcl.Dialogs,
  DragLint.Plugin.Settings;

function ShowSettingsDialog: Boolean;

implementation

uses
  Vcl.Graphics;

{ ---- TBrowseHandler ----
  Bridges TButton.OnClick (TNotifyEvent) to the Browse action, which needs
  access to the edit control and open dialog.  Owned by the form so it is
  freed automatically when the form is destroyed. }

type
  TBrowseHandler = class(TComponent)
  private
    FEdit:    TEdit;
    FOpenDlg: TOpenDialog;
  public
    constructor Create(AOwner: TComponent; AEdit: TEdit;
      AOpenDlg: TOpenDialog); reintroduce;
    procedure DoBrowse(Sender: TObject);
  end;

constructor TBrowseHandler.Create(AOwner: TComponent; AEdit: TEdit;
  AOpenDlg: TOpenDialog);
begin
  inherited Create(AOwner);
  FEdit    := AEdit;
  FOpenDlg := AOpenDlg;
end;

procedure TBrowseHandler.DoBrowse(Sender: TObject);
begin
  if FOpenDlg.Execute then
    FEdit.Text := FOpenDlg.FileName;
end;

{ ---- ShowSettingsDialog ---- }

function ShowSettingsDialog: Boolean;
var
  Form: TForm;
  Settings: TDragLintSettings;
  edExe, edDb: TEdit;
  cbAutoIndex, cbAutoReindex, cbScanLibraries: TCheckBox;
  cbHover, cbCompletion, cbSignature, cbDiag: TCheckBox;
  cbInlineMarkers, cbErrInline, cbWarnInline, cbHintInline, cbInfoInline: TCheckBox;
  cbCodeLens: TCheckBox;
  cbWorkspace: TCheckBox;
  cbHoverTooltip: TCheckBox;
  btnOK, btnCancel, btnBrowse: TButton;
  OpenDlg: TOpenDialog;
  BrowseHandler: TBrowseHandler;
  Y: Integer;

  function AddLabel(const ACaption: string; AY: Integer): TLabel;
  begin
    Result := TLabel.Create(Form);
    Result.Parent := Form;
    Result.Caption := ACaption;
    Result.Left := 16;
    Result.Top := AY;
    Result.AutoSize := True;
  end;

  function AddEdit(AY: Integer; const AText: string): TEdit;
  begin
    Result := TEdit.Create(Form);
    Result.Parent := Form;
    Result.Left := 16;
    Result.Top := AY;
    Result.Width := 380;
    Result.Text := AText;
  end;

  function AddCheck(AY: Integer; const ACaption: string;
    AChecked: Boolean): TCheckBox;
  begin
    Result := TCheckBox.Create(Form);
    Result.Parent := Form;
    Result.Left := 16;
    Result.Top := AY;
    Result.Width := 380;
    Result.Caption := ACaption;
    Result.Checked := AChecked;
  end;

begin
  Result := False;
  Settings := LoadSettings;

  Form := TForm.Create(nil);
  try
    Form.Caption := 'drag-lint Settings';
    Form.BorderStyle := bsDialog;
    Form.Position := poScreenCenter;
    Form.ClientWidth := 480;
    Form.ClientHeight := 660;

    Y := 16;
    AddLabel('drag-lint.exe path:', Y); Inc(Y, 20);
    edExe := AddEdit(Y, Settings.ExePath);
    edExe.Width := 320;

    OpenDlg := TOpenDialog.Create(Form);
    OpenDlg.Filter := 'drag-lint.exe|drag-lint.exe|All files|*.*';

    BrowseHandler := TBrowseHandler.Create(Form, edExe, OpenDlg);

    btnBrowse := TButton.Create(Form);
    btnBrowse.Parent := Form;
    btnBrowse.Left    := 344;
    btnBrowse.Top     := Y;
    btnBrowse.Width   := 60;
    btnBrowse.Caption := 'Browse...';
    btnBrowse.OnClick := BrowseHandler.DoBrowse;
    Inc(Y, 32);

    AddLabel('Database path template (use <projdir> for project dir):', Y);
    Inc(Y, 20);
    edDb := AddEdit(Y, Settings.DbPathTemplate);
    Inc(Y, 32);

    Inc(Y, 8);
    cbAutoIndex   := AddCheck(Y, 'Auto-index project when .dproj opens',
      Settings.AutoIndex);  Inc(Y, 24);
    cbAutoReindex := AddCheck(Y, 'Auto-reindex on file save (.pas, .dpr, .dfm)',
      Settings.AutoReindexOnSave);  Inc(Y, 24);
    cbScanLibraries := AddCheck(Y,
      'Scan libraries (RTL + DevExpress + browsing paths)',
      Settings.ScanLibraries);  Inc(Y, 24);
    cbHover       := AddCheck(Y, 'Enable Hover at Cursor',
      Settings.EnableHover);  Inc(Y, 24);
    cbCompletion := AddCheck(Y, 'Enable Show Completion',
      Settings.EnableCompletion);  Inc(Y, 24);
    cbSignature  := AddCheck(Y, 'Enable Show Signature Help',
      Settings.EnableSignature);  Inc(Y, 24);
    cbDiag       := AddCheck(Y, 'Enable Run Diagnostics',
      Settings.EnableDiagnostics);  Inc(Y, 24);

    Inc(Y, 8);
    cbInlineMarkers := AddCheck(Y, 'Enable inline markers (gutter + underline)',
      Settings.EnableInlineMarkers);  Inc(Y, 24);
    cbErrInline  := AddCheck(Y, '  Show errors inline',
      Settings.ShowErrorsInline);   Inc(Y, 24);
    cbWarnInline := AddCheck(Y, '  Show warnings inline',
      Settings.ShowWarningsInline); Inc(Y, 24);
    cbHintInline := AddCheck(Y, '  Show hints inline',
      Settings.ShowHintsInline);    Inc(Y, 24);
    cbInfoInline := AddCheck(Y, '  Show info inline',
      Settings.ShowInfoInline);  Inc(Y, 24);

    Inc(Y, 8);
    cbCodeLens := AddCheck(Y, 'Enable inline code lens ([N callers])',
      Settings.EnableCodeLens);  Inc(Y, 24);

    Inc(Y, 8);
    cbWorkspace := AddCheck(Y, 'Enable workspace mode (auto-detect .drag-lint-workspace.json)',
      Settings.EnableWorkspaceMode);  Inc(Y, 24);

    cbHoverTooltip := AddCheck(Y,
      'Enable hover tooltip (caret-based, 600ms dwell)',
      Settings.EnableHoverTooltip);  Inc(Y, 24);

    btnOK := TButton.Create(Form);
    btnOK.Parent      := Form;
    btnOK.Left        := 296;
    btnOK.Top         := Form.ClientHeight - 40;
    btnOK.Width       := 80;
    btnOK.Caption     := 'OK';
    btnOK.Default     := True;
    btnOK.ModalResult := mrOk;

    btnCancel := TButton.Create(Form);
    btnCancel.Parent      := Form;
    btnCancel.Left        := 384;
    btnCancel.Top         := Form.ClientHeight - 40;
    btnCancel.Width       := 80;
    btnCancel.Caption     := 'Cancel';
    btnCancel.Cancel      := True;
    btnCancel.ModalResult := mrCancel;

    if Form.ShowModal = mrOk then
    begin
      Settings.ExePath          := edExe.Text;
      Settings.DbPathTemplate   := edDb.Text;
      Settings.AutoIndex           := cbAutoIndex.Checked;
      Settings.AutoReindexOnSave   := cbAutoReindex.Checked;
      Settings.ScanLibraries       := cbScanLibraries.Checked;
      Settings.EnableHover         := cbHover.Checked;
      Settings.EnableCompletion := cbCompletion.Checked;
      Settings.EnableSignature  := cbSignature.Checked;
      Settings.EnableDiagnostics := cbDiag.Checked;
      Settings.EnableInlineMarkers := cbInlineMarkers.Checked;
      Settings.ShowErrorsInline    := cbErrInline.Checked;
      Settings.ShowWarningsInline  := cbWarnInline.Checked;
      Settings.ShowHintsInline     := cbHintInline.Checked;
      Settings.ShowInfoInline      := cbInfoInline.Checked;
      Settings.EnableCodeLens      := cbCodeLens.Checked;
      Settings.EnableWorkspaceMode := cbWorkspace.Checked;
      Settings.EnableHoverTooltip  := cbHoverTooltip.Checked;
      SaveSettings(Settings);
      Result := True;
    end;
  finally
    Form.Free;
  end;
end;

end.
