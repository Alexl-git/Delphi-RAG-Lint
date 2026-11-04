unit DRagLint.Diagnostics.LifetimeShapeChecks;

{ The three AST rules of the old ROADMAP candidate list (1.42 lane ruleset). All OFF by default.

    stream-buffer-after-free   : a pointer into a memory stream's buffer (S.Memory, @S.Bytes[n],
                                 Pointer(S.Bytes)) is used after the stream was freed
                                 unconditionally. This is the real form of the candidate "dangling
                                 TBytes after a stream close": a TBytes copy of S.Bytes is itself
                                 reference-counted and outlives the stream, so it stays silent.
    interfaced-object-nil-leak : `X := TFoo.Create; ...; X := nil` where X is an OBJECT reference to
                                 a TInterfacedObject descendant -- the candidate "Result := nil on a
                                 TInterfacedObject". An object reference holds no count, so nil
                                 releases nothing and the instance leaks. `Result := nil` with no
                                 fresh instance (the find-idiom) is silent, and so is any X that may
                                 have reached an interface holder (a bare use or a method call).
    identifier-case-mismatch   : a name spelled in a different case from its declaration: locals and
                                 parameters from the AST (no index needed), plus -- given a store --
                                 every ref the resolver bound to a project symbol. One finding per
                                 spelling per routine / per symbol per file. }

interface

uses
  System.SysUtils
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  STREAM_BUFFER_AFTER_FREE_RULE = 'stream-buffer-after-free';
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  INTERFACED_OBJECT_NIL_LEAK_RULE = 'interfaced-object-nil-leak';
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  IDENTIFIER_CASE_MISMATCH_RULE = 'identifier-case-mismatch';

type
  /// <summary>Checker for the three lifetime / spelling shape rules of lane ruleset.</summary>
  /// <remarks>Stateless; thread-safe. Called from DoLint and DoLintAll behind
  /// LintRuleWants(rule, LINT_GATE_LIFETIME_SHAPE); every rule is OFF by default, so the post-filter
  /// drops the findings unless the rule was asked for.</remarks>
  TLifetimeShapeChecker = class
  public
    /// <summary>Runs the rules against one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="AStore">Optional symbol store: widens the class-descent checks beyond the file
    /// and supplies the bound refs of identifier-case-mismatch. nil is valid.</param>
    /// <param name="AFileId">File id within AStore; 0 or less means the store does not hold it.</param>
    /// <param name="AIncludeRefs">Read the file's bound refs for identifier-case-mismatch. The caller
    /// passes True only when that rule is enabled: the read costs one query per file.</param>
    /// <returns>One finding per violation; empty when clean or unparsable.</returns>
    class function Check(const AFile: string; const AStore: ISymbolStore; AFileId: Int64;
      AIncludeRefs: Boolean): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.RegularExpressions
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  ;

const
  ANCESTOR_INTERFACED = 'TInterfacedObject';
  ANCESTOR_MEM_STREAM = 'TCustomMemoryStream';
  MEMORY_STREAM_TYPES: array[0..4] of string = (
    'TMemoryStream', 'TBytesStream', 'TStringStream', 'TCustomMemoryStream', 'TResourceStream');
  FREE_MEMBER = 'Free';
  DESTROY_MEMBER = 'Destroy';
  FREE_AND_NIL = 'FreeAndNil';
  RESULT_NAME = 'result';
  NIL_TEXT = 'nil';
  SEV_WARNING = 'warning';
  SEV_INFO = 'info';
  { the `cast(` prefix an alias expression may carry }
  CAST_PREFIX = '(?:(?:Pointer|P[A-Za-z]\w*)\(|\()*';
  { anything after the buffer expression: closing parens, then pointer arithmetic }
  ALIAS_SUFFIX = '\)*(?:[+-].*)?$';
  { `var P := expr;` / `var P: T := expr;`: name, type, initialiser }
  GROUP_INITIALISER = 3;
  INLINE_VAR_PATTERN = '\b(\w+)\s*(:\s*[\w.^]+\s*)?:=\s*(.+?)\s*;?\s*$';

