unit DRagLint.Query.ConceptRepo;

{ drag-lint 1.56 -- lane CON-Q: `query --concept` over three places: the project index (symbols by
  identifier words / doc prose, as 1.55), the COPY of the field repository that `index --project`
  puts into the project index (DRagLint.Index.RepoCopy: captions, display labels, grid column
  captions, hints, table descriptions, and the links field -> persistent fields / grid columns /
  edit controls / code) and the platform library index. Every hit carries its place.
  DRagLint.CLI.DoQueryConcept calls TryRunConceptRepoQuery in ONE line, before its own 1.55 search.
  This unit runs its own SQL; it adds nothing to the store interface.
  Design: docs\superpowers\specs\2026-11-27-three-place-search-caption-concepts-design.md
  (1.3 --place, 1.6 notes, 2.6 shape, 2.7 ranking, 2.8 links).
  Scaffold created by lane FRAME-1; lane CON-Q owns this unit. }

interface

type
  /// <summary>One `query --concept` request, as DRagLint.CLI parsed it.</summary>
  TConceptRepoQuery = record
    /// <summary>The project index (an existing .sqlite file), the first resolved --db.</summary>
    DbPath: string;
    /// <summary>The --concept words; not empty.</summary>
    Words: string;
    /// <summary>The --kind value (comma-separated); '' = every kind. Symbol kinds plus
    /// repo-field, repo-table, dfm-caption.</summary>
    Kinds: string;
    /// <summary>Row cap; greater than 0.</summary>
    Limit: Integer;
    /// <summary>--json.</summary>
    AsJson: Boolean;
    /// <summary>The other resolved databases, in reading order. One named library-*.sqlite is the
    /// place `library`; any other is not searched (as in 1.55).</summary>
    OtherDbs: TArray<string>;
    /// <summary>The --project file, '' when none; used only in the refresh command of a note.</summary>
    ProjectFile: string;
    /// <summary>False (the default) = --place and --links are read from the process command line;
    /// True = Places, Links and LinksGiven below are used as they are.</summary>
    FlagsGiven: Boolean;
    /// <summary>--place: comma-separated subset of library, project, repository; '' = all three.</summary>
    Places: string;
    /// <summary>--links: rows printed per link group; 0 = counts only. Read when LinksGiven.</summary>
    Links: Integer;
    /// <summary>True when --links was given (it also lifts the by-name-only row cap).</summary>
    LinksGiven: Boolean;
  end;

/// <summary>Answers `query --concept` from the project index, the repository copy inside it and
/// the library index: tiers (exact identifier, exact caption words, all words elsewhere, some
/// words), `place` and `tier` on every hit, links of every field hit, text or JSON.</summary>
/// <param name="pQuery">The request.</param>
/// <param name="pExitCode">The verb's exit code when the result is True: 0 = at least one hit,
/// 1 = none, 2 = usage error (--place / --links).</param>
/// <returns>True = this unit printed the whole answer and the caller exits with pExitCode;
/// False = nothing was printed and the caller runs its own search as before -- only when the
/// project index has no concept-search table (the caller's exit 3).</returns>
/// <remarks>Read-only: the databases are opened read-only and the live repository file is only
/// STATed (size, modification time), never opened. Hits go to stdout, note lines to stderr.</remarks>
function TryRunConceptRepoQuery(const pQuery: TConceptRepoQuery; out pExitCode: Integer): Boolean;

implementation

uses
  System.SysUtils, System.Character, System.IOUtils, System.DateUtils, System.JSON,
  System.Generics.Collections, System.Generics.Defaults, System.Math, System.StrUtils,
  Winapi.Windows, Data.DB, FireDAC.Stan.Param, FireDAC.Comp.Client, DRagLint.Core.Interfaces,
  DRagLint.Storage.SQLite;

type
  TPlace = (plProject, plRepository, plLibrary);
  TPlaceSet = set of TPlace;

const
  PLACE_NAMES: array[TPlace] of string = ('project', 'repository', 'library');
  KIND_REPO_FIELD  = 'repo-field';
  KIND_REPO_TABLE  = 'repo-table';
  KIND_DFM_CAPTION = 'dfm-caption';
  TEXT_KIND_COUNT  = 6;
  TEXT_KINDS: array[0..TEXT_KIND_COUNT - 1] of string =
    ('caption', 'display-label', 'grid-caption', 'description', 'table-description', 'hint');
  TEXT_KIND_CAPTION  = 0;
  CAPTION_CLASS_LAST = 2; { TEXT_KINDS[0..2] are the caption class, the rest the prose class }
  MATCHED_NAME       = 'name';
  TIER_EXACT_NAME = 1;
  TIER_CAPTION    = 2;
  TIER_ALL_WORDS  = 3;
  TIER_SOME_WORDS = 4;
  SUB_NONE       = 0;
  SUB_WHOLE      = 1;
  SUB_CONTIGUOUS = 2;
  SUB_ANY_ORDER  = 3;
  DEFAULT_LINK_ROWS = 5;
  BY_NAME_TABLE_CAP = 5;
  EXIT_HITS  = 0;
  EXIT_NONE  = 1;
  EXIT_USAGE = 2;
  STATE_OK             = 'ok';
  STATE_SKIPPED        = 'skipped';
  STATE_COPIED         = 'copied';
  STATE_NOT_CONFIGURED = 'not-configured';
  STATE_MISSING        = 'missing';
  STATE_UNREADABLE     = 'unreadable';
  STATE_NOT_COPIED_YET = 'not-copied-yet';
  STATE_NO_CONCEPT     = 'no-concept-table';
  LINK_PERSISTENT = 'persistent-field';
  LINK_GRID       = 'grid-column';
  LINK_EDIT       = 'edit-control';
  LINK_CODE       = 'code';
  CONF_BY_NAME    = 'by-name-only';
  PLACE_REPOSITORY_TEXT = 'repository';
  LIBRARY_DB_PREFIX = 'library-';
  NO_ENTITY = -1;
  UNKNOWN_TABLE = '?';
  DETAIL_INDENT = '       ';
  ROW_INDENT    = '         ';

