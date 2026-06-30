unit DRagLint.Diagnostics.DeadCodeChecks;

{ v0.68 -- dead-code / redundant-code rules (pure AST, no DB required).
  Rules implemented here:
    unused-parameter   : a routine parameter never referenced in the body.
    identical-then-else: an if-else whose then and else branches are textually
                         identical (copy-paste bug). }

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
    /// <remarks>Rules implemented: unused-parameter and identical-then-else.
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
    /// Known limitation: interface-method implementations are not detected
    /// syntactically (requires a symbol store). If an interface method body slips
    /// through with an unused parameter it will be reported; this is an acceptable
    /// false-positive gap.
    /// identical-then-else emits one finding at the 'if' node when the then and
    /// else branches normalise to the same text. Plain 'if' nodes (no else) are
    /// not visited.
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

  { Emit one finding pointing at ANode with severity 'warning'. }
  procedure EmitAt(const ANode: TTSNode; const ARuleId, AMessage: string);
  var
    P: TTSPoint    ;
    F: TLintFinding;
  begin
    P:= ANode.StartPoint;
    F:= Default(TLintFinding);
    F.RuleId   := ARuleId;
    F.Severity := 'warning';
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

    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
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
