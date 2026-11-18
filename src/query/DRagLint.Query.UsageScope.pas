unit DRagLint.Query.UsageScope;

{ Find Usages scope (1.52 lane FUSCOPE, owner N3 2026-11-17) -- the ONE place the
  four scopes are named, parsed, bound and turned into a database set, so the CLI
  verb, the LSP and the MCP tool cannot disagree on what a scope means.

  THE FOUR SCOPES (same words on every surface; the IDE captions are in brackets):
    symbol     [This symbol] -- the declaration the cursor (or a qualified name) is
                                BOUND to, in this project's index. The default.
    project    [Project]     -- every object of that NAME in this project's index
                                (the pre-1.52 answer: kind-blind, unbound rows too).
    group      [Group]       -- the name in every index of the project group.
    everywhere [Everywhere]  -- the name in every index the manifest knows.

  Symbol ids are per database, so only 'symbol' is bound; the three wider scopes
  match by name. }

interface

uses
  System.SysUtils,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces;

type
  /// <summary>The scope of one Find Usages question.</summary>
  /// <remarks>usSymbol = the bound declaration in this project (default);
  /// usProject = the name in this project; usGroup = the name in the project
  /// group; usEverywhere = the name in every indexed database.</remarks>
  TUsageScope = (usSymbol, usProject, usGroup, usEverywhere);

  /// <summary>What a Find Usages question is bound to in ONE store.</summary>
  /// <remarks>Bound = False means nothing was bound: the caller answers by name
  /// (scope project) and says so. When Bound, either HasDecl (Decl is a
  /// declaration of that store) or QName is a library target the store records
  /// as refs.external_target (no declaration in a project index).</remarks>
  TUsageBinding = record
    /// <summary>The bare identifier asked about, e.g. 'Run'.</summary>
    Ident: string;
    /// <summary>True when a declaration or an external target was bound.</summary>
    Bound: Boolean;
    /// <summary>True when Decl holds the bound declaration.</summary>
    HasDecl: Boolean;
    /// <summary>The bound declaration (valid only when HasDecl).</summary>
    Decl: TSymbol;
    /// <summary>The bound qualified name: Decl.QualifiedName, or the external
    /// target; '' when not Bound.</summary>
    QName: string;
  end;

const
  /// <summary>The scope words, as every surface spells them.</summary>
  USAGE_SCOPE_NAMES: array[TUsageScope] of string = ('symbol', 'project', 'group', 'everywhere');
  /// <summary>The IDE captions of the four scopes (submenu and panel combo).</summary>
  USAGE_SCOPE_CAPTIONS: array[TUsageScope] of string = ('This symbol', 'Project', 'Group', 'Everywhere');
  /// <summary>The scope a question gets when none is named.</summary>
  USAGE_SCOPE_DEFAULT = usSymbol;
  /// <summary>The note of a bare name asked in scope symbol (answered as scope project);
  /// one text for the CLI, the LSP and the MCP tool, so their documents agree.</summary>
  USAGE_NOTE_BARE_NAME = 'a bare name binds no symbol; answered scope project (a qualified name or a position binds one)';

/// <summary>Parses a scope word.</summary>
/// <param name="AText">'symbol' | 'project' | 'group' | 'everywhere', case-insensitive;
/// the IDE captions ('This symbol', ...) are accepted too.</param>
/// <param name="AScope">Receives the scope on True; USAGE_SCOPE_DEFAULT otherwise.</param>
/// <returns>True when AText names a scope. '' is not a scope (False).</returns>
function TryParseUsageScope(const AText: string; out AScope: TUsageScope): Boolean;

/// <summary>The scope words joined for a message: 'symbol|project|group|everywhere'.</summary>
/// <returns>The four words, '|'-separated, in enum order.</returns>
function UsageScopeChoices: string;

/// <summary>Binds the identifier at a source position to what the resolver bound
/// it to in AStore.</summary>
/// <param name="AStore">The project's store; must not be nil.</param>
/// <param name="AFile">The source file, absolute.</param>
/// <param name="AIdent">The identifier at the position (bare).</param>
/// <param name="ALine1">1-based line.</param>
/// <param name="ACol1">1-based column; 0 or less = any reference of AIdent on the line.</param>
/// <returns>The binding. A reference at the position wins: bound to its
/// refs.symbol_id declaration, else to its external target. With no reference
/// there, a declaration of AIdent in AFile whose declaration, forward or
/// implementation header line is ALine1 is bound. Otherwise Bound = False.</returns>
/// <remarks>Uses the index's own binding (refs.symbol_id), the same one the
/// symbol-scope filter reads, so the cursor's symbol and its usage set agree.</remarks>
function BindUsageAt(const AStore: ISymbolStore; const AFile, AIdent: string; ALine1, ACol1: Integer): TUsageBinding;