type
  TEntity = record
    TableName, FieldName: string;
    InRepo: Boolean;
    Caption, TypeText: string;
    Calculated, Lookup, Visible: Boolean;
    NameHit: Boolean;
    Sub: Integer;
    RepoCaptionAll: Boolean;
    UsesMax: Integer;
    ProseAll: Boolean;
    Score: Double;
    KindHit: array[0..TEXT_KIND_COUNT - 1] of Boolean;
  end;

  THit = record
    Tier: Integer;
    Place: TPlace;
    QName, Kind, FilePath: string;
    Line: Integer;
    Score: Double;
    Matched: string;
    SymbolId: Int64;
    EntityIx: Integer;
    Sub, RepoFirst, UsesMax: Integer;
  end;

  TLinkRow = record
    FilePath: string;
    Line: Integer;
    Form, FormClass, Component, Dataset, Caption, Via, InName, Receiver: string;
  end;

  TLinkShape = (lsDfm, lsForm, lsCode, lsByName);

  TLinks = record
    Persistent, Grid, Edit, Forms, Code, ByName: TArray<TLinkRow>;
    CandidateTables: Integer;
  end;

  TTextRow = record
    Kind, Place, Text: string;
    UseCount: Integer;
  end;

  TPlaceInfo = record
    Place: TPlace;
    State, Db, Note: string;
  end;

  TConceptRun = class  // dl:ok god-class@a0b2, high-response@a0b2 -- one query run kept in one object: flags, three places, ranking, links, two renderers share its state
  private
    FQuery     : TConceptRepoQuery;
    FPlaces    : TPlaceSet;
    FLinks     : Integer;
    FLinksGiven: Boolean;
    FStore     : ISymbolStore;
    FConn      : TFDConnection;
    FWords     : TArray<string>;
    FSingle    : string;
    FKinds     : TArray<string>;
    FSymKinds  : string;
    FHasTables : Boolean;
    FEntities  : TList<TEntity>;
    FEntityIx  : TDictionary<string, Integer>;
    FHits      : TList<THit>;
    FSeenSym   : TDictionary<string, Boolean>;
    FLibInfos  : TList<TPlaceInfo>;
    FRepoState, FRepoPath, FRepoError, FRepoNote: string;
    FRepoSize, FRepoMTime, FRepoCopiedAt: Int64;
    FRepoStale : Boolean;
    function  ParseFlags(out pError: string): Boolean;
    procedure SplitKinds;
    function  KindWanted(const pKind: string): Boolean;
    function  SymbolsWanted: Boolean;
    function  TableExists(const pName: string): Boolean;
    procedure ReadRepoCopy;
    procedure FinishRepoNote(pHasRepoHit: Boolean);
    function  WhenText: string;
    function  RefreshCommand: string;
    function  EntityFor(const pTable, pField: string): Integer;
    procedure ScanTexts;
    procedure ScanNames;
    procedure ResolveEntities;
    procedure EntityHits(pTier1, pTier2, pTier3, pTier4: TList<THit>);
    procedure SymbolHits(const pStore: ISymbolStore; pConn: TFDConnection; pPlace: TPlace;
      pTier1, pTier3, pTier4: TList<THit>);
    procedure LibraryHits(pTier1, pTier3, pTier4: TList<THit>);
    procedure Assemble;
    function  LoadTexts(const pEntity: TEntity): TArray<TTextRow>;
    function  LoadLinks(const pEntity: TEntity): TLinks;
    function  RowCap(const pRows: TArray<TLinkRow>): Integer;
    function  ByNameCap(const pLinks: TLinks): Integer;
    function  GroupJson(const pRows: TArray<TLinkRow>; pCap: Integer; pShape: TLinkShape): TJSONObject;
    function  PlacesJson: TJSONArray;
    procedure PrintJson(pAllCount: Integer);
    procedure PrintText(pAllCount: Integer);
    procedure PrintEntityText(const pEntity: TEntity);
    procedure PrintNotes;
  public
    constructor Create(const pQuery: TConceptRepoQuery);
    destructor Destroy; override;
    function Run(out pExitCode: Integer): Boolean;
  end;

