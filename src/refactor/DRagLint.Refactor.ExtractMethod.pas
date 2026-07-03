unit DRagLint.Refactor.ExtractMethod;

{ Extract Method (refactoring-APPLY v1): pull a contiguous run of complete
  statements out of a routine body into a new method (class method) or a new
  implementation-section procedure (free routine), replacing the selection
  with a call. Single-file, driven by a line range. Reuses the M2 CFG
  (DRagLint.Analysis.Cfg) to detect unsafe shapes and REFUSES rather than
  emit anything uncertain -- see TExtractMethodRefactoring.Build.

  This unit (Task 2 of the implementation plan) provides selection resolution
  and the refuse guards only: mapping a line range to a single enclosing
  routine's contiguous statement run, and rejecting every unsafe shape (two
  routines, cut statement, goto/asm, Exit, escaping Break/Continue, nesting
  cross, ambiguous same-line sibling statements). Variable classification
  (Task 3) and method synthesis (Task 4) are layered on top of
  TExtractSelection in later tasks; until then every otherwise-valid
  selection refuses with 'not-yet-implemented'. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Analysis.Cfg
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Refactor.TextEdit
  ;

type
  /// <summary>Result discriminant for selection resolution. eoOK: the
  /// selection was resolved to a safe, contiguous statement run. eoRefused:
  /// resolution failed or the shape is unsafe; see the accompanying reason
  /// string returned alongside.</summary>
  TExtractOutcome = (eoOK, eoRefused);

  /// <summary>A resolved, validated selection: a contiguous run of complete
  /// statements at one nesting level, inside exactly one enclosing routine,
  /// free of escaping control flow.</summary>
  /// <remarks>FirstItem/LastItem index into the flattened statement list of
  /// the single statement-list node that directly contains the run (i.e. the
  /// named children of that 'block'/'statements' node) -- NOT a global index
  /// across the whole routine. StartLine/StartCol/EndLine/EndCol are the
  /// 1-based line/column span from the first statement's start to the last
  /// statement's end, as reported by tree-sitter's StartPoint/EndPoint.</remarks>
  TExtractSelection = record
    Proc      : TTSNode;
    IsMethod  : Boolean;
    OwnerClass: string;
    FirstItem : Integer;
    LastItem  : Integer;
    StartLine : Integer;
    StartCol  : Integer;
    EndLine   : Integer;
    EndCol    : Integer;
  end;

  /// <summary>Orchestrator for the Extract Method refactoring: resolves a
  /// line-range selection, validates it is safe to extract, and (in later
  /// tasks) synthesizes the new method and emits the edit set. Every
  /// uncertain precondition refuses with a specific reason rather than
  /// guessing -- see the module comment.</summary>
  TExtractMethodRefactoring = class
  public
    /// <summary>Computes the text edits that extract lines
    /// [AFromLine..AToLine] of AFile into a new method/procedure named
    /// ANewName, replacing the selection with a call.</summary>
    /// <param name="AFile">Path to the single Delphi source file to edit.</param>
    /// <param name="AFromLine">1-based first line of the selection.</param>
    /// <param name="AToLine">1-based last line of the selection (inclusive).</param>
    /// <param name="ANewName">Name for the new method/procedure.</param>
    /// <param name="ARefuse">Set to a non-empty, specific reason when the
    /// extraction is refused; '' on success.</param>
    /// <returns>nil when refused (ARefuse non-empty); a non-empty edit array
    /// when the extraction succeeds (ARefuse = '').</returns>
    /// <remarks>Task 2 implements selection resolution and the refuse guards
    /// only: every selection that passes all safety checks still refuses
    /// with 'not-yet-implemented' (Tasks 3-4 add classification + synthesis).</remarks>
    class function Build(const AFile: string; AFromLine, AToLine: Integer;
      const ANewName: string; out ARefuse: string): TArray<TTextEdit>;

    /// <summary>Human-readable preview of the edit set, matching the other
    /// refactorings' dry-run rendering (delegates to TTextEditApplier).</summary>
    class function RenderDryRun(const AEdits: TArray<TTextEdit>): string;
  end;

  /// <summary>Resolves [AFromLine..AToLine] in AFile to a validated
  /// TExtractSelection, or a refuse reason. Exposed at unit scope (not just
  /// via Build) so Task 2's tests can assert on resolution alone.</summary>
  /// <param name="AFile">Path to the source file.</param>
  /// <param name="AFromLine">1-based first line of the selection.</param>
  /// <param name="AToLine">1-based last line of the selection (inclusive).</param>
  /// <param name="ASel">The resolved selection on eoOK; undefined on eoRefused.</param>
  /// <param name="ARefuse">Specific reason on eoRefused; '' on eoOK.</param>
  /// <returns>eoOK if a safe, contiguous single-routine statement run was
  /// found; eoRefused otherwise.</returns>
  function ResolveExtractSelection(const AFile: string; AFromLine, AToLine: Integer;
    out ASel: TExtractSelection; out ARefuse: string): TExtractOutcome;

