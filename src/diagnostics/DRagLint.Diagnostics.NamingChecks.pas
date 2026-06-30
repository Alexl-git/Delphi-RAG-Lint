unit DRagLint.Diagnostics.NamingChecks;

{ v0.68 -- naming-convention rules driven by TNamingConfig.
  Rules implemented here:
    type-name-prefix      : class/interface/pointer type name must carry the
                            configured prefix.
    field-name-prefix     : class instance field name must carry the configured
                            prefix.
    param-name-prefix     : routine parameter name must carry the configured
                            prefix.
    method-pascalcase     : routine/method name must match MethodCase.
    const-casing          : constant name must match one of ConstCase.
    local-var-casing      : local variable name must match LocalCase.
    unit-name-matches-file: unit name must equal the file base name
                            (case-insensitive). }

interface

uses
  System.SysUtils
  , System.StrUtils
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
    /// Prefix matching is case-SENSITIVE (so a 'PName' param fails the lowercase
    /// 'p' ParamPrefix and is flagged). The field-name-prefix guard is
    /// section-aware: a T-typed field is skipped ONLY in the implicit-first
    /// section (the auto-generated published DFM component dump, whose fields
    /// sit directly under declClass); a T-typed field in an EXPLICIT
    /// private/protected/public/published section still must carry the F prefix.
    /// local-var-casing fires only for variables declared inside a defProc body
    /// (not unit-level var sections or class fields).
    /// unit-name-matches-file fires when the unit name differs from the file
    /// base name (case-insensitive); program/library roots are skipped.</remarks>
    class function Check(const AFile: string; const ANaming: TNamingConfig;
      const AStore: ISymbolStore = nil; AFileId: Int64 = 0): TArray<TLintFinding>;
  end;

implementation

{ Returns True when AName carries APrefix (matched case-SENSITIVELY) followed
  by an uppercase letter. An empty APrefix always returns False (disables the
  check for that prefix). The prefix match must be exact case so that the
  lowercase ParamPrefix 'p' is not satisfied by a capital-P name: a param named
  'PName' must FAIL HasPrefix(.,'p') and therefore be flagged.
  Examples: HasPrefix('TFoo','T')=True; HasPrefix('Tfoo','T')=False;
  HasPrefix('Things','T')=False; HasPrefix('T','T')=False;
  HasPrefix('pName','p')=True; HasPrefix('PName','p')=False.
  NOTE: used ONLY for the param-name-prefix check and the local-var-casing
  field/param-carry smell (where a strict next-char-uppercase guard is
  intentional). type-name-prefix and field-name-prefix use StartsWithPrefix
  (relaxed -- accepts Tfrm, FfID). }
function HasPrefix(const AName, APrefix: string): Boolean;
var
  PLen: Integer;
begin
  Result:= False;
  PLen:= Length(APrefix);
  if PLen = 0 then Exit;
  if Length(AName) <= PLen then Exit;
  { Case-SENSITIVE prefix comparison (not SameText) -- see remark above. }
  if Copy(AName, 1, PLen) <> APrefix then Exit;
  { char immediately after the prefix must be A..Z (uppercase) to avoid
    matching e.g. 'Things' against prefix 'T'. }
  Result:= CharInSet(AName[PLen + 1], ['A'..'Z']);
end;

{ Returns True when AName starts with APrefix (case-SENSITIVE, exact match)
  and has at least one more character after the prefix. Unlike HasPrefix, the
  character after the prefix does NOT need to be uppercase -- so TfrmMain and
  FfID are accepted as carrying their respective prefixes. An empty APrefix
  always returns False (disables the check for that prefix).
  Used for type-name-prefix (class/pointer) and field-name-prefix checks so
  that common form-class and field naming conventions (Tfrm..., FfID...) do
  not produce false positives.
  Examples: StartsWithPrefix('TfrmMain','T')=True;
  StartsWithPrefix('TFoo','T')=True; StartsWithPrefix('T','T')=False;
  StartsWithPrefix('Widget','T')=False. }
function StartsWithPrefix(const AName, APrefix: string): Boolean;
var
  PLen: Integer;
begin
  Result:= False;
  PLen:= Length(APrefix);
  if PLen = 0 then Exit;
  if Length(AName) <= PLen then Exit;
  Result:= Copy(AName, 1, PLen) = APrefix;
end;

