unit DRagLint.Refactor.RedundantCast;

// ---------------------------------------------------------------------------
// `lint --fix --fix-rule redundant-cast`: removes hard casts whose operand already has exactly the target type (lane 144,
// item 1 of docs\wiki\redundant-cast-fix.md). The static proof reads ref_types (F1) and refuses by name whatever it
// cannot prove; every applied rewrite then passes the compile gate (DRagLint.Refactor.CompileGate).
// Identity only: an upcast can change which hidden non-virtual member binds, so it is never touched.
// ---------------------------------------------------------------------------

interface

uses
  System.SysUtils, DRagLint.Core.Interfaces;

type
  /// <summary>The flags of one `lint --fix --fix-rule redundant-cast` run.</summary>
  TRedundantCastOptions = record
    /// <summary>--project: required with --apply; bounds the edit to the project's own roots.</summary>
    Project: string;
    /// <summary>--platform, '' = win64.</summary>
    Platform: string;
    /// <summary>--rsvars, '' = the Studio the registry / BDS names.</summary>
    RsVars: string;
    /// <summary>--build-timeout in whole seconds, as typed; '' or '0' = no limit.</summary>
    BuildTimeout: string;
    /// <summary>The file named on the command line; '' = every file of the index.</summary>
    Target: string;
    /// <summary>--fix-line: only the casts on this line; 0 = all.</summary>
    Line: Integer;
    /// <summary>--apply: write through the compile gate.</summary>
    Apply: Boolean;
    /// <summary>--no-backup (apply only).</summary>
    NoBackup: Boolean;
    /// <summary>--no-compile: legal on the dry run only (which builds nothing anyway); refused with --apply.</summary>
    NoCompile: Boolean;
    /// <summary>--format json.</summary>
    Json: Boolean;
  end;

  /// <summary>One cast the planner looked at.</summary>
  TCastSite = record
    /// <summary>The file.</summary>
    FilePath: string;
    /// <summary>1-based line of the cast's type name.</summary>
    Line: Integer;
    /// <summary>1-based column of the cast's type name.</summary>
    Col: Integer;
    /// <summary>1-based column one past the closing parenthesis; 0 when the shape was not read.</summary>
    EndCol: Integer;
    /// <summary>The cast as written, or the type name alone when the parenthesis was not read.</summary>
    CastText: string;
    /// <summary>The text that replaces the cast; '' on a refusal.</summary>
    OperandText: string;
    /// <summary>'' for a fix; else the refusal's name.</summary>
    Kind: string;
    /// <summary>Why, in words; '' for a fix.</summary>
    Reason: string;
  end;

  /// <summary>The verdict over one index.</summary>
  TCastPlan = record
    /// <summary>The casts proved identity, in file and line order.</summary>
    Fixes: TArray<TCastSite>;
    /// <summary>Every cast that could be one and could not be proved, each with its named reason.</summary>
    Refused: TArray<TCastSite>;
    /// <summary>The casts between two different types: real conversions, in neither list.</summary>
    NotIdentity: Integer;
  end;

  /// <summary>A source file read once: its text, the same text with comments and strings blanked, and its lines.</summary>
  /// <remarks>Masked has the length of Text, so an offset means the same in both. Comments become spaces, string
  /// literals #1; line breaks stay. Line numbers are 1-based, as in the index.</remarks>
  TMaskedSource = class
  strict private
    procedure Scan;
  public
    /// <summary>The file; '' for CreateFromText.</summary>
    Path: string;  // dl:ok public-field@4449 -- a read-only view of one file, read in tight scan loops; the class owns no invariant to guard
    /// <summary>The decoded text.</summary>
    Text: string;  // dl:ok public-field@c27a -- a read-only view of one file, read in tight scan loops; the class owns no invariant to guard
    /// <summary>The file's encoding; nil for CreateFromText.</summary>
    Enc: TEncoding;  // dl:ok public-field@df5f -- a read-only view of one file, read in tight scan loops; the class owns no invariant to guard
    /// <summary>Text with comments and strings blanked.</summary>
    Masked: string;  // dl:ok public-field@4fd5 -- a read-only view of one file, read in tight scan loops; the class owns no invariant to guard
    /// <summary>The 1-based offset of each line; index 0 is unused.</summary>
    Starts: TArray<Integer>;  // dl:ok public-field@1872 -- a read-only view of one file, read in tight scan loops; the class owns no invariant to guard
    /// <summary>Per line: inside, or holding an edge of, a conditional region.</summary>
    CondAt: TArray<Boolean>;  // dl:ok public-field@c356 -- a read-only view of one file, read in tight scan loops; the class owns no invariant to guard
    /// <summary>Per line: holds a compiler directive.</summary>
    DirAt: TArray<Boolean>;  // dl:ok public-field@b487 -- a read-only view of one file, read in tight scan loops; the class owns no invariant to guard
    /// <summary>Reads and scans a file.</summary>
    /// <param name="pPath">The file.</param>
    constructor Create(const pPath: string);
    /// <summary>Scans text already in memory.</summary>
    /// <param name="pText">The text.</param>
    constructor CreateFromText(const pText: string);
    /// <summary>The offset of a line and column.</summary>
    /// <param name="pLine">1-based line.</param>
    /// <param name="pCol">1-based column.</param>
    /// <returns>The 1-based offset; 0 when there is no such line.</returns>
    function OffsetOf(pLine, pCol: Integer): Integer;
    /// <summary>The offset one past a line's last character, its line break excluded.</summary>
    /// <param name="pLine">1-based line; must exist.</param>
    /// <returns>The offset.</returns>
    function LineEnd(pLine: Integer): Integer;
    /// <summary>The line holding an offset.</summary>
    /// <param name="pOffset">1-based offset.</param>
    /// <returns>The 1-based line.</returns>
    function LineOf(pOffset: Integer): Integer;
  end;

  /// <summary>Raised when the index predates ref_types: there is no fact to prove anything with.</summary>
  ENoRefTypes = class(Exception);