{ The words of a caption or of a query as the concept search compares them: lower case, diacritics
  removed, split at everything that is not a letter or a digit (the FTS mirror's unicode61 rule). }
function ConceptFoldWords(const pText: string): TArray<string>;
var
  Lowered, Folded, Cur: string;
  Len: Integer;
  C: Char;
  L: TList<string>;
begin
  Lowered:= pText.ToLower;
  Folded:= Lowered;
  if Lowered <> '' then
  begin
    { MAP_COMPOSITE splits a letter with a diacritic into the base letter + combining marks. }
    Len:= FoldString(MAP_COMPOSITE, PChar(Lowered), Length(Lowered), nil, 0);
    if Len > 0 then
    begin
      SetLength(Folded, Len);
      FoldString(MAP_COMPOSITE, PChar(Lowered), Length(Lowered), PChar(Folded), Len);
    end;
  end;
  L:= TList<string>.Create;
  try
    Cur:= '';
    for C in Folded do
      if C.IsLetterOrDigit then
        Cur:= Cur + C  // dl:ok concat-in-loop@3e2b -- builds one word of a caption: a few letters
      else if C.GetUnicodeCategory <> TUnicodeCategory.ucNonSpacingMark then
      begin
        if Cur <> '' then L.Add(Cur);
        Cur:= '';
      end;
    if Cur <> '' then L.Add(Cur);
    Result:= L.ToArray;
  finally
    L.Free;
  end; // try
end; // function

{ How many of the query words pText holds as whole words, and -- when it holds all of them --
  how: the whole text, a contiguous run, or any order. }
procedure MatchWords(const pQuery, pTokens: TArray<string>; out pFound, pSub: Integer);
var
  I, J: Integer;
  Run: Boolean;
begin
  pFound:= 0;
  pSub:= SUB_NONE;
  for I:= 0 to High(pQuery) do
    for J:= 0 to High(pTokens) do
      if pTokens[J] = pQuery[I] then
      begin
        Inc(pFound);
        Break;
      end;
  if (pFound < Length(pQuery)) or (pFound = 0) then Exit;
  pSub:= SUB_ANY_ORDER;
  for I:= 0 to Length(pTokens) - Length(pQuery) do
  begin
    Run:= True;
    for J:= 0 to High(pQuery) do
      if pTokens[I + J] <> pQuery[J] then
      begin
        Run:= False;
        Break;
      end;
    if Run then
    begin
      pSub:= if Length(pTokens) = Length(pQuery) then SUB_WHOLE else SUB_CONTIGUOUS;
      Exit;
    end;
  end; // for
end; // procedure

function TextKindIndex(const pKind: string): Integer;
var
  I: Integer;
begin
  for I:= 0 to High(TEXT_KINDS) do
    if SameText(TEXT_KINDS[I], pKind) then Exit(I);
  Result:= -1;
end; // function

function IsLibraryDbName(const pDb: string): Boolean;
begin
  Result:= StartsText(LIBRARY_DB_PREFIX, ExtractFileName(pDb));
end; // function

function UnixLocal(pUnix: Int64): TDateTime;
begin
  Result:= UnixToDateTime(pUnix, False);
end; // function

function CompareHitName(const pLeft, pRight: THit): Integer;
begin
  Result:= CompareText(pLeft.QName, pRight.QName);
end; // function

{ TConceptRun }

constructor TConceptRun.Create(const pQuery: TConceptRepoQuery);
begin
  inherited Create;
  FQuery:= pQuery;
  FEntities:= TList<TEntity>.Create;
  FEntityIx:= TDictionary<string, Integer>.Create;
  FHits:= TList<THit>.Create;
  FSeenSym:= TDictionary<string, Boolean>.Create;
  FLibInfos:= TList<TPlaceInfo>.Create;
end; // constructor

destructor TConceptRun.Destroy;
begin
  FLibInfos.Free;
  FSeenSym.Free;
  FHits.Free;
  FEntityIx.Free;
  FEntities.Free;
  inherited;
end; // destructor

function TConceptRun.ParseFlags(out pError: string): Boolean;
var
  I: Integer;
  Item, Name: string;
  P: TPlace;
  Known: Boolean;
begin
  pError:= '';
  if not FQuery.FlagsGiven then
  begin
    I:= 1;
    while I < ParamCount do
    begin
      if ParamStr(I) = '--place' then
        FQuery.Places:= ParamStr(I + 1)
      else if ParamStr(I) = '--links' then
      begin
        FQuery.LinksGiven:= True;
        FQuery.Links:= StrToIntDef(ParamStr(I + 1), -1);
      end;
      Inc(I);
    end; // while
  end;
  FLinksGiven:= FQuery.LinksGiven;
  FLinks:= if FLinksGiven then FQuery.Links else DEFAULT_LINK_ROWS;
  if FLinks < 0 then
  begin
    pError:= 'ERROR: --links requires a number, 0 or greater';
    Exit(False);
  end;
  FPlaces:= [];
  for Item in FQuery.Places.Split([',']) do
  begin
    Name:= Trim(Item);
    if Name = '' then Continue;
    Known:= False;
    for P:= Low(TPlace) to High(TPlace) do
      if SameText(PLACE_NAMES[P], Name) then
      begin
        Include(FPlaces, P);
        Known:= True;
      end;
    if not Known then
    begin
      pError:= 'ERROR: --place accepts library, project, repository';
      Exit(False);
    end;
  end; // for
  if FPlaces = [] then FPlaces:= [plProject, plRepository, plLibrary];
  Result:= True;
end; // function

procedure TConceptRun.SplitKinds;
var
  Item, Kind: string;
  L: TList<string>;
begin
  FSymKinds:= '';
  L:= TList<string>.Create;
  try
    for Item in FQuery.Kinds.Split([',']) do
    begin
      Kind:= LowerCase(Trim(Item));
      if Kind = '' then Continue;
      L.Add(Kind);
      if (Kind <> KIND_REPO_FIELD) and (Kind <> KIND_REPO_TABLE) and (Kind <> KIND_DFM_CAPTION) then
        FSymKinds:= FSymKinds + IfThen(FSymKinds = '', '', ',') + Kind;
    end; // for
    FKinds:= L.ToArray;
  finally
    L.Free;
  end; // try
end; // procedure

function TConceptRun.KindWanted(const pKind: string): Boolean;
var
  Kind: string;
begin
  if Length(FKinds) = 0 then Exit(True);
  for Kind in FKinds do
    if Kind = pKind then Exit(True);
  Result:= False;
end; // function

function TConceptRun.SymbolsWanted: Boolean;
begin
  Result:= (Length(FKinds) = 0) or (FSymKinds <> '');
end; // function

function TConceptRun.TableExists(const pName: string): Boolean;
var
  Q: TFDQuery;
begin
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.Open('SELECT 1 FROM sqlite_master WHERE name = :n', [pName]);
    Result:= not Q.Eof;
  finally
    Q.Free;
  end; // try
end; // function

procedure TConceptRun.ReadRepoCopy;
var
  Q: TFDQuery;
begin
  FRepoState:= STATE_NOT_COPIED_YET;
  if plRepository not in FPlaces then
  begin
    FRepoState:= STATE_SKIPPED;
    Exit;
  end;
  if not FHasTables then Exit;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.Open('SELECT state, repo_path, repo_size, repo_mtime_unix, copied_at_unix, last_error FROM repo_copy WHERE id = 1');
    if Q.Eof then Exit;
    FRepoState:= Q.FieldByName('state').AsString;
    FRepoPath:= Q.FieldByName('repo_path').AsString;
    FRepoSize:= Q.FieldByName('repo_size').AsLargeInt;
    FRepoMTime:= Q.FieldByName('repo_mtime_unix').AsLargeInt;
    FRepoCopiedAt:= Q.FieldByName('copied_at_unix').AsLargeInt;
    FRepoError:= Q.FieldByName('last_error').AsString;
  finally
    Q.Free;
  end; // try
end; // procedure

function TConceptRun.WhenText: string;
begin
  Result:= FormatDateTime('yyyy-mm-dd hh:nn', UnixLocal(FRepoCopiedAt));
end; // function

function TConceptRun.RefreshCommand: string;
var
  Project: string;
begin
  Project:= if FQuery.ProjectFile = '' then '<X.dproj>' else FQuery.ProjectFile;
  Result:= Format('drag-lint index --project %s --db %s', [Project, FQuery.DbPath]);
end; // function

{ The one repository note of the run (design 1.6). The live file is only STATed. }
procedure TConceptRun.FinishRepoNote(pHasRepoHit: Boolean);
var
  Tail: string;
begin
  FRepoNote:= '';
  FRepoStale:= False;
  if FRepoState = STATE_NOT_COPIED_YET then
    FRepoNote:= 'repository: not copied yet (index made before 1.56); run: ' + RefreshCommand
  else if FRepoState = STATE_NOT_CONFIGURED then
    FRepoNote:= 'repository: not configured'
  else if FRepoState = STATE_MISSING then
    FRepoNote:= 'repository: not found at index time: ' + FRepoPath
  else if FRepoState = STATE_UNREADABLE then
  begin
    Tail:= if FRepoCopiedAt > 0 then 'the copy from ' + WhenText + ' is used' else 'no copy';
    FRepoNote:= Format('repository: not readable at index time: %s (%s); %s', [FRepoPath, FRepoError, Tail]);
  end
  else if FRepoState = STATE_COPIED then
  begin
    if not TFile.Exists(FRepoPath) then
      FRepoNote:= Format('repository: copy from %s; %s no longer exists', [WhenText, FRepoPath])
    else if (TFile.GetSize(FRepoPath) <> FRepoSize)
      or (DateTimeToUnix(TFile.GetLastWriteTimeUtc(FRepoPath), True) <> FRepoMTime) then
    begin
      FRepoStale:= True;
      FRepoNote:= Format('repository: copy from %s is stale (%s changed since); refresh: %s',
        [WhenText, FRepoPath, RefreshCommand]);
    end
    else if pHasRepoHit then
      FRepoNote:= Format('repository: copy from %s of %s', [WhenText, FRepoPath]);
  end;
end; // procedure

function TConceptRun.EntityFor(const pTable, pField: string): Integer;
var
  Key: string;
  E: TEntity;
begin
  Key:= UpperCase(pTable) + #9 + UpperCase(pField);
  if FEntityIx.TryGetValue(Key, Result) then Exit;
  E:= Default(TEntity);
  E.TableName:= pTable;
  E.FieldName:= pField;
  E.Visible:= True;
  Result:= FEntities.Add(E);
  FEntityIx.Add(Key, Result);
end; // function

{ Every text holding at least one query word as a whole word, folded into its field. The FTS
  mirror only narrows the candidates; the whole-word test is ConceptFoldWords on both sides. }
procedure TConceptRun.ScanTexts;
const
  SELECT_TEXTS = 'SELECT t.place AS pl, t.text_kind AS tk, t.table_name AS tn, t.field_name AS fn, ' +
                 't.text AS tx, t.uses AS us, ';
var
  Q: TFDQuery;
  Match, W, Sql: string;
  KindIx, Found, Sub, Ix: Integer;
  E: TEntity;
  ColPlace, ColKind, ColTable, ColField, ColText, ColUses, ColScore: TField;
begin
  if (Length(FWords) = 0) or not FHasTables then Exit;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    if TableExists('concept_texts_fts') then
    begin
      Match:= '';
      for W in FWords do Match:= Match + IfThen(Match = '', '', ' OR ') + '"' + W + '"';
      Sql:= SELECT_TEXTS + '-bm25(concept_texts_fts) AS sc FROM concept_texts_fts ' +
        'JOIN concept_texts t ON t.id = concept_texts_fts.rowid WHERE concept_texts_fts MATCH :q';
      Q.Open(Sql, [Match]);
    end
    else
    begin
      Sql:= SELECT_TEXTS + '0.0 AS sc FROM concept_texts t';
      Q.Open(Sql);
    end;
    ColPlace:= Q.FieldByName('pl');
    ColKind:= Q.FieldByName('tk');
    ColTable:= Q.FieldByName('tn');
    ColField:= Q.FieldByName('fn');
    ColText:= Q.FieldByName('tx');
    ColUses:= Q.FieldByName('us');
    ColScore:= Q.FieldByName('sc');
    while not Q.Eof do
    begin
      KindIx:= TextKindIndex(ColKind.AsString);
      MatchWords(FWords, ConceptFoldWords(ColText.AsString), Found, Sub);
      if (KindIx >= 0) and (Found > 0) and ((ColTable.AsString <> '') or (ColField.AsString <> '')) then
      begin
        Ix:= EntityFor(ColTable.AsString, ColField.AsString);
        E:= FEntities[Ix];
        E.KindHit[KindIx]:= True;
        E.Score:= Max(E.Score, ColScore.AsFloat);
        if (Sub <> SUB_NONE) and (KindIx <= CAPTION_CLASS_LAST) then
        begin
          if (E.Sub = SUB_NONE) or (Sub < E.Sub) then E.Sub:= Sub;
          if (KindIx = TEXT_KIND_CAPTION) and SameText(ColPlace.AsString, PLACE_REPOSITORY_TEXT) then
            E.RepoCaptionAll:= True;
          E.UsesMax:= Max(E.UsesMax, ColUses.AsInteger);
        end
        else if Sub <> SUB_NONE then
          E.ProseAll:= True;
        FEntities[Ix]:= E;
      end;
      Q.Next;
    end; // while
  finally
    Q.Free;
  end; // try
end; // procedure

{ Tier 1 of the repository: the whole query, as one token, is a FIELD_NAME or a TABLE_NAME. }
procedure TConceptRun.ScanNames;
const
  SELECT_NAMES = 'SELECT table_name, field_name FROM concept_fields ' +
                 'WHERE field_name = :f OR (table_name = :t AND field_name = '''')';
var
  Q: TFDQuery;
  Ix: Integer;
  E: TEntity;
begin
  if (FSingle = '') or not FHasTables then Exit;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.Open(SELECT_NAMES, [FSingle, FSingle]);
    while not Q.Eof do
    begin
      Ix:= EntityFor(Q.FieldByName('table_name').AsString, Q.FieldByName('field_name').AsString);  // dl:ok field-by-name-in-loop@4798 -- a few rows per query (the texts, links or name matches of ONE field; symbols capped by --limit): the lookup is noise next to the query
      E:= FEntities[Ix];
      E.NameHit:= True;
      FEntities[Ix]:= E;
      Q.Next;
    end; // while
  finally
    Q.Free;
  end; // try
end; // procedure

procedure TConceptRun.ResolveEntities;
const
  SELECT_FIELD = 'SELECT table_name, field_name, caption, type_text, is_calculated, is_lookup, visible ' +
                 'FROM concept_fields WHERE table_name = :t AND field_name = :f';
var
  Q: TFDQuery;
  I: Integer;
  E: TEntity;
begin
  if FEntities.Count = 0 then Exit;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    for I:= 0 to FEntities.Count - 1 do
    begin
      E:= FEntities[I];
      Q.Close;
      Q.Open(SELECT_FIELD, [E.TableName, E.FieldName]);  // dl:ok query-in-loop@d415 -- one indexed lookup per matched field; the loop is bounded by the fields the query words hit
      if not Q.Eof then
      begin
        E.InRepo:= True;
        E.TableName:= Q.FieldByName('table_name').AsString;  // dl:ok field-by-name-in-loop@7911 -- a few rows per query (the texts, links or name matches of ONE field; symbols capped by --limit): the lookup is noise next to the query
        E.FieldName:= Q.FieldByName('field_name').AsString;
        E.Caption:= Q.FieldByName('caption').AsString;
        E.TypeText:= Q.FieldByName('type_text').AsString;
        E.Calculated:= Q.FieldByName('is_calculated').AsInteger <> 0;
        E.Lookup:= Q.FieldByName('is_lookup').AsInteger <> 0;
        E.Visible:= Q.FieldByName('visible').AsInteger <> 0;
        FEntities[I]:= E;
      end;
    end; // for
  finally
    Q.Free;
  end; // try
end; // procedure

procedure TConceptRun.EntityHits(pTier1, pTier2, pTier3, pTier4: TList<THit>);
const
  SELECT_FIRST_LINK = 'SELECT f.path AS fpath, l.line AS ln FROM concept_links l JOIN files f ON f.id = l.file_id ' +
                      'WHERE l.field_name = :f AND l.table_name = :t AND l.link_kind <> ''code'' ' +
                      'ORDER BY f.path, l.line LIMIT 1';
var
  I, K: Integer;
  E: TEntity;
  H: THit;
  Q: TFDQuery;
begin
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    for I:= 0 to FEntities.Count - 1 do
    begin
      E:= FEntities[I];
      if (E.FieldName = '') and not E.InRepo then Continue;
      H:= Default(THit);
      H.EntityIx:= I;
      H.Place:= if E.InRepo then plRepository else plProject;
      if not E.InRepo then H.Kind:= KIND_DFM_CAPTION
      else if E.FieldName = '' then H.Kind:= KIND_REPO_TABLE
      else H.Kind:= KIND_REPO_FIELD;
      if (H.Place not in FPlaces) or not KindWanted(H.Kind) then Continue;
      if E.FieldName = '' then H.QName:= E.TableName
      else if E.TableName = '' then H.QName:= UNKNOWN_TABLE + '.' + E.FieldName
      else H.QName:= E.TableName + '.' + E.FieldName;
      if E.NameHit then H.Matched:= MATCHED_NAME;
      for K:= 0 to High(TEXT_KINDS) do
        if E.KindHit[K] then H.Matched:= H.Matched + IfThen(H.Matched = '', '', ',') + TEXT_KINDS[K];
      H.Sub:= E.Sub;
      H.RepoFirst:= if E.RepoCaptionAll then 0 else 1;
      H.UsesMax:= E.UsesMax;
      if E.InRepo then
        H.FilePath:= FRepoPath
      else
      begin
        Q.Close;
        Q.Open(SELECT_FIRST_LINK, [E.FieldName, E.TableName]);  // dl:ok query-in-loop@4d6c -- one indexed lookup per project-caption hit; the loop is bounded by the fields the query words hit
        if not Q.Eof then
        begin
          H.FilePath:= Q.FieldByName('fpath').AsString;  // dl:ok field-by-name-in-loop@1536 -- a few rows per query (the texts, links or name matches of ONE field; symbols capped by --limit): the lookup is noise next to the query
          H.Line:= Q.FieldByName('ln').AsInteger;
        end;
      end;
      if E.NameHit then
      begin
        H.Tier:= TIER_EXACT_NAME;
        pTier1.Add(H);
      end
      else if E.Sub <> SUB_NONE then
      begin
        H.Tier:= TIER_CAPTION;
        pTier2.Add(H);
      end
      else
      begin
        { Tiers 3 and 4 are ordered by the text score; tiers 1 and 2 by rule (score 0). }
        H.Score:= E.Score;
        H.Tier:= if E.ProseAll then TIER_ALL_WORDS else TIER_SOME_WORDS;
        if E.ProseAll then pTier3.Add(H) else pTier4.Add(H);
      end;
    end; // for
  finally
    Q.Free;
  end; // try
end; // procedure

procedure TConceptRun.SymbolHits(const pStore: ISymbolStore; pConn: TFDConnection; pPlace: TPlace;
  pTier1, pTier3, pTier4: TList<THit>);
var
  Q: TFDQuery;
  Sql, Kind, InList, Key: string;
  H: THit;
  C: TConceptHit;
begin
  if not SymbolsWanted then Exit;
  if FSingle <> '' then
  begin
    { Tier 1: a symbol NAMED like the whole query. Only symbols the concept search covers
      (symbol_search), so a parameter or a local of that name does not fill the answer. }
    Sql:= 'SELECT s.id AS sid, s.qualified_name AS qn, s.kind AS kd, f.path AS fpath, s.start_line AS ln ' +
          'FROM symbols s JOIN symbol_search ss ON ss.symbol_id = s.id JOIN files f ON f.id = s.file_id ' +
          'WHERE s.name = :w COLLATE NOCASE';
    InList:= '';
    for Kind in FSymKinds.Split([','], TStringSplitOptions.ExcludeEmpty) do
      InList:= InList + IfThen(InList = '', '', ',') + QuotedStr(Kind);
    if InList <> '' then Sql:= Sql + ' AND s.kind IN (' + InList + ')';
    Sql:= Sql + ' ORDER BY s.qualified_name LIMIT :n';
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= pConn;
      Q.Open(Sql, [FSingle, FQuery.Limit]);
      while not Q.Eof do
      begin
        H:= Default(THit);
        H.Tier:= TIER_EXACT_NAME;
        H.Place:= pPlace;
        H.EntityIx:= NO_ENTITY;
        H.SymbolId:= Q.FieldByName('sid').AsLargeInt;  // dl:ok field-by-name-in-loop@6591 -- a few rows per query (the texts, links or name matches of ONE field; symbols capped by --limit): the lookup is noise next to the query
        H.QName:= Q.FieldByName('qn').AsString;
        H.Kind:= Q.FieldByName('kd').AsString;
        H.FilePath:= Q.FieldByName('fpath').AsString;
        H.Line:= Q.FieldByName('ln').AsInteger;
        H.Matched:= MATCHED_NAME;
        pTier1.Add(H);
        FSeenSym.AddOrSetValue(PLACE_NAMES[pPlace] + '#' + IntToStr(H.SymbolId), True);
        Q.Next;
      end; // while
    finally
      Q.Free;
    end; // try
  end;
  for C in pStore.SearchConcept(FQuery.Words, FQuery.Limit, FSymKinds) do
  begin
    Key:= PLACE_NAMES[pPlace] + '#' + IntToStr(C.SymbolId);
    if FSeenSym.ContainsKey(Key) then Continue;
    H:= Default(THit);
    H.Place:= pPlace;
    H.EntityIx:= NO_ENTITY;
    H.SymbolId:= C.SymbolId;
    H.QName:= C.QualifiedName;
    H.Kind:= C.Kind;
    H.FilePath:= C.FilePath;
    H.Line:= C.Line;
    H.Score:= C.Score;
    H.Matched:= C.Matched;
    H.Tier:= if C.AllTerms then TIER_ALL_WORDS else TIER_SOME_WORDS;
    if C.AllTerms then pTier3.Add(H) else pTier4.Add(H);
  end; // for
end; // procedure

procedure TConceptRun.LibraryHits(pTier1, pTier3, pTier4: TList<THit>);
var
  Db: string;
  Info: TPlaceInfo;
  LibObj: TSQLiteSymbolStore;
  LibStore: ISymbolStore;
begin
  Info:= Default(TPlaceInfo);
  Info.Place:= plLibrary;
  if plLibrary not in FPlaces then
  begin
    Info.State:= STATE_SKIPPED;
    FLibInfos.Add(Info);
    Exit;
  end;
  for Db in FQuery.OtherDbs do
  begin
    if not IsLibraryDbName(Db) or not TFile.Exists(Db) then Continue;
    Info.Db:= Db;
    Info.Note:= '';
    Info.State:= STATE_UNREADABLE;
    try
      LibObj:= TSQLiteSymbolStore.Create(Db, {AReadOnly=}True);
      LibStore:= LibObj;
      if LibStore.ConceptSearchReady then
      begin
        Info.State:= STATE_OK;
        SymbolHits(LibStore, LibObj.GetConnection, plLibrary, pTier1, pTier3, pTier4);
      end
      else
      begin
        Info.State:= STATE_NO_CONCEPT;
        Info.Note:= 'library: no concept-search table; run "drag-lint index" on it once';
      end;
    except
      on E: Exception do Info.Note:= 'library: not readable: ' + Db + ' (' + E.Message + ')';
    end; // try
    LibStore:= nil;
    FLibInfos.Add(Info);
  end; // for
  if FLibInfos.Count = 0 then
  begin
    Info.State:= STATE_NOT_CONFIGURED;
    Info.Note:= 'library: not configured';
    FLibInfos.Add(Info);
  end;
end; // procedure

{ Tier, then the order inside the tier (design 2.7), then the --limit cut. }
procedure TConceptRun.Assemble;
var
  Tier1, Tier2: TList<THit>;
  Lists3, Lists4: array[TPlace] of TList<THit>;
  P: TPlace;

  procedure MergeByPosition(const pLists: array of TList<THit>);
  var
    Ix, L: Integer;
    More: Boolean;
  begin
    Ix:= 0;
    repeat
      More:= False;
      for L:= 0 to High(pLists) do
        if Ix < pLists[L].Count then
        begin
          FHits.Add(pLists[L][Ix]);
          More:= True;
        end;
      Inc(Ix);
    until not More;
  end; // procedure

  procedure SortByScore(pList: TList<THit>);
  begin
    pList.Sort(TComparer<THit>.Construct(
      function(const pLeft, pRight: THit): Integer
      begin
        Result:= CompareValue(pRight.Score, pLeft.Score);
        if Result = 0 then Result:= CompareHitName(pLeft, pRight);
      end));
  end; // procedure

begin
  Tier1:= TList<THit>.Create;
  Tier2:= TList<THit>.Create;
  for P:= Low(TPlace) to High(TPlace) do
  begin
    Lists3[P]:= TList<THit>.Create;
    Lists4[P]:= TList<THit>.Create;
  end;
  try
    if plProject in FPlaces then
      SymbolHits(FStore, FConn, plProject, Tier1, Lists3[plProject], Lists4[plProject]);
    { The text list holds repository fields and project captions; it merges in the repository slot. }
    EntityHits(Tier1, Tier2, Lists3[plRepository], Lists4[plRepository]);
    LibraryHits(Tier1, Lists3[plLibrary], Lists4[plLibrary]);
    Tier1.Sort(TComparer<THit>.Construct(
      function(const pLeft, pRight: THit): Integer
      begin
        Result:= Ord(pLeft.Place) - Ord(pRight.Place);
        if Result = 0 then Result:= CompareHitName(pLeft, pRight);
      end));
    Tier2.Sort(TComparer<THit>.Construct(
      function(const pLeft, pRight: THit): Integer
      begin
        Result:= pLeft.Sub - pRight.Sub;
        if Result = 0 then Result:= pLeft.RepoFirst - pRight.RepoFirst;
        if Result = 0 then Result:= pRight.UsesMax - pLeft.UsesMax;
        if Result = 0 then Result:= CompareHitName(pLeft, pRight);
      end));
    SortByScore(Lists3[plRepository]);
    SortByScore(Lists4[plRepository]);
    FHits.AddRange(Tier1);
    FHits.AddRange(Tier2);
    MergeByPosition([Lists3[plProject], Lists3[plRepository], Lists3[plLibrary]]);
    MergeByPosition([Lists4[plProject], Lists4[plRepository], Lists4[plLibrary]]);
    while FHits.Count > FQuery.Limit do FHits.Delete(FHits.Count - 1);
  finally
    for P:= Low(TPlace) to High(TPlace) do
    begin
      Lists3[P].Free;
      Lists4[P].Free;
    end;
    Tier2.Free;
    Tier1.Free;
  end; // try
end; // procedure

function TConceptRun.LoadTexts(const pEntity: TEntity): TArray<TTextRow>;
const
  SELECT_FIELD_TEXTS = 'SELECT text_kind, place, text, uses FROM concept_texts WHERE table_name = :t AND field_name = :f ' +
                       'ORDER BY (place = ''repository'') DESC, id';
var
  Q: TFDQuery;
  L: TList<TTextRow>;
  R: TTextRow;
begin
  L:= TList<TTextRow>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.Open(SELECT_FIELD_TEXTS, [pEntity.TableName, pEntity.FieldName]);
    while not Q.Eof do
    begin
      R.Kind:= Q.FieldByName('text_kind').AsString;  // dl:ok field-by-name-in-loop@9974 -- a few rows per query (the texts, links or name matches of ONE field; symbols capped by --limit): the lookup is noise next to the query
      R.Place:= Q.FieldByName('place').AsString;
      R.Text:= Q.FieldByName('text').AsString;
      R.UseCount:= Q.FieldByName('uses').AsInteger;
      L.Add(R);
      Q.Next;
    end; // while
    Result:= L.ToArray;
  finally
    Q.Free;
    L.Free;
  end; // try
end; // function

{ The links of one field (design 2.8): resolved links by (table, field); code links known by the
  field NAME only in their own group; code through a persistent field read from refs on demand. }
function TConceptRun.LoadLinks(const pEntity: TEntity): TLinks;
const
  SELECT_LINKS =
    'SELECT l.link_kind AS lk, l.confidence AS cf, f.path AS fpath, l.line AS ln, l.form_name AS fm, ' +
    'l.form_class AS fc, l.component_name AS cn, l.dataset_name AS dn, l.via AS via, l.caption AS cap, ' +
    'COALESCE(es.qualified_name, '''') AS encl, l.symbol_id AS sid ' +
    'FROM concept_links l JOIN files f ON f.id = l.file_id LEFT JOIN symbols es ON es.id = l.enclosing_symbol_id ' +
    'WHERE l.field_name = :f AND (l.table_name = :t OR (l.confidence = ''by-name-only'' AND l.link_kind = ''code'')) ' +
    'ORDER BY f.path, l.line, l.col';
  SELECT_FIELD_REFS =
    'SELECT f.path AS fpath, r.start_line AS ln, COALESCE(es.qualified_name, '''') AS encl ' +
    'FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols es ON es.id = r.enclosing_symbol_id ' +
    'WHERE r.symbol_id IN (';
  SELECT_CANDIDATES = 'SELECT COUNT(*) AS n FROM concept_fields WHERE field_name = :f AND field_name <> ''''';
var
  Q: TFDQuery;
  R, F: TLinkRow;
  Kind, SymIds, FormKey, Sql: string;
  Forms: TDictionary<string, Boolean>;
begin
  Result:= Default(TLinks);
  SymIds:= '';
  Forms:= TDictionary<string, Boolean>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.Open(SELECT_LINKS, [pEntity.FieldName, pEntity.TableName]);
    while not Q.Eof do
    begin
      R:= Default(TLinkRow);
      Kind:= Q.FieldByName('lk').AsString;  // dl:ok field-by-name-in-loop@f6db -- a few rows per query (the texts, links or name matches of ONE field; symbols capped by --limit): the lookup is noise next to the query
      R.FilePath:= Q.FieldByName('fpath').AsString;
      R.Line:= Q.FieldByName('ln').AsInteger;
      R.Form:= Q.FieldByName('fm').AsString;
      R.FormClass:= Q.FieldByName('fc').AsString;
      R.Component:= Q.FieldByName('cn').AsString;
      R.Dataset:= Q.FieldByName('dn').AsString;
      R.Via:= Q.FieldByName('via').AsString;
      R.Caption:= Q.FieldByName('cap').AsString;
      R.InName:= Q.FieldByName('encl').AsString;
      R.Receiver:= R.Dataset;
      if Kind = LINK_CODE then
      begin
        if Q.FieldByName('cf').AsString = CONF_BY_NAME then Result.ByName:= Result.ByName + [R]
        else Result.Code:= Result.Code + [R];
      end
      else
      begin
        if Kind = LINK_PERSISTENT then
        begin
          Result.Persistent:= Result.Persistent + [R];
          if not Q.FieldByName('sid').IsNull then
            SymIds:= SymIds + IfThen(SymIds = '', '', ',') + IntToStr(Q.FieldByName('sid').AsLargeInt);
        end
        else if Kind = LINK_GRID then Result.Grid:= Result.Grid + [R]
        else if Kind = LINK_EDIT then Result.Edit:= Result.Edit + [R];
        FormKey:= UpperCase(R.Form + #9 + R.FilePath);
        if (R.Form <> '') and not Forms.ContainsKey(FormKey) then
        begin
          Forms.Add(FormKey, True);
          F:= Default(TLinkRow);
          F.Form:= R.Form;
          F.FormClass:= R.FormClass;
          F.FilePath:= R.FilePath;
          Result.Forms:= Result.Forms + [F];
        end;
      end;
      Q.Next;
    end; // while
    if SymIds <> '' then
    begin
      Q.Close;
      Sql:= SELECT_FIELD_REFS + SymIds + ') ORDER BY f.path, r.start_line, r.start_col';
      Q.Open(Sql);
      while not Q.Eof do
      begin
        R:= Default(TLinkRow);
        R.FilePath:= Q.FieldByName('fpath').AsString;  // dl:ok field-by-name-in-loop@db8a -- a few rows per query (the texts, links or name matches of ONE field; symbols capped by --limit): the lookup is noise next to the query
        R.Line:= Q.FieldByName('ln').AsInteger;
        R.InName:= Q.FieldByName('encl').AsString;
        R.Via:= LINK_PERSISTENT;
        Result.Code:= Result.Code + [R];
        Q.Next;
      end; // while
      TArray.Sort<TLinkRow>(Result.Code, TComparer<TLinkRow>.Construct(
        function(const pLeft, pRight: TLinkRow): Integer
        begin
          Result:= CompareText(pLeft.FilePath, pRight.FilePath);
          if Result = 0 then Result:= pLeft.Line - pRight.Line;
          if Result = 0 then Result:= CompareText(pLeft.Via, pRight.Via);
        end));
    end;
    Q.Close;
    Q.Open(SELECT_CANDIDATES, [pEntity.FieldName]);
    Result.CandidateTables:= Q.FieldByName('n').AsInteger;
  finally
    Q.Free;
    Forms.Free;
  end; // try
end; // function

function TConceptRun.RowCap(const pRows: TArray<TLinkRow>): Integer;
begin
  Result:= Min(Length(pRows), FLinks);
end; // function

{ A field name many tables have (ID, NAME): rows only on an explicit --links (NQ-6). }
function TConceptRun.ByNameCap(const pLinks: TLinks): Integer;
begin
  if (pLinks.CandidateTables > BY_NAME_TABLE_CAP) and not FLinksGiven then Exit(0);
  Result:= RowCap(pLinks.ByName);
end; // function

function TConceptRun.GroupJson(const pRows: TArray<TLinkRow>; pCap: Integer; pShape: TLinkShape): TJSONObject;
var
  JRows: TJSONArray;
  JRow: TJSONObject;
  I: Integer;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('count', TJSONNumber.Create(Length(pRows)));
  JRows:= TJSONArray.Create;
  for I:= 0 to pCap - 1 do
  begin
    JRow:= TJSONObject.Create;
    case pShape of
      lsDfm:
        begin
          JRow.AddPair('file', pRows[I].FilePath);
          JRow.AddPair('line', TJSONNumber.Create(pRows[I].Line));
          JRow.AddPair('form', pRows[I].Form);
          JRow.AddPair('component', pRows[I].Component);
          JRow.AddPair('dataset', pRows[I].Dataset);
          JRow.AddPair('caption', pRows[I].Caption);
          JRow.AddPair('via', pRows[I].Via);
        end;
      lsForm:
        begin
          JRow.AddPair('form', pRows[I].Form);
          JRow.AddPair('class', pRows[I].FormClass);
          JRow.AddPair('file', pRows[I].FilePath);
        end;
      lsCode, lsByName:
        begin
          JRow.AddPair('file', pRows[I].FilePath);
          JRow.AddPair('line', TJSONNumber.Create(pRows[I].Line));
          JRow.AddPair('in', pRows[I].InName);
          if pShape = lsByName then JRow.AddPair('receiver', pRows[I].Receiver);
          JRow.AddPair('via', pRows[I].Via);
        end;
    end; // case
    JRows.AddElement(JRow);
  end; // for
  Result.AddPair('rows', JRows);
end; // function

function TConceptRun.PlacesJson: TJSONArray;
var
  JObj: TJSONObject;
  Info: TPlaceInfo;
  CopiedAt: string;
begin
  Result:= TJSONArray.Create;
  JObj:= TJSONObject.Create;
  JObj.AddPair('place', PLACE_NAMES[plProject]);
  JObj.AddPair('state', IfThen(plProject in FPlaces, STATE_OK, STATE_SKIPPED));
  JObj.AddPair('db', FQuery.DbPath);
  JObj.AddPair('note', '');
  Result.AddElement(JObj);
  JObj:= TJSONObject.Create;
  JObj.AddPair('place', PLACE_NAMES[plRepository]);
  JObj.AddPair('state', FRepoState);
  JObj.AddPair('path', FRepoPath);
  CopiedAt:= if FRepoCopiedAt > 0 then FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', UnixLocal(FRepoCopiedAt)) else '';
  JObj.AddPair('copiedAt', CopiedAt);
  JObj.AddPair('stale', TJSONBool.Create(FRepoStale));
  JObj.AddPair('note', FRepoNote);
  Result.AddElement(JObj);
  for Info in FLibInfos do
  begin
    JObj:= TJSONObject.Create;
    JObj.AddPair('place', PLACE_NAMES[plLibrary]);
    JObj.AddPair('state', Info.State);
    JObj.AddPair('db', Info.Db);
    JObj.AddPair('note', Info.Note);
    Result.AddElement(JObj);
  end; // for
end; // function

procedure TConceptRun.PrintJson(pAllCount: Integer);
var
  JRoot, JObj, JField, JText, JLinks, JByName: TJSONObject;
  JHits, JMatched, JTexts: TJSONArray;
  H: THit;
  E: TEntity;
  T: TTextRow;
  L: TLinks;
  Rank: Integer;
  Col: string;
begin
  JRoot:= TJSONObject.Create;
  try
    JRoot.AddPair('query', FQuery.Words);
    JRoot.AddPair('count', TJSONNumber.Create(FHits.Count));
    JRoot.AddPair('allTermsCount', TJSONNumber.Create(pAllCount));
    JRoot.AddPair('places', PlacesJson);
    JHits:= TJSONArray.Create;
    JRoot.AddPair('hits', JHits);
    Rank:= 0;
    for H in FHits do
    begin
      Inc(Rank);
      JObj:= TJSONObject.Create;
      JHits.AddElement(JObj);
      JObj.AddPair('rank', TJSONNumber.Create(Rank));
      JObj.AddPair('place', PLACE_NAMES[H.Place]);
      JObj.AddPair('tier', TJSONNumber.Create(H.Tier));
      JObj.AddPair('qname', H.QName);
      JObj.AddPair('kind', H.Kind);
      JObj.AddPair('file', H.FilePath);
      JObj.AddPair('line', TJSONNumber.Create(H.Line));
      JObj.AddPair('score', TJSONNumber.Create(H.Score));
      JMatched:= TJSONArray.Create;
      for Col in H.Matched.Split([',']) do
        if Col <> '' then JMatched.Add(Col);
      JObj.AddPair('matched', JMatched);
      JObj.AddPair('allTerms', TJSONBool.Create(H.Tier <= TIER_ALL_WORDS));
      if H.EntityIx = NO_ENTITY then Continue;
      E:= FEntities[H.EntityIx];
      JField:= TJSONObject.Create;
      JObj.AddPair('field', JField);
      JField.AddPair('table', E.TableName);
      JField.AddPair('field', E.FieldName);
      JField.AddPair('caption', E.Caption);
      JField.AddPair('type', E.TypeText);
      JField.AddPair('calculated', TJSONBool.Create(E.Calculated));
      JField.AddPair('lookup', TJSONBool.Create(E.Lookup));
      JField.AddPair('visible', TJSONBool.Create(E.Visible));
      JTexts:= TJSONArray.Create;
      JObj.AddPair('texts', JTexts);
      for T in LoadTexts(E) do
      begin
        JText:= TJSONObject.Create;
        JText.AddPair('kind', T.Kind);
        JText.AddPair('place', T.Place);
        JText.AddPair('text', T.Text);
        if not SameText(T.Place, PLACE_REPOSITORY_TEXT) then JText.AddPair('uses', TJSONNumber.Create(T.UseCount));
        JTexts.AddElement(JText);
      end; // for
      if E.FieldName = '' then Continue;
      L:= LoadLinks(E);
      JLinks:= TJSONObject.Create;
      JObj.AddPair('links', JLinks);
      JLinks.AddPair('persistentFields', GroupJson(L.Persistent, RowCap(L.Persistent), lsDfm));
      JLinks.AddPair('gridColumns', GroupJson(L.Grid, RowCap(L.Grid), lsDfm));
      JLinks.AddPair('editControls', GroupJson(L.Edit, RowCap(L.Edit), lsDfm));
      JLinks.AddPair('forms', GroupJson(L.Forms, RowCap(L.Forms), lsForm));
      JLinks.AddPair('code', GroupJson(L.Code, RowCap(L.Code), lsCode));
      JByName:= GroupJson(L.ByName, ByNameCap(L), lsByName);
      JByName.AddPair('candidateTables', TJSONNumber.Create(L.CandidateTables));
      JLinks.AddPair('codeByNameOnly', JByName);
    end; // for
    Writeln(JRoot.ToJSON);
  finally
    JRoot.Free;
  end; // try
end; // procedure

procedure TConceptRun.PrintEntityText(const pEntity: TEntity);
const
  ROW_FORMAT = ROW_INDENT + '%-17s %s   %s:%d';
var
  Line, Shown: string;
  T: TTextRow;
  L: TLinks;
  I: Integer;
begin
  Shown:= '';
  Line:= '';
  for T in LoadTexts(pEntity) do
    if not SameText(T.Place, PLACE_REPOSITORY_TEXT) and (TextKindIndex(T.Kind) <= CAPTION_CLASS_LAST) then
      Shown:= Shown + IfThen(Shown = '', '', ', ') + Format('"%s" (%d)', [T.Text, T.UseCount])
    else if (pEntity.FieldName = '') and (Line = '') then
      Line:= Format('%s "%s"', [T.Kind, T.Text]);
  if pEntity.FieldName = '' then
  begin
    if Line <> '' then Writeln(DETAIL_INDENT + Line);
    Exit;
  end;
  if pEntity.InRepo then
  begin
    Line:= Format('caption "%s"  %s', [pEntity.Caption, pEntity.TypeText]);
    if Shown <> '' then Line:= Line + '   also shown as: ' + Shown;
  end
  else
    Line:= 'shown as: ' + Shown;
  Writeln(DETAIL_INDENT + Line);
  L:= LoadLinks(pEntity);
  Line:= Format('persistent fields %d, grid columns %d, edit controls %d, forms %d, code %d, by name only %d',
    [Length(L.Persistent), Length(L.Grid), Length(L.Edit), Length(L.Forms), Length(L.Code), Length(L.ByName)]);
  if Length(L.ByName) > 0 then Line:= Line + Format(' (%d tables)', [L.CandidateTables]);
  Writeln(DETAIL_INDENT + Line);
  for I:= 0 to RowCap(L.Persistent) - 1 do
    Writeln(Format(ROW_FORMAT, [LINK_PERSISTENT, L.Persistent[I].Form + '.' + L.Persistent[I].Component,
      L.Persistent[I].FilePath, L.Persistent[I].Line]));
  for I:= 0 to RowCap(L.Grid) - 1 do
    Writeln(Format(ROW_FORMAT, [LINK_GRID, L.Grid[I].Form + '.' + L.Grid[I].Component, L.Grid[I].FilePath, L.Grid[I].Line]));
  for I:= 0 to RowCap(L.Edit) - 1 do
    Writeln(Format(ROW_FORMAT, [LINK_EDIT, L.Edit[I].Form + '.' + L.Edit[I].Component, L.Edit[I].FilePath, L.Edit[I].Line]));
  for I:= 0 to RowCap(L.Code) - 1 do
    Writeln(Format(ROW_FORMAT + '   %s', [LINK_CODE, L.Code[I].InName, L.Code[I].FilePath, L.Code[I].Line, L.Code[I].Via]));
  for I:= 0 to ByNameCap(L) - 1 do
  begin
    Line:= if L.ByName[I].Receiver = '' then L.ByName[I].Via else L.ByName[I].Receiver + '.' + L.ByName[I].Via;
    Writeln(Format(ROW_FORMAT + '   %s', ['by name only', L.ByName[I].InName, L.ByName[I].FilePath, L.ByName[I].Line, Line]));
  end;
end; // procedure

procedure TConceptRun.PrintText(pAllCount: Integer);
var
  H: THit;
  Rank: Integer;
begin
  Writeln(Format('concept "%s": %d hit(s) (%d match every word)', [FQuery.Words, FHits.Count, pAllCount]));
  Rank:= 0;
  for H in FHits do
  begin
    Inc(Rank);
    { The 1.55 line with ` place=<p>` appended (design 1.4): a reader anchored at the start keeps working. }
    Writeln(Format('  %d  %.2f  %-10s %s   %s:%d   [%s] place=%s',  // dl:ok locale-sensitive-conversion@7587 -- the 1.55 hit line with place appended: the same Format call as DRagLint.CLI.DoQueryConcept, so the line stays byte-identical
      [Rank, H.Score, H.Kind, H.QName, H.FilePath, H.Line, H.Matched, PLACE_NAMES[H.Place]]));
    if H.EntityIx <> NO_ENTITY then PrintEntityText(FEntities[H.EntityIx]);
  end; // for
end; // procedure

procedure TConceptRun.PrintNotes;
var
  Info: TPlaceInfo;
begin
  if FRepoNote <> '' then Writeln(ErrOutput, FRepoNote);
  for Info in FLibInfos do
    if Info.Note <> '' then Writeln(ErrOutput, Info.Note);
end; // procedure

function TConceptRun.Run(out pExitCode: Integer): Boolean;
var
  Error, Trimmed: string;
  StoreObj: TSQLiteSymbolStore;
  H: THit;
  AllCount: Integer;
  HasRepoHit: Boolean;
begin
  Result:= True;
  pExitCode:= EXIT_HITS;
  if not ParseFlags(Error) then
  begin
    Writeln(Error);
    pExitCode:= EXIT_USAGE;
    Exit;
  end;
  StoreObj:= TSQLiteSymbolStore.Create(FQuery.DbPath, {AReadOnly=}True);
  FStore:= StoreObj;
  if not FStore.ConceptSearchReady then Exit(False);
  FConn:= StoreObj.GetConnection;
  FHasTables:= FStore.HasConceptTables;
  SplitKinds;
  FWords:= ConceptFoldWords(FQuery.Words);
  Trimmed:= Trim(FQuery.Words);
  FSingle:= if (Trimmed <> '') and (Length(Trimmed.Split([' ', #9, #13, #10], TStringSplitOptions.ExcludeEmpty)) = 1)
    then Trimmed else '';
  ReadRepoCopy;
  ScanTexts;
  ScanNames;
  ResolveEntities;
  Assemble;
  AllCount:= 0;
  HasRepoHit:= False;
  for H in FHits do
  begin
    if H.Tier <= TIER_ALL_WORDS then Inc(AllCount);
    if H.Place = plRepository then HasRepoHit:= True;
  end;
  FinishRepoNote(HasRepoHit);
  if FQuery.AsJson then PrintJson(AllCount) else PrintText(AllCount);
  PrintNotes;
  pExitCode:= if FHits.Count > 0 then EXIT_HITS else EXIT_NONE;
end; // function

function TryRunConceptRepoQuery(const pQuery: TConceptRepoQuery; out pExitCode: Integer): Boolean;
var
  Run: TConceptRun;
begin
  pExitCode:= 0;
  Run:= TConceptRun.Create(pQuery);
  try
    Result:= Run.Run(pExitCode);
  finally
    Run.Free;
  end; // try
end; // function

end.