/// <summary>The identifier at a 1-based position of a source file (a position
/// with no name: `usages --in F --line L --col C`, the MCP find_usages tool).</summary>
/// <param name="AFile">The source file.</param>
/// <param name="ALine1">1-based line.</param>
/// <param name="ACol1">1-based column; 0 or less = the first identifier on the line.</param>
/// <returns>The identifier, or '' when the file, line or column has none.</returns>
function IdentifierAtFilePosition(const AFile: string; ALine1, ACol1: Integer): string;

/// <summary>The usage rows of a binding: the refs the resolver bound to it.</summary>
/// <param name="AStore">The store the binding was made in.</param>
/// <param name="ABinding">A Bound binding.</param>
/// <param name="ADecls">Receives the declaration rows to report: [Decl] or empty.</param>
/// <returns>DRagLint.Query.Callers.UsageRefsForName over the bound name and
/// declaration -- unbound and other same-named rows are left out.</returns>
function BoundUsageRefs(const AStore: ISymbolStore; const ABinding: TUsageBinding;
  out ADecls: TArray<TSymbol>): TArray<TReference>;

/// <summary>The databases a scope reads.</summary>
/// <param name="AScope">The effective scope.</param>
/// <param name="AProjectDbs">The project's own databases (the --db list or the
/// database --in resolved); they come first, in order.</param>
/// <param name="AGroupFile">A .groupproj; read for usGroup only. '' = no group file.</param>
/// <param name="APlatform">The platform for usEverywhere ('' = the manifest default).</param>
/// <param name="ANote">Receives a one-line note when the set is narrower than
/// asked (no group file, manifest unreadable); '' otherwise.</param>
/// <returns>usSymbol / usProject: AProjectDbs WithoutLibraryDbs (1.52 INT8: a
/// library-*.sqlite is not this project's index). usGroup: AProjectDbs plus the
/// database of every project the group file lists (manifest owner first, else
/// &lt;project folder&gt;\_D-RAG\&lt;base&gt;.sqlite) that exists. usEverywhere:
/// AProjectDbs plus every existing database the manifest selects for the
/// platform. Case-insensitive duplicates are dropped.</returns>
function UsageScopeDbs(AScope: TUsageScope; const AProjectDbs: TArray<string>;
  const AGroupFile, APlatform: string; out ANote: string): TArray<string>;

/// <summary>Is APath a platform LIBRARY index (file name library-&lt;platform&gt;.sqlite,
/// the convention the LSP's caller scoping has always used)?</summary>
/// <param name="APath">A database path; only its file name is read.</param>
/// <returns>True when the file name starts with 'library-' (case-insensitive).</returns>
function IsLibraryDbPath(const APath: string): Boolean;

/// <summary>Does AScope answer from this project's own index only? symbol and project do
/// (a library database's rows are not "in this project", INT8 1.52); group and everywhere
/// read every database they name.</summary>
/// <param name="AScope">The scope answered.</param>
/// <returns>True for usSymbol and usProject.</returns>
function UsageScopeExcludesLibraries(AScope: TUsageScope): Boolean;

/// <summary>APaths without the library databases (IsLibraryDbPath), for a scope that
/// UsageScopeExcludesLibraries.</summary>
/// <param name="APaths">The databases a question was given, in order.</param>
/// <returns>The non-library paths in order; APaths unchanged when every one is a library
/// (a library asked alone is still answered) or none is.</returns>
function WithoutLibraryDbs(const APaths: TArray<string>): TArray<string>;


implementation

uses
  System.Classes,
  System.IOUtils,
  System.RegularExpressions,
  System.StrUtils,
  DRagLint.Query.Callers,
  DRagLint.Resolver.TypeAt,
  DRagLint.Index.Manifest,
  DRagLint.Index.DbSelect,
  DRagLint.Project.Resolver;

const
  DRAG_DIR = '_D-RAG';
  DB_EXT = '.sqlite';

