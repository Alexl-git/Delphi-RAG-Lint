unit Config.IndexesFrame;

/// <summary>Frame hosting the section list editor for drag-lint index manifests.
/// Left panel: list of section names with Add/Delete. Right panel: editor for
/// the selected TIndexSection fields. Bottom: placeholder TPageControl with
/// Coverage / Plan preview / Build log tabs (content added in later tasks).</summary>

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Dialogs,
  Vcl.FileCtrl,
  DRagLint.Index.Manifest;

type
  /// <summary>Typed pointer to TIndexManifest, used by BindManifest so the frame
  /// and main form share a single working instance without copying.</summary>
  PIndexManifest = ^TIndexManifest;

  /// <summary>Editor frame for the Indexes tab. Binds to a TIndexManifest pointer
  /// so the main form and this frame share a single working manifest.</summary>
  TIndexesFrame = class(TFrame)
    splMain: TSplitter;
    pnlLeft: TPanel;
    lbSections: TListBox;
    pnlLeftBtns: TPanel;
    btnAddSection: TButton;
    btnDelSection: TButton;
    pnlRight: TPanel;
    scrEditor: TScrollBox;
    lblName: TLabel;
    edName: TEdit;
    lblDb: TLabel;
    edDb: TEdit;
    lblSource: TLabel;
    rgSource: TRadioGroup;
    lblPlatforms: TLabel;
    edPlatforms: TEdit;
    lblInclude: TLabel;
    lbInclude: TListBox;
    pnlIncludeBtns: TPanel;
    btnAddFolder: TButton;
    btnAddDproj: TButton;
    btnRemoveInclude: TButton;
    lblExclude: TLabel;
    edExclude: TEdit;
    lblIncludeOnly: TLabel;
    edIncludeOnly: TEdit;
    lblDedup: TLabel;
    edDedup: TEdit;
    cbUseIgnore: TCheckBox;
    cbSqlOnlyMS: TCheckBox;
    splBottom: TSplitter;
    pcBottom: TPageControl;
    tsCoverage: TTabSheet;
    tsPlanPreview: TTabSheet;
    tsBuildLog: TTabSheet;
    procedure lbSectionsClick(Sender: TObject);
    procedure btnAddSectionClick(Sender: TObject);
    procedure btnDelSectionClick(Sender: TObject);
    procedure edNameChange(Sender: TObject);
    procedure edDbChange(Sender: TObject);
    procedure rgSourceClick(Sender: TObject);
    procedure edPlatformsChange(Sender: TObject);
    procedure lbIncludeClick(Sender: TObject);
    procedure btnAddFolderClick(Sender: TObject);
    procedure btnAddDprojClick(Sender: TObject);
    procedure btnRemoveIncludeClick(Sender: TObject);
    procedure edExcludeChange(Sender: TObject);
    procedure edIncludeOnlyChange(Sender: TObject);
    procedure edDedupChange(Sender: TObject);
    procedure cbUseIgnoreClick(Sender: TObject);
    procedure cbSqlOnlyMSClick(Sender: TObject);
  private
    FManifest:   PIndexManifest;
    FLoading:    Boolean;
    FOpenDialog: TOpenDialog;
    /// <summary>Split a semicolon-joined string into a TArray of strings,
    /// trimming each element and ignoring empty entries.</summary>
    /// <param name="S">Semicolon-joined input string.</param>
    /// <returns>Array of trimmed non-empty parts.</returns>
    function SplitSemicolon(const S: string): TArray<string>;
    /// <summary>Join a TArray of strings with '; ' as the delimiter.</summary>
    /// <param name="A">Array of strings to join.</param>
    /// <returns>Joined string.</returns>
    function JoinSemicolon(const A: TArray<string>): string;
    /// <summary>Return the index of the currently selected section, or -1 if
    /// nothing is selected or FManifest is nil.</summary>
    /// <returns>Zero-based section index, or -1.</returns>
    function SelectedSectionIndex: Integer;
    /// <summary>Load the fields of the section at index AIdx into the editor
    /// controls. Sets FLoading to suppress change events during load.</summary>
    /// <param name="AIdx">Zero-based section index.</param>
    procedure LoadSectionToControls(AIdx: Integer);
    /// <summary>Write the current editor control values back into the section
    /// at index AIdx in FManifest^. No-op if FLoading is True.</summary>
    /// <param name="AIdx">Zero-based section index.</param>
    procedure SaveControlsToSection(AIdx: Integer);
    /// <summary>Rebuild the lbSections listbox from FManifest^.Sections,
    /// preserving the current selection if possible.</summary>
    procedure RefreshSectionList;
    /// <summary>Enable or disable the right-hand editor controls based on
    /// whether a section is currently selected.</summary>
    /// <param name="AEnabled">True to enable; False to disable.</param>
    procedure SetEditorEnabled(AEnabled: Boolean);
  public
    /// <summary>Bind the frame to a manifest pointer. The pointer must remain
    /// valid for the lifetime of the frame (owned by TMainForm). Rebuilds the
    /// section list and clears the editor.</summary>
    /// <param name="AManifest">Pointer to the main form's working TIndexManifest.</param>
    /// <remarks>Not thread-safe; call from the main (UI) thread only.</remarks>
    procedure BindManifest(AManifest: PIndexManifest);
    /// <summary>Flush any pending edits from the currently selected section's
    /// controls back into FManifest^. Called by TMainForm before Save.</summary>
    /// <remarks>Not thread-safe; call from the main (UI) thread only.</remarks>
    procedure FlushToManifest;
  end;

