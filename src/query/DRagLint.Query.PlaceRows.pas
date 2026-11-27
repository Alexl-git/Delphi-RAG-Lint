unit DRagLint.Query.PlaceRows;

{ drag-lint 1.56 -- lane TS-N: the place of every search row (SPEC-SEARCH 1.2-1.6): `place` on the rows of `query --name`, `query --text` and `find-unit`, the repository rows repo-field / repo-table, the --place <list> filter and the note lines.
  DRagLint.CLI parses --place into TArgs.Place (W2FRAME); the routines DoQuery, DoQueryText and DoFindUnit (lane TS-N) call into this unit.
  The repository place is the COPY of the field repository inside the project index (concept_fields / concept_texts / repo_copy, lane CON-I); the live repository file is only STATed, never opened.
  Design: docs\superpowers\specs\2026-11-27-three-place-search-caption-concepts-design.md (1.1-1.6). }

interface

uses
  System.JSON, DRagLint.Core.Model;

type
  /// <summary>The three places of a search (design 1.1), in the order their rows are printed.</summary>
  TSearchPlace = (spProject, spRepository, spLibrary);

  /// <summary>A set of places.</summary>
  TSearchPlaces = set of TSearchPlace;

  /// <summary>One repository row of `query --name`: a field (repo-field) or a table (repo-table) of the repository copy.</summary>
  TRepoNameRow = record
    /// <summary>repo-field or repo-table.</summary>
    Kind: string;
    /// <summary>FIELD_NAME, or the table name for a repo-table row.</summary>
    Name: string;
    /// <summary>TABLE.FIELD, or TABLE.</summary>
    QName: string;
    /// <summary>The field's repository caption; '' for a table.</summary>
    Caption: string;
    /// <summary>The field's type text; '' for a table.</summary>
    TypeText: string;
    /// <summary>The repository file the copy was made from.</summary>
    RepoPath: string;
  end;

/// <summary>Parses a --place list.</summary>
/// <param name="pList">Comma-separated subset of library, project, repository; '' = all three.</param>
/// <param name="pPlaces">The places named.</param>
/// <returns>False when a value is unknown or the list names none; the caller prints the usage error and exits 2.</returns>
function ParsePlaces(const pList: string; out pPlaces: TSearchPlaces): Boolean;

/// <summary>The usage line of an unknown --place value (design 1.3).</summary>
function PlaceUsageError: string;

/// <summary>The place a resolved database answers for: library-*.sqlite is the library, any other is the project.</summary>
function PlaceOfDb(const pDb: string): TSearchPlace;

/// <summary>The text of a place: project, repository or library.</summary>
function PlaceName(pPlace: TSearchPlace): string;

/// <summary>A stable print order for rows: project, repository, library, today's order inside a place.</summary>
/// <param name="pPlaces">The place name of every row, in today's order.</param>
/// <returns>The indexes of pPlaces in print order.</returns>
function PlaceSortOrder(const pPlaces: TArray<string>): TArray<Integer>;

/// <summary>The databases of pDbs whose place is in pPlaces, order kept.</summary>
function FilterDbsByPlaces(const pDbs: TArray<string>; pPlaces: TSearchPlaces): TArray<string>;

/// <summary>Repository rows of `query --name`: a table named pName (repo-table) or fields named pName (repo-field), exact, case-insensitive; a dotted name is TABLE.FIELD.</summary>
/// <param name="pDbs">The resolved databases; the first project one answers.</param>
/// <param name="pName">The --name value.</param>
/// <param name="pKinds">The --kind value (comma-separated); '' = every kind.</param>
/// <returns>The rows; empty when the index has no repository copy.</returns>
/// <remarks>Read-only; any failure to open or read the copy answers no rows.</remarks>
function RepoNameRows(const pDbs: TArray<string>; const pName, pKinds: string): TArray<TRepoNameRow>;