function TryParseUsageScope(const AText: string; out AScope: TUsageScope): Boolean;
begin
  AScope:= USAGE_SCOPE_DEFAULT;
  var Word: string:= Trim(AText);
  for var S:= Low(TUsageScope) to High(TUsageScope) do
    if SameText(Word, USAGE_SCOPE_NAMES[S]) or SameText(Word, USAGE_SCOPE_CAPTIONS[S]) then
    begin
      AScope:= S;
      Exit(True);
    end;
  Result:= False;
end;

function UsageScopeChoices: string;
begin
  Result:= '';
  for var S:= Low(TUsageScope) to High(TUsageScope) do
    Result:= Result + (if Result = '' then '' else '|') + USAGE_SCOPE_NAMES[S];
end;

{ A binding to one declaration of AStore. }
function DeclBinding(const AIdent: string; const ADecl: TSymbol): TUsageBinding;
begin
  Result:= Default(TUsageBinding);
  Result.Ident  := AIdent;
  Result.Bound  := True;
  Result.HasDecl:= True;
  Result.Decl   := ADecl;
  Result.QName  := ADecl.QualifiedName;
end;

function BindUsageAt(const AStore: ISymbolStore; const AFile, AIdent: string; ALine1, ACol1: Integer): TUsageBinding;
begin
  Result:= Default(TUsageBinding);
  Result.Ident:= AIdent;
  if (AStore = nil) or (AIdent = '') or (ALine1 <= 0) then Exit;
  var FileId: Int64:= AStore.FindFileIdByPath(AFile);
  if FileId <= 0 then Exit;

  { 1. A reference at the position: what the resolver bound it to. }
  for var R: TReference in AStore.FindCallersByName(AIdent) do
  begin
    if (R.FileId <> FileId) or (R.StartLine <> ALine1) then Continue;
    if (ACol1 > 0) and ((ACol1 < R.StartCol) or (ACol1 > R.EndCol)) then Continue;
    if R.SymbolId > 0 then
    begin
      var D: TSymbol:= AStore.GetSymbolById(R.SymbolId);
      if D.Id > 0 then Exit(DeclBinding(AIdent, D));
    end;
    if R.ExternalTarget <> '' then
    begin
      Result.Bound:= True;
      Result.QName:= R.ExternalTarget;
      Exit;
    end;
  end;

  { 2. The cursor is ON a declaration: its own, forward or implementation header line. }
  for var D: TSymbol in AStore.FindSymbolsByExactName(AIdent) do
    if (D.FileId = FileId) and ((D.StartLine = ALine1) or (D.ForwardLine = ALine1) or (D.ImplStartLine = ALine1)) then
      Exit(DeclBinding(AIdent, D));
end;

function IdentifierAtFilePosition(const AFile: string; ALine1, ACol1: Integer): string;
begin
  Result:= '';
  if not TFile.Exists(AFile) then Exit;
  var Lines: TArray<string>:= TFile.ReadAllLines(AFile);  // dl:ok taint-path-traversal@4ce1 -- REVIEWED 2026-11-18 FUSCOPE: reads the source file the user named (--in / the MCP file argument); reading it is the point
  if (ALine1 < 1) or (ALine1 > Length(Lines)) then Exit;
  var Text: string:= Lines[ALine1 - 1];
  var Col: Integer:= ACol1;
  if Col <= 0 then
  begin
    Col:= 1;
    while (Col <= Length(Text)) and not CharInSet(Text[Col], ['A'..'Z', 'a'..'z', '_']) do Inc(Col);
  end;
  var PrecedingDot: Boolean;
  var Lhs: string;
  Result:= TTypeAtResolver.ExtractTokenAt(Text, Col, PrecedingDot, Lhs);
end;

function BoundUsageRefs(const AStore: ISymbolStore; const ABinding: TUsageBinding;
  out ADecls: TArray<TSymbol>): TArray<TReference>;
begin
  ADecls:= nil;
  Result:= nil;
  if (AStore = nil) or not ABinding.Bound then Exit;
  if ABinding.HasDecl then ADecls:= [ABinding.Decl];
  { UsageRefsForName takes the qualified (bound) path for a dotted name: the refs of
    its last segment the resolver bound to ADecls, plus the external-target rows. A
    declaration whose qualified name carries no dot gets one, so it still takes that
    path; the external match cannot hit a leading-dot name. }
  var QName: string:= ABinding.QName;
  if not QName.Contains('.') then QName:= '.' + QName;
  Result:= UsageRefsForName(AStore, QName, ADecls);