implementation

{ ---------------------------------------------------------------------------
  Helpers
  --------------------------------------------------------------------------- }

/// <summary>Every 'defProc' node anywhere under N whose body span
/// [StartByte..EndByte] contains ATargetByte. Mirrors
/// TRenameRefactoring.BuildLocal's EnclosingProc byte-containment test, but
/// collects ALL matches (nested procs both contain an inner target byte) so
/// the caller can detect "more than one candidate" ambiguity explicitly
/// rather than silently picking the outermost or innermost.</summary>
procedure CollectEnclosingProcs(const ATargetByte: Integer; const N: TTSNode; AAcc: TList<TTSNode>);
var I: Integer;
begin
  if N.IsNull then Exit;
  if (N.NodeType = 'defProc')
    and (Integer(N.StartByte) <= ATargetByte) and (Integer(N.EndByte) >= ATargetByte) then
    AAcc.Add(N);
  for I:= 0 to N.NamedChildCount - 1 do
    CollectEnclosingProcs(ATargetByte, N.NamedChild(I), AAcc);
end;

/// <summary>The innermost (smallest-span) defProc among AProcs. Assumes every
/// entry in AProcs actually contains the target byte (as CollectEnclosingProcs
/// guarantees); "innermost" is then just "smallest byte span".</summary>
function InnermostProc(const AProcs: TList<TTSNode>): TTSNode;
var I: Integer; BestLen, Len: Int64;
begin
  Result:= Default(TTSNode);
  if AProcs.Count = 0 then Exit;
  Result:= AProcs[0];
  BestLen:= Int64(AProcs[0].EndByte) - Int64(AProcs[0].StartByte);
  for I:= 1 to AProcs.Count - 1 do
  begin
    Len:= Int64(AProcs[I].EndByte) - Int64(AProcs[I].StartByte);
    if Len < BestLen then begin BestLen:= Len; Result:= AProcs[I]; end;
  end;
end;

/// <summary>1-based source line of a tree-sitter node's start point.</summary>
function NLine(const N: TTSNode): Integer;
begin Result:= Integer(N.StartPoint.Row) + 1; end;

/// <summary>1-based source line of a tree-sitter node's end point.</summary>
function NEndLine(const N: TTSNode): Integer;
begin Result:= Integer(N.EndPoint.Row) + 1; end;

/// <summary>1-based source column of a tree-sitter node's start point.</summary>
function NCol(const N: TTSNode): Integer;
begin Result:= Integer(N.StartPoint.Column) + 1; end;

/// <summary>1-based source column of a tree-sitter node's end point.</summary>
function NEndCol(const N: TTSNode): Integer;
begin Result:= Integer(N.EndPoint.Column) + 1; end;