/// <summary>Repository rows of `query --text`: concept_texts of place repository that match the phrase.</summary>
/// <param name="pDbs">The resolved databases; the first project one answers.</param>
/// <param name="pPhrase">The --text value.</param>
/// <param name="pMode">phrase, anyorder or substring (matched case-insensitively as a substring; anyorder = every word).</param>
/// <param name="pSource">--source; only '' and 'repo' let repository rows through.</param>
/// <param name="pKinds">--kind: text kinds (caption, hint, ...); '' = all.</param>
/// <param name="pLimit">Row cap.</param>
/// <returns>String-literal matches with Source = repo, StartLine = 0 and FilePath = the repository file.</returns>
function RepoTextRows(const pDbs: TArray<string>; const pPhrase, pMode, pSource, pKinds: string; pLimit: Integer): TArray<TStringLitMatch>;

/// <summary>The JSON object of a repository `--name` row (same keys as a symbol row, id 0, start_line 0).</summary>
/// <returns>A new object; the caller owns it.</returns>
function RepoNameRowJson(const pRow: TRepoNameRow): TJSONObject;

/// <summary>The text line of a repository `--name` row, without the place token.</summary>
function RepoNameRowText(const pRow: TRepoNameRow): string;

/// <summary>Appends the JSON objects of repository `--name` rows to a result array.</summary>
procedure AppendRepoRowsJson(pArr: TJSONArray; const pRows: TArray<TRepoNameRow>);

/// <summary>Prints repository `--name` rows as text lines, each ending in the token place=repository.</summary>
procedure PrintRepoRowsText(const pRows: TArray<TRepoNameRow>);

/// <summary>Prints the note lines of a name / text / find-unit run to STDERR (design 1.6): the one repository line and `library: not configured`.</summary>
/// <param name="pDbs">All resolved databases.</param>
/// <param name="pPlaces">The places wanted (--place); a narrowed-out place prints nothing.</param>
/// <param name="pProjectFile">The --project file for the refresh command; '' = a placeholder.</param>
/// <param name="pHasRepoRow">True when at least one row of place repository is printed.</param>
/// <param name="pRepoNote">False for find-unit: a repository declares no unit, so it prints no repository line.</param>
procedure PrintPlaceNotes(const pDbs: TArray<string>; pPlaces: TSearchPlaces; const pProjectFile: string;
  pHasRepoRow, pRepoNote: Boolean);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.DateUtils, System.StrUtils,
  Data.DB, FireDAC.Stan.Param, FireDAC.Comp.Client,
  DRagLint.Core.Interfaces, DRagLint.Storage.SQLite;

const
  PLACE_TEXTS: array[TSearchPlace] of string = ('project', 'repository', 'library');
  LIBRARY_DB_PREFIX = 'library-';
  KIND_REPO_FIELD = 'repo-field';
  KIND_REPO_TABLE = 'repo-table';
  SOURCE_REPO = 'repo';
  STATE_COPIED = 'copied';
  STATE_NOT_CONFIGURED = 'not-configured';
  STATE_MISSING = 'missing';
  STATE_UNREADABLE = 'unreadable';
  STATE_NOT_COPIED_YET = 'not-copied-yet';
  META_SCAN_TYPE = 'scan_type';
  SCAN_PROJECT = 'project';
  SQL_WILDCARDS = '%_\';

function ParsePlaces(const pList: string; out pPlaces: TSearchPlaces): Boolean;
var
  Item: string;
  P: TSearchPlace;
  Found: Boolean;
begin
  Result:= True;
  pPlaces:= [spProject, spRepository, spLibrary];
  if Trim(pList) = '' then Exit;
  pPlaces:= [];
  for Item in pList.Split([',']) do
  begin
    Found:= False;
    for P:= Low(TSearchPlace) to High(TSearchPlace) do
      if SameText(Trim(Item), PLACE_TEXTS[P]) then
      begin
        Include(pPlaces, P);
        Found:= True;
      end;
    if not Found then Result:= False;
  end;
  if pPlaces = [] then Result:= False;