{ Returns True when S is a short all-uppercase abbreviation (e.g. GLE, BS, OK,
  FF, ID) that should be exempt from PascalCase / camelCase requirements.
  Criteria: length 1..4, every character is A..Z or 0..9, and at least one
  character is A..Z (rules out pure-digit tokens). No underscores allowed.
  Used to suppress method-pascalcase and local-var-casing false positives on
  common Delphi short-caps names.
  Examples: IsShortAllCaps('GLE')=True; IsShortAllCaps('BS')=True;
  IsShortAllCaps('OK')=True; IsShortAllCaps('FF')=True;
  IsShortAllCaps('ABCDE')=False (>4 chars); IsShortAllCaps('Foo')=False. }
function IsShortAllCaps(const S: string): Boolean;
var
  I      : Integer;
  HasLet : Boolean;
begin
  Result:= False;
  if (Length(S) = 0) or (Length(S) > 4) then Exit;
  HasLet:= False;
  for I:= 1 to Length(S) do
  begin
    if CharInSet(S[I], ['A'..'Z']) then HasLet:= True
    else if not CharInSet(S[I], ['0'..'9']) then Exit; { lowercase or underscore -> False }
  end;
  Result:= HasLet;
end;

{ Returns True when S looks like PascalCase:
  - first char is A..Z
  - no underscore characters
  - not all-uppercase-and-digits (i.e. not UPPER_SNAKE_CASE).
  An empty string returns False. }
function IsPascalCase(const S: string): Boolean;
var
  I       : Integer;
  HasLower: Boolean;
begin
  Result:= False;
  if S = '' then Exit;
  if not CharInSet(S[1], ['A'..'Z']) then Exit;
  { reject names with underscores }
  for I:= 1 to Length(S) do
    if S[I] = '_' then Exit;
  { require at least one lowercase letter (distinguishes PascalCase from
    UPPER_CASE names like 'OK' or 'ID'); single-letter uppercase names like
    'P' are accepted (short local/counter names). }
  HasLower:= False;
  for I:= 1 to Length(S) do
    if CharInSet(S[I], ['a'..'z']) then begin HasLower:= True; Break; end;
  { single-char uppercase identifiers (P, I, J, ...) are PascalCase-compliant }
  Result:= HasLower or (Length(S) = 1);
end;

{ Returns True when S looks like UPPER_SNAKE_CASE:
  - only chars A..Z, 0..9, '_'
  - at least one letter present. }
function IsUpperSnake(const S: string): Boolean;
var
  I      : Integer;
  HasLet : Boolean;
begin
  Result:= False;
  if S = '' then Exit;
  HasLet:= False;
  for I:= 1 to Length(S) do
  begin
    if CharInSet(S[I], ['A'..'Z']) then HasLet:= True
    else if not CharInSet(S[I], ['0'..'9', '_']) then Exit;
  end;
  Result:= HasLet;
end;

{ Returns True when S looks like camelCase:
  - first char is a..z
  - no underscores. }