/// <summary>Decides every hard cast of an index: fix, named refusal, or a real conversion.</summary>
/// <param name="pStore">The project's index; must be a SQLite store with ref_types.</param>
/// <param name="pLibraries">The platform library indexes, or none; they prove ancestors and name clashes.</param>
/// <param name="pOpts">Project, Target and Line bound the run.</param>
/// <returns>The plan. Reads the source files; writes nothing.</returns>
/// <remarks>A cast is fixed only when ALL of these hold; the first that fails names the refusal: the file is what the
/// index read (stale-file), a source unit (include-file) and inside the project (outside-roots); the callee is a bare
/// name with its parenthesis on the same line, no comment and no directive (not-a-plain-cast, multi-line, comment-in-cast,
/// ifdef-line); the operand is a plain identifier chain, calls allowed, no index, dereference or operator (operand-shape),
/// holds no other cast (nested-cast: inner first, the outer one after a re-index), and its last name has a typed ref_types
/// row (operand-untyped, operand-type-unresolved, type-not-indexed); that type IS the target type by symbol id (else a
/// conversion, or alias-not-identical when an alias is involved); the name means one type and nothing else in the project
/// and the libraries (ambiguous-type-name), a non-generic (generic-type), non-procedural one, since a procedural value
/// without a cast may be CALLED (procedural-type); the operand does not name an overloaded routine (overloaded-operand);
/// neither the type nor the operand is declared under a conditional (conditional-decl); no `with` precedes it in its
/// routine (with-body); every ancestor of the enclosing class is indexed (unresolved-ancestor).</remarks>
/// <exception cref="ENoRefTypes">The index has no ref_types table.</exception>
function PlanRedundantCasts(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>;  // dl:ok unused-public-symbol@8fa5 -- public API for the next gated rewrites (items 3 and 4) and the owed report rule
  const pOpts: TRedundantCastOptions): TCastPlan;

/// <summary>Runs the verb: prints the plan and, with --apply, writes the fixes through ApplyGated.</summary>
/// <param name="pStore">The project's index.</param>
/// <param name="pLibraries">The platform library indexes, or none.</param>
/// <param name="pOpts">The flags.</param>
/// <returns>0: dry run, or applied and built (or nothing to do). 1: the gate refused and the project is unchanged.
/// 2: bad flags, an index without ref_types, or a rollback that failed.</returns>
function RunRedundantCastFix(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>;
  const pOpts: TRedundantCastOptions): Integer;

/// <summary>True when the file on disk is what the index read (mtime and sha, the basis of CycleFix's stale gate).</summary>
/// <param name="pStore">The index.</param>
/// <param name="pPath">The file; must exist.</param>
/// <returns>False when it changed since it was indexed.</returns>
function IsFileCurrent(const pStore: ISymbolStore; const pPath: string): Boolean;

/// <summary>The last code character before an offset.</summary>
/// <param name="pMasked">The masked text.</param>
/// <param name="pAt">The offset.</param>
/// <param name="pOffset">Receives that character's offset; 0 when there is none.</param>
/// <returns>The character, #0 when there is none.</returns>
function LastCodeChar(const pMasked: string; pAt: Integer; out pOffset: Integer): Char;

implementation

uses
  System.IOUtils, System.JSON, System.StrUtils, System.RegularExpressions, System.Hash, System.Math, Winapi.Windows,
  System.Generics.Collections, System.Generics.Defaults,
  FireDAC.Comp.Client,
  DRagLint.Core.FileTime, DRagLint.Project.OwnRoots, DRagLint.Report.CyclePlan, DRagLint.Refactor.CompileGate,
  DRagLint.Storage.SQLite;

const
  CMaskString  = #1;     // a string literal's characters in the masked text
  CMaxChain    = 64;     // an ancestor chain longer than this is a cycle, and unproved
  CExitOk      = 0;
  CExitRefused = 1;
  CExitError   = 2;
  CMsPerSec    = 1000;
  CFixRule     = 'lint --fix --fix-rule redundant-cast';
  CSchema      = 'redundant-cast/1';

type
  TNameRow = record
    Kind, QName, GenericParams: string;
  end;

  TSymRow = record
    Found: Boolean;
    Kind, QName, Signature, Heritage, GenericParams, Path: string;
    ParentId: Int64;
    StartLine, ImplStart: Integer;
  end;

  /// <summary>One planning run; owns the file and symbol caches.</summary>
  TCastPlanner = class  // dl:ok high-response@2693 -- one planner class holds one proof and its caches
  strict private
    FStore     : ISymbolStore;
    FConn      : TFDConnection;
    FLibConns  : TArray<TFDConnection>;
    FOpts      : TRedundantCastOptions;
    FOwn       : TOwnRoots;
    FFiles     : TObjectDictionary<string, TMaskedSource>;
    FStamp     : TDictionary<string, Boolean>;
    FNames     : TDictionary<string, TArray<TNameRow>>;
    FSyms      : TDictionary<Int64, TSymRow>;
    FChains    : TDictionary<string, string>;
    FCastSpans : TDictionary<string, TList<Integer>>;
    FFixes     : TList<TCastSite>;
    FRefused   : TList<TCastSite>;
    FNotIdent  : Integer;
    function FileOf(const pPath: string): TMaskedSource;
    function StampOk(const pPath: string): Boolean;
    function NamesOf(const pName: string): TArray<TNameRow>;
    function SymOf(pId: Int64): TSymRow;
    function InScope(const pPath: string; pLine: Integer): Boolean;
    function HasOverloads(const pSym: TSymRow; const pName: string): Boolean;
    function UnresolvedAncestorOf(pEnclosing: Int64): string;
    function RoutineStartLine(pEnclosing: Int64): Integer;
    function CastColsOf(pFileId: Int64; pLine: Integer): TList<Integer>;
    function DeclIsConditional(const pSym: TSymRow): Boolean;
    procedure Decide(pFileId: Int64; const pPath: string; pLine, pCol: Integer; const pName: string;
      pTypeId, pEnclosing: Int64);
    procedure ReadCastRows;
    procedure ReadUntypedCalls;
    procedure Refuse(const pSite: TCastSite; const pKind, pReason: string);
  public
    constructor Create(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>; const pOpts: TRedundantCastOptions);
    destructor Destroy; override;
    function Run: TCastPlan;
  end;

{ ---- the masked text ------------------------------------------------------------------------------- }

constructor TMaskedSource.Create(const pPath: string);
begin
  inherited Create;
  Path:= pPath;
  Text:= DecodeSource(TFile.ReadAllBytes(pPath), Enc);
  Scan;
end;

constructor TMaskedSource.CreateFromText(const pText: string);
begin
  inherited Create;
  Text:= pText;
  Scan;
end;