end; // function

function PlaceUsageError: string;
begin
  Result:= 'ERROR: --place accepts library, project, repository';
end; // function

function PlaceOfDb(const pDb: string): TSearchPlace;
begin
  if StartsText(LIBRARY_DB_PREFIX, ExtractFileName(pDb)) then Result:= spLibrary
  else Result:= spProject;
end; // function

function PlaceName(pPlace: TSearchPlace): string;
begin
  Result:= PLACE_TEXTS[pPlace];
end; // function

function PlaceSortOrder(const pPlaces: TArray<string>): TArray<Integer>;
var
  P: TSearchPlace;
  I: Integer;
begin
  Result:= nil;
  for P:= Low(TSearchPlace) to High(TSearchPlace) do
    for I:= 0 to High(pPlaces) do
      if SameText(pPlaces[I], PLACE_TEXTS[P]) then Result:= Result + [I];
end; // function

function FilterDbsByPlaces(const pDbs: TArray<string>; pPlaces: TSearchPlaces): TArray<string>;
var
  Db: string;
begin
  Result:= nil;
  for Db in pDbs do
    if PlaceOfDb(Db) in pPlaces then Result:= Result + [Db];
end; // function

{ The first project database of the list that exists; '' when none. }
function FirstProjectDb(const pDbs: TArray<string>): string;
var
  Db: string;
begin
  for Db in pDbs do
    if (PlaceOfDb(Db) = spProject) and TFile.Exists(Db) then Exit(Db);
  Result:= '';
end; // function

function KindListed(const pKinds, pKind: string): Boolean;
var
  Item: string;
begin
  if Trim(pKinds) = '' then Exit(True);
  for Item in pKinds.Split([',']) do
    if SameText(Trim(Item), pKind) then Exit(True);
  Result:= False;
end; // function

{ Opens pDb read-only and runs pWork with its connection; a store that cannot be opened or read answers nothing. }
procedure WithCopy(const pDb: string; const pWork: TProc<TFDConnection>);
var
  StoreObj: TSQLiteSymbolStore;
  Store: ISymbolStore;
begin
  try
    StoreObj:= TSQLiteSymbolStore.Create(pDb, {AReadOnly=}True);
    Store:= StoreObj;
    if not Store.HasConceptTables then Exit;
    pWork(StoreObj.GetConnection);
  except // dl:ok try-except-swallowed@767f -- a copy that cannot be read answers no repository rows; the note line says why
    on Exception do ; // dl:ok empty-on-handler@17b2 -- same: the repository place answers nothing, the verb's own places still answer
  end; // try
end; // procedure

function RepoPathOf(pConn: TFDConnection): string;
var
  Q: TFDQuery;
begin
  Result:= '';
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= pConn;
    Q.Open('SELECT repo_path FROM repo_copy WHERE id = 1');
    if not Q.Eof then Result:= Q.FieldByName('repo_path').AsString;
  finally
    Q.Free;
  end; // try
end; // function

function RepoNameRows(const pDbs: TArray<string>; const pName, pKinds: string): TArray<TRepoNameRow>;
var
  Db: string;
  Rows: TArray<TRepoNameRow>;