function IsCamelCase(const S: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if S = '' then Exit;
  if not CharInSet(S[1], ['a'..'z']) then Exit;
  for I:= 1 to Length(S) do
    if S[I] = '_' then Exit;
  Result:= True;
end;

{ Dispatches on ACase to the appropriate casing predicate.
  Supported values: 'PascalCase', 'UPPER_CASE', 'camelCase'.
  Returns True (no finding) for any unknown ACase value. }
function MatchesCase(const S, ACase: string): Boolean;
begin
  if ACase = 'PascalCase' then Result:= IsPascalCase(S)
  else if ACase = 'UPPER_CASE' then Result:= IsUpperSnake(S)
  else if ACase = 'camelCase' then Result:= IsCamelCase(S)
  else Result:= True; { unknown case style: skip }
end;

{ Returns True when S matches ANY of the casing styles in ACases.
  Returns True (no finding) when ACases is empty. }
function MatchesAnyCase(const S: string; const ACases: TArray<string>): Boolean;
var
  C: string;
begin
  Result:= True;
  if Length(ACases) = 0 then Exit;
  for C in ACases do
    if MatchesCase(S, C) then Exit;
  Result:= False;
end;

class function TNamingChecker.Check(const AFile: string; const ANaming: TNamingConfig;
  const AStore: ISymbolStore; AFileId: Int64): TArray<TLintFinding>;
var
  Src       : TBytes             ;
  PF        : TParsedFile        ;
  Findings  : TList<TLintFinding>;
  { Section state for field-name-prefix: True while the walker is inside an
    EXPLICIT visibility section (private/protected/public/published/strict).
    A declField reached while this is False is in the implicit-first section
    (the auto-generated DFM published component dump) and gets the T-typed skip;
    a declField reached while this is True must carry the F prefix regardless
    of type. Saved/restored around each declSection recursion. }
  InExplicitSection: Boolean;
  { Body state for local-var-casing: True while the walker is inside a defProc
    body (implementation block). Saved/restored on defProc entry. Local var
    sections inside a defProc are the ones we check; unit-level var sections
    reached while this is False are skipped. }
  InProcBody: Boolean;
  { Class-body state: True while the walker is inside a declClass body.
    Used to distinguish class-member declProc nodes (where section visibility
    matters for method-pascalcase) from unit-level routines (always checked).
    Saved/restored on declClass entry. }
  InClassBody: Boolean;
  { Method-case skip flag: True when method-pascalcase should be suppressed
    for declProc nodes in the current scope. Set True when entering a declClass
    body (implicit-first assumption for direct members) and updated by each
    declSection: True for published or implicit-first sections, False for
    private/protected/public sections. Saved/restored around each declSection
    and declClass recursion. Form event handlers (btnOkClick etc.) declared in
    the published or implicit-first section are IDE-generated / DFM-wired and
    must not be renamed, so they are exempt from the PascalCase requirement. }
  CurSectionSkipsMethodCase: Boolean;

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

  { True when ASection (a declSection) carries an explicit visibility keyword.
    Mirrors the keyword check in DRagLint.Parser.Delphi13.VisibilityOfSection
    (replicated here because that function is implementation-only). A section
    with no kPrivate/kProtected/kPublic/kPublished/kStrict named child is the
    implicit-first section (its members are auto-generated published fields). }
  function SectionIsExplicit(const ASection: TTSNode): Boolean;
  var
    K : Integer;
    Ch: TTSNode;
    NT: string ;
  begin
    Result:= False;
    for K:= 0 to ASection.NamedChildCount - 1 do
    begin
      Ch:= ASection.NamedChild(K);
      NT:= Ch.NodeType;
      if (NT = 'kPrivate') or (NT = 'kProtected') or (NT = 'kPublic')
        or (NT = 'kPublished') or (NT = 'kStrict') then
      begin
        Result:= True;
        Exit;
      end;
    end;
  end;

  { True when ASection (a declSection) has the explicit 'published' keyword.
    Used together with SectionIsExplicit to determine whether a section is
    the published visibility section (as opposed to private/protected/public).
    Form event-handler declarations live in published sections and are IDE-
    generated / DFM-wired -- skipped for method-pascalcase. }
  function SectionIsPublished(const ASection: TTSNode): Boolean;
  var
    K : Integer;
    Ch: TTSNode;
  begin
    Result:= False;
    for K:= 0 to ASection.NamedChildCount - 1 do
    begin
      Ch:= ASection.NamedChild(K);
      if Ch.NodeType = 'kPublished' then begin Result:= True; Exit; end;
    end;
  end;

  { Find the first named child of AParent whose NodeType = AType. }
  function FindChildOfType(const AParent: TTSNode; const AType: string): TTSNode;
  var
    K: Integer;
  begin
    Result:= Default(TTSNode);
    for K:= 0 to AParent.NamedChildCount - 1 do
      if AParent.NamedChild(K).NodeType = AType then
        Exit(AParent.NamedChild(K));
  end;

  { Walk the entire AST once; emit findings for each rule whose prefix is set. }
  procedure Visit(const N: TTSNode);
  var
    I        : Integer;
    NameNode : TTSNode;
    TypeNode : TTSNode;
    HdrNode  : TTSNode;
    ArgsNode : TTSNode;
    ArgNode  : TTSNode;
    NameId   : TTSNode;
    TypeStart: Integer;
    TypeName : string ;
    ArgName  : string ;
    J        : Integer;
    IsExcClass: Boolean;
    VarTypeStart: Integer;
    VarNameId: TTSNode;
  begin
    if N.IsNull then Exit;

    { unit-name-matches-file: check the unit declaration name vs the file base.
      Only 'unit' roots are checked; 'program' and 'library' are skipped.
      The moduleName named child holds the full unit name (e.g. Foo.Bar). We
      compare case-insensitively against ChangeFileExt(ExtractFileName(AFile),''). }
    if N.NodeType = 'unit' then
    begin
      var ModNode: TTSNode:= FindChildOfType(N, 'moduleName');
      if not ModNode.IsNull then
      begin
        var UnitName: string:= Trim(NodeStr(ModNode));
        var FileBase: string:= ChangeFileExt(ExtractFileName(AFile), '');
        if (UnitName <> '') and (not SameText(UnitName, FileBase)) then
          EmitAt(ModNode, 'unit-name-matches-file',
            Format('Unit name "%s" does not match file name "%s"',
              [UnitName, FileBase]));
      end;
      { Still recurse so inner declarations are checked by other rules. }
      for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
      Exit;
    end;

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

            { StartsWithPrefix is used (not HasPrefix) so that form-style names
              such as TfrmAssignGroups pass the T-prefix check. The relaxed guard
              still rejects bare-prefix names (e.g. just 'T') and names with no
              prefix at all (e.g. 'Widget'). }
            if IsExcClass then
            begin
              if (ANaming.ExceptionPrefix <> '') and (not StartsWithPrefix(TypeName, ANaming.ExceptionPrefix)) then
                EmitAt(NameNode, 'type-name-prefix',
                  Format('Exception class "%s" should start with the "%s" prefix',
                    [TypeName, ANaming.ExceptionPrefix]));
            end
            else
            begin
              if (ANaming.ClassPrefix <> '') and (not StartsWithPrefix(TypeName, ANaming.ClassPrefix)) then
                EmitAt(NameNode, 'type-name-prefix',
                  Format('Class "%s" should start with the "%s" prefix',
                    [TypeName, ANaming.ClassPrefix]));
            end;
          end
          else if TypeNode.NodeType = 'declIntf' then
          begin
            if (ANaming.InterfacePrefix <> '') and (not StartsWithPrefix(TypeName, ANaming.InterfacePrefix)) then
              EmitAt(NameNode, 'type-name-prefix',
                Format('Interface "%s" should start with the "%s" prefix',
                  [TypeName, ANaming.InterfacePrefix]));
          end
          else if TypeNodeIsPointer(TypeNode) then
          begin
            if (ANaming.PointerPrefix <> '') and (not StartsWithPrefix(TypeName, ANaming.PointerPrefix)) then
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

    { declClass: entering a class body. Reset section context for the two
      orthogonal tracking flags:
      - InExplicitSection stays False for direct (implicit-first) members and
        is updated per declSection (unchanged semantics for field-name-prefix).
      - CurSectionSkipsMethodCase is set True here so that any declProc
        encountered directly under the class body (without an enclosing
        declSection) is treated as the implicit-first section and is exempt
        from method-pascalcase. Each nested declSection will override it.
      Save/restore both flags and InClassBody around recursion. }
    if N.NodeType = 'declClass' then
    begin
      var SavedInClass    : Boolean:= InClassBody;
      var SavedSkipMeth   : Boolean:= CurSectionSkipsMethodCase;
      var SavedExplicit   : Boolean:= InExplicitSection;
      InClassBody               := True;
      CurSectionSkipsMethodCase := True; { implicit-first until a section is entered }
      InExplicitSection         := False;
      for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
      InClassBody               := SavedInClass;
      CurSectionSkipsMethodCase := SavedSkipMeth;
      InExplicitSection         := SavedExplicit;
      Exit;
    end;

    { declSection: an explicit visibility section sets InExplicitSection=True
      for the duration of its subtree so the field guard below knows the
      enclosed fields are NOT implicit-first members. A keyword-less declSection
      (rare) is treated as implicit (False). Also updates CurSectionSkipsMethodCase:
      True for published or implicit-first sections (exempt from method-pascalcase);
      False for private/protected/public (still checked). Save/restore around
      recursion. }
    if N.NodeType = 'declSection' then
    begin
      var SavedSection : Boolean:= InExplicitSection;
      var SavedSkipMeth: Boolean:= CurSectionSkipsMethodCase;
      InExplicitSection         := SectionIsExplicit(N);
      CurSectionSkipsMethodCase := (not InExplicitSection) or SectionIsPublished(N);
      for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
      InExplicitSection         := SavedSection;
      CurSectionSkipsMethodCase := SavedSkipMeth;
      Exit;
    end;

    { field-name-prefix: visit declField nodes inside class bodies.
      Section-aware guard: the T-typed component-field skip applies ONLY in the
      implicit-first section (InExplicitSection=False). Verified AST shape:
      implicit-first fields (e.g. `Button1: TButton;` on a form) sit as DIRECT
      children of declClass with no enclosing declSection, so InExplicitSection
      is False there and the T-typed skip suppresses the auto-generated DFM
      component dump. Fields inside an EXPLICIT private/protected/public/
      published section (InExplicitSection=True) must carry the F prefix
      regardless of their declared type -- a private `Grid: TStringList`
      missing F is a real violation and fires. }
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
            { Component-field skip: only honoured in the implicit-first section.
              In an explicit section a T-typed field still must carry F. }
            var IsComponentField: Boolean:= False;
            if not InExplicitSection then
            begin
              var FieldType: string:= '';
              if not TypeNode.IsNull then FieldType:= Trim(NodeStr(TypeNode));
              IsComponentField:= (Length(FieldType) >= 2)
                and (FieldType[1] = 'T') and CharInSet(FieldType[2], ['A'..'Z']);
            end;
            if not IsComponentField then
            begin
              if not StartsWithPrefix(TypeName, ANaming.FieldPrefix) then
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

    { method-pascalcase: on declProc nodes check that the routine name matches
      ANaming.MethodCase. Also fires on defProc header names so both the forward
      declaration and implementation bodies are checked (de-dup handles doubles
      from the same name/line). Operator overloads (name starting with 'operator'
      case-insensitively) are skipped.
      param-name-prefix: visit both declProc (forward/interface declarations)
      and defProc (implementations). Each physical header is checked independently.
      NOTE: declProc has 'args' as a direct field; defProc has 'args' nested
      under 'header'. Both patterns are handled below. }
    if N.NodeType = 'declProc' then
    begin
      NameNode:= N.ChildByField('name');
      { method-pascalcase: skip when the section is published or implicit-first
        (DFM event handlers are IDE-generated / DFM-wired and not renamable).
        Also skip short all-caps abbreviations (FF, OK, BS, etc.). }
      if (not NameNode.IsNull) and (ANaming.MethodCase <> '')
        and (not CurSectionSkipsMethodCase) then
      begin
        var MethName: string:= Trim(NodeStr(NameNode));
        if (MethName <> '') and (not StartsText('operator', MethName)) then
        begin
          if (not MatchesCase(MethName, ANaming.MethodCase))
            and (not IsShortAllCaps(MethName)) then
            EmitAt(NameNode, 'method-pascalcase',
              Format('Method "%s" should be %s', [MethName, ANaming.MethodCase]));
        end;
      end;
      if ANaming.ParamPrefix <> '' then
      begin
        ArgsNode:= N.ChildByField('args');
        if not ArgsNode.IsNull then
        begin
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
              ArgName:= Trim(NodeStr(NameId));
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

    { defProc: the implementation body of a routine. Set InProcBody=True so
      local-var-casing fires for declVar children of this body. Also check the
      header name for method-pascalcase (catches implementation-only routines
      and complements the declProc check; de-dup handles any overlap).
      Also check params for param-name-prefix via the header node. }
    if N.NodeType = 'defProc' then
    begin
      HdrNode:= N.ChildByField('header');
      if not HdrNode.IsNull then
      begin
        { method-pascalcase on the defProc header name.
          For qualified names (TClass.Method) the corresponding declProc in the
          class body is the authoritative check -- the implementation body is
          supplementary for implementation-only (non-forward) unit routines only.
          Qualified defProc names are therefore skipped here: if the class method
          was published or implicit-first the declProc check already suppressed it;
          if it was private/public the declProc check already caught it.
          Skipping qualified names also avoids double-reporting for non-event
          class methods. Un-qualified names (unit-level routines with no forward
          declaration) are still checked. }
        NameNode:= HdrNode.ChildByField('name');
        if (not NameNode.IsNull) and (ANaming.MethodCase <> '') then
        begin
          var MethName: string:= Trim(NodeStr(NameNode));
          var DotPos: Integer:= LastDelimiter('.', MethName);
          { Skip qualified names (class method implementations -- handled by declProc). }
          if DotPos = 0 then
          begin
            var SimpleName: string:= MethName;
            { Skip short all-caps abbreviations (FF, OK, BS, etc.) to avoid FP. }
            if (SimpleName <> '') and (not StartsText('operator', SimpleName)) then
            begin
              if (not MatchesCase(SimpleName, ANaming.MethodCase))
                and (not IsShortAllCaps(SimpleName)) then
                EmitAt(NameNode, 'method-pascalcase',
                  Format('Method "%s" should be %s', [SimpleName, ANaming.MethodCase]));
            end;
          end;
        end;
        { param-name-prefix on the defProc args }
        if ANaming.ParamPrefix <> '' then
        begin
          ArgsNode:= HdrNode.ChildByField('args');
          if not ArgsNode.IsNull then
          begin
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
                ArgName:= Trim(NodeStr(NameId));
                if SameText(ArgName, 'Self') then Continue;
                if not HasPrefix(ArgName, ANaming.ParamPrefix) then
                  EmitAt(NameId, 'param-name-prefix',
                    Format('Parameter "%s" should start with the "%s" prefix',
                      [ArgName, ANaming.ParamPrefix]));
              end;
            end;
          end;
        end;
      end;
      { Enter proc body scope for local-var-casing. }
      var SavedInProcBody: Boolean:= InProcBody;
      InProcBody:= True;
      for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
      InProcBody:= SavedInProcBody;
      Exit;
    end;

    { const-casing: visit declConst nodes (covers unit-level, class, and
      resourcestring consts). Fire when the name does not match any of
      ANaming.ConstCase. Skipped when ConstCase is empty. }
    if N.NodeType = 'declConst' then
    begin
      if Length(ANaming.ConstCase) > 0 then
      begin
        NameNode:= N.ChildByField('name');
        if not NameNode.IsNull then
        begin
          var ConstName: string:= Trim(NodeStr(NameNode));
          if (ConstName <> '') and (not MatchesAnyCase(ConstName, ANaming.ConstCase)) then
            EmitAt(NameNode, 'const-casing',
              Format('Constant "%s" should be %s',
                [ConstName, String.Join(' or ', ANaming.ConstCase)]));
        end;
      end;
      for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
      Exit;
    end;

    { local-var-casing: visit declVar nodes ONLY when inside a defProc body
      (InProcBody=True). Unit-level var sections and class fields are skipped.
      Fire when the name does not match ANaming.LocalCase, OR when the name
      carries the FieldPrefix or ParamPrefix (a local named like a field/param
      is a naming-convention smell). Skipped when LocalCase=''. }
    if N.NodeType = 'declVar' then
    begin
      if InProcBody and (ANaming.LocalCase <> '') then
      begin
        TypeNode:= N.ChildByField('type');
        VarTypeStart:= MaxInt;
        if not TypeNode.IsNull then VarTypeStart:= Integer(TypeNode.StartByte);
        for I:= 0 to N.NamedChildCount - 1 do
        begin
          VarNameId:= N.NamedChild(I);
          if VarNameId.NodeType <> 'identifier' then Continue;
          if Integer(VarNameId.StartByte) >= VarTypeStart then Continue;
          var VarName: string:= Trim(NodeStr(VarNameId));
          if VarName = '' then Continue;
          { Fire when casing is wrong OR the name carries field/param prefix.
            Short all-caps abbreviations (GLE, BS, MS, etc.) are exempt from
            the casing check -- they are intentional initialisms, not casing
            violations. The field/param prefix-carry check still uses HasPrefix
            (strict: next-char must be uppercase) so that e.g. a local named
            'Form' is NOT flagged as carrying the 'F' prefix -- only 'FCount'
            (F + uppercase next char) would fire the carry check. }
          var CasingBad: Boolean:= (not MatchesCase(VarName, ANaming.LocalCase))
            and (not IsShortAllCaps(VarName));
          var HasFieldPfx: Boolean:= (ANaming.FieldPrefix <> '') and HasPrefix(VarName, ANaming.FieldPrefix);
          var HasParamPfx: Boolean:= (ANaming.ParamPrefix <> '') and HasPrefix(VarName, ANaming.ParamPrefix);
          if CasingBad or HasFieldPfx or HasParamPfx then
            EmitAt(VarNameId, 'local-var-casing',
              Format('Local variable "%s" should be %s and not carry a field/param prefix',
                [VarName, ANaming.LocalCase]));
        end;
      end;
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
  InExplicitSection         := False; { root and class-body level = implicit-first section }
  InProcBody                := False; { not inside a routine body at the root level }
  InClassBody               := False; { not inside a class body at the root level }
  CurSectionSkipsMethodCase := False; { root-level routines are always checked }
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