/// <summary>Text of a node, decoded UTF-8 (tree-sitter's own encoding of the
/// byte buffer), mirroring TRenameRefactoring.BuildLocal's NStr helper.</summary>
function NStr(const N: TTSNode; const ASrc: TBytes): string;
var S, E, L: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
  if (L <= 0) or (S < 0) or (E > Length(ASrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(ASrc, S, L);
end;

/// <summary>The single statement-list node ('block' or 'statements') whose
/// DIRECT named children include AProc's routine body top level, found by
/// walking down from AProc's 'body' field. Mirrors how TCfgBuilder.Build
/// feeds AProc.ChildByField('body') straight into EmitStmt, which special-
/// cases K = 'block' or K = 'statements' as the list container.</summary>
function RoutineBodyList(const AProc: TTSNode): TTSNode;
var Body: TTSNode;
begin
  Result:= Default(TTSNode);
  if AProc.IsNull then Exit;
  Body:= AProc.ChildByField('body');
  if Body.IsNull then Exit;
  if (Body.NodeType = 'block') or (Body.NodeType = 'statements') then Exit(Body);
  Result:= Body; { defensive: some grammars may already hand back the list itself }
end;

/// <summary>True when ALine falls strictly between ANode's start and end
/// lines (exclusive of both) -- i.e. ALine is a CONTINUATION line of a
/// multi-line statement, not its first or last line. Used to detect a
/// selection boundary that cuts a statement in half. A selection whose
/// AFromLine/AToLine equals the statement's own StartLine/EndLine does NOT
/// cut it (whole-statement selections may legitimately start/end on the
/// statement's own first/last source line).</summary>
function LineStrictlyInside(const ANode: TTSNode; ALine: Integer): Boolean;
begin
  Result:= (ALine > NLine(ANode)) and (ALine < NEndLine(ANode));
end;

/// <summary>True when K is a COMPOUND statement node kind -- one of the
/// branch/loop/try/with constructs TCfgBuilder.EmitStmt decomposes in
/// DRagLint.Analysis.Cfg ('if'/'ifElse'/'case'/'while'/'for'/'foreach'/
/// 'repeat'/'try'/'with'). A selection line landing strictly inside one of
/// these (with no deeper resolvable statement list) crosses a NESTING level;
/// landing strictly inside a simple statement merely cuts it.</summary>
function IsCompoundStatementKind(const K: string): Boolean;
begin
  Result:= (K = 'if') or (K = 'ifElse') or (K = 'case') or (K = 'while')
    or (K = 'for') or (K = 'foreach') or (K = 'repeat') or (K = 'try') or (K = 'with');
end;

/// <summary>Finds the statement-list node ('block'/'statements') that
/// directly holds the run covering source line ATargetLine, at the DEEPEST
/// nesting level reachable without cutting a statement. Walks AList's own
/// named children by LINE span (not byte span, since a selection line may
/// start in leading whitespace before a statement's first token); if
/// ATargetLine falls strictly between a child's start/end lines (cutting a
/// multi-line statement) but that child itself wraps a nested
/// 'block'/'statements' (if/while/for/case/try/with bodies), descends into
/// every such nested list looking for one whose own child span covers
/// ATargetLine at a deeper level. Returns a null node when ATargetLine is
/// not covered by any child of AList at any depth.</summary>
/// <param name="ACutCompound">Set to True (never reset back -- the caller
/// initializes it to False) when resolution failed because ATargetLine lands
/// strictly inside a COMPOUND statement (see IsCompoundStatementKind) with
/// no deeper list resolving it -- i.e. the line lives at a different nesting
/// level than any reachable statement list. Lets the caller refuse with
/// 'selection crosses nesting levels' instead of the generic cut-statement
/// reason.</param>
function LocateStatementList(const AList: TTSNode; ATargetLine: Integer;
  var ACutCompound: Boolean): TTSNode;
var J, K: Integer; C, Nested, Found: TTSNode;
begin
  Result:= Default(TTSNode);
  if AList.IsNull then Exit;
  for J:= 0 to AList.NamedChildCount - 1 do
  begin
    C:= AList.NamedChild(J);
    if (NLine(C) <= ATargetLine) and (NEndLine(C) >= ATargetLine) then
    begin
      if not LineStrictlyInside(C, ATargetLine) then
        Exit(AList); { boundary lands on this statement's own first/last line: AList is the level }
      { ATargetLine cuts into a continuation line of C -- look for a nested
        statement list under C whose own children cover ATargetLine deeper. }
      for K:= 0 to C.NamedChildCount - 1 do
      begin
        Nested:= C.NamedChild(K);
        if (Nested.NodeType = 'block') or (Nested.NodeType = 'statements') then
        begin
          Found:= LocateStatementList(Nested, ATargetLine, ACutCompound);
          if not Found.IsNull then Exit(Found);
        end;
      end;
      { cuts C and no deeper list resolves it: unresolvable at this level.
        A compound C means the line lives at a nested level inside it (a
        nesting cross); a simple C means the selection cuts a multi-line
        statement in half. }
      if IsCompoundStatementKind(C.NodeType) then ACutCompound:= True;
      Exit;
    end;
  end;
end;

/// <summary>Byte offset of the first character of line ALine (1-based) in
/// ASrc, i.e. the byte offset AFromLine's selection start actually means:
/// the beginning of that source line. Returns -1 if ALine is out of range.
/// Used only to build a target byte for defProc containment / cut-statement
/// checks; line-based (not column-based) since AFromLine/AToLine are whole
/// lines from the caller.</summary>
function ByteOfLineStart(const ASrc: TBytes; ALine: Integer): Integer;
var Cur, Line, I: Integer;
begin
  Result:= -1;
  if ALine < 1 then Exit;
  Cur:= 0; Line:= 1;
  if Line = ALine then Exit(0);
  for I:= 0 to Length(ASrc) - 1 do
  begin
    if ASrc[I] = Ord(#10) then
    begin
      Inc(Line);
      if Line = ALine then Exit(I + 1);
    end;
  end;
  Result:= -1;
end;

/// <summary>Byte offset one past the last character of line ALine (1-based)
/// in ASrc, i.e. the offset of that line's terminating CR/LF (or EOF).
/// Returns Length(ASrc) if ALine is the last line or out of range high.</summary>
function ByteOfLineEnd(const ASrc: TBytes; ALine: Integer): Integer;
var NextStart: Integer;
begin
  NextStart:= ByteOfLineStart(ASrc, ALine + 1);
  if NextStart < 0 then Exit(Length(ASrc));
  Result:= NextStart;
  { back off the line's own CR/LF so the "end" byte sits at end-of-content }
  while (Result > 0) and ((ASrc[Result - 1] = Ord(#13)) or (ASrc[Result - 1] = Ord(#10))) do
    Dec(Result);
end;

/// <summary>True when AProc's header name contains a '.' (e.g. 'TFoo.Bar'),
/// meaning it is a class-method implementation. Mirrors
/// DRagLint.Parser.Delphi13's WalkDeclProc, which strips everything up to
/// the LAST '.' to get the bare method name -- the header name node's text
/// carries the qualifier directly (no genericDot subtree to walk).</summary>
function TryGetOwnerClass(const AProc: TTSNode; const ASrc: TBytes; out AOwnerClass: string): Boolean;
var Hdr, NameN: TTSNode; FullName: string; DotPos: Integer;
begin
  Result:= False;
  AOwnerClass:= '';
  if AProc.IsNull then Exit;
  Hdr:= AProc.ChildByField('header');
  if Hdr.IsNull then Exit;
  NameN:= Hdr.ChildByField('name');
  if NameN.IsNull then Exit;
  FullName:= Trim(NStr(NameN, ASrc));
  if FullName = '' then Exit;
  DotPos:= LastDelimiter('.', FullName);
  if DotPos <= 0 then Exit; { free routine: bare name, no qualifier }
  AOwnerClass:= Copy(FullName, 1, DotPos - 1);
  Result:= True;
end;

/// <summary>True if ANode's own subtree (not descending into a nested
/// defProc) contains a 'goto', 'label', or 'declLabels' node. Extract
/// Method refuses on any such shape even when TCfg.Skipped already covers
/// most of them, because it gives a more specific reason string.</summary>
function ContainsGotoOrLabel(const N: TTSNode): Boolean;
var I: Integer; K: string;
begin
  Result:= False;
  if N.IsNull then Exit;
  K:= N.NodeType;
  if N.NodeType = 'defProc' then Exit; { nested routine: own scope }
  if (K = 'goto') or (K = 'label') or (K = 'declLabels') then Exit(True);
  for I:= 0 to N.NamedChildCount - 1 do
    if ContainsGotoOrLabel(N.NamedChild(I)) then Exit(True);
end;

/// <summary>Lower-cased text of a bare identifier/statement node, mirroring
/// TCfgBuilder's LowerText helper (used to recognise Exit/Break/Continue by
/// name, since the grammar has no dedicated node kind for them).</summary>
function LowerNodeText(const N: TTSNode; const ASrc: TBytes): string;
begin
  Result:= LowerCase(Trim(NStr(N, ASrc)));
end;

/// <summary>Scans ANode's subtree (stopping at nested defProc boundaries) for
/// escaping control flow that would break if the enclosing statements were
/// moved into a new method: a bare 'Exit' call/identifier, any goto/label,
/// or a 'Break'/'Continue' whose innermost enclosing loop (while/for/foreach/
/// repeat) is NOT itself fully inside ANode (i.e. the loop started before
/// ANode, or ANode ends before the loop does -- either way the break/continue
/// would no longer have a loop to target once extracted). Mirrors
/// TCfgBuilder.EmitStmt's own recognition of 'exit'/'break'/'continue' by
/// lower-cased node text and its loop-context tracking (Loops stack).</summary>
function FindEscapingControlFlow(const ANode: TTSNode; const ASrc: TBytes;
  ALoopDepthInsideRun: Integer): string;
var I: Integer; K, Txt: string; Ch: TTSNode; InnerDepth: Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  K:= ANode.NodeType;
  if K = 'defProc' then Exit; { nested routine: own scope, not our concern }

  if (K = 'goto') or (K = 'label') or (K = 'declLabels') then
    Exit('selection contains goto/label');

  if (K = 'while') or (K = 'for') or (K = 'foreach') or (K = 'repeat') then
  begin
    { Everything at/under this loop node is now "inside a loop that is fully
      inside the run" -- Break/Continue targeting THIS loop are safe. }
    for I:= 0 to ANode.NamedChildCount - 1 do
    begin
      Result:= FindEscapingControlFlow(ANode.NamedChild(I), ASrc, ALoopDepthInsideRun + 1);
      if Result <> '' then Exit;
    end;
    Exit;
  end;

  if (K = 'statement') or (K = 'exprCall') or (K = 'exprDot') or (K = 'identifier') then
  begin
    if K = 'exprCall' then Txt:= LowerNodeText(ANode.ChildByField('entity'), ASrc)
    else Txt:= LowerNodeText(ANode, ASrc);
    if Txt = 'exit' then Exit('selection contains Exit');
    if (Txt = 'break') or (Txt = 'continue') then
    begin
      if ALoopDepthInsideRun <= 0 then
        Exit(Format('selection contains %s that escapes the selection (no enclosing loop inside the selection)', [Txt]));
      Exit; { break/continue targets a loop fully inside the run: safe }
    end;
  end;

  for I:= 0 to ANode.NamedChildCount - 1 do
  begin
    Ch:= ANode.NamedChild(I);
    InnerDepth:= ALoopDepthInsideRun;
    Result:= FindEscapingControlFlow(Ch, ASrc, InnerDepth);
    if Result <> '' then Exit;
  end;
end;

/// <summary>True when any item in AList[AFirst..ALast] (inclusive) is a
/// 'with' node (an Opaque-producing construct per DRagLint.Analysis.Cfg) --
/// Extract Method refuses rather than reason about with-bound names crossing
/// the extraction boundary.</summary>
function RunContainsWith(const AList: TTSNode; AFirst, ALast: Integer): Boolean;
var I: Integer;
begin
  Result:= False;
  for I:= AFirst to ALast do
    if AList.NamedChild(I).NodeType = 'with' then Exit(True);
end;

{ ---------------------------------------------------------------------------
  ResolveExtractSelection
  --------------------------------------------------------------------------- }

function ResolveExtractSelection(const AFile: string; AFromLine, AToLine: Integer;
  out ASel: TExtractSelection; out ARefuse: string): TExtractOutcome;
var
  PF        : TParsedFile;
  Src       : TBytes;
  Procs     : TList<TTSNode>;
  Proc      : TTSNode;
  Cfg       : TCfg;
  StmtList  : TTSNode;
  TargetList: TTSNode;
  TargetListTo: TTSNode;
  CutCompound : Boolean;
  FromByte  : Integer;
  ToByte    : Integer;
  FromLine, ToLine: Integer;
  I         : Integer;
  FirstIdx, LastIdx: Integer;
  CountFrom, CountTo: Integer;
  Ch        : TTSNode;
  Reason    : string;
  OwnerClass: string;
begin
  ASel:= Default(TExtractSelection);
  ARefuse:= '';
  Result:= eoRefused;

  if AFromLine > AToLine then
  begin
    ARefuse:= 'selection range is empty (from-line is after to-line)';
    Exit;
  end;

  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then
  begin
    ARefuse:= 'could not parse file';
    Exit;
  end;
  Src:= PF.Src;

  FromLine:= AFromLine;
  ToLine  := AToLine;
  FromByte:= ByteOfLineStart(Src, FromLine);
  ToByte  := ByteOfLineEnd(Src, ToLine);
  if (FromByte < 0) or (ToByte < 0) then
  begin
    ARefuse:= 'selection range is outside the file';
    Exit;
  end;

  { 1. Find the unique enclosing defProc whose body span contains the WHOLE
    selection (both endpoints); more than one match, at this point, only
    happens for a nested defProc containing both bytes -- pick innermost --
    but if the two endpoints resolve to DIFFERENT innermost procs, the
    selection spans two routines and we refuse. }
  Procs:= TList<TTSNode>.Create;
  try
    CollectEnclosingProcs(FromByte, PF.Tree.RootNode, Procs);
    if Procs.Count = 0 then
    begin
      ARefuse:= 'selection is not inside a single routine';
      Exit;
    end;
    Proc:= InnermostProc(Procs);

    { Verify the END of the selection resolves to the SAME innermost proc;
      otherwise the range spans two (sibling or parent/child) routines. }
    Procs.Clear;
    CollectEnclosingProcs(ToByte, PF.Tree.RootNode, Procs);
    if (Procs.Count = 0) or (not (InnermostProc(Procs) = Proc)) then
    begin
      ARefuse:= 'selection is not inside a single routine';
      Exit;
    end;
  finally
    Procs.Free;
  end;

  { 2. Build the CFG; refuse on goto/asm (TCfg.Skipped). }
  Cfg:= TCfgBuilder.Build(Proc, Src);
  try
    Cfg.ComputePreds;
    if Cfg.Skipped then
    begin
      ARefuse:= 'routine uses goto/asm';
      Exit;
    end;
  finally
    Cfg.Free;
  end;
  { Belt-and-braces: TCfgBuilder only inspects the routine body; a goto/label
    anywhere in the routine already sets Skipped, but check explicitly too
    so the reason string is stable even if that invariant ever changes. }
  if ContainsGotoOrLabel(Proc) then
  begin
    ARefuse:= 'routine uses goto/asm';
    Exit;
  end;

  { 3. Flatten the enclosing statement list at the selection's nesting level
    and map [FromLine..ToLine] to a contiguous run of complete statements.
    Line-based (not byte-based): AFromLine/AToLine are whole source lines,
    which typically include leading indentation BEFORE a statement's first
    token, so matching must compare against the statement's line span
    (NLine/NEndLine), not do byte-offset containment against the line's own
    first byte. }
  StmtList:= RoutineBodyList(Proc);
  if StmtList.IsNull or ((StmtList.NodeType <> 'block') and (StmtList.NodeType <> 'statements')) then
  begin
    ARefuse:= 'selection must be whole statements (routine body has no statement list)';
    Exit;
  end;

  { The statement list directly containing the selection is the run's
    nesting level: resolve BOTH endpoints independently (descend from the
    routine's top-level statement list to the deepest list whose own child
    span covers the line -- see LocateStatementList). Refuse when either
    endpoint is unresolvable (a compound statement in the way = the line
    lives at a different nesting level; a simple statement = the selection
    cuts it) or when the two endpoints resolve to DIFFERENT lists (the
    selection starts and ends at different nesting levels). }
  FirstIdx:= -1; LastIdx:= -1;
  CutCompound:= False;
  TargetList  := LocateStatementList(StmtList, FromLine, CutCompound);
  TargetListTo:= LocateStatementList(StmtList, ToLine, CutCompound);
  if TargetList.IsNull or TargetListTo.IsNull then
  begin
    if CutCompound then ARefuse:= 'selection crosses nesting levels'
    else ARefuse:= 'selection must be whole statements';
    Exit;
  end;
  if not (TargetList = TargetListTo) then
  begin
    ARefuse:= 'selection crosses nesting levels';
    Exit;
  end;

  { Find FirstIdx/LastIdx within TargetList by line span; the run must be a
    contiguous sub-sequence [FirstIdx..LastIdx] whose combined span covers
    [FromLine..ToLine] (each statement whole, none cut, none skipped outside
    the run's own span). }
  for I:= 0 to TargetList.NamedChildCount - 1 do
  begin
    Ch:= TargetList.NamedChild(I);
    if (FirstIdx < 0) and (NLine(Ch) <= FromLine) and (NEndLine(Ch) >= FromLine) then
      FirstIdx:= I;
    if (NLine(Ch) <= ToLine) and (NEndLine(Ch) >= ToLine) then
    begin
      LastIdx:= I;
      Break;
    end;
  end;

  if (FirstIdx < 0) or (LastIdx < 0) then
  begin
    ARefuse:= 'selection must be whole statements';
    Exit;
  end;

  { Ambiguity guard: the line-to-statement mapping must be UNIQUE at both
    selection boundaries. With two statements on one line ('a := 1; b := 2;')
    a line-based selection cannot say which of them it means -- the naive
    first-match pick would silently DROP the trailing sibling(s) from the
    run, violating the prime directive (refuse rather than guess). Refuse
    whenever more than one statement in the run's list touches the start
    line or the end line. }
  CountFrom:= 0; CountTo:= 0;
  for I:= 0 to TargetList.NamedChildCount - 1 do
  begin
    Ch:= TargetList.NamedChild(I);
    if (NLine(Ch) <= FromLine) and (NEndLine(Ch) >= FromLine) then Inc(CountFrom);
    if (NLine(Ch) <= ToLine) and (NEndLine(Ch) >= ToLine) then Inc(CountTo);
  end;
  if (CountFrom > 1) or (CountTo > 1) then
  begin
    ARefuse:= 'multiple statements share a line in the selection';
    Exit;
  end;

  { Verify neither boundary statement is CUT by the selection: the selection
    must start EXACTLY on the first statement's own first line (not a
    continuation line of a multi-line statement) and end EXACTLY on the last
    statement's own last line -- otherwise part of a statement sits outside
    the selected line range even though its span overlaps it. }
  if FromLine <> NLine(TargetList.NamedChild(FirstIdx)) then
  begin
    ARefuse:= 'selection must be whole statements';
    Exit;
  end;
  if ToLine <> NEndLine(TargetList.NamedChild(LastIdx)) then
  begin
    ARefuse:= 'selection must be whole statements';
    Exit;
  end;

  { 4. Scan the run for escaping control flow and with-bound (Opaque) items. }
  if RunContainsWith(TargetList, FirstIdx, LastIdx) then
  begin
    ARefuse:= 'selection references a with-bound name';
    Exit;
  end;
  for I:= FirstIdx to LastIdx do
  begin
    Reason:= FindEscapingControlFlow(TargetList.NamedChild(I), Src, 0);
    if Reason <> '' then
    begin
      ARefuse:= Reason;
      Exit;
    end;
  end;

  { 5. Fill out the selection record. }
  ASel.Proc:= Proc;
  ASel.IsMethod:= TryGetOwnerClass(Proc, Src, OwnerClass);
  ASel.OwnerClass:= OwnerClass;
  ASel.FirstItem:= FirstIdx;
  ASel.LastItem := LastIdx;
  ASel.StartLine:= NLine(TargetList.NamedChild(FirstIdx));
  ASel.StartCol := NCol(TargetList.NamedChild(FirstIdx));
  ASel.EndLine  := NEndLine(TargetList.NamedChild(LastIdx));
  ASel.EndCol   := NEndCol(TargetList.NamedChild(LastIdx));

  ARefuse:= '';
  Result:= eoOK;
end;

{ ---------------------------------------------------------------------------
  TExtractMethodRefactoring
  --------------------------------------------------------------------------- }

class function TExtractMethodRefactoring.Build(const AFile: string; AFromLine, AToLine: Integer;
  const ANewName: string; out ARefuse: string): TArray<TTextEdit>;
var
  Sel: TExtractSelection;
begin
  Result:= nil;
  if ResolveExtractSelection(AFile, AFromLine, AToLine, Sel, ARefuse) = eoRefused then Exit;

  { Selection resolution + safety guards succeeded. Variable classification
    (Task 3) and method synthesis + edit emission (Task 4) are not
    implemented yet -- refuse explicitly rather than emit a partial or
    incorrect edit set. }
  ARefuse:= 'not-yet-implemented';
  Result:= nil;
end;

class function TExtractMethodRefactoring.RenderDryRun(const AEdits: TArray<TTextEdit>): string;
begin
  Result:= TTextEditApplier.RenderDryRun(AEdits);
end;

end.