begin
  Result:= nil;
  Db:= FirstProjectDb(pDbs);
  if (Db = '') or (Trim(pName) = '') then Exit;
  Rows:= nil;
  WithCopy(Db,
    procedure(pConn: TFDConnection)
    var
      Q: TFDQuery;
      Row: TRepoNameRow;
      Path: string;
      Dot: Integer;
      ColTable, ColField, ColCaption, ColType: TField;
    begin
      Path:= RepoPathOf(pConn);
      Dot:= Pos('.', pName);
      Q:= TFDQuery.Create(nil);
      try
        Q.Connection:= pConn;
        if KindListed(pKinds, KIND_REPO_TABLE) and (Dot = 0) then
        begin
          Q.Open('SELECT DISTINCT table_name FROM (SELECT table_name FROM concept_fields UNION ' + // dl:ok path-traversal@fa5e -- SQL text, not a file path
            'SELECT table_name FROM concept_texts WHERE place = ''repository'' AND table_name <> '''') ' +
            'WHERE table_name = :n ORDER BY table_name', [pName]);
          ColTable:= Q.FieldByName('table_name');
          while not Q.Eof do
          begin
            Row:= Default(TRepoNameRow);
            Row.Kind:= KIND_REPO_TABLE;
            Row.Name:= ColTable.AsString;
            Row.QName:= Row.Name;
            Row.RepoPath:= Path;
            Rows:= Rows + [Row];
            Q.Next;
          end;
          Q.Close;
        end;
        if KindListed(pKinds, KIND_REPO_FIELD) then
        begin
          if Dot > 0 then
            Q.Open('SELECT table_name, field_name, caption, type_text FROM concept_fields ' + // dl:ok path-traversal@b2d8 -- SQL text, not a file path
              'WHERE table_name = :t AND field_name = :f ORDER BY table_name, field_name',
              [Copy(pName, 1, Dot - 1), Copy(pName, Dot + 1, MaxInt)])
          else
            Q.Open('SELECT table_name, field_name, caption, type_text FROM concept_fields ' + // dl:ok path-traversal@b2d8 -- SQL text, not a file path
              'WHERE field_name = :f ORDER BY table_name, field_name', [pName]);
          ColTable:= Q.FieldByName('table_name');
          ColField:= Q.FieldByName('field_name');
          ColCaption:= Q.FieldByName('caption');
          ColType:= Q.FieldByName('type_text');
          while not Q.Eof do
          begin
            Row:= Default(TRepoNameRow);
            Row.Kind:= KIND_REPO_FIELD;
            Row.Name:= ColField.AsString;
            Row.QName:= ColTable.AsString + '.' + Row.Name;
            Row.Caption:= ColCaption.AsString;
            Row.TypeText:= ColType.AsString;
            Row.RepoPath:= Path;
            Rows:= Rows + [Row];
            Q.Next;
          end;
        end;
      finally
        Q.Free;
      end; // try
    end);
  Result:= Rows;
end; // function

function EscapeLike(const pText: string): string;
var
  C: Char;
begin
  Result:= '';
  for C in pText do
  begin
    if Pos(C, SQL_WILDCARDS) > 0 then Result:= Result + '\';
    Result:= Result + C;
  end;
end; // function

function RepoTextRows(const pDbs: TArray<string>; const pPhrase, pMode, pSource, pKinds: string; pLimit: Integer): TArray<TStringLitMatch>;
var
  Db: string;
  Rows: TArray<TStringLitMatch>;
  Needle: string;
begin
  Result:= nil;
  Db:= FirstProjectDb(pDbs);
  Needle:= Trim(pPhrase);
  if (Length(Needle) >= 2) and Needle.StartsWith('''') and Needle.EndsWith('''') then
    Needle:= Copy(Needle, 2, Length(Needle) - 2);
  if (Db = '') or (Needle = '') or ((pSource <> '') and not SameText(pSource, SOURCE_REPO)) then Exit;
  Rows:= nil;
  WithCopy(Db,
    procedure(pConn: TFDConnection)
    var
      Q: TFDQuery;
      M: TStringLitMatch;
      Path, Sql: string;
      Words: TArray<string>;
      I: Integer;
      ColKind, ColTable, ColField, ColText: TField;
    begin
      Path:= RepoPathOf(pConn);
      if SameText(pMode, 'anyorder') then Words:= Needle.Split([' ', #9], TStringSplitOptions.ExcludeEmpty)
      else Words:= [Needle];
      Sql:= 'SELECT text_kind, table_name, field_name, text FROM concept_texts WHERE place = ''repository''';
      for I:= 0 to High(Words) do Sql:= Sql + Format(' AND text LIKE :w%d ESCAPE ''\''', [I]);
      Sql:= Sql + ' ORDER BY table_name, field_name, text_kind, text';
      Q:= TFDQuery.Create(nil);
      try
        Q.Connection:= pConn;
        Q.SQL.Text:= Sql;
        for I:= 0 to High(Words) do
          Q.ParamByName('w' + IntToStr(I)).AsString:= '%' + EscapeLike(Words[I]) + '%';
        Q.Open;
        ColKind:= Q.FieldByName('text_kind');
        ColTable:= Q.FieldByName('table_name');
        ColField:= Q.FieldByName('field_name');
        ColText:= Q.FieldByName('text');
        while (not Q.Eof) and (Length(Rows) < pLimit) do
        begin
          if KindListed(pKinds, ColKind.AsString) then
          begin
            M:= Default(TStringLitMatch);
            M.FilePath:= Path;
            M.Source:= SOURCE_REPO;
            M.Kind:= ColKind.AsString;
            M.OwnerName:= ColField.AsString;
            M.Text:= ColText.AsString;
            M.EnclosingQName:= ColTable.AsString;
            if M.OwnerName <> '' then M.EnclosingQName:= M.EnclosingQName + '.' + M.OwnerName;
            Rows:= Rows + [M];
          end;
          Q.Next;
        end;
      finally
        Q.Free;
      end; // try
    end);
  Result:= Rows;
end; // function

function RepoNameRowJson(const pRow: TRepoNameRow): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(0));
  Result.AddPair('match_kind', 'exact');
  Result.AddPair('kind', pRow.Kind);
  Result.AddPair('name', pRow.Name);
  Result.AddPair('qualified_name', pRow.QName);
  Result.AddPair('signature', pRow.TypeText);
  Result.AddPair('caption', pRow.Caption);
  Result.AddPair('file', pRow.RepoPath);
  Result.AddPair('start_line', TJSONNumber.Create(0));
  Result.AddPair('start_col', TJSONNumber.Create(0));
  Result.AddPair('end_line', TJSONNumber.Create(0));
  Result.AddPair('end_col', TJSONNumber.Create(0));
  Result.AddPair('place', PLACE_TEXTS[spRepository]);
end; // function

function RepoNameRowText(const pRow: TRepoNameRow): string;
begin
  Result:= Format('%-12s %-30s %s', [pRow.Kind, pRow.Name, pRow.QName]);
  if pRow.TypeText <> '' then Result:= Result + ' : ' + pRow.TypeText;
  if pRow.RepoPath <> '' then Result:= Result + Format('  (%s:0)', [pRow.RepoPath]);
end; // function

procedure AppendRepoRowsJson(pArr: TJSONArray; const pRows: TArray<TRepoNameRow>);
var
  Row: TRepoNameRow;
begin
  for Row in pRows do pArr.AddElement(RepoNameRowJson(Row));
end; // procedure

procedure PrintRepoRowsText(const pRows: TArray<TRepoNameRow>);
var
  Row: TRepoNameRow;
begin
  for Row in pRows do Writeln(RepoNameRowText(Row) + ' place=' + PLACE_TEXTS[spRepository]);
end; // procedure

{ The one repository note of the run, design 1.6; '' = none. The live file is only STATed. }
function RepoNote(const pDbs: TArray<string>; const pProjectFile: string; pHasRepoRow: Boolean): string;
var
  Db, State, Path, Err, When, Refresh, Tail, ProjectText: string;
  Size, MTime, CopiedAt: Int64;
  DirScan: Boolean;
  StoreObj: TSQLiteSymbolStore;
  Store: ISymbolStore;
  Q: TFDQuery;
begin
  Result:= '';
  Db:= FirstProjectDb(pDbs);
  if Db = '' then Exit;
  State:= STATE_NOT_COPIED_YET;
  Path:= '';
  Err:= '';
  Size:= 0;
  MTime:= 0;
  CopiedAt:= 0;
  DirScan:= True;
  try
    StoreObj:= TSQLiteSymbolStore.Create(Db, {AReadOnly=}True);
    Store:= StoreObj;
    DirScan:= not SameText(Store.GetMetaValue(META_SCAN_TYPE), SCAN_PROJECT);
    if Store.HasConceptTables then
    begin
      Q:= TFDQuery.Create(nil);
      try
        Q.Connection:= StoreObj.GetConnection;
        Q.Open('SELECT state, repo_path, repo_size, repo_mtime_unix, copied_at_unix, last_error FROM repo_copy WHERE id = 1');
        if not Q.Eof then
        begin
          State:= Q.FieldByName('state').AsString;
          Path:= Q.FieldByName('repo_path').AsString;
          Size:= Q.FieldByName('repo_size').AsLargeInt;
          MTime:= Q.FieldByName('repo_mtime_unix').AsLargeInt;
          CopiedAt:= Q.FieldByName('copied_at_unix').AsLargeInt;
          Err:= Q.FieldByName('last_error').AsString;
        end;
      finally
        Q.Free;
      end; // try
    end;
  except // dl:ok try-except-swallowed@a25a -- an unreadable index prints no repository note; the verb's own open reports it
    on Exception do Exit;
  end; // try
  ProjectText:= if pProjectFile = '' then '<X.dproj>' else pProjectFile;
  Refresh:= Format('drag-lint index --project %s --db %s', [ProjectText, Db]);
  When:= FormatDateTime('yyyy-mm-dd hh:nn', UnixToDateTime(CopiedAt, False));
  if (State = STATE_NOT_COPIED_YET) and DirScan then
    Result:= 'repository: not copied (this index was made by a directory scan and has no project file); ' +
      'repository hits need a project index: drag-lint index --project ' + ProjectText
  else if State = STATE_NOT_COPIED_YET then
    Result:= 'repository: not copied yet (index made before 1.56); run: ' + Refresh
  else if State = STATE_NOT_CONFIGURED then
    Result:= 'repository: not configured'
  else if State = STATE_MISSING then
    Result:= 'repository: not found at index time: ' + Path
  else if State = STATE_UNREADABLE then
  begin
    Tail:= if CopiedAt > 0 then 'the copy from ' + When + ' is used' else 'no copy';
    Result:= Format('repository: not readable at index time: %s (%s); %s', [Path, Err, Tail]);
  end
  else if State = STATE_COPIED then
  begin
    if not TFile.Exists(Path) then
      Result:= Format('repository: copy from %s; %s no longer exists', [When, Path])
    else if (TFile.GetSize(Path) <> Size)
      or (DateTimeToUnix(TFile.GetLastWriteTimeUtc(Path), True) <> MTime) then
      Result:= Format('repository: copy from %s is stale (%s changed since); refresh: %s', [When, Path, Refresh])
    else if pHasRepoRow then
      Result:= Format('repository: copy from %s of %s', [When, Path]);
  end;
end; // function

procedure PrintPlaceNotes(const pDbs: TArray<string>; pPlaces: TSearchPlaces; const pProjectFile: string;
  pHasRepoRow, pRepoNote: Boolean);
var
  Db, Note: string;
  HasLibrary: Boolean;
begin
  if pRepoNote and (spRepository in pPlaces) then
  begin
    Note:= RepoNote(pDbs, pProjectFile, pHasRepoRow);
    if Note <> '' then Writeln(ErrOutput, Note);
  end;
  if spLibrary in pPlaces then
  begin
    HasLibrary:= False;
    for Db in pDbs do
      if (PlaceOfDb(Db) = spLibrary) and TFile.Exists(Db) then HasLibrary:= True;
    if not HasLibrary then Writeln(ErrOutput, 'library: not configured');
  end;
end; // procedure

end.