type
  { Per-call state; a fresh instance per Check call keeps the checker stateless. }
  TShapeRun = class  // dl:ok high-response@f2f7 -- REVIEWED 2026-11-04: one per-call state class for three small rules; RFC 51 is one over the limit and splitting it would only hide the same calls
  private
    FFile      : string;
    FSrc       : TBytes;
    FStore     : ISymbolStore;
    FFileId    : Int64;
    FFindings  : TList<TLintFinding>;
    FParentOf  : TDictionary<string, string>; { same-file class -> first ancestor, lower-case }
    function NodeStr(const N: TTSNode): string;
    function Squeezed(const N: TTSNode): string;
    procedure Emit(const ARule, AMsg: string; const ANode: TTSNode; const ASev: string);
    function DescendsFrom(const AType, AAncestor: string): Boolean;
    function IsMemoryStreamType(const AType: string): Boolean;
    procedure CollectLocals(const N: TTSNode; ALocals, ASpelled: TDictionary<string, string>;
      AAmbiguous: TDictionary<string, Boolean>);
    procedure CheckStreamBuffers(const ADefProc: TTSNode; ALocals: TDictionary<string, string>);
    procedure CheckNilLeak(const ADefProc: TTSNode; ALocals: TDictionary<string, string>);
    procedure CheckLocalCase(const ADefProc: TTSNode; ASpelled: TDictionary<string, string>;
      AAmbiguous: TDictionary<string, Boolean>);
    procedure CheckRoutine(const ADefProc: TTSNode);
    procedure Walk(const N: TTSNode);
  public
    constructor Create(const AFile: string; const ASrc: TBytes; const AStore: ISymbolStore; AFileId: Int64);
    destructor Destroy; override;
    procedure Run(const ARoot: TTSNode);
    procedure CheckBoundRefs;
    function Findings: TArray<TLintFinding>;
  end;

function IsOneOf(const AKind: string; const AKinds: array of string): Boolean;
begin
  for var K in AKinds do
    if K = AKind then Exit(True);
  Result:= False;
end;

constructor TShapeRun.Create(const AFile: string; const ASrc: TBytes; const AStore: ISymbolStore; AFileId: Int64);
const
  { `TFoo = class(TBar` -- a comment that looks like this only adds an unused edge }
  HERITAGE_PATTERN = '\b(\w+)\s*=\s*class\s*\(\s*([\w.]+)';
var
  M: TMatch;
begin
  inherited Create;
  FFile    := AFile;
  FSrc     := ASrc;
  FStore   := AStore;
  FFileId  := AFileId;
  FFindings:= TList<TLintFinding>.Create;
  FParentOf:= TDictionary<string, string>.Create;
  for M in TRegEx.Matches(TEncoding.ANSI.GetString(ASrc), HERITAGE_PATTERN, [roIgnoreCase]) do
    FParentOf.AddOrSetValue(LowerCase(M.Groups[1].Value), LowerCase(M.Groups[2].Value));
end;

destructor TShapeRun.Destroy;
begin
  FParentOf.Free;
  FFindings.Free;
  inherited Destroy;
end;

function TShapeRun.Findings: TArray<TLintFinding>;
begin
  Result:= FFindings.ToArray;
end;

