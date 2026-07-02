unit DRagLint.Diagnostics.DeadCodeChecks;

{ v0.68 -- dead-code / redundant-code rules (pure AST, no DB required).
  Rules implemented here:
    unused-parameter     : a routine parameter never referenced in the body.
    identical-then-else  : an if-else whose then and else branches are textually
                           identical (copy-paste bug).
    referenced-never-set : a private/strict-private class field that is read in
                           at least one method body but never written anywhere in
                           the class -- always holds its zero value (latent bug).
    redundant-parentheses: (v0.70) an exprParens wrapping either another
                           exprParens ('((X))') or a lone atomic term ('(X)',
                           '(1)'); severity 'hint'. Composite inner expressions
                           are not flagged, and initializer/constructor contexts
                           (const/var defaultValue, arr/rec initializers) are
                           skipped -- there '(x)' is a required constructor
                           (conservative, near-zero FP).
    commented-out-code   : (v0.70) a comment whose ENTIRE stripped text is a
                           single statement -- an anchored 'lhs := rhs;' with a
                           bare lvalue path, or 'idpath(...);'. Prose that merely
                           quotes ':=' or a call inside a sentence is NOT flagged
                           (that was the dominant false positive). Severity
                           'hint'; directives and doc comments are skipped.
    function-result-ignored: (v0.71) a bare-statement call (exprCall whose parent
                           is a 'statement' node) to an UNqualified identifier
                           naming a SAME-UNIT function (a declProc carrying a
                           return-type 'type' field) -- the return value is
                           discarded. Same-unit + pure AST (no symbol store);
                           cross-unit callees are not resolved. Severity 'hint'.
    magic-literal        : (v0.79, #14, Fowler "Replace Magic Literal") a
                           numeric literal not in the set 0, 1, -1, 2 and not
                           the direct value of a const/resourcestring/enum-
                           value/default-param, a case label, a range bound,
                           or a typed-const-array initializer element. Numbers
                           only. Severity 'hint'; OFF by default (medium-FP,
                           opt-in).
    boolean-flag-parameter: (v0.79, #14, Fowler "Remove Flag Argument") a
                           routine parameter typed exactly Boolean whose
                           identifier is referenced inside an if/ifElse/while/
                           repeat CONDITION, or is the case selector, inside
                           the routine body -- it selects behavior rather than
                           carrying data. Skips override methods (contract-
                           bound signature) and event-handler-shaped routines
                           (any parameter named Sender). Severity 'hint'.
    message-chain         : (v0.79, #14, Fowler "Hide Delegate") a member-access
                           chain 'a.b.c.d...' in VALUE-expression context deeper
                           than a configurable threshold (default 4 dotted
                           hops -- fires at 5+). Only 'exprDot' nodes count (a
                           left-nested lhs/rhs chain); the walk drills through an
                           intermediate 'exprCall' via its 'entity' field so
                           'a.b().c().d' also counts as a chain. Qualified type/
                           unit names use distinct node types in this grammar
                           ('typerefDot' for ancestor/typeref position,
                           'moduleName' for the uses clause) so they never match
                           'exprDot' and need no separate exemption. Flagged once
                           at the outermost 'exprDot' of the chain (a node whose
                           parent is not itself a link in the same chain).
                           Severity 'hint', configurable threshold.
    public-writable-field : (v0.79, #14, Fowler "Encapsulate Variable") a
                           'declField' under an EXPLICIT 'public' visibility
                           section ('declSection' carrying a 'kPublic' token
                           child) of a class ('declClass' without a 'kRecord'
                           token). Excludes: records (legitimately expose
                           fields), 'published' sections (auto-generated DFM
                           components -- huge noise if flagged), and the
                           implicit/default section (members listed before any
                           visibility keyword -- also the published-DFM-dump
                           shape). Severity 'info'; OFF by default -- FP-sanity
                           over src/ found 44 findings concentrated in 6/103
                           files, almost all intentional public field-bag
                           "record-like classes" (e.g. TCfgBlock/TCfg internal
                           data carriers, plugin form-helper classes) rather
                           than scattered accidental encapsulation breaks.
    loop-control-flag      : (v0.79, #14, Fowler "Replace Control Flag with
                           Break") a while/repeat loop whose CONDITION
                           references an identifier that is also assigned a
                           BARE True/False literal ('kTrue'/'kFalse' token,
                           never a computed boolean) somewhere inside the loop
                           BODY -- the "flag variable drives the exit" pattern
                           a 'Break' would express more directly. Severity
                           'hint'; OFF by default -- heuristic and the
                           riskiest rule of the v0.79 batch (a benign var that
                           happens to be both referenced in the condition and
                           reset to True/False inside the loop for unrelated
                           reasons would also trip it), gated on src/ FP-sanity. }

interface

uses
  System.SysUtils
  , System.StrUtils
  , System.Classes
  , System.Generics.Collections
  , TreeSitter
  , TreeSitterLib
  , DRagLint.Core.Model
  , DRagLint.Diagnostics.ParseCache
  ;

type
  /// <summary>Dead-code checks that operate on a single .pas file using the
  /// tree-sitter AST only; no symbol-store or DB is required.</summary>
  TDeadCodeChecker = class
  public
    /// <summary>Runs the dead-code rules against a single .pas file and
    /// returns one TLintFinding per violation.</summary>
    /// <param name="AFile">Absolute path to the .pas source file.</param>
    /// <returns>Array of findings (severity 'warning'); empty when the file is
    /// clean or could not be parsed.</returns>
    /// <remarks>Rules implemented: unused-parameter, identical-then-else,
    /// referenced-never-set, redundant-parentheses, commented-out-code, and
    /// function-result-ignored.
    /// unused-parameter guards (parameters NOT flagged even if unreferenced):
    ///   - var/out parameters (caller-visible side effects).
    ///   - Self (implicit class parameter).
    ///   - Methods whose INTERFACE-SECTION declaration (declProc) carries virtual,
    ///     dynamic, override, message, or abstract directives (contract-bound
    ///     signatures; the parameter cannot be freely removed). Detection uses a
    ///     two-pass approach: pass 1 collects the bare method names of all
    ///     contract-bound declProc nodes (via procAttribute children), and pass 2
    ///     skips any defProc whose unqualified name matches the collected set.
    ///     NOTE: in Delphi implementation bodies (defProc), the override/virtual
    ///     directives are NOT repeated -- they exist only on the interface-section
    ///     declProc. This two-pass design correctly handles that grammar structure.
    ///   - Routines with an 'asm' body (assembler block).
    ///   - VCL/FMX event handlers: a routine whose FIRST parameter is named
    ///     'Sender' (case-insensitive) is treated as an event handler -- all of
    ///     its parameters are fixed by the event-type signature and cannot be
    ///     freely removed. The entire method is skipped. Additionally, any
    ///     individual parameter named 'Sender' (any position) is also skipped
    ///     as a defensive secondary guard (some handlers list Sender later).
    ///   - external routines: these never reach the body pass at all. An
    ///     'external' declaration (both interface-section and implementation-
    ///     section forms, e.g. `procedure Foo(A: Integer); external 'x.dll';`)
    ///     is parsed by tree-sitter as a body-less declProc, NOT a defProc, so
    ///     CheckUnusedParams (which only visits defProc nodes) is never invoked
    ///     for it. Verified empirically: an external routine with an obviously-
    ///     unused parameter produces zero unused-parameter findings. This is
    ///     deliberate -- the external body is in a foreign module and the
    ///     parameter cannot be removed.
    /// Known limitation: interface-method implementations are not detected
    /// syntactically (requires a symbol store). If an interface method body slips
    /// through with an unused parameter it will be reported; this is an acceptable
    /// false-positive gap.
    /// identical-then-else emits one finding at the 'if' node when the then and
    /// else branches normalise to the same text. Plain 'if' nodes (no else) are
    /// not visited.
    /// referenced-never-set fires on a private or strict-private class field that
    /// is read in at least one method body of the same class but never assigned
    /// anywhere in the class. Guards (fields NOT flagged):
    ///   - Fields outside private/strict-private sections (protected/public/
    ///     published may be written from descendant units).
    ///   - Fields on classes whose direct ancestor name ends with 'Form', 'Frame',
    ///     or equals 'TComponent'/'TDataModule'/'TCustomForm' (case-insensitive) --
    ///     DFM/RTTI streaming writes these fields invisibly.
    ///   - Fields in the implicit-first section (published DFM component dump):
    ///     a declField that is a direct child of declClass with no enclosing
    ///     declSection is skipped.
    ///   - Fields with 0 reads AND 0 writes (scope of unused-private-member,
    ///     Task 6).
    /// Thread-safe if the parse cache is thread-safe for the caller's pattern;
    /// the checker itself has no shared mutable state.</remarks>
    class function Check(const AFile: string; AMinCaseBranches: Integer = 2;
      AMaxBoolOps: Integer = 4; AMaxUnitLines: Integer = 2000;
      AMaxChainHops: Integer = 4): TArray<TLintFinding>;
  end;

implementation

class function TDeadCodeChecker.Check(const AFile: string; AMinCaseBranches: Integer;
  AMaxBoolOps: Integer; AMaxUnitLines: Integer; AMaxChainHops: Integer): TArray<TLintFinding>;
var
  Src            : TBytes                      ;
  PF             : TParsedFile                 ;
  Findings       : TList<TLintFinding>         ;
  { Pass-1 result: bare lower-cased method names that carry a contract-binding
    directive (virtual/dynamic/override/message/abstract) in their declProc.
    A defProc whose unqualified name matches an entry here is skipped. }
  ContractMethods: TDictionary<string, Boolean>;
  { Bare lower-cased names of routines declared in THIS unit that are FUNCTIONS
    (declProc header carries a return-type 'type' field). Used by
    function-result-ignored -- a bare-statement call to one of these discards a
    return value. Same-unit only (pure AST, no symbol store). }
  LocalFunctions : TDictionary<string, Boolean>;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { Emit one finding pointing at ANode. Severity defaults to 'warning'; pass
    ASeverity to override (e.g. 'hint' for cosmetic rules). }
  procedure EmitAt(const ANode: TTSNode; const ARuleId, AMessage: string;
    const ASeverity: string = 'warning');
  var
    P: TTSPoint    ;
    F: TLintFinding;
  begin
    P:= ANode.StartPoint;
    F:= Default(TLintFinding);
    F.RuleId   := ARuleId;
    F.Severity := ASeverity;
    F.Message  := AMessage;
    F.FilePath := AFile;
    F.StartLine:= Integer(P.Row   ) + 1;
    F.StartCol := Integer(P.Column) + 1;
    F.EndLine  := F.StartLine;
    F.EndCol   := F.StartCol + Length(Trim(NodeStr(ANode)));
    Findings.Add(F);
  end;

  { Collapse internal whitespace to single spaces and trim edges.
    Used to normalise branch text for identical-then-else comparison. }
  function NormaliseText(const S: string): string;
  var
    I      : Integer;
    InSpace: Boolean;
    Buf    : TStringBuilder;
  begin
    Buf:= TStringBuilder.Create;
    try
      InSpace:= True;
      for I:= 1 to Length(S) do
      begin
        if CharInSet(S[I], [' ', #9, #10, #13]) then
        begin
          if not InSpace then
          begin
            Buf.Append(' ');
            InSpace:= True;
          end;
        end
        else
        begin
          Buf.Append(S[I]);
          InSpace:= False;
        end;
      end;
      Result:= Trim(Buf.ToString);
    finally
      Buf.Free;
    end;
  end;

  { Strip the leading/trailing comment delimiters from a raw comment token
    (line-slashes, brace pair, or paren-star pair), returning the trimmed inner
    text. Assumes ARaw is already trimmed. }
  function StripComment(const ARaw: string): string;
  var
    S: string;
  begin
    S:= ARaw;
    if S.StartsWith('//') then
      S:= Copy(S, 3, MaxInt)
    else if S.StartsWith('(*') then
    begin
      S:= Copy(S, 3, MaxInt);
      if S.EndsWith('*)') then S:= Copy(S, 1, Length(S) - 2);
    end
    else if S.StartsWith('{') then
    begin
      S:= Copy(S, 2, MaxInt);
      if S.EndsWith('}') then S:= Copy(S, 1, Length(S) - 1);
    end;
    Result:= Trim(S);
  end;

  { True if C can start a Delphi identifier (A..Z, a..z, _). Uses ordinal
    comparisons (not a set-range literal) so the tree-sitter self-parser is happy. }
  function IsIdentStartCh(const C: Char): Boolean;
  begin
    Result:= ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z')) or (C = '_');
  end;

  { True if C can continue an idpath (ident chars plus digits and '.'). }
  function IsIdentContCh(const C: Char): Boolean;
  begin
    Result:= IsIdentStartCh(C) or ((C >= '0') and (C <= '9')) or (C = '.');
  end;

  { True if the whole S is a bare lvalue path: ident chars, dots and brackets,
    NO spaces or other prose punctuation -- e.g. 'X', 'a[i]', 'Obj.Field'. Used
    to reject prose that merely quotes an assignment inside a sentence. }
  function IsLValuePath(const S: string): Boolean;
  var
    I: Integer;
  begin
    Result:= False;
    if S = '' then Exit;
    if not IsIdentStartCh(S[1]) then Exit;
    for I:= 1 to Length(S) do
      if not (IsIdentContCh(S[I]) or (S[I] = '[') or (S[I] = ']')) then Exit;
    Result:= True;
  end;

  { Conservative: is the WHOLE stripped comment a single assignment statement,
    'lhs := rhs;', whose lhs is a bare lvalue path (no prose)? This rejects the
    common false positive of a doc/explanatory comment that quotes ':=' inside a
    sentence (there the text before ':=' contains spaces / punctuation). }
  function LooksLikeAssignment(const S: string): Boolean;
  var
    P  : Integer;
    Lhs: string ;
    Rhs: string ;
  begin
    Result:= False;
    if (Length(S) < 4) or (S[Length(S)] <> ';') then Exit;   { must end with ';' }
    P:= Pos(':=', S);
    if P <= 1 then Exit;
    Lhs:= Trim(Copy(S, 1, P - 1));
    Rhs:= Trim(Copy(S, P + 2, MaxInt));                       { includes trailing ';' }
    Result:= IsLValuePath(Lhs) and (Length(Rhs) > 1);         { non-empty rhs before ';' }
  end;

  { Conservative test: is the WHOLE stripped comment a single Delphi call
    statement '<idpath>( ... );' -- an identifier/dotted path with the '('
    IMMEDIATELY after it (no space), then a trailing ');'. Anchoring + the
    no-space rule reject prose like 'see Foo (1);' and 'v11 (M1): ... (x);'. }
  function LooksLikeCallStatement(const S: string): Boolean;
  var
    I, N, J: Integer;
  begin
    Result:= False;
    N:= Length(S);
    if N < 4 then Exit;                 { need at least 'a();' }
    if S[N] <> ';' then Exit;           { must end with ';' }
    I:= 1;
    if not IsIdentStartCh(S[I]) then Exit;
    while (I <= N) and IsIdentContCh(S[I]) do Inc(I);
    if (I > N) or (S[I] <> '(') then Exit;   { '(' must IMMEDIATELY follow the idpath }
    { last non-space char before the ';' must be ')' }
    J:= N - 1;
    while (J >= 1) and (S[J] = ' ') do Dec(J);
    Result:= (J >= 1) and (S[J] = ')');
  end;

  { Count every identifier occurrence (lowercased) anywhere in subtree N.
    Uses NamedChildCount (not ChildCount) so keyword tokens are excluded,
    preventing false positives from keyword text that matches an identifier. }
  procedure CountIdents(const N: TTSNode; AMap: TDictionary<string, Integer>);
  var
    I: Integer;
    C: Integer;
    T: string ;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'identifier' then
    begin
      T:= LowerCase(NodeStr(N));
      if T <> '' then
      begin
        if AMap.TryGetValue(T, C) then AMap[T]:= C + 1
        else AMap.Add(T, 1);
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do CountIdents(N.NamedChild(I), AMap);
  end;

  { PASS 1: Collect all declProc bare method names that carry contract-binding
    directives. In Delphi, virtual/override/message etc. appear ONLY on the
    interface-section declProc, NOT on the implementation defProc body.
    A declProc has procAttribute nodes as named children; each procAttribute
    holds the actual keyword nodes. }
  procedure CollectContractDecls(const N: TTSNode);
  var
    I, J   : Integer;
    Attr   : TTSNode;
    NameN  : TTSNode;
    K      : string ;
    MName  : string ;
    IsContr: Boolean;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'declProc' then
    begin
      IsContr:= False;
      for I:= 0 to N.NamedChildCount - 1 do
      begin
        Attr:= N.NamedChild(I);
        if Attr.NodeType <> 'procAttribute' then Continue;
        for J:= 0 to Attr.NamedChildCount - 1 do
        begin
          K:= Attr.NamedChild(J).NodeType;
          if (K = 'kVirtual') or (K = 'kDynamic') or (K = 'kOverride')
            or (K = 'kMessage') or (K = 'kAbstract') then
          begin
            IsContr:= True;
            Break;
          end;
        end;
        if IsContr then Break;
      end;
      if IsContr then
      begin
        NameN:= N.ChildByField('name');
        if not NameN.IsNull then
        begin
          MName:= LowerCase(Trim(NodeStr(NameN)));
          if MName <> '' then ContractMethods.AddOrSetValue(MName, True);
        end;
      end;
      Exit; { no nested declProc inside a declProc }
    end;
    for I:= 0 to N.NamedChildCount - 1 do CollectContractDecls(N.NamedChild(I));
  end;

  { Collect the bare (unqualified, lower-cased) names of every routine declared
    in THIS unit that is a FUNCTION -- its declProc header carries a return-type
    'type' field (grammar: 'function Foo(...): T'). Both interface-section
    declProc declarations and implementation defProc headers are declProc nodes,
    so a single whole-tree walk catches every function (incl. nested). Used by
    function-result-ignored. }
  procedure CollectLocalFunctions(const N: TTSNode);
  var
    I     : Integer;
    NameN : TTSNode;
    Nm    : string ;
    DotPos: Integer;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'declProc' then
    begin
      if not N.ChildByField('type').IsNull then   { has a return type -> function }
      begin
        NameN:= N.ChildByField('name');
        if not NameN.IsNull then
        begin
          Nm:= LowerCase(Trim(NodeStr(NameN)));
          DotPos:= LastDelimiter('.', Nm);         { strip 'TClass.' qualifier }
          if DotPos > 0 then Nm:= Copy(Nm, DotPos + 1, MaxInt);
          if Nm <> '' then LocalFunctions.AddOrSetValue(Nm, True);
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do CollectLocalFunctions(N.NamedChild(I));
  end;

  { Check one defProc for unused-parameter findings. }
  procedure CheckUnusedParams(const ADefProc: TTSNode);
  var
    HdrNode   : TTSNode;
    ArgsNode  : TTSNode;
    ArgNode   : TTSNode;
    BodyNode  : TTSNode;
    TypeNode  : TTSNode;
    NameId    : TTSNode;
    Counts    : TDictionary<string, Integer>;
    I, J      : Integer;
    TypeStart : Integer;
    ParamName : string ;
    ParamLower: string ;
    Cnt       : Integer;
    IsVarOut  : Boolean;
    K         : string ;
    FullName  : string ;
    BareName  : string ;
    DotPos    : Integer;
  begin
    HdrNode:= ADefProc.ChildByField('header');
    if HdrNode.IsNull then Exit;

    { Resolve the unqualified method name (strip 'TClass.' prefix if present).
      For 'TDer.Go' the bare name is 'go'. For a free routine 'Plain' it stays
      'plain'. We check this bare name against the contract-methods set collected
      in pass 1. }
    var NameNode: TTSNode:= HdrNode.ChildByField('name');
    if not NameNode.IsNull then
    begin
      FullName:= LowerCase(Trim(NodeStr(NameNode)));
      DotPos:= LastDelimiter('.', FullName);
      if DotPos > 0 then BareName:= Copy(FullName, DotPos + 1, MaxInt)
      else BareName:= FullName;
      if ContractMethods.ContainsKey(BareName) then Exit;
    end;

    { Skip asm bodies -- identifier nodes are not emitted inside asm blocks. }
    BodyNode:= ADefProc.ChildByField('body');
    if (not BodyNode.IsNull) and (BodyNode.NodeType = 'asm') then Exit;

    { Collect args from the header (defProc has args under header, not directly). }
    ArgsNode:= HdrNode.ChildByField('args');
    if ArgsNode.IsNull then Exit;

    { EVENT-HANDLER GUARD: if the FIRST declArg's first name identifier is
      'Sender' (case-insensitive), this is a VCL/FMX event handler. All
      parameters are fixed by the event-type signature and cannot be removed --
      skip the entire method. }
    begin
      var FirstArg: TTSNode:= Default(TTSNode);
      var FAIdx: Integer;
      for FAIdx:= 0 to ArgsNode.NamedChildCount - 1 do
      begin
        if ArgsNode.NamedChild(FAIdx).NodeType = 'declArg' then
        begin
          FirstArg:= ArgsNode.NamedChild(FAIdx);
          Break;
        end;
      end;
      if not FirstArg.IsNull then
      begin
        var FATy: TTSNode:= FirstArg.ChildByField('type');
        var FATyStart: Integer:= MaxInt;
        if not FATy.IsNull then FATyStart:= Integer(FATy.StartByte);
        var FANameIdx: Integer;
        for FANameIdx:= 0 to FirstArg.NamedChildCount - 1 do
        begin
          var FANId: TTSNode:= FirstArg.NamedChild(FANameIdx);
          if FANId.NodeType <> 'identifier' then Continue;
          if Integer(FANId.StartByte) >= FATyStart then Continue;
          if SameText(Trim(NodeStr(FANId)), 'Sender') then Exit;
          Break; { only check the first name identifier }
        end;
      end;
    end;

    { Count all identifiers in the entire defProc subtree (including header).
      A parameter name appearing only in the header decl counts as 1; any use
      in the body raises the count above 1. }
    Counts:= TDictionary<string, Integer>.Create;
    try
      CountIdents(ADefProc, Counts);

      { Walk each declArg in the args list. }
      for I:= 0 to ArgsNode.NamedChildCount - 1 do
      begin
        ArgNode:= ArgsNode.NamedChild(I);
        if ArgNode.NodeType <> 'declArg' then Continue;

        { Detect var/out modifier: keyword tokens are non-named children of
          the declArg node. }
        IsVarOut:= False;
        for J:= 0 to ArgNode.ChildCount - 1 do
        begin
          K:= ArgNode.Child(J).NodeType;
          if (K = 'kVar') or (K = 'kOut') then
          begin
            IsVarOut:= True;
            Break;
          end;
        end;
        if IsVarOut then Continue;

        { Collect the parameter name identifier(s): identifiers that come before
          the type field in the declArg. }
        TypeNode:= ArgNode.ChildByField('type');
        TypeStart:= MaxInt;
        if not TypeNode.IsNull then TypeStart:= Integer(TypeNode.StartByte);

        for J:= 0 to ArgNode.NamedChildCount - 1 do
        begin
          NameId:= ArgNode.NamedChild(J);
          if NameId.NodeType <> 'identifier' then Continue;
          if Integer(NameId.StartByte) >= TypeStart then Continue;

          ParamName := NodeStr(NameId);
          ParamLower:= LowerCase(ParamName);

          { Skip the implicit Self parameter. }
          if ParamLower = 'self' then Continue;

          { SECONDARY EVENT-HANDLER GUARD: skip any parameter named 'Sender'
            regardless of position -- defensive guard for non-standard handler
            signatures where Sender appears later. }
          if ParamLower = 'sender' then Continue;

          { Count = 1 means the name appears only in the header declaration (no
            uses in the body); count = 0 would be a grammar anomaly -- both are
            flagged. }
          Cnt:= 0;
          Counts.TryGetValue(ParamLower, Cnt);
          if Cnt <= 1 then
            EmitAt(NameId, 'unused-parameter',
              Format('Parameter "%s" is declared but never used', [ParamName]));
        end;
      end;
    finally
      Counts.Free;
    end;
  end;

  { boolean-flag-parameter (Fowler "Remove Flag Argument", #14): True if the
    identifier ALower (already lower-cased) is referenced anywhere inside the
    CONDITION of an if/ifElse/while/repeat, or as the case selector, within
    the subtree N. The case selector has no grammar field (verified against
    grammar.js: the case-of expression is an unfielded $._expr) -- its NAMED
    children include keyword tokens (kCase/kOf/kElse/kEnd) plus caseCase arms,
    so the selector is the first named child that is neither a keyword
    ('k'-prefixed NodeType) nor a caseCase/statement/statements wrapper. }
  function SubtreeUsesIdentInCondition(const N: TTSNode; const ALower: string): Boolean;

    function IdentSubtreeMatches(const AExpr: TTSNode): Boolean;
    var K: Integer;
    begin
      Result:= False;
      if AExpr.IsNull then Exit;
      if (AExpr.NodeType = 'identifier') and SameText(Trim(NodeStr(AExpr)), ALower) then Exit(True);
      for K:= 0 to AExpr.ChildCount - 1 do
        if IdentSubtreeMatches(AExpr.Child(K)) then Exit(True);
    end;

  var
    I    : Integer;
    Cond : TTSNode;
    Sel  : TTSNode;
    Kid  : TTSNode;
    KT   : string;
  begin
    Result:= False;
    if N.IsNull then Exit;

    if (N.NodeType = 'if') or (N.NodeType = 'ifElse') or (N.NodeType = 'while') or (N.NodeType = 'repeat') then
    begin
      Cond:= N.ChildByField('condition');
      if IdentSubtreeMatches(Cond) then Exit(True);
    end
    else if N.NodeType = 'case' then
    begin
      Sel:= Default(TTSNode);
      for I:= 0 to N.NamedChildCount - 1 do
      begin
        Kid:= N.NamedChild(I);
        KT := Kid.NodeType;
        if (Length(KT) > 0) and (KT[1] = 'k') then Continue;
        if (KT = 'caseCase') or (KT = 'statement') or (KT = 'statements') then Continue;
        Sel:= Kid;
        Break;
      end;
      if IdentSubtreeMatches(Sel) then Exit(True);
    end;

    for I:= 0 to N.NamedChildCount - 1 do
      if SubtreeUsesIdentInCondition(N.NamedChild(I), ALower) then Exit(True);
  end;

  { Check one defProc for boolean-flag-parameter findings: a Boolean-typed
    parameter whose identifier drives an if/while/repeat condition or a case
    selector in the body -- it selects behavior rather than carrying data
    (Fowler "Remove Flag Argument"). Skips virtual/override methods (interface/
    inheritance contract -- the signature can't be freely changed; reuses the
    same ContractMethods set CheckUnusedParams relies on, because Delphi does
    NOT repeat virtual/override on the implementation defProc header -- only on
    the interface-section declProc) and event-handler-shaped routines (any
    parameter named 'Sender'). }
  procedure CheckBooleanFlagParam(const ADefProc: TTSNode);
  var
    HdrNode  : TTSNode;
    ArgsNode : TTSNode;
    ArgNode  : TTSNode;
    BodyNode : TTSNode;
    TypeNode : TTSNode;
    NameId   : TTSNode;
    I, J     : Integer;
    TypeStart: Integer;
    ParamName: string;
    HasSender: Boolean;
    FullName : string;
    BareName : string;
    DotPos   : Integer;
  begin
    HdrNode:= ADefProc.ChildByField('header');
    if HdrNode.IsNull then Exit;

    { Skip virtual/override methods: contract-bound signature, can't split the
      routine. Mirrors CheckUnusedParams -- the directive is only present on
      the interface-section declProc, not repeated here on the defProc. }
    var NameNode: TTSNode:= HdrNode.ChildByField('name');
    if not NameNode.IsNull then
    begin
      FullName:= LowerCase(Trim(NodeStr(NameNode)));
      DotPos:= LastDelimiter('.', FullName);
      if DotPos > 0 then BareName:= Copy(FullName, DotPos + 1, MaxInt)
      else BareName:= FullName;
      if ContractMethods.ContainsKey(BareName) then Exit;
    end;

    ArgsNode:= HdrNode.ChildByField('args');
    if ArgsNode.IsNull then Exit;

    BodyNode:= ADefProc.ChildByField('body');
    if BodyNode.IsNull then Exit;
    if BodyNode.NodeType = 'asm' then Exit;

    { Event-handler guard: any parameter named 'Sender' (any position) marks
      this as a VCL/FMX event handler -- the Boolean param (if any) is fixed
      by the event-type signature, not a design choice. }
    HasSender:= False;
    for I:= 0 to ArgsNode.NamedChildCount - 1 do
    begin
      ArgNode:= ArgsNode.NamedChild(I);
      if ArgNode.NodeType <> 'declArg' then Continue;
      TypeNode:= ArgNode.ChildByField('type');
      TypeStart:= MaxInt;
      if not TypeNode.IsNull then TypeStart:= Integer(TypeNode.StartByte);
      for J:= 0 to ArgNode.NamedChildCount - 1 do
      begin
        NameId:= ArgNode.NamedChild(J);
        if NameId.NodeType <> 'identifier' then Continue;
        if Integer(NameId.StartByte) >= TypeStart then Continue;
        if SameText(Trim(NodeStr(NameId)), 'Sender') then HasSender:= True;
      end;
    end;
    if HasSender then Exit;

    for I:= 0 to ArgsNode.NamedChildCount - 1 do
    begin
      ArgNode:= ArgsNode.NamedChild(I);
      if ArgNode.NodeType <> 'declArg' then Continue;

      TypeNode:= ArgNode.ChildByField('type');
      if TypeNode.IsNull then Continue;
      if not SameText(Trim(NodeStr(TypeNode)), 'Boolean') then Continue;

      TypeStart:= Integer(TypeNode.StartByte);
      for J:= 0 to ArgNode.NamedChildCount - 1 do
      begin
        NameId:= ArgNode.NamedChild(J);
        if NameId.NodeType <> 'identifier' then Continue;
        if Integer(NameId.StartByte) >= TypeStart then Continue;

        ParamName:= Trim(NodeStr(NameId));
        if SameText(ParamName, 'Self') then Continue;

        if SubtreeUsesIdentInCondition(BodyNode, LowerCase(ParamName)) then
          EmitAt(NameId, 'boolean-flag-parameter',
            Format('Boolean flag parameter "%s" selects behavior -- consider splitting into two routines', [ParamName]),
            'hint');
      end;
    end;
  end;

  { ---- v0.72 helpers: resource (#5), complexity (#6), exceptions (#7) ---- }

  { True if N's subtree carries a virtual-family directive (virtual/dynamic/
    override/abstract). Backs destructor-without-override. }
  function HasVirtOverrideAttr(const N: TTSNode): Boolean;
  var I: Integer; K: string;
  begin
    Result:= False;
    if N.IsNull then Exit;
    K:= N.NodeType;
    if (K = 'kVirtual') or (K = 'kDynamic') or (K = 'kOverride') or (K = 'kAbstract') then Exit(True);
    for I:= 0 to N.ChildCount - 1 do
      if HasVirtOverrideAttr(N.Child(I)) then Exit(True);
  end;

  { True if N's subtree contains a node of type AKind. A declProc has no nested
    procs, so a full scan is safe for the destructor keyword / class qualifier. }
  function SubtreeHasNodeType(const N: TTSNode; const AKind: string): Boolean;
  var I: Integer;
  begin
    Result:= False;
    if N.IsNull then Exit;
    if N.NodeType = AKind then Exit(True);
    for I:= 0 to N.ChildCount - 1 do
      if SubtreeHasNodeType(N.Child(I), AKind) then Exit(True);
  end;

  { True if AName looks like an exception class -- 'E'+Uppercase (EFoo) or ends
    with 'Exception'. Backs exception-constructed-but-not-raised. }
  function LooksLikeExceptionClass(const AName: string): Boolean;
  var S: string;
  begin
    S:= Trim(AName);
    Result:= ((Length(S) >= 2) and (S[1] = 'E') and (S[2] >= 'A') and (S[2] <= 'Z'))
          or ((Length(S) >= 9) and SameText(Copy(S, Length(S) - 8, 9), 'Exception'));
  end;

  { The class-type text (original case) of an 'on <v>: <Type> do' handler, or ''.
    Tries the 'type' field, else the first named child that is not the variable. }
  function HandlerClassText(const H: TTSNode): string;
  var I: Integer; T, V, C: TTSNode;
  begin
    Result:= '';
    T:= H.ChildByField('type');
    if not T.IsNull then Exit(Trim(NodeStr(T)));
    V:= H.ChildByField('variable');
    for I:= 0 to H.NamedChildCount - 1 do
    begin
      C:= H.NamedChild(I);
      if (not V.IsNull) and (Integer(C.StartByte) = Integer(V.StartByte)) then Continue;
      if (C.NodeType = 'typeref') or (C.NodeType = 'identifier') then Exit(Trim(NodeStr(C)));
    end;
  end;

  { Count boolean operator nodes (and/or/xor) in N's subtree. Backs
    boolean-expression-complexity. }
  function CountBoolOps(const N: TTSNode): Integer;
  var I: Integer; K: string;
  begin
    Result:= 0;
    if N.IsNull then Exit;
    K:= N.NodeType;
    if (K = 'kAnd') or (K = 'kOr') or (K = 'kXor') then Inc(Result);
    for I:= 0 to N.ChildCount - 1 do Inc(Result, CountBoolOps(N.Child(I)));
  end;

  { duplicate-exception-handler: within one try's except clause, flag a second
    'on <Class>' for a class already handled. Recurses but stops at a nested
    'try' (its handlers are its own). ASeen is a case-insensitive TStringList. }
  procedure FlagDupHandlers(const N: TTSNode; const ASeen: TStringList; const ATop: Boolean);
  var I: Integer; Cls: string;
  begin
    if N.IsNull then Exit;
    if (not ATop) and (N.NodeType = 'try') then Exit;
    if N.NodeType = 'exceptionHandler' then
    begin
      Cls:= HandlerClassText(N);
      if Cls <> '' then
      begin
        if ASeen.IndexOf(Cls) >= 0 then
          EmitAt(N, 'duplicate-exception-handler',
            Format('Duplicate exception handler for "%s" -- an earlier ''on'' already handles it; this branch is unreachable', [Cls]))
        else
          ASeen.Add(Cls);
      end;
    end;
    for I:= 0 to N.ChildCount - 1 do FlagDupHandlers(N.Child(I), ASeen, False);
  end;

  { v0.73: count identifier descendants of a declProp whose text equals the
    property name -- EXCLUDING the name node itself (ANameStart) and the property's
    type subtree (AType). A non-zero count means an accessor (read/write) names the
    property itself -> infinite recursion. Backs property-references-itself. }
  function IdentSelfRefCount(const N: TTSNode; const AName: string;
    ANameStart: Integer; const AType: TTSNode): Integer;
  var I: Integer;
  begin
    Result:= 0;
    if N.IsNull then Exit;
    if (not AType.IsNull) and (Integer(N.StartByte) = Integer(AType.StartByte))
       and (Integer(N.EndByte) = Integer(AType.EndByte)) then Exit; { skip the type }
    if (N.NodeType = 'identifier') and (Integer(N.StartByte) <> ANameStart)
       and SameText(Trim(NodeStr(N)), AName) then Inc(Result);
    for I:= 0 to N.ChildCount - 1 do
      Inc(Result, IdentSelfRefCount(N.Child(I), AName, ANameStart, AType));
  end;

  { v0.75 #10: True if AName (a variable/field name) looks security-sensitive --
    a substring match on a focused, low-FP set. Backs weak-random-for-security. }
  function IsSecurityName(const AName: string): Boolean;
  var L: string;
  begin
    L:= LowerCase(AName);
    Result:= (Pos('password', L) > 0) or (Pos('passphrase', L) > 0) or (Pos('secret', L) > 0)
          or (Pos('token', L) > 0) or (Pos('apikey', L) > 0) or (Pos('privatekey', L) > 0)
          or (Pos('salt', L) > 0) or (Pos('nonce', L) > 0) or (Pos('sessionid', L) > 0)
          or (Pos('cryptokey', L) > 0) or (Pos('securitykey', L) > 0);
  end;

  { v0.75 #10: True if N's subtree calls System.Random / RandomRange. }
  function SubtreeCallsRandom(const N: TTSNode): Boolean;
  var I: Integer; Ent: TTSNode;
  begin
    Result:= False;
    if N.IsNull then Exit;
    if N.NodeType = 'exprCall' then
    begin
      Ent:= N.ChildByField('entity');
      if (not Ent.IsNull) and (Ent.NodeType = 'identifier')
         and (SameText(Trim(NodeStr(Ent)), 'Random') or SameText(Trim(NodeStr(Ent)), 'RandomRange')) then
        Exit(True);
    end;
    for I:= 0 to N.ChildCount - 1 do
      if SubtreeCallsRandom(N.Child(I)) then Exit(True);
  end;

  { v0.79 #14 loop-control-flag helper: recursively collect every identifier
    name (lower-cased) referenced anywhere inside AExpr into AAcc. Used to
    pull the candidate flag names out of a while/repeat CONDITION subtree
    (handles wrappers like 'exprUnary not X' or 'exprBinary X = True'). }
  procedure LcfCollectIdents(const AExpr: TTSNode; AAcc: TList<string>);
  var K: Integer;
  begin
    if AExpr.IsNull then Exit;
    if AExpr.NodeType = 'identifier' then
    begin
      AAcc.Add(LowerCase(Trim(NodeStr(AExpr))));
      Exit;
    end;
    for K:= 0 to AExpr.ChildCount - 1 do
      LcfCollectIdents(AExpr.Child(K), AAcc);
  end;

  { v0.79 #14 loop-control-flag helper: True if ABody's subtree contains an
    'assignment' whose lhs is the bare identifier AFlagLower and whose rhs is
    a BARE True/False literal token ('kTrue'/'kFalse', not a computed boolean
    expression). This is the sentinel-flag-assignment signal. }
  function LcfBodyAssignsFlag(const ABody: TTSNode; const AFlagLower: string): Boolean;
  var K: Integer; Lhs, Rhs: TTSNode;
  begin
    Result:= False;
    if ABody.IsNull then Exit;
    if ABody.NodeType = 'assignment' then
    begin
      Lhs:= ABody.ChildByField('lhs');
      Rhs:= ABody.ChildByField('rhs');
      if (not Lhs.IsNull) and (not Rhs.IsNull) and (Lhs.NodeType = 'identifier')
         and SameText(Trim(NodeStr(Lhs)), AFlagLower)
         and ((Rhs.NodeType = 'kTrue') or (Rhs.NodeType = 'kFalse')) then
        Exit(True);
    end;
    for K:= 0 to ABody.ChildCount - 1 do
      if LcfBodyAssignsFlag(ABody.Child(K), AFlagLower) then Exit(True);
  end;

  { v0.76 #2: True if a node type is a top-level statement (an item that can be a
    direct sibling in a begin..end / try block). Used to detect two statements on
    one source line. Deliberately excludes expression/keyword nodes. }
  function IsStatementNodeType(const ANt: string): Boolean;
  begin
    Result:=
      (ANt = 'statement') or (ANt = 'assignment') or (ANt = 'exprCall') or
      (ANt = 'if') or (ANt = 'ifElse') or (ANt = 'while') or (ANt = 'repeat') or
      (ANt = 'for') or (ANt = 'forIn') or (ANt = 'case') or (ANt = 'with') or
      (ANt = 'try') or (ANt = 'raise') or (ANt = 'inherited') or (ANt = 'goto');
  end;

  { v0.76 #10: True if the callee text of an exprCall is a file read/write API
    (a temp path handed to one of these lands data in a predictable location). }
  function IsFileApiCallee(const AText: string): Boolean;
  var L: string;
  begin
    L:= LowerCase(AText);
    Result:= (Pos('savetofile', L) > 0) or (Pos('loadfromfile', L) > 0)
          or (Pos('writealltext', L) > 0) or (Pos('writeallbytes', L) > 0)
          or (Pos('readalltext', L) > 0) or (Pos('readallbytes', L) > 0)
          or (Pos('filecreate', L) > 0) or (Pos('assignfile', L) > 0)
          or (Pos('tfilestream', L) > 0);
  end;

  { v0.76 #10: True if a literalString's raw text is a hardcoded temp path. }
  function IsTempPathText(const AText: string): Boolean;
  var L: string;
  begin
    L:= LowerCase(AText);
    Result:= (Pos('\temp\', L) > 0) or (Pos('c:\temp', L) > 0)
          or (Pos('/tmp/', L) > 0) or (Pos('\windows\temp', L) > 0)
          or (Pos('\winnt\temp', L) > 0);
  end;

  { v0.76 #10: emit insecure-temp-file at the first hardcoded-temp-path string
    literal in a subtree (one per call site is enough). }
  procedure EmitTempPathLiteral(const N: TTSNode);
  var I: Integer;
  begin
    if N.IsNull then Exit;
    if (N.NodeType = 'literalString') and IsTempPathText(NodeStr(N)) then
    begin
      EmitAt(N, 'insecure-temp-file',
        'Hardcoded temp path in a file API -- predictable, world-readable location prone to races/symlink attacks. Use TPath.GetTempFileName / a per-user secured directory.');
      Exit;
    end;
    for I:= 0 to N.ChildCount - 1 do EmitTempPathLiteral(N.Child(I));
  end;

  { v0.79 #14 (message-chain, Fowler "Hide Delegate"): True if AParent is a node
    that continues the SAME dotted chain as a child 'exprDot' sitting in its
    lhs/entity spine -- i.e. AChild is not the outermost link. Two shapes chain:
      - AParent is 'exprDot' and AChild is AParent's 'lhs' (a.B.C -- C's lhs is
        the exprDot for a.B);
      - AParent is 'exprCall' and AChild is AParent's 'entity' (a.B() -- the
        exprCall wraps the exprDot as a qualified call, still mid-chain), AND
        that exprCall is itself further dotted (checked by the caller walking
        one level up: an exprCall is only "mid-chain" when ITS parent continues
        the chain too -- handled by IsChainLink being called on the exprCall's
        parent from CountChainHops, not here). }
  function IsChainLink(const AParent, AChild: TTSNode): Boolean;
  begin
    Result:= False;
    if AParent.IsNull or AChild.IsNull then Exit;
    if AParent.NodeType = 'exprDot' then
      Result:= Integer(AParent.ChildByField('lhs').StartByte) = Integer(AChild.StartByte)
    else if AParent.NodeType = 'exprCall' then
      Result:= Integer(AParent.ChildByField('entity').StartByte) = Integer(AChild.StartByte);
  end;

  { v0.79 #14: count the dotted hops of a member-access chain rooted at
    ATop (an 'exprDot'), walking DOWN the lhs spine and drilling through an
    intermediate 'exprCall' via its 'entity' field so 'a.b().c().d' counts the
    same as 'a.b.c.d'. Each 'exprDot' visited contributes one hop (its 'rhs'
    member). 'a.b.c.d.e' = 4 hops (b,c,d,e off a). }
  function CountChainHops(const ATop: TTSNode): Integer;
  var
    Cur: TTSNode;
  begin
    Result:= 0;
    Cur:= ATop;
    while (not Cur.IsNull) and (Cur.NodeType = 'exprDot') do
    begin
      Inc(Result);
      Cur:= Cur.ChildByField('lhs');
      while (not Cur.IsNull) and (Cur.NodeType = 'exprCall') do
        Cur:= Cur.ChildByField('entity');
    end;
  end;

  { v0.79 #14: True when N (an 'exprDot') is the OUTERMOST link of its chain --
    its parent does not continue the same chain (see IsChainLink). Only the
    outermost link is flagged, so a 6-hop chain emits exactly one finding. }
  function IsTopOfChain(const N: TTSNode): Boolean;
  begin
    Result:= (not N.Parent.IsNull) and (not IsChainLink(N.Parent, N));
  end;

  { v0.75 #5: drill through 'statement'/'statements' wrappers to the innermost
    first named child (the actual assignment/call); N unchanged if not a wrapper. }
  function UnwrapStmt(const N: TTSNode): TTSNode;
  begin
    Result:= N;
    while (not Result.IsNull) and ((Result.NodeType = 'statement') or (Result.NodeType = 'statements'))
          and (Result.NamedChildCount >= 1) do
      Result:= Result.NamedChild(0);
  end;

  { v0.75 #5: True if N is an assignment whose rhs is a constructor call --
    'TFoo.Create(...)' (exprCall whose entity is an exprDot '.Create') OR the
    paren-less 'TFoo.Create' (a bare exprDot '.Create'). }
  function IsConstructorAssignment(const N: TTSNode): Boolean;
  var Rhs, Dot, Dr: TTSNode;
  begin
    Result:= False;
    if N.IsNull or (N.NodeType <> 'assignment') then Exit;
    Rhs:= N.ChildByField('rhs');
    if Rhs.IsNull then Exit;
    if Rhs.NodeType = 'exprCall' then Dot:= Rhs.ChildByField('entity')
    else Dot:= Rhs;
    if Dot.IsNull or (Dot.NodeType <> 'exprDot') then Exit;
    Dr:= Dot.ChildByField('rhs');
    Result:= (not Dr.IsNull) and (Dr.NodeType = 'identifier') and SameText(Trim(NodeStr(Dr)), 'Create');
  end;

  { PASS 2: Walk looking for defProc (unused-parameter) and ifElse
    (identical-then-else). }
  procedure Visit(const N: TTSNode);
  var
    I       : Integer;
    ThenNode: TTSNode;
    ElseNode: TTSNode;
    ThenTxt : string ;
    ElseTxt : string ;
  begin
    if N.IsNull then Exit;

    if N.NodeType = 'defProc' then
    begin
      CheckUnusedParams(N);
      CheckBooleanFlagParam(N);
      for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
      Exit;
    end;

    if N.NodeType = 'ifElse' then
    begin
      ThenNode:= N.ChildByField('then');
      ElseNode:= N.ChildByField('else');
      if (not ThenNode.IsNull) and (not ElseNode.IsNull) then
      begin
        ThenTxt:= NormaliseText(NodeStr(ThenNode));
        ElseTxt:= NormaliseText(NodeStr(ElseNode));
        if (ThenTxt <> '') and (ElseTxt <> '') and (ThenTxt = ElseTxt) then
          EmitAt(N, 'identical-then-else',
            'Both branches of this if-statement are identical');
      end;
    end;

    { redundant-parentheses: an exprParens is redundant (cosmetic) when its sole
      wrapped expression either is itself an exprParens -- '((X))' -- or is a
      lone atomic term (identifier / integer literal; NamedChildCount = 0), e.g.
      '(X)' or '(1)'. Parens around a composite expression (exprBinary, exprCall,
      exprDot, ...) are NOT flagged: they may aid readability or precedence.
      Conservative by design -> near-zero false positives. }
    if N.NodeType = 'exprParens' then
    begin
      { Skip constant/variable initializer + array/record constructor contexts:
        there '(x)' is a REQUIRED single-element constructor (e.g. a typed
        const 'array[0..0] of string = (''x'')'), not a redundant expression
        paren -- and the two cannot be told apart without type analysis. }
      var PrntN: TTSNode:= N.Parent;
      var PT   : string := '';
      if not PrntN.IsNull then PT:= PrntN.NodeType;
      if (PT <> 'defaultValue') and (PT <> 'arrInitializer') and
         (PT <> 'recInitializer') and (PT <> 'recInitializerField') and
         (PT <> 'declConst') and (PT <> 'constInline') and
         (N.NamedChildCount >= 1) then
      begin
        var Inner: TTSNode:= N.NamedChild(0);
        if Inner.NodeType = 'exprParens' then
          EmitAt(N, 'redundant-parentheses', 'Redundant nested parentheses', 'hint')
        else if Inner.NamedChildCount = 0 then
          EmitAt(N, 'redundant-parentheses',
            'Redundant parentheses around a single term', 'hint');
      end;
    end;

    { commented-out-code: a comment token whose stripped inner text looks like
      Delphi code -- it contains an assignment operator (prose almost never
      does) or is an anchored call statement. Compiler directives and doc
      comments are skipped. Severity 'hint'; conservative -> near-zero FP. }
    if N.NodeType = 'comment' then
    begin
      var Raw: string:= Trim(NodeStr(N));
      if not (Raw.StartsWith('///') or Raw.StartsWith('{$') or Raw.StartsWith('(*$')) then
      begin
        var Inner: string:= StripComment(Raw);
        if (Inner <> '') and (LooksLikeAssignment(Inner) or LooksLikeCallStatement(Inner)) then
          EmitAt(N, 'commented-out-code',
            'Commented-out code -- remove it or restore it', 'hint');
      end;
    end;

    { magic-literal (Fowler "Replace Magic Literal", #14): a numeric literal
      ('literalNumber') used in an expression that is not a named constant.
      Numbers only -- string literals are excluded (too noisy). Off by default
      (medium-FP, opt-in). Exempt:
        - the values 0, 1, -1, 2 (common sentinels/increments, rarely "magic");
          '-1' is a single literalNumber token here (the grammar folds the sign
          into the literal, verified via dumptree -- NOT a unary-minus wrapper);
        - the literal IS the constant: parent 'defaultValue' covers a const/
          resourcestring initializer (declConst), an enum-value assignment
          (declEnumValue), AND a default parameter value (declArg) -- all three
          share the same 'defaultValue: (kEq) <value>' wrapper in this grammar;
        - a case label: parent 'caseLabel';
        - an array/set range bound (e.g. 'array[0..9]'): parent 'range';
        - a typed-const/const-array initializer element: parent 'arrInitializer',
          'recInitializer', or 'recInitializerField' (mirrors the exempt set
          redundant-parentheses already uses for the same constructor contexts). }
    if N.NodeType = 'literalNumber' then
    begin
      var LitTxt: string:= Trim(NodeStr(N));
      if (LitTxt <> '0') and (LitTxt <> '1') and (LitTxt <> '-1') and (LitTxt <> '2') then
      begin
        var LitPrnt: TTSNode:= N.Parent;
        var LitPT  : string := '';
        if not LitPrnt.IsNull then LitPT:= LitPrnt.NodeType;
        if (LitPT <> 'defaultValue') and (LitPT <> 'caseLabel') and (LitPT <> 'range')
           and (LitPT <> 'arrInitializer') and (LitPT <> 'recInitializer') and (LitPT <> 'recInitializerField') then
          EmitAt(N, 'magic-literal',
            'Unexplained numeric literal -- extract a named constant', 'hint');
      end;
    end;

    { loop-control-flag (Fowler "Replace Control Flag with Break", #14): a
      while/repeat loop whose CONDITION references an identifier that is
      assigned a bare True/False literal somewhere inside the loop BODY --
      the classic "flag variable drives the exit" pattern that a 'Break'
      would express more directly. OFF by default (heuristic, FP-prone --
      any counter/state var that happens to be reassigned a boolean inside
      the loop and also appear in the condition trips it; kept conservative
      by requiring a BARE literal True/False rhs, never a computed boolean).
      Grammar (verified via dumptree): while/repeat both expose 'condition'
      and 'body' fields; 'while X' wraps the guard directly (e.g. exprUnary
      'not Found'), 'repeat' places 'body' BEFORE 'condition' in source order
      but the field names are the same. A True/False literal is a bare
      'kTrue'/'kFalse' token node (verified elsewhere in this codebase, e.g.
      the X.Active := True/False check) -- not a sub-expression, so a computed
      boolean rhs ('Found := (I >= N)') is never mistaken for the sentinel
      pattern. }
    if (N.NodeType = 'while') or (N.NodeType = 'repeat') then
    begin
      var LcfCond: TTSNode:= N.ChildByField('condition');
      var LcfBody: TTSNode:= N.ChildByField('body');
      if (not LcfCond.IsNull) and (not LcfBody.IsNull) then
      begin
        var LcfFlagName: string:= '';
        var LcfCondNames: TList<string>:= TList<string>.Create;
        try
          LcfCollectIdents(LcfCond, LcfCondNames);
          for var LcfName in LcfCondNames do
          begin
            if LcfBodyAssignsFlag(LcfBody, LcfName) then
            begin
              LcfFlagName:= LcfName;
              Break;
            end;
          end;
        finally
          LcfCondNames.Free;
        end;

        if LcfFlagName <> '' then
          EmitAt(N, 'loop-control-flag',
            Format('Loop exit driven by a boolean flag "%s" -- consider Break', [LcfFlagName]), 'hint');
      end;
    end;

    { function-result-ignored: a bare-statement call whose return value is
      discarded. Bare-statement = the exprCall's parent is a 'statement' node
      (not an assignment rhs / expression / argument). Only UNqualified
      identifier callees resolved against LocalFunctions (same-unit functions)
      are flagged -- keeps it store-free and near-zero FP on callee identity. }
    if N.NodeType = 'exprCall' then
    begin
      var Prnt: TTSNode:= N.Parent;
      if (not Prnt.IsNull) and (Prnt.NodeType = 'statement') then
      begin
        var Ent: TTSNode:= N.ChildByField('entity');
        if (not Ent.IsNull) and (Ent.NodeType = 'identifier') then
        begin
          var CName: string:= LowerCase(Trim(NodeStr(Ent)));
          if (CName <> '') and LocalFunctions.ContainsKey(CName) then
            EmitAt(N, 'function-result-ignored',
              Format('Result of function "%s" is ignored', [Trim(NodeStr(Ent))]), 'hint');
        end
        { exception-constructed-but-not-raised: a bare-statement 'EFoo.Create(...)'
          (entity = exprDot '.Create' on an exception-looking class) with no
          'raise'. A raise wraps the call in its 'exception' field, so its parent
          would be 'raise', not 'statement' -> a statement-parent construction is
          an unraised exception (a common forgotten-raise bug). }
        else if (not Ent.IsNull) and (Ent.NodeType = 'exprDot') then
        begin
          var Rhs: TTSNode:= Ent.ChildByField('rhs');
          var Lhs: TTSNode:= Ent.ChildByField('lhs');
          if (not Rhs.IsNull) and (Rhs.NodeType = 'identifier') and SameText(Trim(NodeStr(Rhs)), 'Create')
             and (not Lhs.IsNull) and (Lhs.NodeType = 'identifier') and LooksLikeExceptionClass(NodeStr(Lhs)) then
            EmitAt(N, 'exception-constructed-but-not-raised',
              Format('%s.Create(...) is constructed as a statement but never raised -- did you mean ''raise %s.Create(...)''?',
                [Trim(NodeStr(Lhs)), Trim(NodeStr(Lhs))]), 'warning');
        end;
      end;
    end;

    { destructor-without-override (#5): a class-declaration destructor with no
      virtual-family directive hides the inherited (virtual) destructor and leaks.
      declProc only (the declaration -- where 'override' belongs); a 'class
      destructor' is exempt (it has no inherited to override). }
    if N.NodeType = 'declProc' then
    begin
      { The class-declaration destructor has a simple identifier name ('Destroy');
        an IMPLEMENTATION signature (a defProc's header is also a declProc) has a
        qualified 'genericDot' name ('TFoo.Destroy') and never carries 'override'
        -- exclude it so we flag only the declaration where 'override' belongs. }
      var NameN: TTSNode:= N.ChildByField('name');
      if (not NameN.IsNull) and (NameN.NodeType = 'identifier')
         and SubtreeHasNodeType(N, 'kDestructor') and not SubtreeHasNodeType(N, 'kClass')
         and not HasVirtOverrideAttr(N) then
        EmitAt(N, 'destructor-without-override',
          'Destructor is not declared ''override'' -- it hides the inherited destructor (objects leak). Add ''override''.');
    end;

    { case-with-too-few-branches (#6): a case with fewer than AMinCaseBranches arms
      reads better as an if. Counts 'caseCase' children only (the 'else' part is
      not a caseCase). }
    if N.NodeType = 'case' then
    begin
      var Arms: Integer:= 0;
      for I:= 0 to N.NamedChildCount - 1 do
        if N.NamedChild(I).NodeType = 'caseCase' then Inc(Arms);
      if (Arms >= 1) and (Arms < AMinCaseBranches) then
        EmitAt(N, 'case-with-too-few-branches',
          Format('case has only %d branch(es) -- an if statement is clearer', [Arms]), 'hint');
    end;

    { boolean-expression-complexity (#6): a boolean expression (and/or/xor) with
      more than AMaxBoolOps operators is hard to read. Flag once at the TOP of a
      boolean-operator chain (parent is not itself a boolean exprBinary) so a long
      chain is reported a single time. }
    if N.NodeType = 'exprBinary' then
    begin
      var Op: TTSNode:= N.ChildByField('operator');
      if (not Op.IsNull) and ((Op.NodeType = 'kAnd') or (Op.NodeType = 'kOr') or (Op.NodeType = 'kXor')) then
      begin
        var Par: TTSNode:= N.Parent;
        var ParIsBool: Boolean:= False;
        if (not Par.IsNull) and (Par.NodeType = 'exprBinary') then
        begin
          var POp: TTSNode:= Par.ChildByField('operator');
          ParIsBool:= (not POp.IsNull) and ((POp.NodeType = 'kAnd') or (POp.NodeType = 'kOr') or (POp.NodeType = 'kXor'));
        end;
        if not ParIsBool then
        begin
          var Cnt: Integer:= CountBoolOps(N);
          if Cnt > AMaxBoolOps then
            EmitAt(N, 'boolean-expression-complexity',
              Format('Boolean expression has %d and/or/xor operators (limit %d) -- extract named boolean sub-expressions', [Cnt, AMaxBoolOps]), 'info');
        end;
      end;
    end;

    { duplicate-exception-handler (#7): two 'on <Class>' clauses for the same class
      in one try's except -- the second is unreachable. }
    if N.NodeType = 'try' then
    begin
      var SeenH: TStringList:= TStringList.Create;
      try
        SeenH.CaseSensitive:= False;
        FlagDupHandlers(N, SeenH, True);
      finally
        SeenH.Free;
      end;
      { create-inside-try (#5): a try..finally whose FIRST protected statement is
        'X := TFoo.Create(...)'. If Create raises, X is undefined and the finally's
        X.Free crashes -- construct BEFORE the try. Only when the try has a finally
        and the first real statement is a constructor assignment. }
      var HasFin: Boolean:= False;
      for var Fi:= 0 to N.ChildCount - 1 do
        if N.Child(Fi).NodeType = 'kFinally' then begin HasFin:= True; Break; end;
      if HasFin then
        for var Pi:= 0 to N.NamedChildCount - 1 do
        begin
          var Pc: TTSNode:= N.NamedChild(Pi);
          var Pt: string := Pc.NodeType;
          if Pt = 'kFinally' then Break;
          if (Length(Pt) > 0) and (Pt[1] = 'k') then Continue; { skip kTry etc. }
          { first real protected statement }
          if IsConstructorAssignment(UnwrapStmt(Pc)) then
            EmitAt(UnwrapStmt(Pc), 'create-inside-try',
              'Object is constructed as the first statement INSIDE its try..finally -- if the constructor raises, the finally frees an undefined reference. Construct it before the try.');
          Break;
        end;
    end;

    { weak-random-for-security (#10): a security-named variable assigned from
      System.Random/RandomRange -- not cryptographically secure. }
    if N.NodeType = 'assignment' then
    begin
      var Lhs: TTSNode:= N.ChildByField('lhs');
      if (not Lhs.IsNull) and (Lhs.NodeType = 'identifier') and IsSecurityName(NodeStr(Lhs)) then
      begin
        var Rhs: TTSNode:= N.ChildByField('rhs');
        if (not Rhs.IsNull) and SubtreeCallsRandom(Rhs) then
          EmitAt(N, 'weak-random-for-security',
            Format('"%s" is generated with System.Random -- not cryptographically secure. Use a CSPRNG (e.g. TRandomGenerator / OS crypto) for security tokens, keys, or salts.', [Trim(NodeStr(Lhs))]));
      end;
    end;

    { repeated-else-if-condition (#8): the same condition text appears twice in one
      if / else-if chain -- the later branch is unreachable. Walk the chain from its
      TOP (an ifElse that is not itself the else-slot of another if/ifElse) via the
      'else' field, collecting NormaliseText(condition). }
    if N.NodeType = 'ifElse' then
    begin
      var Par: TTSNode:= N.Parent;
      var IsCont: Boolean:= False;
      if (not Par.IsNull) and ((Par.NodeType = 'if') or (Par.NodeType = 'ifElse')) then
      begin
        var PElse: TTSNode:= Par.ChildByField('else');
        IsCont:= (not PElse.IsNull) and (Integer(PElse.StartByte) = Integer(N.StartByte));
      end;
      if not IsCont then
      begin
        var SeenC: TStringList:= TStringList.Create;
        try
          SeenC.CaseSensitive:= False;
          var Cur: TTSNode:= N;
          while (not Cur.IsNull) and ((Cur.NodeType = 'if') or (Cur.NodeType = 'ifElse')) do
          begin
            var Cond: TTSNode:= Cur.ChildByField('condition');
            if not Cond.IsNull then
            begin
              var CT: string:= NormaliseText(NodeStr(Cond));
              if CT <> '' then
              begin
                if SeenC.IndexOf(CT) >= 0 then
                  EmitAt(Cond, 'repeated-else-if-condition',
                    'This else-if repeats an earlier condition in the chain -- the branch is unreachable')
                else
                  SeenC.Add(CT);
              end;
            end;
            var Els: TTSNode:= Cur.ChildByField('else');
            if (not Els.IsNull) and ((Els.NodeType = 'if') or (Els.NodeType = 'ifElse')) then
              Cur:= Els
            else
              Break;
          end;
        finally
          SeenC.Free;
        end;
      end;
    end;

    { property-references-itself (#8): a property whose read/write accessor is the
      property itself -> infinite recursion. Count identifiers in the declProp that
      match the property name, excluding the name node + the type subtree. }
    if N.NodeType = 'declProp' then
    begin
      var PName: TTSNode:= N.ChildByField('name');
      if (not PName.IsNull) and (PName.NodeType = 'identifier') then
      begin
        var PTxt: string:= Trim(NodeStr(PName));
        var PType: TTSNode:= N.ChildByField('type');
        if (PTxt <> '') and (IdentSelfRefCount(N, PTxt, Integer(PName.StartByte), PType) >= 1) then
          EmitAt(PName, 'property-references-itself',
            Format('Property "%s" is read/written through itself -- this recurses forever. Use the backing field or an accessor method.', [PTxt]));
      end;
    end;

    { insecure-temp-file (#10): a file read/write API called with a hardcoded temp
      path string literal. Conservative -- fires only when the callee is a known
      file API, so a temp path used elsewhere (logging, a message) stays quiet. }
    if N.NodeType = 'exprCall' then
    begin
      var Ent: TTSNode:= N.ChildByField('entity');
      if (not Ent.IsNull) and IsFileApiCallee(Trim(NodeStr(Ent))) then
        EmitTempPathLiteral(N);
    end;

    { message-chain (#14, Fowler "Hide Delegate"): a member-access chain
      'a.b.c.d...' in value-expression context longer than AMaxChainHops hops.
      Only 'exprDot' nodes count (a left-nested lhs/rhs chain); qualified type/
      unit names use distinct node types ('typerefDot', 'moduleName') so they
      never reach here -- no separate exemption needed. Flag once, at the
      outermost link of the chain, so a long chain gets exactly one finding. }
    if (N.NodeType = 'exprDot') and IsTopOfChain(N) then
    begin
      var Hops: Integer:= CountChainHops(N);
      if Hops > AMaxChainHops then
        EmitAt(N, 'message-chain',
          Format('Message chain of %d members -- consider Hide Delegate', [Hops]), 'hint');
    end;

    { multiple-statements-per-line (#2): two or more sibling statements (direct
      named children of the same block/try) that start on the same source line.
      Off by default (pure style). Comparing SIBLINGS means a single-line
      'if..then X' or 'for..do X' is ONE child and never trips it; only genuine
      'a := 1; b := 2;' packing fires. Container-agnostic: works whether the block
      inlines statements directly or wraps them in a 'statement' node. }
    begin
      var PrevRow: Integer:= -1;
      var LastFlagged: Integer:= -1;   { one finding per line, not one per extra statement }
      for I:= 0 to N.NamedChildCount - 1 do
      begin
        var Stmt: TTSNode:= N.NamedChild(I);
        if Stmt.IsNull or (not IsStatementNodeType(Stmt.NodeType)) then Continue;
        var Row: Integer:= Integer(Stmt.StartPoint.Row);
        if (PrevRow >= 0) and (Row = PrevRow) and (Row <> LastFlagged) then
        begin
          EmitAt(Stmt, 'multiple-statements-per-line',
            'More than one statement on this line -- put each statement on its own line for readability and cleaner diffs.');
          LastFlagged:= Row;
        end;
        PrevRow:= Row;
      end;
    end;

    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end;

  { ------------------------------------------------------------------ }
  { referenced-never-set: whole-class single-unit field def-use pass.  }
  { ------------------------------------------------------------------ }

  { A field record: name (lowercased), declaration node (for EmitAt). }
  type
    TFieldInfo = record
      NameLower: string  ;
      DeclNode : TTSNode ;
    end;

  { Returns True when ASectionNode (a declSection) is a private or strict-
    private section. We check for a kPrivate named child; a kStrict child
    may or may not accompany it. }
  function SectionIsPrivate(const ASectionNode: TTSNode): Boolean;
  var
    I : Integer;
    Ch: TTSNode;
  begin
    Result:= False;
    for I:= 0 to ASectionNode.NamedChildCount - 1 do
    begin
      Ch:= ASectionNode.NamedChild(I);
      if Ch.NodeType = 'kPrivate' then
      begin
        Result:= True;
        Exit;
      end;
    end;
  end;

  { Returns True when ASectionNode (a declSection) is an EXPLICIT public
    section -- carries a kPublic named child. Mirrors SectionIsPrivate. Note
    this deliberately does NOT match the implicit/default section (members
    listed directly under declClass before any visibility keyword, which the
    symbol-store walker treats as 'public' for UML purposes) -- those are the
    published-DFM-component-dump shape and must NOT be flagged here; only an
    explicit 'public' keyword counts (public-writable-field, #14). }
  function SectionIsPublic(const ASectionNode: TTSNode): Boolean;
  var
    I : Integer;
    Ch: TTSNode;
  begin
    Result:= False;
    for I:= 0 to ASectionNode.NamedChildCount - 1 do
    begin
      Ch:= ASectionNode.NamedChild(I);
      if Ch.NodeType = 'kPublic' then
      begin
        Result:= True;
        Exit;
      end;
    end;
  end;

  { Returns True when the class whose declClass node is AClassNode should be
    excluded from the referenced-never-set check because it descends from a
    form / frame / component base (DFM/RTTI streaming writes fields invisibly).
    Detection: check the first typeref named child of AClassNode (the direct
    ancestor). Excluded when:
      - ancestor name ends with 'form' or 'frame' (case-insensitive)
      - ancestor name equals 'tcomponent' or 'tdatamodule' (case-insensitive)
      - ancestor name equals 'tcustomform' (case-insensitive) }
  function ClassIsFormLike(const AClassNode: TTSNode): Boolean;
  var
    I       : Integer;
    RefNode : TTSNode;
    AncName : string ;
    AncLow  : string ;
    AncLen  : Integer;
  begin
    Result:= False;
    for I:= 0 to AClassNode.NamedChildCount - 1 do
    begin
      RefNode:= AClassNode.NamedChild(I);
      if RefNode.NodeType <> 'typeref' then Continue;
      AncName:= Trim(NodeStr(RefNode));
      AncLow := LowerCase(AncName);
      AncLen := Length(AncLow);
      { Check name endings and exact names. }
      if (AncLen >= 4) and (Copy(AncLow, AncLen - 3, 4) = 'form') then begin Result:= True; Exit; end;
      if (AncLen >= 5) and (Copy(AncLow, AncLen - 4, 5) = 'frame') then begin Result:= True; Exit; end;
      if AncLow = 'tcomponent'  then begin Result:= True; Exit; end;
      if AncLow = 'tdatamodule' then begin Result:= True; Exit; end;
      { Only check the first typeref (the direct parent). }
      Break;
    end;
  end;

  { Collect private/strict-private fields from AClassNode (a declClass node).
    Fields must be inside an explicit private declSection (SectionIsPrivate).
    Fields directly under the class with no declSection parent are implicit-
    published (DFM dump) and are skipped. }
  procedure CollectPrivateFields(const AClassNode: TTSNode;
    AFields: TList<TFieldInfo>);
  var
    I     : Integer;
    SecN  : TTSNode;
    J     : Integer;
    FieldN: TTSNode;
    NameN : TTSNode;
    FInfo : TFieldInfo;
    FName : string    ;
  begin
    for I:= 0 to AClassNode.NamedChildCount - 1 do
    begin
      SecN:= AClassNode.NamedChild(I);
      if SecN.NodeType <> 'declSection' then Continue;
      if not SectionIsPrivate(SecN) then Continue;
      { Walk children of this private section. }
      for J:= 0 to SecN.NamedChildCount - 1 do
      begin
        FieldN:= SecN.NamedChild(J);
        if FieldN.NodeType <> 'declField' then Continue;
        NameN:= FieldN.ChildByField('name');
        if NameN.IsNull then Continue;
        FName:= Trim(NodeStr(NameN));
        if FName = '' then Continue;
        FInfo.NameLower:= LowerCase(FName);
        FInfo.DeclNode := NameN;
        AFields.Add(FInfo);
      end;
    end;
  end;

  { True when AClassNode (a declClass node) is a record shape (carries a
    kRecord token child) rather than a class (kClass). Local copy of the same
    check in DRagLint.Parser.Delphi13.ClassNodeIsRecord (not exported from
    that unit); used to exclude records from public-writable-field -- records
    legitimately expose fields, only classes get the "wrap it in a property"
    smell. }
  function IsRecordClassNode(const AClassNode: TTSNode): Boolean;
  var
    I: Integer;
    C: TTSNode;
    T: string ;
  begin
    Result:= False;
    for I:= 0 to AClassNode.ChildCount - 1 do
    begin
      C:= AClassNode.Child(I);
      T:= C.NodeType;
      if T = 'kClass'  then Exit(False);
      if T = 'kRecord' then Exit(True );
    end;
  end;

  { public-writable-field (#14, Fowler "Encapsulate Variable"): a field
    declared under an EXPLICIT 'public' visibility section of a class (not a
    record -- records legitimately expose fields; not 'published' -- those are
    auto-generated DFM components; not the implicit/default section -- that is
    the published-DFM-component-dump shape). Walk every declClass reachable
    from AClassNode's declSection children and emit one finding per field. }
  procedure EmitPublicFieldsInClass(const AClassNode: TTSNode);
  var
    I     : Integer;
    SecN  : TTSNode;
    J     : Integer;
    FieldN: TTSNode;
    NameN : TTSNode;
    FName : string    ;
  begin
    for I:= 0 to AClassNode.NamedChildCount - 1 do
    begin
      SecN:= AClassNode.NamedChild(I);
      if SecN.NodeType <> 'declSection' then Continue;
      if not SectionIsPublic(SecN) then Continue;
      for J:= 0 to SecN.NamedChildCount - 1 do
      begin
        FieldN:= SecN.NamedChild(J);
        if FieldN.NodeType <> 'declField' then Continue;
        NameN:= FieldN.ChildByField('name');
        if NameN.IsNull then Continue;
        FName:= Trim(NodeStr(NameN));
        if FName = '' then Continue;
        EmitAt(NameN, 'public-writable-field',
          Format('Public field "%s" -- expose it through a property instead', [FName]),
          'info');
      end;
    end;
  end;

  { Walk every declType in the unit (including nested types), and for each
    declClass that is NOT a record, flag its explicit-public fields. Mirrors
    the CollectClasses walk shape but drives EmitPublicFieldsInClass directly
    instead of accumulating a list -- this rule has no cross-reference pass. }
  procedure CheckPublicWritableFields(const ARoot: TTSNode);
  var
    I      : Integer;
    J      : Integer;
    NameN  : TTSNode;
    TypeWN : TTSNode;
    ClassN : TTSNode;
  begin
    if ARoot.IsNull then Exit;
    if ARoot.NodeType = 'declType' then
    begin
      NameN := ARoot.ChildByField('name');
      TypeWN:= ARoot.ChildByField('type');
      if (not NameN.IsNull) and (not TypeWN.IsNull) then
      begin
        ClassN:= Default(TTSNode);
        if TypeWN.NodeType = 'declClass' then ClassN:= TypeWN
        else
        begin
          for J:= 0 to TypeWN.NamedChildCount - 1 do
            if TypeWN.NamedChild(J).NodeType = 'declClass' then
            begin
              ClassN:= TypeWN.NamedChild(J);
              Break;
            end;
        end;
        if (not ClassN.IsNull) and (not IsRecordClassNode(ClassN)) then
          EmitPublicFieldsInClass(ClassN);
      end;
      { Recurse into nested type declarations. }
      for I:= 0 to ARoot.NamedChildCount - 1 do
        CheckPublicWritableFields(ARoot.NamedChild(I));
      Exit;
    end;
    for I:= 0 to ARoot.NamedChildCount - 1 do
      CheckPublicWritableFields(ARoot.NamedChild(I));
  end;

  { Find the leftmost base identifier in an LHS expression (handles
    FField, FField.Sub, FField[i], FField.Sub[j] etc.).
    Returns the lowercased name or '' when no identifier found. }
  function LhsBaseIdent(const ALhsNode: TTSNode): string;
  var
    Cur: TTSNode;
    Nxt: TTSNode;
    I  : Integer;
  begin
    Result:= '';
    Cur:= ALhsNode;
    if Cur.IsNull then Exit;
    { Peel qualified/indexed access to the leftmost identifier.
      Grammar: exprDot has lhs/rhs fields; exprIndex/exprCall may have entity/lhs.
      We walk the leftmost child repeatedly until we hit an identifier. }
    repeat
      if Cur.NodeType = 'identifier' then
      begin
        Result:= LowerCase(Trim(NodeStr(Cur)));
        Exit;
      end;
      { Try standard field names first. }
      Nxt:= Cur.ChildByField('lhs');
      if Nxt.IsNull then Nxt:= Cur.ChildByField('entity');
      if Nxt.IsNull then
      begin
        { Fall back: first named child. }
        if Cur.NamedChildCount > 0 then Nxt:= Cur.NamedChild(0)
        else Exit;
      end;
      Cur:= Nxt;
    until Cur.IsNull;
  end;

  { Walk a method body subtree and classify each field reference as a read or
    write. Updates AReads and AWrites maps (field-name-lower -> count).
    AInArgPos=True while walking actual call arguments (conservative: any field
    in an arg position is counted as a possible write). }
  procedure ClassifyRefs(const ANode: TTSNode;
    AFields: TDictionary<string, Boolean>;
    AReads, AWrites: TDictionary<string, Integer>;
    AInArgPos: Boolean);
  var
    I       : Integer;
    LhsNode : TTSNode;
    K       : string ;
    BaseName: string ;
    Cnt     : Integer;
    ArgsNode: TTSNode;
    ArgNode : TTSNode;
    Ident   : string ;
  begin
    if ANode.IsNull then Exit;
    K:= ANode.NodeType;

    { assignment node: the lhs base identifier is a WRITE. }
    if K = 'assignment' then
    begin
      LhsNode:= ANode.ChildByField('lhs');
      if not LhsNode.IsNull then
      begin
        BaseName:= LhsBaseIdent(LhsNode);
        if (BaseName <> '') and AFields.ContainsKey(BaseName) then
        begin
          if AWrites.TryGetValue(BaseName, Cnt) then AWrites[BaseName]:= Cnt + 1
          else AWrites.Add(BaseName, 1);
        end;
        { Still walk the rhs for reads, but also walk non-base parts of lhs
          (e.g. index expressions like FField[FIndex] := x -- FIndex is a read). }
      end;
      { Walk all children (rhs, complex lhs parts) as reads. }
      for I:= 0 to ANode.NamedChildCount - 1 do
        ClassifyRefs(ANode.NamedChild(I), AFields, AReads, AWrites, AInArgPos);
      Exit;
    end;

    { Call expression: arguments are passed potentially as var/out. Treat all
      field identifiers that appear as direct argument expressions as writes
      (conservative -- avoids FP when callee modifies through a var param). }
    if K = 'exprCall' then
    begin
      ArgsNode:= ANode.ChildByField('args');
      if not ArgsNode.IsNull then
      begin
        for I:= 0 to ArgsNode.NamedChildCount - 1 do
        begin
          ArgNode:= ArgsNode.NamedChild(I);
          { Walk the argument itself with AInArgPos=True. }
          ClassifyRefs(ArgNode, AFields, AReads, AWrites, True);
        end;
      end;
      { Walk entity (the callee expression) as normal read context. }
      ClassifyRefs(ANode.ChildByField('entity'), AFields, AReads, AWrites, False);
      Exit;
    end;

    { Plain identifier: read if not already handled as an lhs base. }
    if K = 'identifier' then
    begin
      Ident:= LowerCase(Trim(NodeStr(ANode)));
      if (Ident <> '') and AFields.ContainsKey(Ident) then
      begin
        if AInArgPos then
        begin
          { In argument position -> conservative write. }
          if AWrites.TryGetValue(Ident, Cnt) then AWrites[Ident]:= Cnt + 1
          else AWrites.Add(Ident, 1);
        end
        else
        begin
          { Regular read. }
          if AReads.TryGetValue(Ident, Cnt) then AReads[Ident]:= Cnt + 1
          else AReads.Add(Ident, 1);
        end;
      end;
      Exit;
    end;

    { Default: recurse into all named children. }
    for I:= 0 to ANode.NamedChildCount - 1 do
      ClassifyRefs(ANode.NamedChild(I), AFields, AReads, AWrites, AInArgPos);
  end;

  { Per-class info collected during the class-collection pass. }
  type
    TClassInfo = record
      NameLower: string         ;
      Fields   : TList<TFieldInfo>;
    end;

  { Collect all classes from the unit interface section. Returns a list of
    TClassInfo records (caller owns the lists inside). Skips form-like classes
    and classes with no qualifying private fields. }
  procedure CollectClasses(const ARoot: TTSNode;
    AClasses: TList<TClassInfo>);
  var
    I       : Integer;
    J       : Integer;
    N       : TTSNode;
    DeclT   : TTSNode;
    NameN   : TTSNode;
    TypeWN  : TTSNode;
    ClassN  : TTSNode;
    ClassName: string;
    Fields  : TList<TFieldInfo>;
    CI      : TClassInfo;
  begin
    if ARoot.IsNull then Exit;
    { Walk the entire tree to find all declType nodes. }
    if ARoot.NodeType = 'declType' then
    begin
      NameN:= ARoot.ChildByField('name');
      TypeWN:= ARoot.ChildByField('type');
      if (not NameN.IsNull) and (not TypeWN.IsNull) then
      begin
        { The type wrapper may be a declClass directly, or contain one as a
          named child (for parameterised / wrapped forms). }
        ClassN:= Default(TTSNode);
        if TypeWN.NodeType = 'declClass' then ClassN:= TypeWN
        else
        begin
          for J:= 0 to TypeWN.NamedChildCount - 1 do
            if TypeWN.NamedChild(J).NodeType = 'declClass' then
            begin
              ClassN:= TypeWN.NamedChild(J);
              Break;
            end;
        end;
        if not ClassN.IsNull then
        begin
          if not ClassIsFormLike(ClassN) then
          begin
            ClassName:= LowerCase(Trim(NodeStr(NameN)));
            if ClassName <> '' then
            begin
              Fields:= TList<TFieldInfo>.Create;
              try
                CollectPrivateFields(ClassN, Fields);
                if Fields.Count > 0 then
                begin
                  CI.NameLower:= ClassName;
                  CI.Fields   := Fields;
                  AClasses.Add(CI);
                  Fields:= nil; { ownership transferred to AClasses -- do not free }
                end;
              finally
                if Assigned(Fields) then Fields.Free;
              end;
            end;
          end;
        end;
      end;
      { Recurse into nested type declarations. }
      for I:= 0 to ARoot.NamedChildCount - 1 do
        CollectClasses(ARoot.NamedChild(I), AClasses);
      Exit;
    end;
    for I:= 0 to ARoot.NamedChildCount - 1 do
      CollectClasses(ARoot.NamedChild(I), AClasses);
  end;

  { Walk all defProc nodes and accumulate reads/writes for each known class. }
  procedure ProcessDefProcs(const ARoot: TTSNode;
    AClassMap: TDictionary<string, Integer>;
    AClassList: TList<TClassInfo>;
    AReadMaps, AWriteMaps: TArray<TDictionary<string, Integer>>;
    AFieldMaps: TArray<TDictionary<string, Boolean>>);
  var
    I       : Integer;
    N       : TTSNode;
    HdrNode : TTSNode;
    NameN   : TTSNode;
    FullName: string ;
    DotPos  : Integer;
    ClsName : string ;
    ClsIdx  : Integer;
  begin
    if ARoot.IsNull then Exit;
    if ARoot.NodeType = 'defProc' then
    begin
      HdrNode:= ARoot.ChildByField('header');
      if not HdrNode.IsNull then
      begin
        NameN:= HdrNode.ChildByField('name');
        if not NameN.IsNull then
        begin
          FullName:= LowerCase(Trim(NodeStr(NameN)));
          DotPos:= LastDelimiter('.', FullName);
          if DotPos > 0 then
          begin
            ClsName:= Copy(FullName, 1, DotPos - 1);
            if AClassMap.TryGetValue(ClsName, ClsIdx) then
            begin
              { Walk the entire defProc body to classify field refs. }
              var BodyN: TTSNode:= ARoot.ChildByField('body');
              ClassifyRefs(BodyN, AFieldMaps[ClsIdx],
                AReadMaps[ClsIdx], AWriteMaps[ClsIdx], False);
            end;
          end;
        end;
      end;
      { Recurse into nested defProcs (local procedures). }
      for I:= 0 to ARoot.NamedChildCount - 1 do
        ProcessDefProcs(ARoot.NamedChild(I), AClassMap, AClassList,
          AReadMaps, AWriteMaps, AFieldMaps);
      Exit;
    end;
    for I:= 0 to ARoot.NamedChildCount - 1 do
      ProcessDefProcs(ARoot.NamedChild(I), AClassMap, AClassList,
        AReadMaps, AWriteMaps, AFieldMaps);
  end;

  { Main referenced-never-set check. }
  procedure CheckReferencedNeverSet;
  var
    Classes   : TList<TClassInfo>                      ;
    ClassMap  : TDictionary<string, Integer>           ;
    FieldMaps : TArray<TDictionary<string, Boolean>>   ;
    ReadMaps  : TArray<TDictionary<string, Integer>>   ;
    WriteMaps : TArray<TDictionary<string, Integer>>   ;
    I, J      : Integer                                ;
    CI        : TClassInfo                             ;
    FI        : TFieldInfo                             ;
    ReadCnt   : Integer                                ;
    WriteCnt  : Integer                                ;
  begin
    Classes:= TList<TClassInfo>.Create;
    try
      CollectClasses(PF.Tree.RootNode, Classes);
      if Classes.Count = 0 then Exit;

      { Build class name -> index map and per-class field/read/write maps. }
      ClassMap:= TDictionary<string, Integer>.Create;
      SetLength(FieldMaps, Classes.Count);
      SetLength(ReadMaps,  Classes.Count);
      SetLength(WriteMaps, Classes.Count);
      try
        for I:= 0 to Classes.Count - 1 do
        begin
          CI:= Classes[I];
          ClassMap.AddOrSetValue(CI.NameLower, I);
          FieldMaps[I]:= TDictionary<string, Boolean>.Create;
          ReadMaps[I] := TDictionary<string, Integer>.Create;
          WriteMaps[I]:= TDictionary<string, Integer>.Create;
          for J:= 0 to CI.Fields.Count - 1 do
            FieldMaps[I].AddOrSetValue(CI.Fields[J].NameLower, True);
        end;

        { Walk all defProc nodes, classify refs for each class. }
        ProcessDefProcs(PF.Tree.RootNode, ClassMap, Classes,
          ReadMaps, WriteMaps, FieldMaps);

        { Emit findings for fields with >= 1 read and 0 writes. }
        for I:= 0 to Classes.Count - 1 do
        begin
          CI:= Classes[I];
          for J:= 0 to CI.Fields.Count - 1 do
          begin
            FI:= CI.Fields[J];
            ReadCnt := 0; ReadMaps[I].TryGetValue(FI.NameLower, ReadCnt);
            WriteCnt:= 0; WriteMaps[I].TryGetValue(FI.NameLower, WriteCnt);
            if (ReadCnt > 0) and (WriteCnt = 0) then
              EmitAt(FI.DeclNode, 'referenced-never-set',
                Format('Field "%s" is read but never written -- it always holds its zero value',
                  [Trim(NodeStr(FI.DeclNode))]));
          end;
        end;
      finally
        ClassMap.Free;
        for I:= 0 to Classes.Count - 1 do
        begin
          if Assigned(FieldMaps[I]) then FieldMaps[I].Free;
          if Assigned(ReadMaps[I])  then ReadMaps[I].Free;
          if Assigned(WriteMaps[I]) then WriteMaps[I].Free;
        end;
      end;
    finally
      for I:= 0 to Classes.Count - 1 do
        Classes[I].Fields.Free;
      Classes.Free;
    end;
  end;

var
  Seen   : TDictionary<string, Boolean>;
  Raw    : TArray<TLintFinding>        ;
  Deduped: TList<TLintFinding>         ;
  LF     : TLintFinding                ;
  Key    : string                      ;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  ContractMethods:= TDictionary<string, Boolean>.Create;
  LocalFunctions := TDictionary<string, Boolean>.Create;
  try
    { v0.74: unit-too-large (#6) -- one info finding when the unit exceeds
      AMaxUnitLines source lines (root node's last row). }
    if (AMaxUnitLines > 0) and (PF.Tree <> nil) then
    begin
      var ULines: Integer:= Integer(PF.Tree.RootNode.EndPoint.Row) + 1;
      if ULines > AMaxUnitLines then
      begin
        var UF: TLintFinding:= Default(TLintFinding);
        UF.RuleId  := 'unit-too-large';
        UF.Severity:= 'info';
        UF.Message := Format('Unit is %d lines (limit %d) -- consider splitting it into smaller units', [ULines, AMaxUnitLines]);
        UF.FilePath:= AFile;
        UF.StartLine:= 1; UF.StartCol:= 1; UF.EndLine:= 1; UF.EndCol:= 1;
        Findings.Add(UF);
      end;
    end;
    { Pass 1: collect all declProc names with contract-binding directives. }
    CollectContractDecls(PF.Tree.RootNode);
    { Pass 1b: collect same-unit function names for function-result-ignored. }
    CollectLocalFunctions(PF.Tree.RootNode);
    { Pass 2: walk defProc bodies, ifElse, exprParens, comments, exprCall. }
    Visit(PF.Tree.RootNode);
    { Pass 3: referenced-never-set field def-use. }
    CheckReferencedNeverSet;
    { Pass 4: public-writable-field (#14, Fowler "Encapsulate Variable"). }
    CheckPublicWritableFields(PF.Tree.RootNode);
    Raw:= Findings.ToArray;
  finally
    Findings.Free;
    ContractMethods.Free;
    LocalFunctions.Free;
  end;
  { De-duplicate by (RuleId, StartLine, StartCol). }
  Seen:= TDictionary<string, Boolean>.Create;
  Deduped:= TList<TLintFinding>.Create;
  try
    for LF in Raw do
    begin
      Key:= LF.RuleId + ':' + IntToStr(LF.StartLine) + ':' + IntToStr(LF.StartCol);
      if not Seen.ContainsKey(Key) then
      begin
        Seen.Add(Key, True);
        Deduped.Add(LF);
      end;
    end;
    Result:= Deduped.ToArray;
  finally
    Deduped.Free;
    Seen.Free;
  end;
end;

end.