// Blanks comments with spaces and string literals with CMaskString, keeping every offset, and notes per line where
// the directives and the conditional regions are.
procedure TMaskedSource.Scan;
var
  Depth, I, LineNo: Integer;

  procedure NewLine(pAt: Integer);
  begin
    Inc(LineNo);
    SetLength(Starts, LineNo + 1);
    SetLength(CondAt, LineNo + 1);
    SetLength(DirAt, LineNo + 1);
    Starts[LineNo]:= pAt;
    CondAt[LineNo]:= Depth > 0;
  end;

  procedure Directive(pFrom, pTo: Integer);
  begin
    DirAt[LineNo]:= True;
    var Word:= UpperCase(TRegEx.Match(Copy(Text, pFrom, pTo - pFrom), '^\s*\$\s*(\w+)').Groups[1].Value);
    if MatchStr(Word, ['IF', 'IFDEF', 'IFNDEF', 'IFOPT']) then
    begin
      Inc(Depth);
      CondAt[LineNo]:= True;
    end
    else if MatchStr(Word, ['ENDIF', 'IFEND']) then
    begin
      CondAt[LineNo]:= True;
      if Depth > 0 then Dec(Depth);
    end
    else if MatchStr(Word, ['ELSE', 'ELSEIF']) then CondAt[LineNo]:= True;
  end;

  procedure Blank(pFrom, pTo: Integer; pWith: Char);
  begin
    for var K:= pFrom to pTo do
      if not CharInSet(Masked[K], [#13, #10]) then Masked[K]:= pWith;
  end;

  // pFrom is the comment's first character; returns the offset of its last.
  function SkipComment(pFrom, pOpenLen: Integer; const pClose: string): Integer;
  begin
    var Stop:= PosEx(pClose, Text, pFrom + pOpenLen);
    Result:= if Stop = 0 then Length(Text) else Stop + Length(pClose) - 1;
    if (pFrom + pOpenLen <= Length(Text)) and (Text[pFrom + pOpenLen] = '$') then
      Directive(pFrom + pOpenLen, if Stop = 0 then Result else Stop);
    Blank(pFrom, Result, ' ');
    for var K:= pFrom to Result do
      if Text[K] = #10 then NewLine(K + 1);
  end;

begin
  Masked:= Text;
  UniqueString(Masked);
  Depth := 0;
  LineNo:= 0;
  NewLine(1);
  I:= 1;
  while I <= Length(Text) do
  begin
    var C:= Text[I];
    if C = #10 then NewLine(I + 1)
    else if C = '{' then I:= SkipComment(I, 1, '}')
    else if (C = '(') and (I < Length(Text)) and (Text[I + 1] = '*') then I:= SkipComment(I, 2, '*)')
    else if (C = '/') and (I < Length(Text)) and (Text[I + 1] = '/') then
    begin
      var Stop:= I;
      while (Stop < Length(Text)) and not CharInSet(Text[Stop + 1], [#13, #10]) do Inc(Stop);
      Blank(I, Stop, ' ');
      I:= Stop;
    end
    else if C = '''' then
    begin
      var Stop:= I;
      while (Stop < Length(Text)) and not CharInSet(Text[Stop + 1], ['''', #13, #10]) do Inc(Stop);
      if (Stop < Length(Text)) and (Text[Stop + 1] = '''') then Inc(Stop);
      Blank(I, Stop, CMaskString);
      I:= Stop;
    end;
    Inc(I);
  end;
end;

function TMaskedSource.OffsetOf(pLine, pCol: Integer): Integer;
begin
  if (pLine < 1) or (pLine > High(Starts)) then Exit(0);
  Result:= Starts[pLine] + pCol - 1;
end;

function TMaskedSource.LineOf(pOffset: Integer): Integer;
begin
  var Lo:= 1;
  var Hi:= High(Starts);
  while Lo < Hi do
  begin
    var Mid:= (Lo + Hi + 1) div 2;
    if Starts[Mid] <= pOffset then Lo:= Mid else Hi:= Mid - 1;
  end;
  Result:= Lo;
end;

function TMaskedSource.LineEnd(pLine: Integer): Integer;
begin
  Result:= if pLine < High(Starts) then Starts[pLine + 1] else Length(Text) + 1;
  while (Result > Starts[pLine]) and CharInSet(Text[Result - 1], [#13, #10]) do Dec(Result);
end;

{ ---- the operand's shape ------------------------------------------------------------------------- }

function IsIdentStart(pC: Char): Boolean;
begin
  Result:= CharInSet(pC, ['A'..'Z', 'a'..'z', '_']);
end;

function IsIdentPart(pC: Char): Boolean;
begin
  Result:= CharInSet(pC, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

// The offset of the parenthesis closing the one at pOpen, within [pOpen, pEnd); 0 when the line ends first.
function MatchingParen(const pMasked: string; pOpen, pEnd: Integer): Integer;
begin
  var Depth:= 0;
  for var I:= pOpen to pEnd - 1 do
    if pMasked[I] = '(' then Inc(Depth)
    else if pMasked[I] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then Exit(I);
    end;
  Result:= 0;
end;

// Reads `a.b(args).c` from pFrom up to pClose (exclusive). True when the operand is exactly such a chain; pLast is the
// offset of its last identifier, pLen that identifier's length. pWhy names what stopped it otherwise.
function ChainEnd(const pMasked: string; pFrom, pClose: Integer; out pLast, pLen: Integer; out pWhy: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  pLast := 0;
  pLen  := 0;
  pWhy  := 'the operand is not an identifier chain';
  I:= pFrom;
  while True do
  begin
    while (I < pClose) and (pMasked[I] = ' ') do Inc(I);
    if (I >= pClose) or not IsIdentStart(pMasked[I]) then
    begin
      if (I < pClose) and (pMasked[I] = CMaskString) then pWhy:= 'the operand is a literal';
      Exit;
    end;
    pLast:= I;
    while (I < pClose) and IsIdentPart(pMasked[I]) do Inc(I);
    pLen:= I - pLast;
    if MatchText(Copy(pMasked, pLast, pLen), ['nil', 'not', 'inherited', 'True', 'False']) then
    begin
      pWhy:= 'the operand is the keyword or constant ' + Copy(pMasked, pLast, pLen);
      Exit;
    end;
    while (I < pClose) and (pMasked[I] = ' ') do Inc(I);
    if (I < pClose) and (pMasked[I] = '(') then
    begin
      var Close:= MatchingParen(pMasked, I, pClose);
      if Close = 0 then Exit;
      I:= Close + 1;
      while (I < pClose) and (pMasked[I] = ' ') do Inc(I);
    end;
    if I >= pClose then Exit(True);
    if pMasked[I] = '.' then
    begin
      Inc(I);
      Continue;
    end;
    case pMasked[I] of
      '[': pWhy:= 'the operand is indexed: its ref types the array or list, not the element';
      '^': pWhy:= 'the operand is dereferenced: its ref types the pointer, not the target';
    else pWhy:= 'the operand is an expression, not an identifier chain';
    end;
    Exit;
  end;
end;

{ ---- the planner ------------------------------------------------------------------------------------ }

function LastCodeChar(const pMasked: string; pAt: Integer; out pOffset: Integer): Char;
begin
  pOffset:= pAt - 1;
  while (pOffset >= 1) and CharInSet(pMasked[pOffset], [' ', #9, #13, #10]) do Dec(pOffset);
  Result:= if pOffset >= 1 then pMasked[pOffset] else #0;
end;

constructor TCastPlanner.Create(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>; const pOpts: TRedundantCastOptions);
begin
  inherited Create;
  FStore:= pStore;
  FOpts := pOpts;
  if pStore is not TSQLiteSymbolStore then raise ENoRefTypes.Create('the index is not a SQLite index');
  FConn:= (pStore as TSQLiteSymbolStore).GetConnection;
  for var L in pLibraries do
    if L is TSQLiteSymbolStore then FLibConns:= FLibConns + [(L as TSQLiteSymbolStore).GetConnection];
  if pOpts.Project <> '' then FOwn:= TOwnRoots.Load(ExtractFilePath(ExpandFileName(pOpts.Project)));
  FFiles    := TObjectDictionary<string, TMaskedSource>.Create([doOwnsValues]);
  FStamp    := TDictionary<string, Boolean>.Create;
  FNames    := TDictionary<string, TArray<TNameRow>>.Create;
  FSyms     := TDictionary<Int64, TSymRow>.Create;
  FChains   := TDictionary<string, string>.Create;
  FCastSpans:= TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  FFixes    := TList<TCastSite>.Create;
  FRefused  := TList<TCastSite>.Create;
end;

destructor TCastPlanner.Destroy;
begin
  FRefused.Free;
  FFixes.Free;
  FCastSpans.Free;
  FChains.Free;
  FSyms.Free;
  FNames.Free;
  FStamp.Free;
  FFiles.Free;
  inherited Destroy;
end;

function TCastPlanner.FileOf(const pPath: string): TMaskedSource;
begin
  var Key:= LowerCase(pPath);
  if not FFiles.TryGetValue(Key, Result) then
  begin
    Result:= TMaskedSource.Create(pPath);
    FFiles.Add(Key, Result);
  end;
end;

function IsFileCurrent(const pStore: ISymbolStore; const pPath: string): Boolean;
begin
  Result:= pStore.FileIsUpToDate(pPath, FileMTimeUnix(pPath), THashSHA2.GetHashString(TEncoding.ANSI.GetString(TFile.ReadAllBytes(pPath))));
end;

function TCastPlanner.StampOk(const pPath: string): Boolean;
begin
  var Key:= LowerCase(pPath);
  if FStamp.TryGetValue(Key, Result) then Exit;
  Result:= TFile.Exists(pPath) and IsFileCurrent(FStore, pPath);
  FStamp.Add(Key, Result);
end;

// Every symbol of that name, of any kind, in the project and the libraries.
function TCastPlanner.NamesOf(const pName: string): TArray<TNameRow>;
var
  Rows: TList<TNameRow>;

  procedure ReadFrom(pConn: TFDConnection);
  begin
    var Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= pConn;
      Q.SQL.Text:= 'SELECT kind, qualified_name, generic_params FROM symbols WHERE name = :n COLLATE NOCASE';
      Q.ParamByName('n').AsWideString:= pName;
      Q.Open;
      while not Q.Eof do
      begin
        var R: TNameRow;
        R.Kind         := Q.FieldByName('kind').AsString;  // dl:ok field-by-name-in-loop@bdc2 -- a few thousand rows at most; column names beat positions (magic-literal) here
        R.QName        := Q.FieldByName('qualified_name').AsString;
        R.GenericParams:= Q.FieldByName('generic_params').AsString;
        Rows.Add(R);
        Q.Next;
      end;
    finally
      Q.Free;
    end;
  end;

begin
  var Key:= LowerCase(pName);
  if FNames.TryGetValue(Key, Result) then Exit;
  Rows:= TList<TNameRow>.Create;
  try
    ReadFrom(FConn);
    for var C in FLibConns do ReadFrom(C);
    Result:= Rows.ToArray;
  finally
    Rows.Free;
  end;
  FNames.Add(Key, Result);
end;

function TCastPlanner.SymOf(pId: Int64): TSymRow;
begin
  if FSyms.TryGetValue(pId, Result) then Exit;
  Result:= Default(TSymRow);
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT s.kind, s.qualified_name, s.signature, s.heritage, s.generic_params, s.parent_id, s.start_line, ' +
                 's.impl_start_line, f.path FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.id = :i';
    Q.ParamByName('i').AsLargeInt:= pId;
    Q.Open;
    if not Q.Eof then
    begin
      Result.Found        := True;
      Result.Kind         := Q.FieldByName('kind').AsString;
      Result.QName        := Q.FieldByName('qualified_name').AsString;
      Result.Signature    := Q.FieldByName('signature').AsString;
      Result.Heritage     := Q.FieldByName('heritage').AsString;
      Result.GenericParams:= Q.FieldByName('generic_params').AsString;
      Result.ParentId     := Q.FieldByName('parent_id').AsLargeInt;
      Result.StartLine    := Q.FieldByName('start_line').AsInteger;
      Result.ImplStart    := Q.FieldByName('impl_start_line').AsInteger;
      Result.Path         := Q.FieldByName('path').AsString;
    end;
  finally
    Q.Free;
  end;
  FSyms.Add(pId, Result);
end;

function TCastPlanner.InScope(const pPath: string; pLine: Integer): Boolean;
begin
  Result:= (FOpts.Target = '') or SameText(ExpandFileName(FOpts.Target), ExpandFileName(pPath));
  Result:= Result and ((FOpts.Line = 0) or (FOpts.Line = pLine));
end;

// True when the operand names one of several routines of that name in one scope: the index picks an overload by
// heuristics, and a wrong pick is a wrong type.
function TCastPlanner.HasOverloads(const pSym: TSymRow; const pName: string): Boolean;
begin
  if not MatchText(pSym.Kind, ['function', 'method', 'procedure']) then Exit(False);
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    if pSym.ParentId > 0 then
    begin
      Q.SQL.Text:= 'SELECT COUNT(*) FROM symbols WHERE parent_id = :p AND name = :n COLLATE NOCASE';
      Q.ParamByName('p').AsLargeInt:= pSym.ParentId;
    end
    else Q.SQL.Text:= 'SELECT COUNT(*) FROM symbols WHERE parent_id IS NULL AND name = :n COLLATE NOCASE';
    Q.ParamByName('n').AsWideString:= pName;
    Q.Open;
    Result:= Q.Fields[0].AsInteger > 1;
  finally
    Q.Free;
  end;
end;

// The first ancestor of the class enclosing pEnclosing no index holds; '' when the chain is whole or there is no class.
function TCastPlanner.UnresolvedAncestorOf(pEnclosing: Int64): string;

  function HeritageOf(const pName: string; out pFound: Boolean): string;

    function ReadFrom(pConn: TFDConnection; out pHit: Boolean): string;
    begin
      Result:= '';
      pHit:= False;
      var Q:= TFDQuery.Create(nil);
      try
        Q.Connection:= pConn;
        Q.SQL.Text:= 'SELECT heritage FROM symbols WHERE name = :n COLLATE NOCASE AND kind = ''class'' ORDER BY (heritage IS NULL) LIMIT 1';
        Q.ParamByName('n').AsWideString:= pName;
        Q.Open;
        pHit:= not Q.Eof;
        if pHit then Result:= Q.FieldByName('heritage').AsString;
      finally
        Q.Free;
      end;
    end;

  begin
    Result:= ReadFrom(FConn, pFound);
    if pFound then Exit;
    for var C in FLibConns do
    begin
      Result:= ReadFrom(C, pFound);
      if pFound then Exit;
    end;
  end;

  // The class part of a heritage list: its first entry, without the generic arguments and the unit qualifier.
  function ParentOf(const pHeritage: string): string;
  begin
    Result:= Trim(pHeritage);
    if Result.Contains(',') then Result:= Trim(Copy(Result, 1, Pos(',', Result) - 1));
    if Result.Contains('<') then Result:= Copy(Result, 1, Pos('<', Result) - 1);
    Result:= Trim(Result);
    while Result.Contains('.') do Result:= Copy(Result, Pos('.', Result) + 1, MaxInt);
  end;

begin
  Result:= '';
  var Sym:= SymOf(pEnclosing);
  var Guard:= 0;
  while Sym.Found and (Sym.Kind <> 'class') and (Sym.Kind <> 'record') and (Sym.ParentId > 0) and (Guard < CMaxChain) do
  begin
    Sym:= SymOf(Sym.ParentId);
    Inc(Guard);
  end;
  if not Sym.Found or (Sym.Kind <> 'class') then Exit;
  if FChains.TryGetValue(Sym.QName, Result) then Exit;
  var Name:= ParentOf(Sym.Heritage);
  var Depth:= 0;
  while (Name <> '') and not SameText(Name, 'TObject') do
  begin
    if Depth >= CMaxChain then
    begin
      Result:= Name;
      Break;
    end;
    var Found: Boolean;
    var Up:= HeritageOf(Name, Found);
    if not Found then
    begin
      Result:= Name;
      Break;
    end;
    Name:= ParentOf(Up);
    Inc(Depth);
  end;
  FChains.Add(Sym.QName, Result);
end;

// Where the routine holding the site starts, climbing out of nested routines: an outer `with` reaches an anonymous
// method. 1 when the index names no routine (a program block).
function TCastPlanner.RoutineStartLine(pEnclosing: Int64): Integer;
begin
  Result:= 1;
  if pEnclosing <= 0 then Exit;
  var Sym:= SymOf(pEnclosing);
  var Guard:= 0;
  while Sym.Found and (Sym.ParentId > 0) and (Guard < CMaxChain) do
  begin
    var Up:= SymOf(Sym.ParentId);
    if not MatchText(Up.Kind, ['function', 'procedure', 'method', 'constructor', 'destructor']) then Break;
    Sym:= Up;
    Inc(Guard);
  end;
  if Sym.Found then Result:= if Sym.ImplStart > 0 then Sym.ImplStart else Sym.StartLine;
end;

function TCastPlanner.CastColsOf(pFileId: Int64; pLine: Integer): TList<Integer>;
begin
  var Key:= IntToStr(pFileId) + ':' + IntToStr(pLine);
  if not FCastSpans.TryGetValue(Key, Result) then
  begin
    Result:= TList<Integer>.Create;
    FCastSpans.Add(Key, Result);
  end;
end;

function TCastPlanner.DeclIsConditional(const pSym: TSymRow): Boolean;
begin
  Result:= False;
  if not pSym.Found or (pSym.Path = '') or not TFile.Exists(pSym.Path) then Exit;
  var F:= FileOf(pSym.Path);
  Result:= InRange(pSym.StartLine, 1, High(F.CondAt)) and F.CondAt[pSym.StartLine];
end;

procedure TCastPlanner.Refuse(const pSite: TCastSite; const pKind, pReason: string);
begin
  var S:= pSite;
  S.Kind       := pKind;
  S.Reason     := pReason;
  S.OperandText:= '';
  FRefused.Add(S);
end;

procedure TCastPlanner.Decide(pFileId: Int64; const pPath: string; pLine, pCol: Integer; const pName: string;  // dl:ok cyclomatic-complexity@7f59, too-many-exit-points@6420 -- one branch per named refusal, documented on the public function
  pTypeId, pEnclosing: Int64);
const
  CTypeKinds: array[0..4] of string = ('class', 'record', 'interface', 'enum', 'type');
begin
  var Site:= Default(TCastSite);
  Site.FilePath:= pPath;
  Site.Line    := pLine;
  Site.Col     := pCol;
  Site.CastText:= pName;
  if not StampOk(pPath) then
  begin
    Refuse(Site, 'stale-file', 'the file changed since it was indexed; re-index');
    Exit;
  end;
  if not MatchText(ExtractFileExt(pPath), ['.pas', '.dpr', '.dpk']) then
  begin
    Refuse(Site, 'include-file', 'an include file compiles in every unit that includes it');
    Exit;
  end;
  if (FOpts.Project <> '') and not FOwn.IsOurs(pPath) then
  begin
    Refuse(Site, 'outside-roots', 'the file lies outside the project''s own roots');
    Exit;
  end;
  var F:= FileOf(pPath);
  var At:= F.OffsetOf(pLine, pCol);
  if (At < 1) or not SameText(Copy(F.Text, At, Length(pName)), pName) then
  begin
    Refuse(Site, 'stale-file', Format('the file does not hold %s at %d:%d; re-index', [pName, pLine, pCol]));
    Exit;
  end;
  var Before: Integer;
  var Prev:= LastCodeChar(F.Masked, At, Before);
  if CharInSet(Prev, ['.', '&']) or SameText(Copy(F.Masked, Before - Length('inherited') + 1, Length('inherited')), 'inherited') then
  begin
    Refuse(Site, 'not-a-plain-cast', 'the type name is qualified, or follows inherited');
    Exit;
  end;
  var Stop:= F.LineEnd(pLine);
  var Open:= At + Length(pName);
  while (Open < Stop) and (F.Masked[Open] = ' ') do Inc(Open);
  if (Open >= Stop) or (F.Masked[Open] <> '(') then
  begin
    Refuse(Site, if Open >= Stop then 'multi-line' else 'not-a-plain-cast', 'no opening parenthesis follows the type name on its line');
    Exit;
  end;
  var Close:= MatchingParen(F.Masked, Open, Stop);
  if Close = 0 then
  begin
    Refuse(Site, 'multi-line', 'the cast does not close on its line');
    Exit;
  end;
  Site.CastText:= Copy(F.Text, At, Close - At + 1);
  Site.EndCol  := Close - F.Starts[pLine] + 2;
  if F.DirAt[pLine] then
  begin
    Refuse(Site, 'ifdef-line', 'a compiler directive on the line: the other branch cannot be seen');
    Exit;
  end;
  for var I:= Open to Close do
    if (F.Masked[I] = ' ') and (F.Text[I] <> ' ') then
    begin
      Refuse(Site, 'comment-in-cast', 'a comment inside the cast would go with it');
      Exit;
    end;
  for var C in CastColsOf(pFileId, pLine) do
    if (C <> pCol) and (F.Starts[pLine] + C - 1 > Open) and (F.Starts[pLine] + C - 1 < Close) then
    begin
      Refuse(Site, 'nested-cast', 'another cast inside it goes first; run again after a re-index');
      Exit;
    end;
  var Last, Len: Integer;
  var Why: string;
  if not ChainEnd(F.Masked, Open + 1, Close, Last, Len, Why) then
  begin
    Refuse(Site, 'operand-shape', Why);
    Exit;
  end;
  { the operand's last name: the row that types it }
  var OperandName:= Copy(F.Text, Last, Len);
  var OperandCol := Last - F.Starts[pLine] + 1;
  var HasRow: Boolean;
  var OperandType: Int64:= 0;
  var OperandQName, OperandVia: string;
  var OperandSym : Int64:= 0;
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT r.symbol_id, t.type_symbol_id, t.type_qname, t.via FROM refs r JOIN ref_types t ON t.ref_id = r.id ' +
                 'WHERE r.file_id = :f AND r.start_line = :l AND r.start_col = :c AND r.name_text = :n COLLATE NOCASE ORDER BY r.id LIMIT 1';
    Q.ParamByName('f').AsLargeInt  := pFileId;
    Q.ParamByName('l').AsInteger   := pLine;
    Q.ParamByName('c').AsInteger   := OperandCol;
    Q.ParamByName('n').AsWideString:= OperandName;
    Q.Open;
    HasRow:= not Q.Eof;
    if HasRow then
    begin
      OperandSym  := Q.FieldByName('symbol_id').AsLargeInt;
      OperandType := Q.FieldByName('type_symbol_id').AsLargeInt;
      OperandQName:= Q.FieldByName('type_qname').AsString;
      OperandVia  := Q.FieldByName('via').AsString;
    end;
  finally
    Q.Free;
  end;
  if not HasRow then
  begin
    Refuse(Site, 'operand-untyped', Format('the index has no static type for %s', [OperandName]));
    Exit;
  end;
  if OperandType <= 0 then
  begin
    { a name the project does not declare: `Integer(N)` has no cast row at all, so this is its only proof }
    if pTypeId <= 0 then Refuse(Site, 'type-not-indexed', Format('%s is not a type this index holds', [pName]))
    { TCommandID(Hdr.CommandID): the operand's type has another name than a target that is its own type (enum, class,
      record, not an alias): not the identity this fix removes, whatever the bare text means. No write either way;
      a conversion is counted, not refused. A plain alias target stays refused: it could be the operand's very type. }
    else if not SameText(SymOf(pTypeId).Kind, 'type') and
      not SameText(OperandQName.Substring(OperandQName.LastIndexOf('.') + 1), pName) then Inc(FNotIdent)
    else Refuse(Site, 'operand-type-unresolved', Format('the type of %s is the bare text %s', [OperandName, OperandQName]));
    Exit;
  end;
  if pTypeId <= 0 then
  begin
    if not SameText(OperandQName.Substring(OperandQName.LastIndexOf('.') + 1), pName) then Exit;
    Refuse(Site, 'type-not-indexed', Format('%s is not a type this index holds', [pName]));
    Exit;
  end;
  var TypeSym:= SymOf(pTypeId);
  if OperandType <> pTypeId then
  begin
    var OperandTypeSym:= SymOf(OperandType);
    if SameText(TypeSym.Kind, 'type') or SameText(OperandTypeSym.Kind, 'type') then
      Refuse(Site, 'alias-not-identical', Format('%s and %s are different symbols; an alias declared with `type` is a distinct type', [TypeSym.QName, OperandTypeSym.QName]))
    else Inc(FNotIdent);
    Exit;
  end;
  var Rows:= NamesOf(pName);
  for var R in Rows do
    if R.GenericParams <> '' then
    begin
      Refuse(Site, 'generic-type', Format('%s has a generic form; the symbol id does not carry the type arguments', [pName]));
      Exit;
    end;
  if TypeSym.QName.Contains('<') then
  begin
    Refuse(Site, 'generic-type', Format('%s has a generic form; the symbol id does not carry the type arguments', [pName]));
    Exit;
  end;
  for var R in Rows do
    if not MatchText(R.Kind, CTypeKinds) or not SameText(R.QName, TypeSym.QName) then
    begin
      Refuse(Site, 'ambiguous-type-name', Format('%s also names %s (%s): the call cannot be proved a cast', [pName, R.QName, R.Kind]));
      Exit;
    end;
  if SameText(TypeSym.Kind, 'type') and ((TypeSym.Signature = '') or
    TRegEx.IsMatch(TypeSym.Signature, '^\s*(procedure|function|reference)\b', [roIgnoreCase])) then
  begin
    Refuse(Site, 'procedural-type', 'a procedural value without its cast may be called instead of read');
    Exit;
  end;
  var OpSym:= if OperandSym > 0 then SymOf(OperandSym) else Default(TSymRow);
  if HasOverloads(OpSym, OperandName) then
  begin
    Refuse(Site, 'overloaded-operand', Format('%s is overloaded: the index picks an overload by heuristics', [OperandName]));
    Exit;
  end;
  if DeclIsConditional(TypeSym) or DeclIsConditional(OpSym) then
  begin
    Refuse(Site, 'conditional-decl', 'the type or the operand is declared under a conditional: another configuration may differ');
    Exit;
  end;
  var From:= F.OffsetOf(RoutineStartLine(pEnclosing), 1);
  if TRegEx.IsMatch(Copy(F.Masked, From, At - From), '\bwith\b', [roIgnoreCase]) then
  begin
    Refuse(Site, 'with-body', 'a with precedes it in the routine: its names may bind to the with subject');
    Exit;
  end;
  var Missing:= UnresolvedAncestorOf(pEnclosing);
  if Missing <> '' then
  begin
    Refuse(Site, 'unresolved-ancestor', Format('the enclosing class descends from %s, which no index holds: a member there could hide these names', [Missing]));
    Exit;
  end;
  Site.OperandText:= Trim(Copy(F.Text, Open + 1, Close - Open - 1));
  FFixes.Add(Site);
end;

procedure TCastPlanner.ReadCastRows;
type
  TCastRow = record
    FileId, TypeId, Enclosing: Int64;
    Path, Name: string;
    Line, Col: Integer;
  end;
var
  Rows: TList<TCastRow>;
begin
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.FetchOptions.Unidirectional:= True;
    Q.SQL.Text:= 'SELECT r.file_id, f.path, r.start_line, r.start_col, r.name_text, t.type_symbol_id, r.enclosing_symbol_id ' +
                 'FROM refs r JOIN ref_types t ON t.ref_id = r.id JOIN files f ON f.id = r.file_id ' +
                 'WHERE t.via = ''cast'' ORDER BY f.path, r.start_line, r.start_col';
    Q.Open;
    Rows:= TList<TCastRow>.Create;
    try
      while not Q.Eof do
      begin
        var R: TCastRow;
        R.FileId   := Q.FieldByName('file_id').AsLargeInt;  // dl:ok field-by-name-in-loop@48e6 -- a few thousand rows at most; column names beat positions (magic-literal) here
        R.Path     := Q.FieldByName('path').AsString;
        R.Line     := Q.FieldByName('start_line').AsInteger;
        R.Col      := Q.FieldByName('start_col').AsInteger;
        R.Name     := Q.FieldByName('name_text').AsString;
        R.TypeId   := Q.FieldByName('type_symbol_id').AsLargeInt;
        R.Enclosing:= Q.FieldByName('enclosing_symbol_id').AsLargeInt;
        Rows.Add(R);
        Q.Next;
      end;
      Q.Close;
      for var R in Rows do CastColsOf(R.FileId, R.Line).Add(R.Col);
      for var R in Rows do
        if InScope(R.Path, R.Line) then Decide(R.FileId, R.Path, R.Line, R.Col, R.Name, R.TypeId, R.Enclosing);
    finally
      Rows.Free;
    end;
  finally
    Q.Free;
  end;
end;

// `Integer(N)`: a call with no cast row whose single-name operand is typed by the very name: the identity the F1 rows
// cannot prove, since the project does not declare that type. Decided here so it is a named refusal, not silence.
procedure TCastPlanner.ReadUntypedCalls;
begin
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT c.file_id, f.path, c.start_line, c.start_col, c.name_text, c.enclosing_symbol_id ' +
                 'FROM refs c JOIN files f ON f.id = c.file_id ' +
                 'JOIN refs o ON o.file_id = c.file_id AND o.start_line = c.start_line AND o.start_col = c.end_col + 1 ' +
                 'JOIN ref_types ot ON ot.ref_id = o.id ' +
                 'LEFT JOIN ref_types ct ON ct.ref_id = c.id ' +
                 'WHERE c.kind = ''call'' AND c.symbol_id IS NULL AND ct.ref_id IS NULL AND (c.receiver_text IS NULL OR c.receiver_text = '''') ' +
                 'AND ot.type_qname = c.name_text COLLATE NOCASE ORDER BY f.path, c.start_line, c.start_col';
    Q.Open;
    while not Q.Eof do
    begin
      if InScope(Q.FieldByName('path').AsString, Q.FieldByName('start_line').AsInteger) then  // dl:ok field-by-name-in-loop@656f -- a few thousand rows at most; column names beat positions (magic-literal) here
        Decide(Q.FieldByName('file_id').AsLargeInt, Q.FieldByName('path').AsString, Q.FieldByName('start_line').AsInteger, Q.FieldByName('start_col').AsInteger,
          Q.FieldByName('name_text').AsString, 0, Q.FieldByName('enclosing_symbol_id').AsLargeInt);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TCastPlanner.Run: TCastPlan;
begin
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT 1 FROM sqlite_master WHERE type = ''table'' AND name = ''ref_types''';
    Q.Open;
    if Q.Eof then raise ENoRefTypes.Create('this index has no ref_types table (it predates 1.44): re-index with this engine');
  finally
    Q.Free;
  end;
  ReadCastRows;
  ReadUntypedCalls;
  Result.Fixes      := FFixes.ToArray;
  Result.Refused    := FRefused.ToArray;
  Result.NotIdentity:= FNotIdent;
  var ByPlace:= TComparer<TCastSite>.Construct(
    function(const pA, pB: TCastSite): Integer
    begin
      Result:= CompareText(pA.FilePath, pB.FilePath);
      if Result = 0 then Result:= pA.Line - pB.Line;
      if Result = 0 then Result:= pA.Col - pB.Col;
    end);
  TArray.Sort<TCastSite>(Result.Refused, ByPlace);
  TArray.Sort<TCastSite>(Result.Fixes, ByPlace);
end;

function PlanRedundantCasts(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>;
  const pOpts: TRedundantCastOptions): TCastPlan;
begin
  var Planner:= TCastPlanner.Create(pStore, pLibraries, pOpts);
  try
    Result:= Planner.Run;
  finally
    Planner.Free;
  end;
end;

{ ---- the verb ----------------------------------------------------------------------------------------- }

function SiteToJson(const pS: TCastSite): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('file', pS.FilePath);
  Result.AddPair('line', TJSONNumber.Create(pS.Line));
  Result.AddPair('col', TJSONNumber.Create(pS.Col));
  Result.AddPair('cast', pS.CastText);
  if pS.Kind = '' then Result.AddPair('operand', pS.OperandText)
  else
  begin
    Result.AddPair('kind', pS.Kind);
    Result.AddPair('reason', pS.Reason);
  end;
end;

// The refusal kinds with their counts, most frequent first.
function RefusalCounts(const pPlan: TCastPlan): TArray<TPair<string, Integer>>;
begin
  var Counts:= TDictionary<string, Integer>.Create;
  try
    for var S in pPlan.Refused do
    begin
      var N: Integer;
      if not Counts.TryGetValue(S.Kind, N) then N:= 0;
      Counts.AddOrSetValue(S.Kind, N + 1);
    end;
    Result:= Counts.ToArray;
    TArray.Sort<TPair<string, Integer>>(Result, TComparer<TPair<string, Integer>>.Construct(
      function(const pA, pB: TPair<string, Integer>): Integer
      begin
        Result:= pB.Value - pA.Value;
        if Result = 0 then Result:= CompareStr(pA.Key, pB.Key);
      end));
  finally
    Counts.Free;
  end;
end;

// The rewrite's new bytes per file: each fix replaced right to left, so the earlier offsets hold.
function BuildGateFiles(const pPlan: TCastPlan): TArray<TGateFile>;
begin
  Result:= nil;
  var Paths: TList<string>:= TList<string>.Create;
  try
    for var S in pPlan.Fixes do
      if not Paths.Contains(S.FilePath) then Paths.Add(S.FilePath);
    for var P in Paths do
    begin
      var Enc: TEncoding;
      var Text:= DecodeSource(TFile.ReadAllBytes(P), Enc);
      var Offs: TArray<Integer>:= [1];
      for var I:= 1 to Length(Text) do
        if Text[I] = #10 then Offs:= Offs + [I + 1];
      for var K:= High(pPlan.Fixes) downto 0 do
      begin
        var S:= pPlan.Fixes[K];
        if not SameText(S.FilePath, P) then Continue;
        var At:= Offs[S.Line - 1] + S.Col - 1;
        Text:= Copy(Text, 1, At - 1) + S.OperandText + Copy(Text, At + (S.EndCol - S.Col), MaxInt);
      end;
      var G: TGateFile;
      G.Path := P;
      G.Bytes:= EncodeSource(Text, Enc);
      Result:= Result + [G];
    end;
  finally
    Paths.Free;
  end;
end;

procedure PrintPlanText(const pPlan: TCastPlan; pApply: Boolean);
begin
  Writeln(Format('redundant-cast: %d identity cast(s) to remove, %d refused, %d real conversion(s) left alone%s',
    [Length(pPlan.Fixes), Length(pPlan.Refused), pPlan.NotIdentity, if pApply then '' else ' (dry run; add --apply --project <X.dproj> to write)']));
  for var C in RefusalCounts(pPlan) do Writeln(Format('  refused %-24s %d', [C.Key, C.Value]));
  for var S in pPlan.Fixes do
    Writeln(Format('fix      %s:%d:%d  %s -> %s', [S.FilePath, S.Line, S.Col, S.CastText, S.OperandText]));
  for var S in pPlan.Refused do
    Writeln(Format('refused  %s:%d:%d  %s  %s -- %s', [S.FilePath, S.Line, S.Col, S.CastText, S.Kind, S.Reason]));
end;

function RunRedundantCastFix(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>;
  const pOpts: TRedundantCastOptions): Integer;
var
  Gate: TGateOutcome;
  Ran : Boolean;

  procedure SayError(const pMessage: string);
  begin
    if pOpts.Json then
    begin
      var J:= TJSONObject.Create;
      try
        J.AddPair('schema', CSchema);
        J.AddPair('error', pMessage);
        J.AddPair('exit_code', TJSONNumber.Create(CExitError));
        Writeln(J.Format(2));
      finally
        J.Free;
      end;
    end
    else Writeln('ERROR: ', pMessage);
  end;

begin
  Result:= CExitOk;
  Gate:= Default(TGateOutcome);
  Ran := False;
  if pOpts.Apply and pOpts.NoCompile then
  begin
    SayError(CFixRule + ' --apply cannot take --no-compile: every applied rewrite passes the compile gate');
    Exit(CExitError);
  end;
  if pOpts.Apply and (pOpts.Project = '') then
  begin
    SayError(CFixRule + ' --apply needs --project <X.dproj>: the compile gate builds it before and after the rewrite');
    Exit(CExitError);
  end;
  var Plan: TCastPlan;
  try
    Plan:= PlanRedundantCasts(pStore, pLibraries, pOpts);
  except
    on E: ENoRefTypes do
    begin
      SayError(E.Message);
      Exit(CExitError);
    end;
  end;
  if pOpts.Apply and (Length(Plan.Fixes) > 0) then
  begin
    var Secs:= StrToIntDef(pOpts.BuildTimeout, 0);
    GBuildTimeoutMs:= if Secs <= 0 then INFINITE else Cardinal(Secs) * CMsPerSec;
    var Req:= Default(TGateRequest);
    Req.Project := ExpandFileName(pOpts.Project);
    Req.Platform:= pOpts.Platform;
    Req.Verb    := CFixRule;
    Req.RsVars  := if pOpts.RsVars <> '' then ExpandFileName(pOpts.RsVars) else '';
    Req.NoBackup:= pOpts.NoBackup;
    Req.Header  := Format('[%s] %s --apply: %d cast(s) removed', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), CFixRule, Length(Plan.Fixes)]);
    Req.LogDir  := FreshScratchName('_build');
    Req.Files   := BuildGateFiles(Plan);
    Gate:= ApplyGated(Req);
    Ran := True;
    if not GScratchCited and TDirectory.Exists(Req.LogDir) then
    try
      TDirectory.Delete(Req.LogDir, True);  // dl:ok taint-path-traversal@ff48 -- the path is the operator's own --project, the run's fixed scratch or the Studio root: local input, no privilege crossed
    except
      on EInOutError do Writeln(ErrOutput, 'drag-lint: note: scratch not deleted: ', Req.LogDir); // best effort: a locked log must not change the result
    end;
    if not Gate.Applied then Result:= if Gate.RollbackFailed then CExitError else CExitRefused;
  end;
  if pOpts.Json then
  begin
    var J:= TJSONObject.Create;
    try
      J.AddPair('schema', CSchema);
      J.AddPair('applied', TJSONBool.Create(Ran and Gate.Applied));
      J.AddPair('not_identity', TJSONNumber.Create(Plan.NotIdentity));
      var Fixes:= TJSONArray.Create;
      J.AddPair('fixes', Fixes);
      for var S in Plan.Fixes do Fixes.AddElement(SiteToJson(S));
      var Refused:= TJSONArray.Create;
      J.AddPair('refused', Refused);
      for var S in Plan.Refused do Refused.AddElement(SiteToJson(S));
      if Ran then
      begin
        var G:= TJSONObject.Create;
        J.AddPair('gate', G);
        G.AddPair('refusal', Gate.Refusal);
        G.AddPair('detail', Gate.Detail);
        G.AddPair('rolled_back', TJSONBool.Create(Gate.RolledBack));
        var Written:= TJSONArray.Create;
        G.AddPair('written', Written);
        for var W in Gate.Tx.Written do Written.Add(W);
      end;
      J.AddPair('exit_code', TJSONNumber.Create(Result));
      Writeln(J.Format(2));
    finally
      J.Free;
    end;
    Exit;
  end;
  PrintPlanText(Plan, pOpts.Apply);
  if Ran then
    if Gate.Applied then
      Writeln(Format('applied: %d file(s) written, the project builds; re-index, then run again: a nested cast''s outer half is decided on the new text', [Length(Gate.Tx.Written)]))
    else Writeln(Format('NOT applied: %s -- %s', [Gate.Refusal, Gate.Detail]));
end;

end.
