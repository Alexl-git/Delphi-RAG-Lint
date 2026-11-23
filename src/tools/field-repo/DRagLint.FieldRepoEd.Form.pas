unit DRagLint.FieldRepoEd.Form;

{ drag-lint 1.52 -- lane TTD: the field repository editor window (TableTools migration M13).

  One tab per editable repository table (DL_FIELDS_INFO, DL_DATASETS_INFO, DL_ENUMVALUES,
  DL_ERROR_MESSAGES; DL_META is bookkeeping and is not edited here). Each tab is a grid over a
  cached-updates query, so edits stay in memory until "Save changes". The whole window is built
  in code (no .dfm). The grid control itself comes from DRagLint.FieldRepoEd.Grid. }

interface

uses
  System.Classes,
  System.SysUtils,
  Vcl.Forms,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.StdCtrls,
  Data.DB,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepoEd.Grid;

type
  /// <summary>One tab: a repository table, its query and its grid.</summary>
  TRepoTab = record
    Table: TRepoTable;
    Query: TFDQuery;
    Grid: TRepoGrid;
  end;

  /// <summary>The editor window over one open repository.</summary>
  /// <remarks>Owns the repository connection and every tab. Main thread only.</remarks>
  TRepoEditorForm = class(TForm)
  private
    FConnection: TFDConnection;
    FFileName: string;
    FPages: TPageControl;
    FStatus: TLabel;
    FTabs: TArray<TRepoTab>;
    procedure BuildChrome;
    procedure ClearTabs;
    procedure AddTab(const pTable: TRepoTable);
    procedure SetStatus(const pText: string);
    procedure OpenClick(pSender: TObject);
    procedure ReloadClick(pSender: TObject);
    procedure SaveClick(pSender: TObject);
    procedure BackupClick(pSender: TObject);
    procedure RestoreClick(pSender: TObject);
    function GetTabCount: Integer;
    function GetTabs(pIndex: Integer): TRepoTab;
  public
    /// <summary>Creates the window chrome (toolbar, tab control); no repository is open yet.</summary>
    /// <param name="pOwner">Owner component, usually Application.</param>
    constructor CreateEditor(pOwner: TComponent);
    destructor Destroy; override;
    /// <summary>Opens a repository file and builds one tab per editable table.</summary>
    /// <param name="pFileName">An existing ".dlrepo" file.</param>
    /// <exception cref="ERepoError">The file is missing or is not a repository.</exception>
    /// <remarks>Replaces any repository that was open; unsaved edits of it are discarded.</remarks>
    procedure OpenRepo(const pFileName: string);
    /// <summary>Posts and applies every pending edit of every tab.</summary>
    /// <exception cref="ERepoError">A tab reported failed updates; nothing is silently dropped.</exception>
    procedure SaveChanges;
    /// <summary>Discards unsaved edits and re-reads every tab from the file.</summary>
    procedure ReloadAll;
    /// <summary>Number of tabs (4 for an open repository, 0 before OpenRepo).</summary>
    property TabCount: Integer read GetTabCount;
    /// <summary>Tab by zero-based index.</summary>
    property Tabs[pIndex: Integer]: TRepoTab read GetTabs;
    /// <summary>The open connection (nil before OpenRepo).</summary>
    property Connection: TFDConnection read FConnection;
  end;

implementation

uses
  System.UITypes,
  Vcl.Controls,
  Vcl.Dialogs,
  DRagLint.FieldRepo.TextBackup;

const
  CAPTION_TEXT = 'drag-lint field repository';
  FORM_WIDTH = 1000;
  FORM_HEIGHT = 640;
  BTN_WIDTH = 120;
  BTN_PAD = 4;
  BTN_GAP = 8;
  BTN_COUNT = 5;
  BTN_SAVE = 2;
  BTN_BACKUP = 3;
  BTN_RESTORE = 4;
  STATUS_TOP = 9;
  STATUS_WIDTH = 300;
  STATUS_HEIGHT = 16;
  TOOLBAR_HEIGHT = 32;
  TEXT_FILTER = 'Field repository text backup (*.txt)|*.txt|All files (*.*)|*.*';
  REPO_FILTER = 'Field repository (*.dlrepo)|*.dlrepo|All files (*.*)|*.*';

function IsEditableTable(const pTable: TRepoTable): Boolean;
begin
  Result := not (SameText(pTable.Name, REPO_META_TABLE) or SameText(pTable.Name, REPO_TABLE_LAYOUT_EVENTS)
    or SameText(pTable.Name, REPO_TABLE_EXCEPTIONS)); { schema-2 tables are edited through repo verbs, not as tabs }
end;

constructor TRepoEditorForm.CreateEditor(pOwner: TComponent);
begin
  inherited CreateNew(pOwner);
  Caption := CAPTION_TEXT;
  Width := FORM_WIDTH;
  Height := FORM_HEIGHT;
  Position := poScreenCenter;
  BuildChrome;
end;

destructor TRepoEditorForm.Destroy;
begin
  ClearTabs;
  FreeAndNil(FConnection);
  inherited;
end;

procedure TRepoEditorForm.BuildChrome;
  procedure AddButton(const pCaption: string; pIndex: Integer; pPanel: TPanel;
    pHandler: TNotifyEvent);
  var
    Btn: TButton;
  begin
    Btn := TButton.Create(pPanel);  // dl:ok object-leak@2c5c -- owned by pPanel, freed with the form
    Btn.Parent := pPanel;
    Btn.Caption := pCaption;
    Btn.SetBounds(pIndex * BTN_WIDTH, BTN_PAD, BTN_WIDTH - BTN_GAP, TOOLBAR_HEIGHT - BTN_GAP);
    Btn.OnClick := pHandler;
  end;