implementation

{$R *.dfm}

{ helpers }

function TIndexesFrame.SplitSemicolon(const S: string): TArray<string>;
var
  Parts: TArray<string>;
  I, N: Integer;
  T: string;
begin
  Parts := S.Split([';']);
  SetLength(Result, Length(Parts));
  N := 0;
  for I := 0 to High(Parts) do
  begin
    T := Trim(Parts[I]);
    if T <> '' then
    begin
      Result[N] := T;
      Inc(N);
    end;
  end;
  SetLength(Result, N);
end;

function TIndexesFrame.JoinSemicolon(const A: TArray<string>): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(A) do
  begin
    if Result <> '' then
      Result := Result + '; ';
    Result := Result + A[I];
  end;
end;

function TIndexesFrame.SelectedSectionIndex: Integer;
begin
  if (FManifest = nil) or (lbSections.ItemIndex < 0) then
    Result := -1
  else
    Result := lbSections.ItemIndex;
end;

procedure TIndexesFrame.LoadSectionToControls(AIdx: Integer);
var
  Sec: TIndexSection;
  S: string;
begin
  if (FManifest = nil) or (AIdx < 0) or (AIdx > High(FManifest^.Sections)) then
  begin
    SetEditorEnabled(False);
    Exit;
  end;

  FLoading := True;
  try
    Sec := FManifest^.Sections[AIdx];

    edName.Text := Sec.Name;
    edDb.Text   := Sec.Db;

    if Sec.Source = 'registry-libraries' then
      rgSource.ItemIndex := 1
    else
      rgSource.ItemIndex := 0;

    edPlatforms.Text := JoinSemicolon(Sec.Platforms);

    lbInclude.Clear;
    for S in Sec.Include do
      lbInclude.Items.Add(S);

    edExclude.Text     := JoinSemicolon(Sec.Exclude);
    edIncludeOnly.Text := JoinSemicolon(Sec.IncludeOnly);
    edDedup.Text       := JoinSemicolon(Sec.DedupAgainst);

    cbUseIgnore.Checked := Sec.UseIgnoreFiles;
    cbSqlOnlyMS.Checked := Sec.SqlOnlyMS;

    SetEditorEnabled(True);
  finally
    FLoading := False;
  end;
end;

procedure TIndexesFrame.SaveControlsToSection(AIdx: Integer);
var
  I: Integer;
begin
  if FLoading then Exit;
  if (FManifest = nil) or (AIdx < 0) or (AIdx > High(FManifest^.Sections)) then
    Exit;

  with FManifest^.Sections[AIdx] do
  begin
    Name := edName.Text;
    Db   := edDb.Text;

    if rgSource.ItemIndex = 1 then
      Source := 'registry-libraries'
    else
      Source := '';

    Platforms    := SplitSemicolon(edPlatforms.Text);
    Exclude      := SplitSemicolon(edExclude.Text);
    IncludeOnly  := SplitSemicolon(edIncludeOnly.Text);
    DedupAgainst := SplitSemicolon(edDedup.Text);

    SetLength(Include, lbInclude.Items.Count);
    for I := 0 to lbInclude.Items.Count - 1 do
      Include[I] := lbInclude.Items[I];

    UseIgnoreFiles := cbUseIgnore.Checked;
    SqlOnlyMS      := cbSqlOnlyMS.Checked;
  end;

  { Refresh the section name in the listbox in case Name changed }
  lbSections.Items[AIdx] := FManifest^.Sections[AIdx].Name;
end;

procedure TIndexesFrame.RefreshSectionList;
var
  I, PrevIdx: Integer;
begin
  PrevIdx := lbSections.ItemIndex;
  lbSections.Items.BeginUpdate;
  try
    lbSections.Clear;
    if FManifest <> nil then
      for I := 0 to High(FManifest^.Sections) do
        lbSections.Items.Add(FManifest^.Sections[I].Name);
  finally
    lbSections.Items.EndUpdate;
  end;

  if (PrevIdx >= 0) and (PrevIdx < lbSections.Count) then
    lbSections.ItemIndex := PrevIdx
  else if lbSections.Count > 0 then
    lbSections.ItemIndex := 0
  else
    lbSections.ItemIndex := -1;

  LoadSectionToControls(lbSections.ItemIndex);
