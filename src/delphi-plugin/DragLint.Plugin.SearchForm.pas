unit DragLint.Plugin.SearchForm;

{ Unified Search dock tab: Kind (Symbol/Text/Usages) + query + one flat grid.
  Spawns drag-lint --json, parses via SearchParse, fills a TListView, jumps to
  source on activate. Never shows raw JSON / debug. }

interface

uses
  System.Classes, Vcl.Controls;

/// <summary>Build the Search UI into AParent (a dock tab). Controls are owned
/// by AOwner so they live/die with the dock frame.</summary>
procedure CreateEmbeddedSearch(AOwner: TComponent; AParent: TWinControl);

implementation

uses
  System.SysUtils, System.Generics.Collections,
  Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, Winapi.Windows,
  DragLint.Plugin.ProcRun, DragLint.Plugin.SearchParse,
  DragLint.Plugin.HoverForm, DragLint.Plugin.DbResolver, DragLint.Plugin.Settings;

type
  TSearchHandler = class(TComponent)
  public
    FKind      : TComboBox ;
    FQuery     : TEdit     ;
    FBtn       : TButton   ;
    FAdvChk    : TCheckBox ;
    FAdvPanel  : TPanel    ;
    FKindFilter: TComboBox ;
    FTextMode  : TComboBox ;
    FTextSource: TComboBox ;
    FWidth     : TComboBox ;
    FList      : TListView ;
    FStatus    : TLabel    ;
    FDebounce  : TTimer    ;
    FRows      : TSearchRows;
    function ResolveExe: string;
    function DbArgs: string;
    function CurrentKind: string;
    procedure Reconfigure;
    procedure RebuildColumns;
    procedure RunSearch;
    procedure Fill(const ARows: TSearchRows);
    procedure SetEmpty(const AMsg: string);
    procedure KindChange(Sender: TObject);
    procedure AdvChange(Sender: TObject);
    procedure QueryKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure QueryChange(Sender: TObject);
    procedure DebounceFired(Sender: TObject);
    procedure BtnClick(Sender: TObject);
    procedure ListActivate(Sender: TObject);
  end;

function TSearchHandler.ResolveExe: string;
begin
  Result:= LoadSettings.ExePath;
  if (Result = '') or not FileExists(Result) then Result:= ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(Result) then Result:= 'drag-lint.exe';
end;

function TSearchHandler.DbArgs: string;
var Dbs: TArray<string>; P: string;
begin
  Result:= '';
  try Dbs:= ResolveActiveIndexDbs(LoadSettings); except SetLength(Dbs, 0); end;
  for P in Dbs do if P <> '' then Result:= Result + Format(' --db "%s"', [P]);
end;

function TSearchHandler.CurrentKind: string;
begin
  case FKind.ItemIndex of
    1: Result:= 'Text';
    2: Result:= 'Usages';
    else Result:= 'Symbol';
  end;
end;

procedure TSearchHandler.Reconfigure;
var K: string;
begin
  K:= CurrentKind;
  FKindFilter.Visible:= (K = 'Symbol');
  FTextMode  .Visible:= (K = 'Text');
  FTextSource.Visible:= (K = 'Text');
  FWidth     .Visible:= (K = 'Usages');
end;

procedure TSearchHandler.RebuildColumns;
  procedure Cols(const A, B, C: string);
  var col: TListColumn;
  begin
    FList.Columns.Clear;
    col:= FList.Columns.Add; col.Caption:= A; col.Width:= 90;
    col:= FList.Columns.Add; col.Caption:= B; col.Width:= 280;
    col:= FList.Columns.Add; col.Caption:= C; col.Width:= 260;
  end;
begin
  if CurrentKind = 'Symbol' then Cols('Kind', 'Name', 'Location')
  else if CurrentKind = 'Text' then Cols('Source', 'Text', 'Location')
  else Cols('Category', 'Detail', 'Location');
end;

procedure TSearchHandler.SetEmpty(const AMsg: string);
begin
  FStatus.Caption:= AMsg;
end;

procedure TSearchHandler.Fill(const ARows: TSearchRows);
var i: Integer; it: TListItem;
begin
  FRows:= ARows;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for i:= 0 to High(ARows) do
    begin
      it:= FList.Items.Add;
      if CurrentKind = 'Symbol' then begin it.Caption:= ARows[i].ColB; it.SubItems.Add(ARows[i].ColA); end
      else if CurrentKind = 'Text' then begin it.Caption:= ARows[i].ColB; it.SubItems.Add(ARows[i].ColA); end
      else begin it.Caption:= ARows[i].Category; it.SubItems.Add(ARows[i].ColA); end;
      if ARows[i].Line > 0 then it.SubItems.Add(Format('%s:%d', [ExtractFileName(ARows[i].FilePath), ARows[i].Line]))
      else it.SubItems.Add('');
      it.Data:= Pointer(i);
    end;
  finally
    FList.Items.EndUpdate;
  end;
