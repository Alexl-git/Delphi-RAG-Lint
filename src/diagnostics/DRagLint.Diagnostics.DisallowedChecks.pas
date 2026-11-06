unit DRagLint.Diagnostics.DisallowedChecks;

{ Clippy-parity wave (plan 2026-10-27-clippy-rules-plan.md), lane L10.
  Rules: disallowed-method, disallowed-type, disallowed-name -- config-driven
  (the "disallowed" block of the lint config), category policy, silent without
  config. Matching is TEXTUAL (v1): the source is tokenised with comments, strings
  and compiler directives skipped, and identifier sequences are compared
  case-insensitively. With a project index two facts refine it (lane 145 li): a dotted "Obj.Sleep"
  whose ref the index binds to a MEMBER no longer matches a bare "Sleep" entry, and a "Type.Method"
  entry also matches "Recv.Method" when ref_types types Recv as Type. No store, no ref_types table
  or no row = the textual answer. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Checker for the disallowed-method, disallowed-type, disallowed-name rules.</summary>
  /// <remarks>
  /// Stateless; thread-safe. Called from DoLint and DoLintAll behind
  /// LintRuleWants(rule, LINT_GATE_DISALLOWED). Every rule is silent when its list in
  /// the config is empty, so the checker costs nothing (no file read) unconfigured.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDisallowedChecker = class
  public
    /// <summary>Runs the three disallowed-* rules against one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="ACfg">Effective lint configuration (DisallowedMethods/Types/Names, severity).</param>
    /// <param name="AStore">Optional project index; nil or an index without the facts keeps the textual match.</param>
    /// <param name="AFileId">The file id in AStore; 0 means no index facts.</param>
    /// <returns>One finding per matched occurrence, message "NAME is disallowed by project
    /// policy -- REASON"; empty when unconfigured, excepted or clean.</returns>
    /// <remarks>
    /// disallowed-method: the (dotted) name outside a routine declaration header.
    /// disallowed-type: the name outside a routine header and outside its own definition
    /// (NAME = ...). disallowed-name: single identifiers not reached through a dot (a
    /// member of someone else's record is not our binding), outside routine headers.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
    /// <para>Calls: DRagLint.Diagnostics.DisallowedChecks.ScanKind, DRagLint.Diagnostics.DisallowedChecks.Tokenise</para>
    /// <para>Returns: nil</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Diagnostics.DisallowedChecks.ScanKind"/>
    /// <seealso cref="DRagLint.Diagnostics.DisallowedChecks.Tokenise"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Check(const AFile: string; const ACfg: TLintConfig;
      const AStore: ISymbolStore; AFileId: Int64): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , System.Generics.Collections
  , FireDAC.Comp.Client
  , FireDAC.Stan.Param
  , DRagLint.Storage.SQLite
  , DRagLint.Lint.RefTypeRules
  ;

type
  TTok = record
    Text   : string ;
    Line   : Integer;
    Col    : Integer;
    IsIdent: Boolean;
  end;

  TRuleKind = (rkMethod, rkType, rkName);

  { The index facts for the file being checked; Store = nil means none. }
  TIndexFacts = record
    Store : ISymbolStore;
    FileId: Int64;
  end;

const
  DECL_KEYWORDS: array[0..6] of string = (
    'procedure', 'function', 'constructor', 'destructor', 'property', 'operator', 'event');

function IsIdentStart(AChar: Char): Boolean;
begin
  Result:= CharInSet(AChar, ['A'..'Z', 'a'..'z', '_']);
end;

function IsIdentPart(AChar: Char): Boolean;
begin
  Result:= IsIdentStart(AChar) or CharInSet(AChar, ['0'..'9']);
end;

{ Tokenise: identifiers and single punctuation characters; comments, strings and
  numbers dropped. Line/Col are 1-based. }
function Tokenise(const ASrc: string): TArray<TTok>;
var
  L      : TList<TTok>;
  I, N   : Integer;
  Line   : Integer;
  LineBeg: Integer;
  T      : TTok;

  procedure Newline(APos: Integer);
  begin
    Inc(Line);
    LineBeg:= APos + 1;
  end;

  { Skip a comment body starting at I up to and including ACloser. }
  procedure SkipTo(const ACloser: string);
  begin
    while I <= N do
    begin
      if ASrc[I] = #10 then Newline(I);
      if Copy(ASrc, I, Length(ACloser)) = ACloser then
      begin
        Inc(I, Length(ACloser));
        Exit;
      end;
      Inc(I);
    end;
  end;

  procedure SkipString;
  begin
    Inc(I);
    while I <= N do
    begin
      if ASrc[I] = '''' then
      begin
        if (I < N) and (ASrc[I + 1] = '''') then Inc(I, 2)
        else
        begin
          Inc(I);
          Exit;
        end;
      end
      else if ASrc[I] = #10 then Exit
      else Inc(I);
    end;
  end;

  procedure TakeIdent;
  var
    S: Integer;
  begin
    T.Line:= Line;
    T.Col:= I - LineBeg + 1;
    T.IsIdent:= True;
    S:= I;
    while (I <= N) and IsIdentPart(ASrc[I]) do Inc(I);
    T.Text:= Copy(ASrc, S, I - S);
    L.Add(T);
  end;