function TShapeRun.NodeStr(const N: TTSNode): string;  // dl:ok duplicate-code@aa08 -- REVIEWED 2026-11-04: the per-checker NodeStr every Diagnostics unit carries, by convention (see the SrcStr marker in AstChecks)
var
  S, L: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte);
  L:= Integer(N.EndByte) - S;
  if (L <= 0) or (S < 0) or (S + L > Length(FSrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(FSrc, S, L);
end;

{ The node's text with every whitespace run removed: the alias patterns need not spell spacing. }
function TShapeRun.Squeezed(const N: TTSNode): string;
begin
  Result:= TRegEx.Replace(NodeStr(N), '\s+', '');
end;

procedure TShapeRun.Emit(const ARule, AMsg: string; const ANode: TTSNode; const ASev: string);
var
  P: TTSPoint;
  F: TLintFinding;
begin
  P:= ANode.StartPoint;
  F:= Default(TLintFinding);
  F.RuleId   := ARule;
  F.Severity := ASev;
  F.Message  := AMsg;
  F.FilePath := FFile;
  F.StartLine:= Integer(P.Row) + 1;
  F.StartCol := Integer(P.Column) + 1;
  F.EndLine  := F.StartLine;
  F.EndCol   := F.StartCol + 1;
  FFindings.Add(F);
end;

{ True when AType is AAncestor or reaches it: the same-file chain first, then the store. An unknown
  chain answers False, so every rule built on this stays silent on what it cannot prove. }
function TShapeRun.DescendsFrom(const AType, AAncestor: string): Boolean;
var
  Cur, Next: string;
  Seen     : TDictionary<string, Boolean>;
begin
  Cur:= LowerCase(AType);
  Seen:= TDictionary<string, Boolean>.Create;
  try
    while Cur <> '' do
    begin
      if Cur = LowerCase(AAncestor) then Exit(True);
      if Seen.ContainsKey(Cur) or not FParentOf.TryGetValue(Cur, Next) then Break;
      Seen.Add(Cur, True);
      Cur:= Next;
    end;
  finally
    Seen.Free;
  end;
  Result:= (FStore <> nil) and (FFileId > 0) and FStore.IsDescendantOf(AType, AAncestor, FFileId);
end;

function TShapeRun.IsMemoryStreamType(const AType: string): Boolean;
begin
  for var T in MEMORY_STREAM_TYPES do
    if SameText(T, AType) then Exit(True);
  Result:= DescendsFrom(AType, ANCESTOR_MEM_STREAM);
end;

{ Locals, inline locals and parameters of one routine, nested routines excluded. ALocals maps the
  lower-case name to the declared type ('' when untyped); ASpelled to the declared spelling. A name
  declared twice in different spellings (two inline blocks) is ambiguous: the case rule skips it. }
procedure TShapeRun.CollectLocals(const N: TTSNode; ALocals, ASpelled: TDictionary<string, string>;
  AAmbiguous: TDictionary<string, Boolean>);
var
  I        : Integer;
  Ty, Kid  : TTSNode;
  Key, Prev: string;
begin
  if N.IsNull or (N.NodeType = 'lambda') then Exit;
  if IsOneOf(N.NodeType, ['declVar', 'varDef', 'varAssignDef', 'declArg']) then
  begin
    Ty:= N.ChildByField('type');
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      Kid:= N.NamedChild(I);
      if Kid.NodeType <> 'identifier' then Continue;
      if (not Ty.IsNull) and (Integer(Kid.StartByte) >= Integer(Ty.StartByte)) then Break;
      Key:= LowerCase(NodeStr(Kid));
      if ASpelled.TryGetValue(Key, Prev) and (Prev <> NodeStr(Kid)) then AAmbiguous.AddOrSetValue(Key, True);
      ASpelled.AddOrSetValue(Key, NodeStr(Kid));
      ALocals.AddOrSetValue(Key, Trim(NodeStr(Ty)));
      if (N.NodeType = 'varDef') or (N.NodeType = 'varAssignDef') then Break; { what follows the one name is the initialiser }
    end;
    Exit;
  end;
  for I:= 0 to N.NamedChildCount - 1 do
  begin
    Kid:= N.NamedChild(I);
    if Kid.NodeType <> 'defProc' then CollectLocals(Kid, ALocals, ASpelled, AAmbiguous);
  end;
end;

{ --- stream-buffer-after-free -------------------------------------------------------------------- }

procedure TShapeRun.CheckStreamBuffers(const ADefProc: TTSNode; ALocals: TDictionary<string, string>);
var
  Streams : TDictionary<string, Boolean>;
  Pointers: TDictionary<string, Boolean>;
  AliasOf : TDictionary<string, string>;  { pointer -> stream it points into }
  Dangling: TDictionary<string, string>;  { pointer -> stream, once that stream was freed }
  Reported: TDictionary<string, Boolean>;

  function IsPointerType(const AType: string): Boolean;
  begin
    Result:= SameText(AType, 'Pointer') or TRegEx.IsMatch(AType, '^P[A-Z]\w*$');
  end;

  { The stream ARhs points into, or ''. ARequireCast: a bare S.Bytes is a TBytes copy, not a pointer,
    when the target's type is not spelled (an inline `var B := S.Bytes`). }
  function AliasedStream(const ARhs: string; ARequireCast: Boolean): string;
  begin
    Result:= '';
    for var S in Streams.Keys do
    begin
      var Q: string:= TRegEx.Escape(S);
      if TRegEx.IsMatch(ARhs, '^' + CAST_PREFIX + '(?:@?' + Q + '\.Memory|@' + Q + '\.Bytes\[[^\]]*\]|' + Q + '\.Bytes)' + ALIAS_SUFFIX, [roIgnoreCase])
        and not (ARequireCast and SameText(ARhs, S + '.Bytes')) then Exit(S);
    end;
  end;

  procedure MarkFreed(const AStream: string);
  begin
    for var Pair in AliasOf do
      if Pair.Value = AStream then Dangling.AddOrSetValue(Pair.Key, AStream);
  end;

  { The stream an unconditional free statement frees, or ''. }
  function FreedStream(const N: TTSNode): string;
  var
    L, R, Args: TTSNode;
  begin
    Result:= '';
    if N.NodeType = 'exprDot' then
    begin
      L:= N.ChildByField('lhs');
      R:= N.ChildByField('rhs');
      if (not L.IsNull) and (not R.IsNull) and (L.NodeType = 'identifier')
        and (SameText(NodeStr(R), FREE_MEMBER) or SameText(NodeStr(R), DESTROY_MEMBER)) then
        Result:= LowerCase(NodeStr(L));
    end
    else if N.NodeType = 'exprCall' then
    begin
      if SameText(NodeStr(N.ChildByField('entity')), FREE_AND_NIL) then
      begin
        Args:= N.ChildByField('args');
        if (not Args.IsNull) and (Args.NamedChildCount >= 1) then Result:= LowerCase(NodeStr(Args.NamedChild(0)));
      end
      else
        Result:= FreedStream(N.ChildByField('entity')); { S.Free() }
    end;
    if not Streams.ContainsKey(Result) then Result:= '';
  end;

  procedure Visit(const N: TTSNode; AConditional: Boolean);  // dl:ok too-many-exit-points@dbf0, cyclomatic-complexity@2ba0 -- REVIEWED 2026-11-04: a node-kind dispatch; each arm is one early Exit and the order is the source order the rule follows
  var
    I         : Integer;
    Kid, L, R : TTSNode;
    Name, Stm : string;
    InExcept  : Boolean;
    Typed     : Boolean;
    InlineVar : TMatch;
  begin
    if N.IsNull or (N.NodeType = 'defProc') or (N.NodeType = 'lambda') or (N.NodeType = 'asm') then Exit;
    if N.NodeType = 'identifier' then
    begin
      Name:= LowerCase(NodeStr(N));
      if Dangling.TryGetValue(Name, Stm) and not Reported.ContainsKey(Name) then
      begin
        Reported.Add(Name, True);
        Emit(STREAM_BUFFER_AFTER_FREE_RULE, NodeStr(N) + ' points into the buffer of stream ' + Stm
          + ', which was freed above -- the pointer dangles. Keep the stream alive past this use, or copy the bytes out first.',
          N, SEV_WARNING);
      end;
      Exit;
    end;
    if IsOneOf(N.NodeType, ['varDef', 'varAssignDef', 'declVar'])
      or ((N.NodeType = 'assignment') and TRegEx.IsMatch(NodeStr(N), '^var\b', [roIgnoreCase])) then
    begin
      { an inline declaration, which the grammar can also hand over as an assignment: read off the text,
        so the wrapper layout does not matter }
      Visit(N.ChildByField('rhs'), AConditional);
      InlineVar:= TRegEx.Match(NodeStr(N), INLINE_VAR_PATTERN, [roIgnoreCase, roSingleLine]);
      if InlineVar.Success then
      begin
        Name:= LowerCase(InlineVar.Groups[1].Value);
        Typed:= InlineVar.Groups[2].Success and (InlineVar.Groups[2].Value <> '');
        if (not Typed) or Pointers.ContainsKey(Name) then
        begin
          Stm:= AliasedStream(TRegEx.Replace(InlineVar.Groups[GROUP_INITIALISER].Value, '\s+', ''), not Typed);
          if Stm <> '' then AliasOf.AddOrSetValue(Name, Stm);
        end;
      end;
      Exit;
    end;
    if N.NodeType = 'assignment' then
    begin
      L:= N.ChildByField('lhs');
      R:= N.ChildByField('rhs');
      Visit(R, AConditional);
      if (not L.IsNull) and (L.NodeType = 'identifier') then
      begin
        Name:= LowerCase(NodeStr(L));
        Dangling.Remove(Name);
        AliasOf.Remove(Name);
        if Pointers.ContainsKey(Name) then
        begin
          Stm:= AliasedStream(Squeezed(R), False);
          if Stm <> '' then AliasOf.AddOrSetValue(Name, Stm);
        end;
      end
      else
        Visit(L, AConditional);
      Exit;
    end;
    if not AConditional then
    begin
      Stm:= FreedStream(N);
      if Stm <> '' then
      begin
        MarkFreed(Stm);
        Exit;
      end;
    end;
    if N.NodeType = 'exprDot' then
    begin
      Visit(N.ChildByField('lhs'), AConditional);
      R:= N.ChildByField('rhs');
      if (not R.IsNull) and (R.NodeType <> 'identifier') then Visit(R, AConditional);
      Exit;
    end;
    if N.NodeType = 'try' then
    begin
      InExcept:= False;
      for I:= 0 to N.ChildCount - 1 do
      begin
        Kid:= N.Child(I);
        if Kid.NodeType = 'kExcept' then InExcept:= True;
        if Kid.NodeType = 'kFinally' then InExcept:= False;
        Visit(Kid, AConditional or InExcept);
      end;
      Exit;
    end;
    { a free inside any of these may not have run when control reaches the next statement }
    if IsOneOf(N.NodeType, ['if', 'ifElse', 'case', 'while', 'for', 'foreach', 'repeat', 'with']) then
      AConditional:= True;
    for I:= 0 to N.ChildCount - 1 do Visit(N.Child(I), AConditional);
  end;

begin
  Streams := TDictionary<string, Boolean>.Create;
  Pointers:= TDictionary<string, Boolean>.Create;
  AliasOf := TDictionary<string, string>.Create;
  Dangling:= TDictionary<string, string>.Create;
  Reported:= TDictionary<string, Boolean>.Create;
  try
    for var Pair in ALocals do
      if (Pair.Value <> '') and IsMemoryStreamType(Pair.Value) then Streams.AddOrSetValue(Pair.Key, True)
      else if IsPointerType(Pair.Value) then Pointers.AddOrSetValue(Pair.Key, True);
    if Streams.Count > 0 then Visit(ADefProc.ChildByField('body'), False);
  finally
    Reported.Free;
    Dangling.Free;
    AliasOf.Free;
    Pointers.Free;
    Streams.Free;
  end;
end;

{ --- interfaced-object-nil-leak ------------------------------------------------------------------ }

procedure TShapeRun.CheckNilLeak(const ADefProc: TTSNode; ALocals: TDictionary<string, string>);
const
  CTOR_PATTERN = '^[\w.<>,]+\.Create\b';
  ELSE_NODE = 'kElse';
var
  Candidates: TDictionary<string, string>; { lower name -> declared type }
  Live      : TDictionary<string, string>; { lower name -> branch path of its ctor assignment }

  { The function's declared return type, or ''. }
  function ReturnType: string;
  var
    Header: TTSNode;
  begin
    Result:= '';
    for var I:= 0 to ADefProc.NamedChildCount - 1 do
    begin
      Header:= ADefProc.NamedChild(I);
      if Header.NodeType = 'declProc' then Exit(Trim(NodeStr(Header.ChildByField('type'))));
    end;
  end;

  { A use outside `X := ...`. In a right-hand side `X.Member` only reads; anywhere else it may be a
    method call handing Self to an interface holder. A bare X can reach one directly. }
  procedure VisitUse(const N: TTSNode; AInRhs: Boolean);
  var
    I   : Integer;
    L, R: TTSNode;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'identifier' then
    begin
      Live.Remove(LowerCase(NodeStr(N)));
      Exit;
    end;
    if N.NodeType = 'exprDot' then
    begin
      L:= N.ChildByField('lhs');
      R:= N.ChildByField('rhs');
      if (not L.IsNull) and (L.NodeType = 'identifier') then
      begin
        if not AInRhs then Live.Remove(LowerCase(NodeStr(L)));
      end
      else
        VisitUse(L, AInRhs);
      if (not R.IsNull) and (R.NodeType <> 'identifier') then VisitUse(R, AInRhs);
      Exit;
    end;
    for I:= 0 to N.ChildCount - 1 do VisitUse(N.Child(I), AInRhs);
  end;

  procedure Visit(const N: TTSNode; const APath: string);
  var
    I, Branch: Integer;
    Kid, L, R: TTSNode;
    Name, Ctor, Txt: string;
  begin
    if N.IsNull or (N.NodeType = 'defProc') or (N.NodeType = 'asm') then Exit;
    if N.NodeType = 'assignment' then
    begin
      L:= N.ChildByField('lhs');
      R:= N.ChildByField('rhs');
      VisitUse(R, True);
      if (not L.IsNull) and (L.NodeType = 'identifier') then
      begin
        Name:= LowerCase(NodeStr(L));
        if not Candidates.ContainsKey(Name) then Exit;
        Txt:= Squeezed(R);
        if SameText(Txt, NIL_TEXT) then
        begin
          { the ctor's branch path must enclose this nil: `if c then X := T.Create else X := nil` is no leak }
          if Live.TryGetValue(Name, Ctor) and APath.StartsWith(Ctor) then
            Emit(INTERFACED_OBJECT_NIL_LEAK_RULE, NodeStr(L) + ' is an object reference of a TInterfacedObject descendant ('
              + Candidates[Name] + ') and holds a fresh instance: an object reference holds no count, so nil releases nothing and the instance leaks. '
              + 'Declare it as an interface, or Free it.', N, SEV_WARNING);
          Live.Remove(Name);
        end
        else if TRegEx.IsMatch(Txt, CTOR_PATTERN, [roIgnoreCase]) then
          Live.AddOrSetValue(Name, APath)
        else
          Live.Remove(Name);
      end
      else if (not L.IsNull) and (L.NodeType = 'exprDot') and (L.ChildByField('lhs').NodeType = 'identifier') then
        { X.Field := v writes a member; it does not hand X to anyone }
      else
        VisitUse(L, True);
      Exit;
    end;
    if (N.NodeType = 'if') or (N.NodeType = 'ifElse') or (N.NodeType = 'case') then
    begin
      Branch:= 0;
      for I:= 0 to N.ChildCount - 1 do
      begin
        Kid:= N.Child(I);
        if (Kid.NodeType = ELSE_NODE) or (Kid.NodeType = 'caseCase') then Inc(Branch);
        Visit(Kid, APath + '/' + IntToStr(Integer(N.StartByte)) + ':' + IntToStr(Branch));
      end;
      Exit;
    end;
    if IsOneOf(N.NodeType, ['exprDot', 'exprCall', 'identifier', 'lambda', 'with']) then
    begin
      VisitUse(N, False);
      Exit;
    end;
    for I:= 0 to N.ChildCount - 1 do Visit(N.Child(I), APath);
  end;

begin
  Candidates:= TDictionary<string, string>.Create;
  Live      := TDictionary<string, string>.Create;
  try
    for var Pair in ALocals do
      if (Pair.Value <> '') and DescendsFrom(Pair.Value, ANCESTOR_INTERFACED) then
        Candidates.AddOrSetValue(Pair.Key, Pair.Value);
    var Ret: string:= ReturnType;
    if (Ret <> '') and DescendsFrom(Ret, ANCESTOR_INTERFACED) then Candidates.AddOrSetValue(RESULT_NAME, Ret);
    if Candidates.Count > 0 then Visit(ADefProc.ChildByField('body'), '');
  finally
    Live.Free;
    Candidates.Free;
  end;
end;

{ --- identifier-case-mismatch: locals and parameters ---------------------------------------------- }

procedure TShapeRun.CheckLocalCase(const ADefProc: TTSNode; ASpelled: TDictionary<string, string>;
  AAmbiguous: TDictionary<string, Boolean>);
var
  Seen: TDictionary<string, Boolean>;

  procedure Visit(const N: TTSNode);
  var
    I        : Integer;
    R        : TTSNode;
    Txt, Decl: string;
  begin
    if N.IsNull then Exit;
    { `with` can rebind any bare name to a member; a type name, a declaration or asm is not a use }
    if IsOneOf(N.NodeType, ['defProc', 'lambda', 'with', 'asm', 'typeref', 'type', 'declVar']) then Exit;
    if N.NodeType = 'identifier' then
    begin
      Txt:= NodeStr(N);
      if ASpelled.TryGetValue(LowerCase(Txt), Decl) and (Txt <> Decl) and not AAmbiguous.ContainsKey(LowerCase(Txt))
        and not Seen.ContainsKey(Txt) then
      begin
        Seen.Add(Txt, True);
        Emit(IDENTIFIER_CASE_MISMATCH_RULE, Txt + ' is declared as ' + Decl + ' -- use the declared spelling.', N, SEV_INFO);
      end;
      Exit;
    end;
    if N.NodeType = 'exprDot' then
    begin
      Visit(N.ChildByField('lhs'));
      R:= N.ChildByField('rhs');
      if (not R.IsNull) and (R.NodeType <> 'identifier') then Visit(R);
      Exit;
    end;
    if (N.NodeType = 'varDef') or (N.NodeType = 'varAssignDef') then
    begin
      { the first identifier is the declared name; only the initialiser is a use }
      var Declared: Boolean:= False;
      for I:= 0 to N.NamedChildCount - 1 do
        if Declared then Visit(N.NamedChild(I))
        else Declared:= N.NamedChild(I).NodeType = 'identifier';
      Exit;
    end;
    for I:= 0 to N.ChildCount - 1 do Visit(N.Child(I));
  end;

begin
  Seen:= TDictionary<string, Boolean>.Create;
  try
    Visit(ADefProc.ChildByField('body'));
  finally
    Seen.Free;
  end;
end;

procedure TShapeRun.CheckRoutine(const ADefProc: TTSNode);
var
  Locals, Spelled: TDictionary<string, string>;
  Ambiguous      : TDictionary<string, Boolean>;
begin
  if ADefProc.ChildByField('body').IsNull then Exit;
  Locals   := TDictionary<string, string>.Create;
  Spelled  := TDictionary<string, string>.Create;
  Ambiguous:= TDictionary<string, Boolean>.Create;
  try
    CollectLocals(ADefProc, Locals, Spelled, Ambiguous);
    CheckStreamBuffers(ADefProc, Locals);
    CheckNilLeak(ADefProc, Locals);
    CheckLocalCase(ADefProc, Spelled, Ambiguous);
  finally
    Ambiguous.Free;
    Spelled.Free;
    Locals.Free;
  end;
end;

procedure TShapeRun.Walk(const N: TTSNode);
var
  I: Integer;
begin
  if N.IsNull then Exit;
  if N.NodeType = 'defProc' then CheckRoutine(N);
  for I:= 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I));
end;

procedure TShapeRun.Run(const ARoot: TTSNode);
begin
  Walk(ARoot);
end;

{ --- identifier-case-mismatch: bound refs ----------------------------------------------------------- }

procedure TShapeRun.CheckBoundRefs;
var
  Names: TDictionary<Int64, string>; { symbol id -> declared name }
  Seen : TDictionary<string, Boolean>;
begin
  if (FStore = nil) or (FFileId <= 0) then Exit;
  Names:= TDictionary<Int64, string>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for var R in FStore.GetReferencesFromFile(FFileId) do
    begin
      if R.SymbolId <= 0 then Continue;
      var Decl: string;
      if not Names.TryGetValue(R.SymbolId, Decl) then
      begin
        Decl:= FStore.GetSymbolById(R.SymbolId).Name;
        Names.Add(R.SymbolId, Decl);
      end;
      if (R.NameText = Decl) or not SameText(R.NameText, Decl) then Continue;
      var Key: string:= IntToStr(R.SymbolId) + ':' + R.NameText;
      if Seen.ContainsKey(Key) then Continue;
      Seen.Add(Key, True);
      var F: TLintFinding:= Default(TLintFinding);
      F.RuleId   := IDENTIFIER_CASE_MISMATCH_RULE;
      F.Severity := SEV_INFO;
      F.Message  := R.NameText + ' is declared as ' + Decl + ' -- use the declared spelling.';
      F.FilePath := FFile;
      F.StartLine:= R.StartLine;
      F.StartCol := R.StartCol;
      F.EndLine  := R.EndLine;
      F.EndCol   := R.EndCol;
      FFindings.Add(F);
    end;
  finally
    Seen.Free;
    Names.Free;
  end;
end;

class function TLifetimeShapeChecker.Check(const AFile: string; const AStore: ISymbolStore; AFileId: Int64;
  AIncludeRefs: Boolean): TArray<TLintFinding>;
var
  PF : TParsedFile;
  Run: TShapeRun;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Run:= TShapeRun.Create(AFile, PF.Src, AStore, AFileId);
  try
    Run.Run(PF.Tree.RootNode);
    if AIncludeRefs then Run.CheckBoundRefs;
    Result:= Run.Findings;
  finally
    Run.Free;
  end;
end;

end.