end;

procedure TSearchHandler.RunSearch;
var
  Exe, Cmd, Outp, K, Q: string; ExitCode: Integer; Rows: TSearchRows;
begin
  Q:= Trim(FQuery.Text);
  if Q = '' then begin FList.Items.Clear; SetEmpty('Type to search.'); Exit; end;
  Exe:= ResolveExe;
  K:= CurrentKind;
  RebuildColumns;
  SetEmpty('Searching.');

  if K = 'Symbol' then
    Cmd:= Format('"%s" query --name "%s"%s --json', [Exe, Q, DbArgs])
  else if K = 'Text' then
  begin
    Cmd:= Format('"%s" query --text "%s"', [Exe, Q]);
    case FTextMode.ItemIndex of 1: Cmd:= Cmd + ' --substring'; 2: Cmd:= Cmd + ' --any-order'; end;
    if FTextSource.ItemIndex > 0 then Cmd:= Cmd + ' --source ' + LowerCase(FTextSource.Text);
    Cmd:= Cmd + DbArgs + ' --json';
  end
  else
  begin
    Cmd:= Format('"%s" usages --name "%s" --width %s%s --format json',
      [Exe, Q, LowerCase(StringReplace(FWidth.Text, ' ', '-', [rfReplaceAll])), DbArgs]);
  end;

  if K = 'Usages' then ExitCode:= RunCaptureStdout(Cmd, Outp, 30000)
  else ExitCode:= RunCaptureStdout(Cmd, Outp, 15000);
  Outp:= Trim(Outp);

  if ExitCode < 0 then begin FList.Items.Clear; SetEmpty('drag-lint not found or failed to start'); Exit; end;
  if (Outp = '') or (not (CharInSet(Outp[1], ['[', '{']))) then
  begin
    FList.Items.Clear;
    if Copy(Outp, 1, 5) = 'ERROR' then SetEmpty('drag-lint error: ' + Copy(Outp, 1, 200))
    else SetEmpty(Format('drag-lint error (exit %d)', [ExitCode]));
    Exit;
  end;

  if K = 'Symbol' then
  begin
    Rows:= ParseNameJson(Outp);
    if FKindFilter.ItemIndex > 0 then
    begin
      var Keep: TList<TSearchRow>:= TList<TSearchRow>.Create;
      try
        for var R in Rows do if KindMatchesFilter(R.ColB, FKindFilter.Text) then Keep.Add(R);
        Rows:= Keep.ToArray;
      finally Keep.Free; end;
    end;
  end
  else if K = 'Text' then Rows:= ParseTextJson(Outp)
  else Rows:= ParseUsagesJson(Outp);

  Fill(Rows);
  if Length(Rows) = 0 then
  begin
    if Trim(DbArgs) = '' then SetEmpty('No project index found - run Tools > drag-lint > Lint Buffer, or set the exe/DB in settings.')
    else if (K = 'Symbol') then SetEmpty(Format('No matches for "%s"  -  drag-lint indexes types/methods/fields/consts, not locals or parameters.', [Q]))
    else if (K = 'Text') and (FTextMode.ItemIndex = 1) and (Length(Q) < 3) then SetEmpty('--substring needs >= 3 characters; try Any-word.')
    else SetEmpty(Format('No matches for "%s"', [Q]));
  end
  else SetEmpty(Format('%d result(s)', [Length(Rows)]));
end;

procedure TSearchHandler.KindChange(Sender: TObject);
begin Reconfigure; RebuildColumns; if Trim(FQuery.Text) <> '' then RunSearch; end;

procedure TSearchHandler.AdvChange(Sender: TObject);
begin FAdvPanel.Visible:= FAdvChk.Checked; end;

procedure TSearchHandler.QueryKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin if Key = VK_RETURN then begin Key:= 0; RunSearch; end; end;

procedure TSearchHandler.QueryChange(Sender: TObject);
begin
  if CurrentKind = 'Symbol' then begin FDebounce.Enabled:= False; FDebounce.Enabled:= True; end;
end;

procedure TSearchHandler.DebounceFired(Sender: TObject);
begin FDebounce.Enabled:= False; if CurrentKind = 'Symbol' then RunSearch; end;

procedure TSearchHandler.BtnClick(Sender: TObject);
begin RunSearch; end;

procedure TSearchHandler.ListActivate(Sender: TObject);
var idx: Integer;
begin
  if FList.Selected = nil then Exit;
  idx:= Integer(FList.Selected.Data);
  if (idx < 0) or (idx > High(FRows)) then Exit;
  if (FRows[idx].FilePath <> '') and (FRows[idx].Line > 0) then OpenSourceAt(FRows[idx].FilePath, FRows[idx].Line);