begin
  L:= TList<TTok>.Create;
  try
    N:= Length(ASrc);
    I:= 1;
    Line:= 1;
    LineBeg:= 1;
    while I <= N do
    begin
      if ASrc[I] = #10 then
      begin
        Newline(I);
        Inc(I);
      end
      else if ASrc[I] <= ' ' then Inc(I)
      else if ASrc[I] = '{' then SkipTo('}')
      else if (ASrc[I] = '(') and (I < N) and (ASrc[I + 1] = '*') then SkipTo('*)')
      else if (ASrc[I] = '/') and (I < N) and (ASrc[I + 1] = '/') then
        while (I <= N) and (ASrc[I] <> #10) do Inc(I)
      else if ASrc[I] = '''' then SkipString
      else if IsIdentStart(ASrc[I]) then TakeIdent
      else if IsIdentPart(ASrc[I]) then
        while (I <= N) and IsIdentPart(ASrc[I]) do Inc(I)
      else
      begin
        T.Line:= Line;
        T.Col:= I - LineBeg + 1;
        T.IsIdent:= False;
        T.Text:= ASrc[I];
        L.Add(T);
        Inc(I);
      end;
    end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function IsDeclKeyword(const AText: string): Boolean;
var
  K: string;
begin
  for K in DECL_KEYWORDS do
    if SameText(K, AText) then Exit(True);
  Result:= False;
end;

{ True when the token run at AAt spells ASegs (ident . ident ...), case-insensitively. }
function RunMatches(const ATok: TArray<TTok>; AAt: Integer; const ASegs: TArray<string>): Boolean;
var
  K, P: Integer;
begin
  Result:= False;
  P:= AAt;
  for K:= 0 to High(ASegs) do
  begin
    if (P > High(ATok)) or (not ATok[P].IsIdent) or (not SameText(ATok[P].Text, ASegs[K])) then Exit;
    Inc(P);
    if K < High(ASegs) then
    begin
      if (P > High(ATok)) or (ATok[P].Text <> '.') then Exit;
      Inc(P);
    end;
  end;
  Result:= True;
end;

{ A match inside a routine header (procedure TFoo.Sleep ...) is the declaration, not a use. }
function InRoutineHeader(const ATok: TArray<TTok>; AAt: Integer): Boolean;
var
  J: Integer;
begin
  J:= AAt;
  while (J >= 2) and (ATok[J - 1].Text = '.') and ATok[J - 2].IsIdent do Dec(J, 2);
  Result:= (J >= 1) and ATok[J - 1].IsIdent and IsDeclKeyword(ATok[J - 1].Text);
end;

{ NAME = ... right after 'type' or a statement end: the definition of the type. }
function IsOwnDefinition(const ATok: TArray<TTok>; AAt, ALast: Integer): Boolean;
begin
  Result:= (ALast + 1 <= High(ATok)) and (ATok[ALast + 1].Text = '=')
    and ((AAt = 0) or (ATok[AAt - 1].Text = ';') or SameText(ATok[AAt - 1].Text, 'type'));
end;

function EntryHit(AKind: TRuleKind; const ATok: TArray<TTok>; AAt: Integer;
  const ASegs: TArray<string>): Boolean;
begin
  Result:= False;
  if (not RunMatches(ATok, AAt, ASegs)) or InRoutineHeader(ATok, AAt) then Exit;
  case AKind of
    rkType: Result:= not IsOwnDefinition(ATok, AAt, AAt + 2 * High(ASegs));
    rkName: Result:= (Length(ASegs) = 1) and ((AAt = 0) or (ATok[AAt - 1].Text <> '.'));
  else
    Result:= True;
  end;
end;

function RuleIdFor(AKind: TRuleKind): string;
begin
  case AKind of
    rkMethod: Result:= 'disallowed-method';
    rkType  : Result:= 'disallowed-type';
  else
    Result:= 'disallowed-name';
  end;
end;

function MakeFinding(const ARule, AFile: string; const ACfg: TLintConfig;
  const AEntry: TDisallowedEntry; const AFirst, ALast: TTok): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId   := ARule;
  Result.Severity := ACfg.ApplySeverity(ARule, 'warning');
  Result.FilePath := AFile;
  Result.StartLine:= AFirst.Line;
  Result.StartCol := AFirst.Col;
  Result.EndLine  := ALast.Line;
  Result.EndCol   := ALast.Col + Length(ALast.Text);
  Result.Message  := AEntry.Name + ' is disallowed by project policy';
  if AEntry.Reason <> '' then Result.Message:= Result.Message + ' -- ' + AEntry.Reason;
end;

{ True when the index binds the reference written at ATok to a MEMBER symbol (method,
  constructor, destructor, property, field): `Obj.Sleep` bound to TWorker.Sleep is not the
  global Sleep a bare policy entry names. False with no store, no row or an unbound ref:
  today's textual answer stands. }
function BoundToMember(const AStore: ISymbolStore; AFileId: Int64; const ATok: TTok): Boolean;
var
  Q: TFDQuery;
begin
  Result:= False;
  if (AStore = nil) or (AFileId <= 0) or (AStore is not TSQLiteSymbolStore) then Exit;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= (AStore as TSQLiteSymbolStore).GetConnection;
    Q.SQL.Text:= 'SELECT 1 FROM refs r JOIN symbols s ON s.id = r.symbol_id ' +
                 'WHERE r.file_id = :f AND r.start_line = :l AND r.start_col = :c ' +
                 'AND r.name_text = :n COLLATE NOCASE ' +
                 'AND s.kind IN (''method'', ''constructor'', ''destructor'', ''property'', ''field'') LIMIT 1';
    Q.ParamByName('f').AsLargeInt  := AFileId;
    Q.ParamByName('l').AsInteger   := ATok.Line;
    Q.ParamByName('c').AsInteger   := ATok.Col;
    Q.ParamByName('n').AsWideString:= ATok.Text;
    Q.Open;
    Result:= not Q.Eof;
  finally
    Q.Free;
  end;
end;

{ True when ATok[AAt] is the method of `Recv.Method` and Recv is an identifier the index
  types as the policy's type (Segs[0]) although the source never spells that type. }
function TypedReceiverHit(const AFacts: TIndexFacts; const ATok: TArray<TTok>;
  AAt: Integer; const ASegs: TArray<string>): Boolean;
var
  Leaf: string;
begin
  Result:= False;
  if (Length(ASegs) <> 2) or (AAt < 2) or (not ATok[AAt].IsIdent) or (not SameText(ATok[AAt].Text, ASegs[1])) then Exit;
  if (ATok[AAt - 1].Text <> '.') or (not ATok[AAt - 2].IsIdent) or SameText(ATok[AAt - 2].Text, ASegs[0]) then Exit;
  if InRoutineHeader(ATok, AAt) then Exit;
  Result:= RefStaticTypeAt(AFacts.Store, AFacts.FileId, ATok[AAt - 2].Line, ATok[AAt - 2].Col, ATok[AAt - 2].Text, Leaf)
    and SameText(Leaf, ASegs[0]);
end;

procedure ScanKind(AKind: TRuleKind; const AFile: string; const ACfg: TLintConfig;
  const AEntries: TArray<TDisallowedEntry>; const ATok: TArray<TTok>;
  const AFacts: TIndexFacts; var AFindings: TArray<TLintFinding>);
var
  E   : TDisallowedEntry;
  Segs: TArray<string>;
  I   : Integer;
begin
  for E in AEntries do
  begin
    if TLintConfig.MatchesAnyGlob(AFile, E.Exempt) then Continue;
    Segs:= E.Name.Split(['.']);
    for I:= 0 to High(ATok) do
      if EntryHit(AKind, ATok, I, Segs) then
      begin
        if (AKind = rkMethod) and (Length(Segs) = 1) and (I > 0) and (ATok[I - 1].Text = '.')
          and BoundToMember(AFacts.Store, AFacts.FileId, ATok[I]) then Continue;
        AFindings:= AFindings + [MakeFinding(RuleIdFor(AKind), AFile, ACfg, E, ATok[I], ATok[I + 2 * High(Segs)])];
      end
      else if (AKind = rkMethod) and TypedReceiverHit(AFacts, ATok, I, Segs) then
        AFindings:= AFindings + [MakeFinding(RuleIdFor(AKind), AFile, ACfg, E, ATok[I - 2], ATok[I])];
  end;
end;

class function TDisallowedChecker.Check(const AFile: string; const ACfg: TLintConfig;
  const AStore: ISymbolStore; AFileId: Int64): TArray<TLintFinding>;
var
  Tok  : TArray<TTok>;
  Facts: TIndexFacts;
begin
  Result:= nil;
  if (Length(ACfg.DisallowedMethods) + Length(ACfg.DisallowedTypes) + Length(ACfg.DisallowedNames) = 0)
    or (not TFile.Exists(AFile)) then Exit;
  Tok:= Tokenise(TFile.ReadAllText(AFile));
  Facts.Store := AStore;
  Facts.FileId:= AFileId;
  ScanKind(rkMethod, AFile, ACfg, ACfg.DisallowedMethods, Tok, Facts, Result);
  ScanKind(rkType, AFile, ACfg, ACfg.DisallowedTypes, Tok, Facts, Result);
  ScanKind(rkName, AFile, ACfg, ACfg.DisallowedNames, Tok, Facts, Result);
end;

end.