var
  Bar: TPanel;
begin
  Bar := TPanel.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := TOOLBAR_HEIGHT;
  Bar.BevelOuter := bvNone;
  AddButton('Open...', 0, Bar, OpenClick);
  AddButton('Reload', 1, Bar, ReloadClick);
  AddButton('Save changes', BTN_SAVE, Bar, SaveClick);
  AddButton('Backup to text...', BTN_BACKUP, Bar, BackupClick);
  AddButton('Restore from text...', BTN_RESTORE, Bar, RestoreClick);
  FStatus := TLabel.Create(Bar);
  FStatus.Parent := Bar;
  FStatus.SetBounds(BTN_WIDTH * BTN_COUNT + BTN_GAP, STATUS_TOP, STATUS_WIDTH, STATUS_HEIGHT);
  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
end;

procedure TRepoEditorForm.ClearTabs;
var
  I: Integer;
begin
  for I := High(FTabs) downto 0 do
    FTabs[I].Query.Close;
  for I := FPages.PageCount - 1 downto 0 do
    FPages.Pages[I].Free;
  FTabs := nil;
end;

procedure TRepoEditorForm.AddTab(const pTable: TRepoTable);
var
  Sheet: TTabSheet;
  Source: TDataSource;
  Keys: TArray<string>;
  Pk: TRepoColumn;
  Tab: TRepoTab;
begin
  Sheet := TTabSheet.Create(FPages);
  Sheet.PageControl := FPages;
  Sheet.Caption := pTable.Name;
  Tab.Table := pTable;
  Tab.Query := TFDQuery.Create(Sheet);
  Tab.Query.Connection := FConnection;
  // The repository keeps trailing blanks; a trimming reader would lose them on every save.
  Tab.Query.FormatOptions.StrsTrim := False;
  Tab.Query.SQL.Text := 'SELECT * FROM ' + QuoteRepoIdent(pTable.Name);
  Tab.Query.CachedUpdates := True;
  Tab.Query.UpdateOptions.UpdateTableName := QuoteRepoIdent(pTable.Name);
  Keys := nil;
  for Pk in pTable.PkColumns do
    Keys := Keys + [Pk.Name];
  Tab.Query.UpdateOptions.KeyFields := string.Join(';', Keys);
  Tab.Query.UpdateOptions.UpdateMode := upWhereKeyOnly;
  Tab.Query.Open;
  Source := TDataSource.Create(Sheet);
  Source.DataSet := Tab.Query;
  Tab.Grid := CreateRepoGrid(Sheet, Sheet, Source);
  FTabs := FTabs + [Tab];
end;

procedure TRepoEditorForm.OpenRepo(const pFileName: string);
var
  Table: TRepoTable;
  Fresh: TFDConnection;
begin
  Fresh := OpenRepository(pFileName, False);
  ClearTabs;
  FreeAndNil(FConnection);
  FConnection := Fresh;
  FFileName := pFileName;
  for Table in RepoTablesFor(RepoSchemaVersion(FConnection)) do
    if IsEditableTable(Table) then
      AddTab(Table);
  Caption := CAPTION_TEXT + ' - ' + pFileName;
  SetStatus(Format('%d tables', [Length(FTabs)]));
end;

procedure TRepoEditorForm.SaveChanges;
var
  Tab: TRepoTab;
  Errors: Integer;
begin
  for Tab in FTabs do
  begin
    if Tab.Query.State in dsEditModes then
      Tab.Query.Post;
    if Tab.Query.UpdatesPending then
    begin
      Errors := Tab.Query.ApplyUpdates(0);
      if Errors > 0 then
        raise ERepoError.CreateFmt('%s: %d row(s) could not be saved', [Tab.Table.Name, Errors]);
      Tab.Query.CommitUpdates;
    end;
  end;
  SetStatus('saved');
end;

procedure TRepoEditorForm.ReloadAll;
var
  Tab: TRepoTab;
begin
  for Tab in FTabs do
  begin
    Tab.Query.Close;
    Tab.Query.Open;
  end;
  SetStatus('reloaded');
end;

procedure TRepoEditorForm.SetStatus(const pText: string);
begin
  FStatus.Caption := pText;
end;

function TRepoEditorForm.GetTabCount: Integer;
begin
  Result := Length(FTabs);
end;

function TRepoEditorForm.GetTabs(pIndex: Integer): TRepoTab;
begin
  Result := FTabs[pIndex];
end;

procedure TRepoEditorForm.OpenClick(pSender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := REPO_FILTER;
    Dlg.FileName := FFileName;
    if Dlg.Execute then
      OpenRepo(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TRepoEditorForm.ReloadClick(pSender: TObject);
begin
  ReloadAll;
end;

procedure TRepoEditorForm.SaveClick(pSender: TObject);
begin
  SaveChanges;
end;

procedure TRepoEditorForm.BackupClick(pSender: TObject);
var
  Dlg: TSaveDialog;
begin
  SaveChanges;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := TEXT_FILTER;
    Dlg.DefaultExt := 'txt';
    Dlg.FileName := ChangeFileExt(FFileName, '.txt');
    if Dlg.Execute then
    begin
      BackupRepository(FConnection, Dlg.FileName);
      SetStatus('backup written');
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TRepoEditorForm.RestoreClick(pSender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := TEXT_FILTER;
    if Dlg.Execute and (MessageDlg('Restore replaces ALL rows of the repository with the text file. Continue?',
      mtConfirmation, [mbYes, mbNo], 0) = mrYes) then
    begin
      RestoreRepository(FConnection, Dlg.FileName, True);
      ReloadAll;
      SetStatus('restored');
    end;
  finally
    Dlg.Free;
  end;
end;

end.