end;

procedure CreateEmbeddedSearch(AOwner: TComponent; AParent: TWinControl);
var H: TSearchHandler; Pnl: TPanel;
begin
  H:= TSearchHandler.Create(AOwner);

  // toolbar row
  Pnl:= TPanel.Create(AOwner); Pnl.Parent:= AParent; Pnl.Align:= alTop; Pnl.Height:= 28; Pnl.BevelOuter:= bvNone;
  H.FKind:= TComboBox.Create(AOwner); H.FKind.Parent:= Pnl; H.FKind.Align:= alLeft; H.FKind.Width:= 90; H.FKind.Style:= csDropDownList;
  H.FKind.Items.Add('Symbol'); H.FKind.Items.Add('Text'); H.FKind.Items.Add('Usages'); H.FKind.ItemIndex:= 0;
  H.FKind.OnChange:= H.KindChange;
  H.FAdvChk:= TCheckBox.Create(AOwner); H.FAdvChk.Parent:= Pnl; H.FAdvChk.Align:= alRight; H.FAdvChk.Width:= 90; H.FAdvChk.Caption:= 'Advanced'; H.FAdvChk.OnClick:= H.AdvChange;
  H.FBtn:= TButton.Create(AOwner); H.FBtn.Parent:= Pnl; H.FBtn.Align:= alRight; H.FBtn.Width:= 70; H.FBtn.Caption:= 'Search'; H.FBtn.OnClick:= H.BtnClick;
  H.FQuery:= TEdit.Create(AOwner); H.FQuery.Parent:= Pnl; H.FQuery.Align:= alClient; H.FQuery.TextHint:= 'type, then Enter';
  H.FQuery.OnKeyDown:= H.QueryKeyDown; H.FQuery.OnChange:= H.QueryChange;

  // advanced row (hidden by default)
  H.FAdvPanel:= TPanel.Create(AOwner); H.FAdvPanel.Parent:= AParent; H.FAdvPanel.Align:= alTop; H.FAdvPanel.Height:= 28; H.FAdvPanel.BevelOuter:= bvNone; H.FAdvPanel.Visible:= False;
  H.FKindFilter:= TComboBox.Create(AOwner); H.FKindFilter.Parent:= H.FAdvPanel; H.FKindFilter.Align:= alLeft; H.FKindFilter.Width:= 110; H.FKindFilter.Style:= csDropDownList;
  for var s in ['Any','Method','Type/Class','Field/Var','Const','Property','Unit'] do H.FKindFilter.Items.Add(s);
  H.FKindFilter.ItemIndex:= 0; H.FKindFilter.OnChange:= H.AdvChange;
  H.FTextMode:= TComboBox.Create(AOwner); H.FTextMode.Parent:= H.FAdvPanel; H.FTextMode.Align:= alLeft; H.FTextMode.Width:= 100; H.FTextMode.Style:= csDropDownList;
  for var s in ['Phrase','Substring','Any-word'] do H.FTextMode.Items.Add(s); H.FTextMode.ItemIndex:= 0;
  H.FTextSource:= TComboBox.Create(AOwner); H.FTextSource.Parent:= H.FAdvPanel; H.FTextSource.Align:= alLeft; H.FTextSource.Width:= 90; H.FTextSource.Style:= csDropDownList;
  for var s in ['All','pas','dfm','sql'] do H.FTextSource.Items.Add(s); H.FTextSource.ItemIndex:= 0;
  H.FWidth:= TComboBox.Create(AOwner); H.FWidth.Parent:= H.FAdvPanel; H.FWidth.Align:= alLeft; H.FWidth.Width:= 100; H.FWidth.Style:= csDropDownList;
  for var s in ['Narrow','Wide','Very wide'] do H.FWidth.Items.Add(s); H.FWidth.ItemIndex:= 0;

  // status + grid
  H.FStatus:= TLabel.Create(AOwner); H.FStatus.Parent:= AParent; H.FStatus.Align:= alBottom; H.FStatus.Layout:= tlCenter; H.FStatus.Height:= 18; H.FStatus.Caption:= 'Type to search.';
  H.FList:= TListView.Create(AOwner); H.FList.Parent:= AParent; H.FList.Align:= alClient; H.FList.ViewStyle:= vsReport; H.FList.ReadOnly:= True; H.FList.RowSelect:= True; H.FList.HideSelection:= False;
  H.FList.OnDblClick:= H.ListActivate;

  H.FDebounce:= TTimer.Create(H); H.FDebounce.Interval:= 300; H.FDebounce.Enabled:= False; H.FDebounce.OnTimer:= H.DebounceFired;

  H.Reconfigure; H.RebuildColumns;
end;

end.