end;

procedure TIndexesFrame.SetEditorEnabled(AEnabled: Boolean);
begin
  edName.Enabled        := AEnabled;
  edDb.Enabled          := AEnabled;
  rgSource.Enabled      := AEnabled;
  edPlatforms.Enabled   := AEnabled;
  lbInclude.Enabled     := AEnabled;
  btnAddFolder.Enabled  := AEnabled;
  btnAddDproj.Enabled   := AEnabled;
  btnRemoveInclude.Enabled := AEnabled;
  edExclude.Enabled     := AEnabled;
  edIncludeOnly.Enabled := AEnabled;
  edDedup.Enabled       := AEnabled;
  cbUseIgnore.Enabled   := AEnabled;
  cbSqlOnlyMS.Enabled   := AEnabled;
end;

{ public }

procedure TIndexesFrame.BindManifest(AManifest: PIndexManifest);
begin
  FManifest := AManifest;
  RefreshSectionList;
end;

procedure TIndexesFrame.FlushToManifest;
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

{ event handlers }

procedure TIndexesFrame.lbSectionsClick(Sender: TObject);
begin
  LoadSectionToControls(lbSections.ItemIndex);
end;

procedure TIndexesFrame.btnAddSectionClick(Sender: TObject);
var
  NewSec: TIndexSection;
  N: Integer;
begin
  if FManifest = nil then Exit;

  NewSec            := Default(TIndexSection);
  NewSec.Name       := 'NewDB';
  NewSec.UseIgnoreFiles := True;
  NewSec.SqlOnlyMS  := True;
  NewSec.Include    := [];

  N := Length(FManifest^.Sections);
  SetLength(FManifest^.Sections, N + 1);
  FManifest^.Sections[N] := NewSec;

  lbSections.Items.Add(NewSec.Name);
  lbSections.ItemIndex := N;
  LoadSectionToControls(N);
end;

procedure TIndexesFrame.btnDelSectionClick(Sender: TObject);
var
  Idx, I, N: Integer;
begin
  Idx := SelectedSectionIndex;
  if Idx < 0 then Exit;

  N := Length(FManifest^.Sections);
  for I := Idx to N - 2 do
    FManifest^.Sections[I] := FManifest^.Sections[I + 1];
  SetLength(FManifest^.Sections, N - 1);

  lbSections.Items.Delete(Idx);

  if lbSections.Count > 0 then
  begin
    if Idx >= lbSections.Count then
      lbSections.ItemIndex := lbSections.Count - 1
    else
      lbSections.ItemIndex := Idx;
    LoadSectionToControls(lbSections.ItemIndex);
  end
  else
  begin
    lbSections.ItemIndex := -1;
    SetEditorEnabled(False);
  end;
end;

procedure TIndexesFrame.edNameChange(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

procedure TIndexesFrame.edDbChange(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

procedure TIndexesFrame.rgSourceClick(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

procedure TIndexesFrame.edPlatformsChange(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

procedure TIndexesFrame.lbIncludeClick(Sender: TObject);
begin
  { Selection change only; no write-back needed here }
end;

procedure TIndexesFrame.btnAddFolderClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := '';
  if SelectDirectory('Select folder to include', '', Dir) then
  begin
    lbInclude.Items.Add(Dir);
    SaveControlsToSection(SelectedSectionIndex);
  end;
end;

procedure TIndexesFrame.btnAddDprojClick(Sender: TObject);
begin
  if FOpenDialog = nil then
  begin
    FOpenDialog := TOpenDialog.Create(Self);
    FOpenDialog.Title  := 'Select project file';
    FOpenDialog.Filter := 'Delphi project|*.dpr;*.dproj|All files|*.*';
    FOpenDialog.Options := FOpenDialog.Options + [ofFileMustExist];
  end;

  if FOpenDialog.Execute then
  begin
    lbInclude.Items.Add(FOpenDialog.FileName);
    SaveControlsToSection(SelectedSectionIndex);
  end;
end;

procedure TIndexesFrame.btnRemoveIncludeClick(Sender: TObject);
begin
  if lbInclude.ItemIndex >= 0 then
  begin
    lbInclude.Items.Delete(lbInclude.ItemIndex);
    SaveControlsToSection(SelectedSectionIndex);
  end;
end;

procedure TIndexesFrame.edExcludeChange(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

procedure TIndexesFrame.edIncludeOnlyChange(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

procedure TIndexesFrame.edDedupChange(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

procedure TIndexesFrame.cbUseIgnoreClick(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

procedure TIndexesFrame.cbSqlOnlyMSClick(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

end.
