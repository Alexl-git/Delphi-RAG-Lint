unit DRagLint.Diagnostics.NamingChecks;

{ v0.68 -- naming-convention rules driven by TNamingConfig.
  Rules implemented here (Task 2 -- prefix rules):
    type-name-prefix  : class/interface/pointer type name must carry the configured prefix.
    field-name-prefix : class instance field name must carry the configured prefix.
    param-name-prefix : routine parameter name must carry the configured prefix.
  Task 3 will extend TNamingChecker.Check with the remaining 4 naming-rule ids
  (method-pascalcase, const-casing, unit-name-matches-file, local-var-casing). }

interface

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  , TreeSitter
  , TreeSitterLib
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Config-driven naming-convention checks (pure AST, no DB required for
  /// prefix rules). The store is optional and is used only for the exception-class
  /// sub-check of type-name-prefix.</summary>
  TNamingChecker = class
  public
    /// <summary>Runs the configured naming rules against a single .pas file and
    /// returns one TLintFinding per violation.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="ANaming">Naming config from TLintConfig.Naming; prefix fields
    /// set to '' disable that prefix rule.</param>
    /// <param name="AStore">Optional symbol store; when non-nil, enables the
    /// exception-ancestry sub-check for type-name-prefix.</param>
    /// <param name="AFileId">File id within AStore (ignored when AStore=nil).</param>
    /// <returns>Array of findings (all severity 'info'); empty when the file is
    /// clean or could not be parsed.</returns>
    /// <remarks>Thread-safe if the parse cache is thread-safe for the caller's
    /// use pattern; the checker itself has no shared mutable state.
    /// Task 3 extends this same function with 4 additional naming rule ids.</remarks>
    class function Check(const AFile: string; const ANaming: TNamingConfig;
      const AStore: ISymbolStore = nil; AFileId: Int64 = 0): TArray<TLintFinding>;
  end;

implementation

{ Returns True when AName carries APrefix followed by an uppercase letter.
  An empty APrefix always returns False (disables the check for that prefix).
  Examples: HasPrefix('TFoo','T')=True; HasPrefix('Tfoo','T')=False;
  HasPrefix('Things','T')=False; HasPrefix('T','T')=False. }
function HasPrefix(const AName, APrefix: string): Boolean;
var
  PLen: Integer;
begin
  Result:= False;
  PLen:= Length(APrefix);
  if PLen = 0 then Exit;
  if Length(AName) <= PLen then Exit;
  if not SameText(Copy(AName, 1, PLen), APrefix) then Exit;
  { char immediately after the prefix must be A..Z (uppercase) to avoid
    matching e.g. 'Things' against prefix 'T'. Case-sensitive check here. }
  Result:= CharInSet(AName[PLen + 1], ['A'..'Z']);
end;

class function TNamingChecker.Check(const AFile: string; const ANaming: TNamingConfig;
  const AStore: ISymbolStore; AFileId: Int64): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

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

  { Emit one finding pointing at the name identifier node. }
  procedure EmitAt(const ANameNode: TTSNode; const ARuleId, AMessage: string);
  var
    P: TTSPoint     ;
    F: TLintFinding ;
  begin
    P:= ANameNode.StartPoint;
    F:= Default(TLintFinding);
    F.RuleId   := ARuleId;
    F.Severity := 'info';
    F.Message  := AMessage;
    F.FilePath := AFile;
    F.StartLine:= Integer(P.Row   ) + 1;
    F.StartCol := Integer(P.Column) + 1;
    F.EndLine  := F.StartLine;
    F.EndCol   := F.StartCol + Length(Trim(NodeStr(ANameNode)));
    Findings.Add(F);
  end;

  { True when ATypeNode (the `type:` field child of a declType) is a pointer
    type declaration: a `declType` whose type child is a `typeref` prefixed
    with '^' (the tree-sitter grammar represents `^T` as a `typeptr` or similar).
    In practice the grammar wraps the caret as a `kCaret` or `typePointer` node;
    we check the raw text for a leading '^'. }
  function TypeNodeIsPointer(const ATypeNode: TTSNode): Boolean;
  var
    Raw: string;
  begin
    Result:= False;
    if ATypeNode.IsNull then Exit;
    Raw:= Trim(NodeStr(ATypeNode));
    Result:= (Length(Raw) > 0) and (Raw[1] = '^');
  end;

  { Walk the entire AST once; emit findings for each rule whose prefix is set. }
  procedure Visit(const N: TTSNode);
  var
    I         : Integer;
    NameNode  : TTSNode;
    TypeNode  : TTSNode;
    HdrNode   : TTSNode;
    ArgsNode  : TTSNode;
    ArgNode   : TTSNode;
    NameId    : TTSNode;
    TypeStart : Integer;
    TypeName  : string ;
    ArgName   : string ;
    J         : Integer;
    IsExcClass: Boolean;
  begin
    if N.IsNull then Exit;

    { type-name-prefix: visit declType nodes in interface/implementation sections.
      Grammar note: ChildByField('type') on a declType returns a wrapper node
      (the raw type expression). For classes, declClass is a *named child* of
      that wrapper (not the wrapper itself); for interfaces, the wrapper IS
      declIntf directly. We check both patterns below. }
    if N.NodeType = 'declType' then
    begin
      NameNode:= N.ChildByField('name');
      TypeNode:= N.ChildByField('type');
      if (not NameNode.IsNull) and (not TypeNode.IsNull) then
      begin
        TypeName:= Trim(NodeStr(NameNode));
        if TypeName <> '' then
        begin
          { Locate the inner class/interface node. For classes it is a named
            child of the type wrapper; for interfaces the wrapper IS declIntf. }
          var ClassBodyNode: TTSNode:= Default(TTSNode);
          for I:= 0 to TypeNode.NamedChildCount - 1 do
          begin
            var Ch: TTSNode:= TypeNode.NamedChild(I);
            if Ch.NodeType = 'declClass' then begin ClassBodyNode:= Ch; Break; end;
          end;
          if TypeNode.NodeType = 'declClass' then ClassBodyNode:= TypeNode;

          if not ClassBodyNode.IsNull then
          begin
            { Is this an exception class? Use store when available, else fall
              back to requiring the class prefix (conservative -- no guessing). }
            IsExcClass:= False;
            if (AStore <> nil) and (ANaming.ExceptionPrefix <> '') then
              IsExcClass:= AStore.IsDescendantOf(TypeName, 'Exception', AFileId);

            if IsExcClass then
            begin
              if (ANaming.ExceptionPrefix <> '') and (not HasPrefix(TypeName, ANaming.ExceptionPrefix)) then
                EmitAt(NameNode, 'type-name-prefix',
                  Format('Exception class "%s" should start with the "%s" prefix',
                    [TypeName, ANaming.ExceptionPrefix]));
            end
            else
            begin
              if (ANaming.ClassPrefix <> '') and (not HasPrefix(TypeName, ANaming.ClassPrefix)) then
                EmitAt(NameNode, 'type-name-prefix',
                  Format('Class "%s" should start with the "%s" prefix',
                    [TypeName, ANaming.ClassPrefix]));
            end;
          end
          else if TypeNode.NodeType = 'declIntf' then
          begin
            if (ANaming.InterfacePrefix <> '') and (not HasPrefix(TypeName, ANaming.InterfacePrefix)) then
              EmitAt(NameNode, 'type-name-prefix',
                Format('Interface "%s" should start with the "%s" prefix',
                  [TypeName, ANaming.InterfacePrefix]));
          end
          else if TypeNodeIsPointer(TypeNode) then
          begin
            if (ANaming.PointerPrefix <> '') and (not HasPrefix(TypeName, ANaming.PointerPrefix)) then
              EmitAt(NameNode, 'type-name-prefix',
                Format('Pointer type "%s" should start with the "%s" prefix',
                  [TypeName, ANaming.PointerPrefix]));
          end;
        end;
      end;
      { Still recurse for nested type declarations. }
      for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
      Exit;
    end;

    { field-name-prefix: visit declField nodes inside class bodies.
      Guard: skip fields in a published section whose declared type starts with
      'T' -- these are auto-generated DFM component fields (Name: TType) on
      form/frame classes. The heuristic is conservative (near-zero-FP): when a
      field looks like a published component reference, do not flag it.
      Implementation: we read the current section visibility from the parent
      declSection sibling walk; but since we visit only the declField here (not
      tracking parent state), we detect "published" by checking whether the
      declField's own type text begins with 'T'. This means truly private/public
      fields whose type starts with 'T' are also guarded -- accepted trade-off
      documented here as a known FP-suppression heuristic. }
    if N.NodeType = 'declField' then
    begin
      if ANaming.FieldPrefix <> '' then
      begin
        NameNode:= N.ChildByField('name');
        TypeNode:= N.ChildByField('type');
        if not NameNode.IsNull then
        begin
          TypeName:= Trim(NodeStr(NameNode));
          if TypeName <> '' then
          begin
            { Heuristic guard: if the field's declared type starts with 'T' it
              may be a VCL component reference in a published section -- skip. }
            var FieldType: string:= '';
            if not TypeNode.IsNull then FieldType:= Trim(NodeStr(TypeNode));
            var IsComponentField: Boolean:= (Length(FieldType) >= 2)
              and (FieldType[1] = 'T') and CharInSet(FieldType[2], ['A'..'Z']);
            if not IsComponentField then
            begin
              if not HasPrefix(TypeName, ANaming.FieldPrefix) then
                EmitAt(NameNode, 'field-name-prefix',
                  Format('Field "%s" should start with the "%s" prefix',
                    [TypeName, ANaming.FieldPrefix]));
            end;
          end;
        end;
      end;
      { Recurse into children (the type node may contain nested expressions). }
      for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
      Exit;
    end;

    { param-name-prefix: visit both declProc (forward/interface declarations)
      and defProc (implementations). Each physical header is checked independently.
      NOTE: declProc has 'args' as a direct field; defProc has 'args' nested
      under 'header'. Both patterns are handled below. }
    if (N.NodeType = 'declProc') or (N.NodeType = 'defProc') then
    begin
      if ANaming.ParamPrefix <> '' then
      begin
        { declProc (forward/interface decl) exposes 'args' as a direct field.
          defProc (implementation) nests 'args' under 'header'. Try header first
          so defProc is handled correctly; fall back to direct 'args' for declProc. }
        ArgsNode:= Default(TTSNode);
        HdrNode:= N.ChildByField('header');
        if not HdrNode.IsNull then
          ArgsNode:= HdrNode.ChildByField('args');
        if ArgsNode.IsNull then
          ArgsNode:= N.ChildByField('args');
        if not ArgsNode.IsNull then
        begin
          for I:= 0 to ArgsNode.NamedChildCount - 1 do
          begin
            ArgNode:= ArgsNode.NamedChild(I);
            if ArgNode.NodeType <> 'declArg' then Continue;
            { Get the type field position to identify name identifiers. }
            TypeNode:= ArgNode.ChildByField('type');
            TypeStart:= MaxInt;
            if not TypeNode.IsNull then TypeStart:= Integer(TypeNode.StartByte);
            { Iterate named children: identifier nodes before the type are param names. }
            for J:= 0 to ArgNode.NamedChildCount - 1 do
            begin
              NameId:= ArgNode.NamedChild(J);
              if NameId.NodeType <> 'identifier' then Continue;
              if Integer(NameId.StartByte) >= TypeStart then Continue;
              ArgName:= Trim(NodeStr(NameId));
              { Skip 'Self' parameter (Delphi implicit). }
              if SameText(ArgName, 'Self') then Continue;
              if not HasPrefix(ArgName, ANaming.ParamPrefix) then
                EmitAt(NameId, 'param-name-prefix',
                  Format('Parameter "%s" should start with the "%s" prefix',
                    [ArgName, ANaming.ParamPrefix]));
            end;
          end;
        end;
      end;
      { Recurse into the body/local sections (may contain nested routines). }
      for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
      Exit;
    end;

    { Default: recurse into all named children. }
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end; // procedure Visit

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
  try
    Visit(PF.Tree.RootNode);
    Raw:= Findings.ToArray;
  finally
    Findings.Free;
  end;
  { De-duplicate by (RuleId, StartLine, StartCol) -- a declProc that is also
    a named child of its defProc can otherwise cause double-emission. }
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
end; // function Check

end.
