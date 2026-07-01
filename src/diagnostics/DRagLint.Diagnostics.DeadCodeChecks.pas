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
                           are not flagged (conservative, near-zero FP). }

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
    /// referenced-never-set, and redundant-parentheses.
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
    class function Check(const AFile: string): TArray<TLintFinding>;
  end;

implementation

class function TDeadCodeChecker.Check(const AFile: string): TArray<TLintFinding>;
var
  Src            : TBytes                      ;
  PF             : TParsedFile                 ;
  Findings       : TList<TLintFinding>         ;
  { Pass-1 result: bare lower-cased method names that carry a contract-binding
    directive (virtual/dynamic/override/message/abstract) in their declProc.
    A defProc whose unqualified name matches an entry here is skipped. }
  ContractMethods: TDictionary<string, Boolean>;

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
      if N.NamedChildCount >= 1 then
      begin
        var Inner: TTSNode:= N.NamedChild(0);
        if Inner.NodeType = 'exprParens' then
          EmitAt(N, 'redundant-parentheses', 'Redundant nested parentheses', 'hint')
        else if Inner.NamedChildCount = 0 then
          EmitAt(N, 'redundant-parentheses',
            'Redundant parentheses around a single term', 'hint');
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
  try
    { Pass 1: collect all declProc names with contract-binding directives. }
    CollectContractDecls(PF.Tree.RootNode);
    { Pass 2: walk defProc bodies and ifElse nodes. }
    Visit(PF.Tree.RootNode);
    { Pass 3: referenced-never-set field def-use. }
    CheckReferencedNeverSet;
    Raw:= Findings.ToArray;
  finally
    Findings.Free;
    ContractMethods.Free;
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
