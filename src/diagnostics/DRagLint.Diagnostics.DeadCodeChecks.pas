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
                           cross-unit callees are not resolved. Severity 'hint'. }

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
      AMaxBoolOps: Integer = 4): TArray<TLintFinding>;
  end;

implementation

class function TDeadCodeChecker.Check(const AFile: string; AMinCaseBranches: Integer;
  AMaxBoolOps: Integer): TArray<TLintFinding>;
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
    { Pass 1: collect all declProc names with contract-binding directives. }
    CollectContractDecls(PF.Tree.RootNode);
    { Pass 1b: collect same-unit function names for function-result-ignored. }
    CollectLocalFunctions(PF.Tree.RootNode);
    { Pass 2: walk defProc bodies, ifElse, exprParens, comments, exprCall. }
    Visit(PF.Tree.RootNode);
    { Pass 3: referenced-never-set field def-use. }
    CheckReferencedNeverSet;
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