end;

{ The project files a .groupproj lists, absolute, in file order; empty when the file is missing. }
function GroupProjectFiles(const AGroupFile: string): TArray<string>;
begin
  Result:= nil;
  if (AGroupFile = '') or not TFile.Exists(AGroupFile) then Exit;
  var Dir: string:= ExtractFilePath(ExpandFileName(AGroupFile));
  var Text: string:= TFile.ReadAllText(AGroupFile);  // dl:ok taint-path-traversal@d6d4 -- REVIEWED 2026-11-18 FUSCOPE: reads the project group file the user named (--group / the IDE open group); reading it is the point
  for var M: TMatch in TRegEx.Matches(Text, '<Projects\s+Include="([^"]+)"', [roIgnoreCase]) do
    Result:= Result + [ExpandFileName(TPath.Combine(Dir, M.Groups[1].Value))];
end;

procedure AddUnique(var AList: TArray<string>; const APath: string);
begin
  if APath = '' then Exit;
  var Full: string:= ExpandFileName(APath);
  for var Have: string in AList do
    if SameText(ExpandFileName(Have), Full) then Exit;
  AList:= AList + [Full];
end;

{ The index of one project of a group: the manifest's owner, else the conventional path. }
function GroupMemberDb(const AManifest: TIndexManifest; AHaveManifest: Boolean; const AProject: string): string;
begin
  Result:= '';
  if AHaveManifest then
  begin
    var Db: string;
    var Claimants: TArray<string>;
    if (ResolveProjectDb(AManifest, AProject, Db, Claimants) = pdmUnique) and TFile.Exists(Db) then Exit(Db);
  end;
  var Conventional: string:= TPath.Combine(TPath.Combine(ExtractFilePath(AProject), DRAG_DIR),
    ChangeFileExt(ExtractFileName(AProject), DB_EXT));
  if TFile.Exists(Conventional) then Result:= Conventional;
end;

function UsageScopeDbs(AScope: TUsageScope; const AProjectDbs: TArray<string>;
  const AGroupFile, APlatform: string; out ANote: string): TArray<string>;
begin
  ANote:= '';
  Result:= nil;
  for var Db: string in AProjectDbs do AddUnique(Result, Db);
  if UsageScopeExcludesLibraries(AScope) then Exit(WithoutLibraryDbs(Result));

  var Manifest: TIndexManifest:= Default(TIndexManifest);
  var HaveManifest: Boolean:= False;
  try
    Manifest:= TManifestIO.Load(ExtractFilePath(ParamStr(0)), GetCurrentDir);
    HaveManifest:= True;
  except
    on E: Exception do ANote:= 'manifest not read (' + E.Message + ')';
  end;

  if AScope = usGroup then
  begin
    if AGroupFile = '' then
    begin
      ANote:= 'scope group: no project group file given (--group <x.groupproj>); the group is the --db list';
      Exit;
    end;
    if not TFile.Exists(AGroupFile) then
    begin
      ANote:= 'scope group: project group file not found: ' + AGroupFile;
      Exit;
    end;
    for var Proj: string in GroupProjectFiles(AGroupFile) do AddUnique(Result, GroupMemberDb(Manifest, HaveManifest, Proj));
    Exit;
  end;

  { usEverywhere }
  if not HaveManifest then Exit;
  var Platform: string:= if APlatform <> '' then APlatform else Manifest.Settings.DefaultPlatform;
  var Resolver: TProjectResolver:= TProjectResolver.Create;
  try
    for var Db: string in TDbSelect.Resolve(Manifest, Platform, Resolver, True) do AddUnique(Result, Db);
  finally
    Resolver.Free;
  end;
end;

function IsLibraryDbPath(const APath: string): Boolean;
begin
  Result:= StartsText('library-', ExtractFileName(APath));
end;

function UsageScopeExcludesLibraries(AScope: TUsageScope): Boolean;
begin
  Result:= AScope in [usSymbol, usProject];
end;

function WithoutLibraryDbs(const APaths: TArray<string>): TArray<string>;
begin
  Result:= nil;
  for var P: string in APaths do
    if not IsLibraryDbPath(P) then Result:= Result + [P];
  if Result = nil then Result:= APaths;
end;

end.
