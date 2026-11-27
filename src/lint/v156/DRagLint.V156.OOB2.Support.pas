unit DRagLint.V156.OOB2.Support;

{ Wave v156 lane OOB-2 -- helpers of DRagLint.V156.OOB2 (private to the lane).
    dunitx-attribute-hygiene (G-26) -- from the index tables attributes / symbols / type_ancestors of one file:
                                       a [TestFixture] without a test, a bare [Ignore], a [Setup]-like attribute twice
    variant-in-loop          (G-30) -- from the parse tree: arithmetic on a Variant that a declaration proves, inside a loop
  A question the source and the index do not answer completely is answered "no finding". }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

const
  /// <summary>Rule id of G-26.</summary>
  RULE_DUNITX_ATTRIBUTE_HYGIENE = 'dunitx-attribute-hygiene';
  /// <summary>Rule id of G-30.</summary>
  RULE_VARIANT_IN_LOOP = 'variant-in-loop';

type
  /// <summary>G-26 over one file: reads the attributes of the file from the index.</summary>
  /// <remarks>Stateless; class methods only. Nothing without an index that has the attributes table.</remarks>
  TOob2Dunitx = class
  public
    /// <summary>Reports the fixtures of ACtx.Path that break the DUnitX attribute rules.</summary>
    /// <param name="ACtx">The file; Store and FileId must be set, else nothing is reported.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>A fixture is a class that carries [TestFixture]. Three findings: a fixture with no [Test],
    /// [TestCase] or [TestCaseSource] method, no published method and no ancestor but TObject (inherited tests
    /// are not seen); an [Ignore] on a fixture or one of its methods without a reason; [Setup], [TearDown],
    /// [SetupFixture] or [TearDownFixture] on two methods of one fixture (reported on the later ones).</remarks>
    class function Check(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
  end;

  /// <summary>G-30 over one parsed unit: one run, collected and checked in Check.</summary>
  /// <remarks>Stateless; class methods only. A Variant is "proven" by a parameter, local variable, inline
  /// variable or function result declared Variant / OleVariant in the routine or an enclosing one; a field or a
  /// global is not proven.</remarks>
  TOob2Variant = class
  public
    /// <summary>Reports each assignment inside a loop whose right side does arithmetic on a proven Variant.</summary>
    /// <param name="ACtx">The file; the index is not needed.</param>
    /// <returns>Findings; nil when none.</returns>
    class function Check(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.StrUtils
  , FireDAC.Comp.Client
  , FireDAC.Stan.Param
  , TreeSitter
  , DRagLint.Core.Interfaces
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Storage.SQLite
  , DRagLint.Analysis.Flow.Lattices
  ;

const
  SEVERITY_WARNING = 'warning';
  SEVERITY_HINT = 'hint';
  ATTRIBUTE_SUFFIX = 'attribute';
  ATTR_FIXTURE = 'testfixture';
  ATTR_IGNORE = 'ignore';
  TEST_ATTRIBUTES: array[0..2] of string = ('test', 'testcase', 'testcasesource');
  ONCE_ATTRIBUTES: array[0..3] of string = ('setup', 'teardown', 'setupfixture', 'teardownfixture');
  LOOP_NODES: array[0..3] of string = ('while', 'for', 'foreach', 'repeat');
  ARITHMETIC: array[0..5] of string = ('+', '-', '*', '/', 'div', 'mod');
  VARIANT_TYPES: array[0..3] of string = ('variant', 'olevariant', 'system.variant', 'system.olevariant');
  SECTION_PUBLISHED = 'published';
  TEST_PREFIX = 'test';

function MakeFinding(const APath, ARule, ASeverity, AMessage: string; ALine, ACol, AEndCol: Integer): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId   := ARule;
  Result.Severity := ASeverity;
  Result.Message  := AMessage;
  Result.FilePath := APath;
  Result.StartLine:= ALine;
  Result.StartCol := ACol;
  Result.EndLine  := ALine;
  Result.EndCol   := AEndCol;
end;

{ The attribute name without a unit prefix and without the "Attribute" suffix, lower case. }
function CanonAttribute(const AName: string): string;
begin
  Result:= LowerCase(Trim(AName));
  var Dot: Integer:= Result.LastDelimiter('.');
  if Dot >= 0 then Result:= Result.Substring(Dot + 1);
  if Result.EndsWith(ATTRIBUTE_SUFFIX) and (Result.Length > ATTRIBUTE_SUFFIX.Length) then
    Result:= Result.Substring(0, Result.Length - ATTRIBUTE_SUFFIX.Length);
end;

{ True when AArgs gives no reason: nothing, or only an empty string literal. }
function NoReason(const AArgs: string): Boolean;
begin
  var Flat: string:= StringReplace(Trim(AArgs), '''', '', [rfReplaceAll]);
  Result:= Trim(Flat) = '';
end;

{ TOob2Dunitx }

type
  TAttrRow = record
    Attr    : string;
    Args    : string;
    Line    : Integer;
    Col     : Integer;
    SymbolId: Int64;
    Kind    : string;
    Name    : string;
    ParentId: Int64;
    StartLine: Integer;
    StartCol : Integer;
  end;

function OpenQuery(const AStore: ISymbolStore; const ASql: string): TFDQuery;
begin
  Result:= TFDQuery.Create(nil);
  try
    Result.Connection:= (AStore as TSQLiteSymbolStore).GetConnection;
    Result.SQL.Text  := ASql;
  except
    Result.Free;
    raise;
  end;
end;

class function TOob2Dunitx.Check(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Rows     : TList<TAttrRow>;
  Fixtures : TDictionary<Int64, TAttrRow>;
  HasTest  : TDictionary<Int64, Boolean>;
  Findings : TList<TLintFinding>;
  Seen     : TDictionary<string, string>;  { 'classId|attr' to the first method name }

  procedure Load;
  var
    Q: TFDQuery;
    R: TAttrRow;
  begin
    Q:= OpenQuery(ACtx.Store,
      'SELECT a.attr_name, a.arg_text, a.line, a.col, s.id, s.kind, s.name, COALESCE(s.parent_id, 0), s.start_line, s.start_col ' +
      'FROM attributes a JOIN symbols s ON s.id = a.symbol_id WHERE a.file_id = :f ORDER BY a.ordinal');
    try
      Q.ParamByName('f').AsLargeInt:= ACtx.FileId;
      Q.Open;
      while not Q.Eof do
      begin
        R:= Default(TAttrRow);
        R.Attr     := CanonAttribute(Q.Fields[0].AsString);
        R.Args     := Q.Fields[1].AsString;
        R.Line     := Q.Fields[2].AsInteger;
        R.Col      := Q.Fields[3].AsInteger;
        R.SymbolId := Q.Fields[4].AsLargeInt;
        R.Kind     := Q.Fields[5].AsString;
        R.Name     := Q.Fields[6].AsString;
        R.ParentId := Q.Fields[7].AsLargeInt;
        R.StartLine:= Q.Fields[8].AsInteger;
        R.StartCol := Q.Fields[9].AsInteger;
        Rows.Add(R);
        Q.Next;
      end;
    finally
      Q.Free;
    end;
  end;

  { A class that has an ancestor besides TObject, or a published method, or a method named Test*: tests may come from there. }
  function MayHaveOtherTests(AClassId: Int64): Boolean;
  var
    Q: TFDQuery;
  begin
    Q:= OpenQuery(ACtx.Store,
      'SELECT 1 FROM type_ancestors WHERE symbol_id = :c AND LOWER(ancestor_name) <> ''tobject'' ' +
      'UNION ALL SELECT 1 FROM symbols WHERE parent_id = :c AND kind = ''method'' ' +
      'AND (LOWER(COALESCE(section, '''')) = :pub OR LOWER(name) LIKE :tst) LIMIT 1');
    try
      Q.ParamByName('c').AsLargeInt:= AClassId;
      Q.ParamByName('pub').AsString:= SECTION_PUBLISHED;
      Q.ParamByName('tst').AsString:= TEST_PREFIX + '%';
      Q.Open;
      Result:= not Q.Eof;
    finally
      Q.Free;
    end;
  end;

  { The row is on a fixture class itself, or on a method of one. }
  function InFixture(const ARow: TAttrRow): Boolean;
  begin
    Result:= if ARow.Kind = 'class' then Fixtures.ContainsKey(ARow.SymbolId)
      else (ARow.Kind = 'method') and Fixtures.ContainsKey(ARow.ParentId);
  end;

  procedure Report(const AMessage: string; ALine, ACol, ALen: Integer);
  begin
    Findings.Add(MakeFinding(ACtx.Path, RULE_DUNITX_ATTRIBUTE_HYGIENE, SEVERITY_WARNING, AMessage, ALine, ACol, ACol + ALen));
  end;

var
  R, F: TAttrRow;
  Key : string;
  First: string;
begin
  Result:= nil;
  if (ACtx.Store = nil) or (ACtx.FileId = 0) or (not ACtx.Store.HasAttributes) then Exit;
  Rows    := TList<TAttrRow>.Create;
  Fixtures:= TDictionary<Int64, TAttrRow>.Create;
  HasTest := TDictionary<Int64, Boolean>.Create;
  Findings:= TList<TLintFinding>.Create;
  Seen    := TDictionary<string, string>.Create;
  try
    Load;
    for R in Rows do
      if (R.Kind = 'class') and (R.Attr = ATTR_FIXTURE) then Fixtures.AddOrSetValue(R.SymbolId, R);
    if Fixtures.Count = 0 then Exit;
    for R in Rows do
      if (R.Kind = 'method') and Fixtures.ContainsKey(R.ParentId) and MatchStr(R.Attr, TEST_ATTRIBUTES) then
        HasTest.AddOrSetValue(R.ParentId, True);
    for F in Fixtures.Values do
      if (not HasTest.ContainsKey(F.SymbolId)) and (not MayHaveOtherTests(F.SymbolId)) then  // dl:ok query-in-loop@e601 -- REVIEWED LINTFIX-B 2026-11-27: only fixtures with no [Test] of their own reach the ancestor walk, which is recursive
        Report(Format('Test fixture %s has no test: no method with [Test] or [TestCase], and no ancestor that could bring one', [F.Name]),
          F.StartLine, F.StartCol, F.Name.Length);
    for R in Rows do
    begin
      if (R.Attr = ATTR_IGNORE) and NoReason(R.Args) and InFixture(R) then
        Report(Format('[Ignore] on %s gives no reason; write [Ignore(''why'')] so the skipped test is not forgotten', [R.Name]),
          R.Line, R.Col, R.Attr.Length);
      if (R.Kind = 'method') and InFixture(R) and MatchStr(R.Attr, ONCE_ATTRIBUTES) then
      begin
        Key:= IntToStr(R.ParentId) + '|' + R.Attr;
        if Seen.TryGetValue(Key, First) then
        begin
          if not SameText(First, R.Name) then
            Report(Format('[%s] is already on %s of the same fixture; DUnitX runs only one method for it', [R.Attr, First]),
              R.Line, R.Col, R.Attr.Length);
        end
        else Seen.Add(Key, R.Name);
      end;
    end;
    Result:= Findings.ToArray;
  finally
    Seen.Free;
    Findings.Free;
    HasTest.Free;
    Fixtures.Free;
    Rows.Free;
  end;
end;

{ TOob2VariantRun }

type
  TOob2VariantRun = class
  strict private
    FCtx     : TV151FileCtx;
    FSrc     : TBytes;
    FScopes  : TObjectList<TDictionary<string, Boolean>>;
    FFindings: TList<TLintFinding>;
    function Text(const ANode: TTSNode): string;
    function IsVariantType(const ATypeNode: TTSNode): Boolean;
    procedure DeclareNames(const AGroup: TTSNode; AScope: TDictionary<string, Boolean>);
    procedure DeclareInline(const ANode: TTSNode; AScope: TDictionary<string, Boolean>);
    function DeclareRoutine(const ARoutine: TTSNode): TDictionary<string, Boolean>;
    function IsVariantName(const AName: string): Boolean;
    function VariantOperand(const AOperand: TTSNode): Boolean;
    function HasVariantArithmetic(const ANode: TTSNode): Boolean;
    procedure Emit(const ANode: TTSNode);
    procedure Walk(const ANode: TTSNode; ALoopDepth: Integer);
  public
    constructor Create(const ACtx: TV151FileCtx);
    destructor Destroy; override;
    function Run: TArray<TLintFinding>;
  end;

constructor TOob2VariantRun.Create(const ACtx: TV151FileCtx);
begin
  inherited Create;
  FCtx     := ACtx;
  FScopes  := TObjectList<TDictionary<string, Boolean>>.Create(True);
  FFindings:= TList<TLintFinding>.Create;
end;

destructor TOob2VariantRun.Destroy;
begin
  FFindings.Free;
  FScopes.Free;
  inherited;
end;

function TOob2VariantRun.Text(const ANode: TTSNode): string;
begin
  Result:= NodeText(ANode, FSrc);
end;

function TOob2VariantRun.IsVariantType(const ATypeNode: TTSNode): Boolean;
begin
  Result:= (not ATypeNode.IsNull) and MatchStr(LowerCase(StringReplace(Trim(Text(ATypeNode)), ' ', '', [rfReplaceAll])), VARIANT_TYPES);
end;

{ One declVar / declArg: every identifier child is a name, the type child decides. }
procedure TOob2VariantRun.DeclareNames(const AGroup: TTSNode; AScope: TDictionary<string, Boolean>);
var
  I: Integer;
  Child: TTSNode;
  Proven: Boolean;
begin
  Proven:= IsVariantType(AGroup.ChildByField('type'));
  for I:= 0 to AGroup.NamedChildCount - 1 do
  begin
    Child:= AGroup.NamedChild(I);
    if Child.NodeType = 'identifier' then AScope.AddOrSetValue(LowerCase(Text(Child)), Proven);
  end;
end;

{ `var X: Variant := ...` inside the body. }
procedure TOob2VariantRun.DeclareInline(const ANode: TTSNode; AScope: TDictionary<string, Boolean>);
var
  I: Integer;
  Child: TTSNode;
begin
  if (ANode.NodeType = 'defProc') or (ANode.NodeType = 'lambda') then Exit;
  if ANode.NodeType = 'varAssignDef' then
  begin
    for I:= 0 to ANode.NamedChildCount - 1 do
    begin
      Child:= ANode.NamedChild(I);
      if Child.NodeType = 'identifier' then AScope.AddOrSetValue(LowerCase(Text(Child)), IsVariantType(ANode.ChildByField('type')));
    end;
    Exit;
  end;
  for I:= 0 to ANode.NamedChildCount - 1 do DeclareInline(ANode.NamedChild(I), AScope);
end;

{ The names of one routine: parameters, locals, inline variables and Result; true = proven Variant. }
function TOob2VariantRun.DeclareRoutine(const ARoutine: TTSNode): TDictionary<string, Boolean>;
var
  I, J: Integer;
  Header, Args, Child, Group: TTSNode;
begin
  Result:= TDictionary<string, Boolean>.Create;
  Header:= ARoutine.ChildByField('header');
  if not Header.IsNull then
  begin
    Args:= Header.ChildByField('args');
    if not Args.IsNull then
      for I:= 0 to Args.NamedChildCount - 1 do
        if Args.NamedChild(I).NodeType = 'declArg' then DeclareNames(Args.NamedChild(I), Result);
    if IsVariantType(Header.ChildByField('type')) then Result.AddOrSetValue('result', True);
  end;
  for I:= 0 to ARoutine.NamedChildCount - 1 do
  begin
    Child:= ARoutine.NamedChild(I);
    if Child.NodeType = 'declVars' then
      for J:= 0 to Child.NamedChildCount - 1 do
      begin
        Group:= Child.NamedChild(J);
        if Group.NodeType = 'declVar' then DeclareNames(Group, Result);
      end;
  end;
  DeclareInline(ARoutine.ChildByField('body'), Result);
end;

{ The innermost routine that declares the name decides. }
function TOob2VariantRun.IsVariantName(const AName: string): Boolean;
var
  K: Integer;
begin
  for K:= FScopes.Count - 1 downto 0 do
    if FScopes[K].TryGetValue(AName, Result) then Exit;
  Result:= False;
end;

function TOob2VariantRun.VariantOperand(const AOperand: TTSNode): Boolean;
var
  Inner: TTSNode;
begin
  Result:= False;
  if AOperand.IsNull then Exit;
  if AOperand.NodeType = 'identifier' then Exit(IsVariantName(LowerCase(Text(AOperand))));
  if (AOperand.NodeType = 'exprParens') and (AOperand.NamedChildCount = 1) then
  begin
    Inner:= AOperand.NamedChild(0);
    Result:= VariantOperand(Inner);
  end;
end;

{ An arithmetic binary expression below ANode that has a proven Variant as a direct operand. }
function TOob2VariantRun.HasVariantArithmetic(const ANode: TTSNode): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if ANode.IsNull then Exit;
  if (ANode.NodeType = 'defProc') or (ANode.NodeType = 'lambda') then Exit;
  if (ANode.NodeType = 'exprBinary') and MatchStr(LowerCase(Trim(Text(ANode.ChildByField('operator')))), ARITHMETIC) and
     (VariantOperand(ANode.ChildByField('lhs')) or VariantOperand(ANode.ChildByField('rhs'))) then Exit(True);
  for I:= 0 to ANode.NamedChildCount - 1 do
    if HasVariantArithmetic(ANode.NamedChild(I)) then Exit(True);
end;

procedure TOob2VariantRun.Emit(const ANode: TTSNode);
begin
  FFindings.Add(MakeFinding(FCtx.Path, RULE_VARIANT_IN_LOOP, SEVERITY_HINT,
    'Arithmetic on a Variant inside a loop: every operation is a late-bound call; compute in a typed local and assign the Variant once',
    Integer(ANode.StartPoint.Row) + 1, TAstParseCache.CharCol(FCtx.Path, ANode.StartPoint),
    TAstParseCache.CharCol(FCtx.Path, ANode.EndPoint)));
end;

procedure TOob2VariantRun.Walk(const ANode: TTSNode; ALoopDepth: Integer);
var
  I, Depth: Integer;
begin
  if ANode.IsNull then Exit;
  if ANode.NodeType = 'defProc' then
  begin
    FScopes.Add(DeclareRoutine(ANode));
    try
      for I:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(I), 0);
    finally
      FScopes.Delete(FScopes.Count - 1);
    end;
    Exit;
  end;
  Depth:= ALoopDepth;
  if MatchStr(ANode.NodeType, LOOP_NODES) then Inc(Depth);
  if (ALoopDepth > 0) and (ANode.NodeType = 'assignment') and HasVariantArithmetic(ANode.ChildByField('rhs')) then Emit(ANode);
  for I:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(I), Depth);
end;

function TOob2VariantRun.Run: TArray<TLintFinding>;
var
  Parsed: TParsedFile;
begin
  Result:= nil;
  Parsed:= TAstParseCache.Get(FCtx.Path);
  if Parsed.Tree = nil then Exit;
  FSrc:= Parsed.Src;
  Walk(Parsed.Tree.RootNode, 0);
  Result:= FFindings.ToArray;
end;

{ TOob2Variant }

class function TOob2Variant.Check(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Run: TOob2VariantRun;
begin
  Run:= TOob2VariantRun.Create(ACtx);
  try
    Result:= Run.Run;
  finally
    Run.Free;
  end;
end;

end.
