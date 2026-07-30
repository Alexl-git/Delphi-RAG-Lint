unit DRagLint.Parser.Delphi13;

interface

uses
  System.SysUtils
  , System.StrUtils
  , System.Classes
  , System.Generics.Collections
  , TreeSitter
  , TreeSitterLib
  , DRagLint.Core  .Model
  , DRagLint.Core  .Interfaces
  , DRagLint.Parser.SpringDI
  ;

type
  TDelphi13Parser = class(TInterfacedObject, IParser)
    strict private
      FLanguage: PTSLanguage;
    public
      { v0.42: deep scan -> emit identifier usage refs (read/write/attribute).
      Set by the indexer from the --deep/--shallow flag before parsing. }
      EmitUsageRefs: Boolean;
      constructor Create;
      function LanguageName: string                                               ;
      function FileExtensions: TArray<string>                                     ;
      function Parse(const ASource: TBytes; const AFilePath: string): TParseResult;
  end;

function tree_sitter_delphi13: PTSLanguage; cdecl;
external 'tree-sitter-delphi13';

implementation

function NodeText(const ANode: TTSNode; const ASource: TBytes): string;
var
  StartIdx: Integer;
  EndIdx  : Integer;
  Len     : Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  StartIdx:= Integer(ANode.StartByte);
  EndIdx  := Integer(ANode.EndByte  );
  Len:= EndIdx - StartIdx;
  if (Len <= 0) or (StartIdx < 0) or (EndIdx > Length(ASource)) then Exit;
  Result:= TEncoding.UTF8.GetString(ASource, StartIdx, Len);
end;

function FindNamedChildOfType(const AParent: TTSNode; const AType: string): TTSNode;
var
  i    : Integer;
  Child: TTSNode;
begin
  // Default(TTSNode) is the null sentinel - ts_node_is_null() returns true
  // for a zero-filled record. Avoid AParent.Child(-1) which casts -1 to
  // UInt32 and trips ERangeError under {$R+}.
  Result:= Default(TTSNode);
  for i:= 0 to AParent.NamedChildCount - 1 do
  begin
    Child:= AParent.NamedChild(i);
    if Child.NodeType = AType then Exit(Child);
  end;
end;

type
  TWalkState = class
    Source     : TBytes              ;
    Symbols    : TList<TSymbol>      ;
    References : TList<TReference>   ;
    UsesEntries: TList<TUnitUse>     ; { v0.40.4 }
    DiBindings : TList<TDiBindingRow>; { v8: Spring4D DI registrations }
    { Current member visibility while walking a class/record body -- set by the
      declSection handler ('public'/'private'/'protected'/'published', with a
      'strict ' prefix when applicable) and stamped into each member's
      Modifiers.  Drives the UML visibility glyphs (+/-/#/~) in the graph. }
    CurrentVisibility: string;
    { 'interface' | 'implementation' | '' -- which unit section the current
      symbol lives in; stamped into TSymbol.Section by Emit (agent gap #3:
      tells whether a symbol is usable from another unit). }
    CurrentSection: string;
    { v0.42: when True (deep scan), emit read/write/attribute usage references
      for identifiers in expression position, so Find-Usages works for
      variables/components/properties -- not just calls. Off = today's
      call/type_use-only behaviour (shallow scan, e.g. libraries). }
    EmitUsageRefs: Boolean;
    { v0.48: nesting depth while walking routine bodies. 0 = top-level (unit /
      implementation section). Lets us emit a symbol only for TOP-LEVEL
      implementation-only free routines, never for nested local procedures. }
    RoutineDepth: Integer;
    constructor Create(const ASource: TBytes);
    destructor Destroy; override;
    function Emit(
      AKind: TSymbolKind; const AName, AQualifiedName: string; AParentSymbolIdx: Integer; const ARangeNode: TTSNode; const ASignature: string = ''; const AModifiers: string = '';
      const AHeritage: string = ''; AIsVirtual: Boolean = False; AIsHelper: Boolean = False; const APropAccess: string = ''
    ): Integer;
    procedure EmitRef(const AKind, ANameText: string; const ARangeNode: TTSNode);
    procedure EmitUnitUse(const AUnitName, AInPath: string; ASection: TUnitUseSection; const ARangeNode: TTSNode);
  end;

constructor TWalkState.Create(const ASource: TBytes);
begin
  inherited Create;
  Source:= ASource;
  Symbols    := TList<TSymbol      >.Create;
  References := TList<TReference   >.Create;
  UsesEntries:= TList<TUnitUse     >.Create;
  DiBindings := TList<TDiBindingRow>.Create;
end;

destructor TWalkState.Destroy;
begin
  Symbols.Free;
  References.Free;
  UsesEntries.Free;
  DiBindings.Free;
  inherited;
end;

procedure TWalkState.EmitUnitUse(const AUnitName, AInPath: string; ASection: TUnitUseSection; const ARangeNode: TTSNode);
var
  U     : TUnitUse;
  Stem  : string  ;
  DotPos: Integer ;
begin
  if AUnitName = '' then Exit;
  U.FileId:= -1; { indexer will fill in from files table }
  U.UnitName:= AUnitName;
  U.Section := ASection;
  U.InPath  := AInPath;
  U.StartLine:= Integer(ARangeNode.StartPoint.row   ) + 1;
  U.StartCol := Integer(ARangeNode.StartPoint.column) + 1;
  U.EndLine  := Integer(ARangeNode.EndPoint  .row   ) + 1;
  U.EndCol   := Integer(ARangeNode.EndPoint  .column) + 1;
  UsesEntries.Add(U);
  { Suppress hint: Stem reserved for a future normalize-here path. }
  Stem:= AUnitName;
  DotPos:= LastDelimiter('.', Stem);
  if DotPos > 0 then Stem:= Copy(Stem, DotPos + 1, MaxInt);
end; // procedure

procedure TWalkState.EmitRef(const AKind, ANameText: string; const ARangeNode: TTSNode);
var
  Ref: TReference;
begin
  if ARangeNode.IsNull or (ANameText = '') then Exit;
  Ref:= Default(TReference);
  Ref.Kind    := AKind;
  Ref.NameText:= ANameText;
  Ref.SymbolId:= 0; // unresolved at parse time
  Ref.StartLine:= Integer(ARangeNode.StartPoint.row   ) + 1;
  Ref.StartCol := Integer(ARangeNode.StartPoint.column) + 1;
  Ref.EndLine  := Integer(ARangeNode.EndPoint  .row   ) + 1;
  Ref.EndCol   := Integer(ARangeNode.EndPoint  .column) + 1;
  References.Add(Ref);
end;

function TWalkState.Emit(AKind: TSymbolKind; const AName, AQualifiedName: string; AParentSymbolIdx: Integer; const ARangeNode: TTSNode; const ASignature,
  AModifiers, AHeritage: string; AIsVirtual: Boolean; AIsHelper: Boolean; const APropAccess: string): Integer;
var
  Sym: TSymbol;
begin
  Sym:= Default(TSymbol);
  Sym.Kind         := AKind;
  Sym.Name         := AName;
  Sym.QualifiedName:= AQualifiedName;
  Sym.Signature    := ASignature;
  Sym.Modifiers    := AModifiers;
  Sym.Section      := CurrentSection;
  Sym.PropAccess   := APropAccess; { v17 (Task 6/R1): ro/rw/wo for a property; '' otherwise }
  Sym.Heritage     := AHeritage; { v11 (M1): class/interface ancestor list text; v15: helper target when IsHelper }
  Sym.IsVirtual    := AIsVirtual; { v12 (M1): method virtual dispatch flag }
  Sym.IsHelper     := AIsHelper;  { v15: record/class helper declaration flag }
  if AParentSymbolIdx >= 0 then Sym.ParentId:= AParentSymbolIdx
  else Sym.ParentId:= -1;
  if not ARangeNode.IsNull then
  begin
    Sym.StartLine:= Integer(ARangeNode.StartPoint.row   ) + 1;
    Sym.StartCol := Integer(ARangeNode.StartPoint.column) + 1;
    Sym.EndLine  := Integer(ARangeNode.EndPoint  .row   ) + 1;
    Sym.EndCol   := Integer(ARangeNode.EndPoint  .column) + 1;
  end;
  Symbols.Add(Sym);
  Result:= Symbols.Count - 1;
end; // function

procedure Walk(const ANode: TTSNode; const AState: TWalkState; AParentSymbolIdx: Integer; const AParentQualifiedName: string); forward;

// v0.8: every `typeref` node that appears in a parameter type, field type,
// inheritance clause, etc. emits a kind='type_use' reference. This lets
// `find-callers` / LSP references answer "where is type X used?" not just
// "where is method X called?".
procedure EmitTypeUseReference(const ANode: TTSNode; const AState: TWalkState);
var
  Child  : TTSNode;
  RefName: string ;
begin
  // A typeref is (typeref (identifier "TFoo")) or sometimes
  // (typeref (genericDot lhs: id operator: kDot rhs: id)) for qualified types
  // and (typeref (identifier) (declTypeArgs ...)) for generics. Take the
  // first named-child identifier-shaped thing.
  if ANode.NamedChildCount = 0 then Exit;
  Child:= ANode.NamedChild(0);
  if Child.NodeType      = 'identifier' then RefName:= NodeText(Child, AState.Source)
  else if Child.NodeType = 'genericDot' then
  begin
    // qualified: take rhs
    var Rhs:= Child.ChildByField('rhs');
    if not Rhs.IsNull then RefName:= NodeText(Rhs, AState.Source)
    else Exit;
    Child:= Rhs;
  end
  else Exit;
  if RefName = '' then Exit;
  AState.EmitRef('type_use', RefName, Child);
end; // procedure

procedure EmitCallReference(const ANode: TTSNode; const AState: TWalkState);
var
  EntityNode: TTSNode;
  NameNode  : TTSNode;
  CalleeName: string ;
begin
  EntityNode:= ANode.ChildByField('entity');
  if EntityNode.IsNull then Exit;
  if EntityNode.NodeType      = 'identifier' then NameNode:= EntityNode
  else if EntityNode.NodeType = 'exprDot' then
  begin
    NameNode:= EntityNode.ChildByField('rhs');
    if NameNode.IsNull then Exit;
  end
  else Exit;
  CalleeName:= NodeText(NameNode, AState.Source);
  if CalleeName = '' then Exit;
  AState.EmitRef('call', CalleeName, NameNode);
end; // procedure

// v0.40.4: extract the literal string body from a `kIn literalString` pair
// inside a declUsesUnit. Strips the surrounding single quotes.
function ExtractInPath(const ALitNode: TTSNode; const ASource: TBytes): string;
begin
  Result:= NodeText(ALitNode, ASource);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then Result:= Copy(Result, 2, Length(Result) - 2);
end;

// Remove EVERY whitespace byte from a dotted module name, not just the ones on
// the ends (ported from feat/autodoc-phase3; counts below re-derived on this
// machine by tools/measure/phase1_verify.py, read-only).
//
// A `moduleName` node spans the WHOLE dotted name, so its source text carries
// whatever the author wrote BETWEEN the tokens -- and this repo aligns its own
// `uses` clauses (`DRagLint.Core   .Model`). `Trim` removes only the ends, so
// that interior padding was stored verbatim in `unit_uses.unit_name`, where
// ResolveUnitUseTargets' rule A -- an equality against `LOWER(unit_name)` -- can
// never match it. Rule B keys on `unit_name_norm`, the dotted TAIL, which the
// padding does not reach, and so MASKED this whenever the tail happened to be
// unique; where two units share a tail it declines as ambiguous and the row was
// simply lost. Measured before the fix: 147 of 1836 rows in this repo's own index
// carry embedded whitespace (137 of them unresolved) and 286 of 14223 in ORM3
// (285 unresolved); 0 in library-Win64 and 0 in M2022, because the alignment is
// our house style and not third-party code's.
//
// Stripping ALL whitespace is exactly equivalent to re-joining the tokens: a
// `moduleName` is `ident ('.' ident)*`, so whitespace here can only ever be
// inter-token padding and can never be part of a legal name. `C <= ' '` rather
// than a four-way match on #32/#9/#13/#10 because #11 (VT) and #12 (FF) are also
// Pascal whitespace and would otherwise survive INVISIBLY; nothing legal in a
// moduleName sorts below #32, since every retained byte is an identifier
// character or a dot.
//
// Fixed at the STORE, not at the lookup: normalizing inside the resolver's WHERE
// clause would hide the bad value rather than stop it being written, and every
// other consumer of `unit_name` would still read the padded string.
//
// NOT HANDLED: a comment written inside the dotted name (`Alpha.{x}Config`) is
// still stored verbatim -- rarer than this was, and no worse than before.
// Guarded by tests/autotest/run_uses_padded_name.ps1.
function StripModuleNameWhitespace(const AName: string): string;
var
  I: Integer;
  N: Integer;
  C: Char   ;
begin
  SetLength(Result, Length(AName));
  N:= 0;
  for I:= 1 to Length(AName) do
  begin
    C:= AName[I];
    if C <= ' ' then Continue;
    Inc(N);
    Result[N]:= C;
  end;
  SetLength(Result, N);
end;

// v0.40.4: walk a declUses node, emitting one TUnitUse per declUsesUnit child.
procedure WalkUsesClause(const ANode: TTSNode; const AState: TWalkState; ASection: TUnitUseSection);
var
  i       : Integer;
  J       : Integer;
  Child   : TTSNode;
  Sub     : TTSNode;
  ModNode : TTSNode;
  LitNode : TTSNode;
  UnitName: string ;
  InPath  : string ;
begin
  for i:= 0 to ANode.NamedChildCount - 1 do
  begin
    Child:= ANode.NamedChild(i);
    if Child.NodeType <> 'declUsesUnit' then Continue;
    ModNode:= Default(TTSNode);
    LitNode:= Default(TTSNode);
    for J:= 0 to Child.NamedChildCount - 1 do
    begin
      Sub:= Child.NamedChild(J);
      if Sub.NodeType      = 'moduleName' then ModNode:= Sub
      else if Sub.NodeType = 'literalString' then LitNode:= Sub;
    end;
    if ModNode.IsNull then Continue;
    UnitName:= StripModuleNameWhitespace(NodeText(ModNode, AState.Source));
    if UnitName = '' then Continue;
    InPath:= '';
    if not LitNode.IsNull then InPath:= ExtractInPath(LitNode, AState.Source);
    AState.EmitUnitUse(UnitName, InPath, ASection, Child);
  end; // for
end; // procedure

// v0.40.4: walk a unit's interface or implementation section, looking for a
// declUses child and emitting its entries under the appropriate section.
procedure WalkSection(const ASectionNode: TTSNode; const AState: TWalkState; ASection: TUnitUseSection);
var
  i    : Integer;
  Child: TTSNode;
begin
  for i:= 0 to ASectionNode.NamedChildCount - 1 do
  begin
    Child:= ASectionNode.NamedChild(i);
    if Child.NodeType = 'declUses' then WalkUsesClause(Child, AState, ASection);
  end;
end;

procedure WalkUnit(const ANode: TTSNode; const AState: TWalkState);
var
  ModNode : TTSNode;
  UnitName: string ;
  UnitIdx : Integer;
  i       : Integer;
  Child   : TTSNode;
begin
  ModNode:= FindNamedChildOfType(ANode, 'moduleName');
  if ModNode.IsNull then Exit;
  // Take the full text of moduleName so multi-segment unit names like
  // DRagLint.Core.Interfaces are preserved verbatim. Earlier impl grabbed
  // only the first identifier and lost everything after the dot.
  //
  // The SAME strip as WalkUsesClause above, for the same reason -- a `moduleName`
  // node spans the whole dotted name, so `unit Alpha  .Config;` hands back the
  // padding too and `Trim` removes only the ends. This site is the more expensive
  // one to get wrong: the value becomes the skUnit symbol's own name AND the
  // qualified-name prefix of every symbol the unit declares (AState.Emit below,
  // and the `UnitName + '.initialization'` forms), so one padded `unit` line
  // would mis-key a whole unit's rows rather than one edge. LATENT when fixed --
  // 0 of the 7098 kind='unit' symbols across Delphi-RAG-lint / ORM3 /
  // library-Win64 / M2022 carry embedded whitespace, because we align `uses`
  // clauses and not the `unit` line -- which is exactly why it is pinned by a
  // fixture and not by a live query.
  UnitName:= StripModuleNameWhitespace(NodeText(ModNode, AState.Source));
  if UnitName = '' then Exit;
  AState.CurrentSection:= ''; { the unit symbol itself is section-less }
  UnitIdx:= AState.Emit(skUnit, UnitName, UnitName, -1, ANode);

  // v0.40.4: explicitly walk interface/implementation children to extract
  // their `declUses` entries under the correct section.
  for i:= 0 to ANode.NamedChildCount - 1 do
  begin
    Child:= ANode.NamedChild(i);
    if Child.NodeType      = 'interface' then WalkSection(Child, AState, uusInterface)
    else if Child.NodeType = 'implementation' then WalkSection(Child, AState, uusImplementation);
  end;

  { Stamp each symbol with the unit section it is declared in (gap #3): set
    CurrentSection as we descend into the interface vs implementation child. }
  for i:= 0 to ANode.NamedChildCount - 1 do
  begin
    Child:= ANode.NamedChild(i);
    if Child.NodeType      = 'interface' then AState.CurrentSection:= 'interface'
    else if Child.NodeType = 'implementation' then AState.CurrentSection:= 'implementation';
    Walk(Child, AState, UnitIdx, UnitName);
  end;

  { v0.41: emit initialization / finalization sections as named unit-child
    markers (they carry no identifier of their own).  Placed in the
    implementation section conceptually -- they run after it. }
  AState.CurrentSection:= 'implementation';
  for i:= 0 to ANode.NamedChildCount - 1 do
  begin
    Child:= ANode.NamedChild(i);
    if Child.NodeType      = 'initialization' then AState.Emit(skInitialization, 'initialization', UnitName + '.initialization', UnitIdx, Child)
    else if Child.NodeType = 'finalization' then AState.Emit(skFinalization, 'finalization', UnitName + '.finalization', UnitIdx, Child);
  end;
  AState.CurrentSection:= '';
end; // procedure

// Determines whether a declClass node is actually a record (first token is
// kRecord) versus a regular class (kClass). The grammar reuses declClass for
// both shapes; the kind is carried by the leading token child.
function ClassNodeIsRecord(const AClassNode: TTSNode): Boolean;
var
  i: Integer;
  C: TTSNode;
  T: string ;
begin
  Result:= False;
  for i:= 0 to AClassNode.ChildCount - 1 do
  begin
    C:= AClassNode.Child(i);
    T:= C.NodeType;
    if T = 'kClass'  then Exit(False);
    if T = 'kRecord' then Exit(True );
  end;
end;

// Read the visibility of a declSection node ('private'/'protected'/'public'/
// 'published', prefixed 'strict ' when applicable).  Defaults to 'public'.
function VisibilityOfSection(const ANode: TTSNode; const ASource: TBytes): string;
var
  i       : Integer;
  C       : TTSNode;
  NT      : string ;
  Vis     : string ;
  IsStrict: Boolean;
begin
  IsStrict:= False;
  Vis     := '';
  for i:= 0 to ANode.NamedChildCount - 1 do
  begin
    C:= ANode.NamedChild(i);
    NT:= C.NodeType;
    if NT      = 'kStrict' then IsStrict:= True
    else if NT = 'kPrivate'   then Vis:= 'private'
    else if NT = 'kProtected' then Vis:= 'protected'
    else if NT = 'kPublic'    then Vis:= 'public'
    else if NT = 'kPublished' then Vis:= 'published'
    else if Vis <> '' then Break; // past the keyword(s), into members
  end;
  if Vis = '' then Vis:= 'public';
  if IsStrict and ((Vis = 'private') or (Vis = 'protected')) then Result:= 'strict ' + Vis
  else Result:= Vis;
end; // function

// v11 (M1): collapse a class/interface node's ancestor list to raw source text,
// e.g. 'TBar, IBaz'. The ancestors are the bare `typeref` named children of the
// declClass/declIntf node -- verified that member field/property/method types
// are nested inside declField/declProp/declSection (never direct typeref
// children) and that records with no parent yield ''. Names are kept verbatim
// (qualified/generic intact); the resolve pass normalizes + links them later.
function HeritageTextOf(const ATypeNode: TTSNode; const ASource: TBytes): string;
var
  i    : Integer;
  Child: TTSNode;
  Raw  : string ;
  Clean: string ;
  k    : Integer;
  Ch   : Char   ;
  Prev : Boolean; // previous char was whitespace
begin
  Result:= '';
  for i:= 0 to ATypeNode.NamedChildCount - 1 do
  begin
    Child:= ATypeNode.NamedChild(i);
    if Child.NodeType <> 'typeref' then Continue;
    Raw:= NodeText(Child, ASource);
    { collapse any internal whitespace (a wrapped generic arg list) to single
      spaces so the stored heritage is one clean line. }
    Clean:= '';
    Prev := False;
    for k:= 1 to Length(Raw) do
    begin
      Ch:= Raw[k];
      if (Ch = #9) or (Ch = #10) or (Ch = #13) or (Ch = ' ') then
      begin
        if not Prev then Clean:= Clean + ' ';
        Prev:= True;
      end
      else
      begin
        Clean:= Clean + Ch;
        Prev := False;
      end;
    end;
    Clean:= Trim(Clean);
    if Clean = '' then Continue;
    if Result = '' then Result:= Clean
    else Result:= Result + ', ' + Clean;
  end;
end; // function

// v15: does a declHelper node describe a `record helper` (True) or `class
// helper` (False)? Grammar rule: declHelper := choice(kClass, kRecord, kType),
// kHelper, ... -- the FIRST of {kClass, kRecord, kType} child carries the
// helper's own shape (distinct from the target after kFor). `type helper for
// X` (kType) is rare/legacy; treated as a class helper (kind='class') since
// it has no value-type storage semantics of its own.
function HelperNodeIsRecord(const AHelperNode: TTSNode): Boolean;
var
  i: Integer;
  C: TTSNode;
  T: string ;
begin
  Result:= False;
  for i:= 0 to AHelperNode.ChildCount - 1 do
  begin
    C:= AHelperNode.Child(i);
    T:= C.NodeType;
    if T = 'kRecord' then Exit(True );
    if (T = 'kClass') or (T = 'kType') then Exit(False);
    if T = 'kHelper' then Break; // past the shape token with no match - bail
  end;
end;

// v15: extract the helper's TARGET type (the `for TX` in `record helper for
// TX`). Grammar: declHelper := shape, kHelper, field('parent', optional('('
// typeref,... ')')), kFor, typeref, _declClass(members...). The optional
// parenthesized `parent` field is a DIFFERENT thing (a helper-of-helper
// ancestor list, e.g. `record helper for TX (TBaseHelper)`) -- so the target
// is NOT simply "the first typeref child"; it is the first typeref that
// appears AFTER the kFor token. Scan children in order and take the first
// typeref seen once kFor has been passed.
function HelperTargetOf(const AHelperNode: TTSNode; const ASource: TBytes): string;
var
  i       : Integer;
  C       : TTSNode;
  PastFor : Boolean;
begin
  Result := '';
  PastFor:= False;
  for i:= 0 to AHelperNode.NamedChildCount - 1 do
  begin
    C:= AHelperNode.NamedChild(i);
    if C.NodeType = 'kFor' then
    begin
      PastFor:= True;
      Continue;
    end;
    if PastFor and (C.NodeType = 'typeref') then
    begin
      Result:= Trim(NodeText(C, ASource));
      Exit;
    end;
  end;
end;

// v15: `record helper for TX` / `class helper for TX`. A DISTINCT grammar node
// (declHelper) from declClass -- confirmed via the tree-sitter-delphi13
// node-types.json grammar (declHelper := {kClass|kRecord|kType}, kHelper,
// optional parent-helper-list, kFor, typeref-TARGET, member decls). Before this
// function existed, a declHelper fell through TryWalkClassOrRecord (which only
// recognizes declClass) and was mis-picked-up by TryWalkAlias's direct-typeref
// scan -- emitting the whole helper as a flat skTypeAlias leaf with the target
// in Signature and NEVER walking its members (e.g. a helper method like ToByte
// was silently dropped from the index). This function fixes both: it emits a
// proper skRecord/skClass symbol (so members are indexed) with IsHelper=True
// and the target name in Heritage (reusing the ancestor-list slot, which is
// otherwise always empty for a real record/class helper -- helpers cannot
// have ordinary ancestors). ResolveHelpers reads IsHelper/Heritage to populate
// type_helpers; consumers never need to string-scan for 'helper' themselves.
function TryWalkHelper(const ADeclTypeNode: TTSNode; const AState: TWalkState; AParentSymbolIdx: Integer; const AParentQualifiedName: string): Boolean;
var
  TypeWrapNode: TTSNode    ;
  HelperNode  : TTSNode    ;
  NameNode    : TTSNode    ;
  TypeName    : string     ;
  QName       : string     ;
  Target      : string     ;
  OldVis      : string     ;
  TypeIdx     : Integer    ;
  i           : Integer    ;
  Kind        : TSymbolKind;
begin
  Result:= False;
  TypeWrapNode:= ADeclTypeNode.ChildByField('type');
  if TypeWrapNode.IsNull then Exit;
  { Confirmed via `tree-sitter parse` on the Task 0 probe fixture: unlike
    declClass (always wrapped one level deep in an intermediate `type` node --
    type: (type (declClass ...))), declHelper is the direct `type` field child
    itself -- type: (declHelper ...), no wrapper. Mirrors how TryWalkAlias
    special-cases TypeWrapNode.NodeType = 'typeref' directly below. }
  if TypeWrapNode.NodeType = 'declHelper' then HelperNode:= TypeWrapNode
  else HelperNode:= FindNamedChildOfType(TypeWrapNode, 'declHelper');
  if HelperNode.IsNull then Exit;
  NameNode:= ADeclTypeNode.ChildByField('name');
  if NameNode.IsNull then Exit;
  TypeName:= NodeText(NameNode, AState.Source);
  if TypeName = '' then Exit;
  if AParentQualifiedName <> '' then QName:= AParentQualifiedName + '.' + TypeName
  else QName:= TypeName;
  if HelperNodeIsRecord(HelperNode) then Kind:= skRecord
  else Kind:= skClass;
  Target:= HelperTargetOf(HelperNode, AState.Source);
  TypeIdx:= AState.Emit(Kind, TypeName, QName, AParentSymbolIdx, ADeclTypeNode, '', '', Target, False, True);
  { Same member-walk convention as TryWalkClassOrRecord: default visibility
    'public', save/restore so a nested type doesn't leak sections outward. }
  OldVis:= AState.CurrentVisibility;
  AState.CurrentVisibility:= 'public';
  for i:= 0 to HelperNode.NamedChildCount - 1 do Walk(HelperNode.NamedChild(i), AState, TypeIdx, QName);
  AState.CurrentVisibility:= OldVis;
  Result:= True;
end; // function

function TryWalkClassOrRecord(const ADeclTypeNode: TTSNode; const AState: TWalkState; AParentSymbolIdx: Integer; const AParentQualifiedName: string): Boolean;
var
  TypeWrapNode: TTSNode    ;
  ClassNode   : TTSNode    ;
  NameNode    : TTSNode    ;
  TypeName    : string     ;
  QName       : string     ;
  OldVis      : string     ;
  TypeIdx     : Integer    ;
  i           : Integer    ;
  Kind        : TSymbolKind;
begin
  Result:= False;
  TypeWrapNode:= ADeclTypeNode.ChildByField('type');
  if TypeWrapNode.IsNull then Exit;
  ClassNode:= FindNamedChildOfType(TypeWrapNode, 'declClass');
  if ClassNode.IsNull then Exit;
  NameNode:= ADeclTypeNode.ChildByField('name');
  if NameNode.IsNull then Exit;
  TypeName:= NodeText(NameNode, AState.Source);
  if TypeName = '' then Exit;
  if AParentQualifiedName <> '' then QName:= AParentQualifiedName + '.' + TypeName
  else QName:= TypeName;
  if ClassNodeIsRecord(ClassNode) then Kind:= skRecord
  else Kind:= skClass;
  TypeIdx:= AState.Emit(Kind, TypeName, QName, AParentSymbolIdx, ADeclTypeNode, '', '', HeritageTextOf(ClassNode, AState.Source));
  { Members before any visibility keyword default to 'public'; declSection
    handlers update it as they are walked.  Save/restore so a nested type does
    not leak its sections to the enclosing one. }
  OldVis:= AState.CurrentVisibility;
  AState.CurrentVisibility:= 'public';
  for i:= 0 to ClassNode.NamedChildCount - 1 do Walk(ClassNode.NamedChild(i), AState, TypeIdx, QName);
  AState.CurrentVisibility:= OldVis;
  Result:= True;
end; // function

function TryWalkInterface(const ADeclTypeNode: TTSNode; const AState: TWalkState; AParentSymbolIdx: Integer; const AParentQualifiedName: string): Boolean;
var
  TypeNode: TTSNode;
  NameNode: TTSNode;
  TypeName: string ;
  QName   : string ;
  OldVis  : string ;
  Idx     : Integer;
  i       : Integer;
begin
  Result:= False;
  TypeNode:= ADeclTypeNode.ChildByField('type');
  // declIntf is the `type:` child directly - not wrapped in (type).
  if TypeNode.IsNull or (TypeNode.NodeType <> 'declIntf') then Exit;
  NameNode:= ADeclTypeNode.ChildByField('name');
  if NameNode.IsNull then Exit;
  TypeName:= NodeText(NameNode, AState.Source);
  if TypeName = '' then Exit;
  if AParentQualifiedName <> '' then QName:= AParentQualifiedName + '.' + TypeName
  else QName:= TypeName;
  Idx:= AState.Emit(skInterface, TypeName, QName, AParentSymbolIdx, ADeclTypeNode, '', '', HeritageTextOf(TypeNode, AState.Source));
  { All interface members are public. }
  OldVis:= AState.CurrentVisibility;
  AState.CurrentVisibility:= 'public';
  for i:= 0 to TypeNode.NamedChildCount - 1 do Walk(TypeNode.NamedChild(i), AState, Idx, QName);
  AState.CurrentVisibility:= OldVis;
  Result:= True;
end; // function

function TryWalkEnum(const ADeclTypeNode: TTSNode; const AState: TWalkState; AParentSymbolIdx: Integer; const AParentQualifiedName: string): Boolean;
var
  TypeWrapNode: TTSNode;
  EnumNode    : TTSNode;
  NameNode    : TTSNode;
  ValNode     : TTSNode;
  ValNameNode : TTSNode;
  TypeName    : string ;
  QName       : string ;
  ValName     : string ;
  EnumIdx     : Integer;
  i           : Integer;
begin
  Result:= False;
  TypeWrapNode:= ADeclTypeNode.ChildByField('type');
  if TypeWrapNode.IsNull then Exit;
  EnumNode:= FindNamedChildOfType(TypeWrapNode, 'declEnum');
  if EnumNode.IsNull then Exit;
  NameNode:= ADeclTypeNode.ChildByField('name');
  if NameNode.IsNull then Exit;
  TypeName:= NodeText(NameNode, AState.Source);
  if TypeName = '' then Exit;
  if AParentQualifiedName <> '' then QName:= AParentQualifiedName + '.' + TypeName
  else QName:= TypeName;
  EnumIdx:= AState.Emit(skEnum, TypeName, QName, AParentSymbolIdx, ADeclTypeNode);
  // Emit each enum value as a child symbol, carrying its ORDINAL VALUE in the
  // signature (like the IDE's "= 128"). The ordinal runs by declaration position
  // (0-based) and is RESET by an explicit `name = N` initializer, matching Pascal
  // enum semantics. A non-integer initializer (rare: `= SomeConst`) leaves the
  // running counter (best-effort; absence-over-wrong is not possible for a bare
  // number, so we keep the positional value).
  var EnumOrd: Integer:= 0;
  for i:= 0 to EnumNode.NamedChildCount - 1 do
  begin
    ValNode:= EnumNode.NamedChild(i);
    if ValNode.NodeType = 'declEnumValue' then
    begin
      ValNameNode:= ValNode.ChildByField('name');
      if not ValNameNode.IsNull then
      begin
        ValName:= NodeText(ValNameNode, AState.Source);
        if ValName <> '' then
        begin
          var ValText: string:= NodeText(ValNode, AState.Source); // 'ptObject' or 'foo = 5'
          var EqP: Integer:= Pos('=', ValText);
          if EqP > 0 then
          begin
            var ExplicitVal: Integer;
            if TryStrToInt(Trim(Copy(ValText, EqP + 1, MaxInt)), ExplicitVal) then EnumOrd:= ExplicitVal;
          end;
          AState.Emit(skEnumValue, ValName, QName + '.' + ValName, EnumIdx, ValNode, IntToStr(EnumOrd));
          Inc(EnumOrd);
        end;
      end;
    end;
  end;
  Result:= True;
end; // function

// v11 (M1): simple type-reference alias `type X = SomeType;` -> emit skTypeAlias
// with the target type text in Signature, so ResolveTypeCategory can chase
// `type TMyFloat = Double;` to its intrinsic. ONLY a direct `typeref` target
// qualifies; sets/subranges/proc-types/classes/interfaces/enums are handled by
// the earlier TryWalk* dispatch (or left unemitted) and are skipped here.
function TryWalkAlias(const ADeclTypeNode: TTSNode; const AState: TWalkState; AParentSymbolIdx: Integer; const AParentQualifiedName: string): Boolean;
var
  TypeWrapNode: TTSNode;
  RefNode     : TTSNode;
  NameNode    : TTSNode;
  TypeName    : string ;
  QName       : string ;
  Target      : string ;
begin
  Result:= False;
  TypeWrapNode:= ADeclTypeNode.ChildByField('type');
  if TypeWrapNode.IsNull then Exit;
  if TypeWrapNode.NodeType = 'typeref' then RefNode:= TypeWrapNode
  else RefNode:= FindNamedChildOfType(TypeWrapNode, 'typeref');
  if RefNode.IsNull then Exit;
  NameNode:= ADeclTypeNode.ChildByField('name');
  if NameNode.IsNull then Exit;
  TypeName:= NodeText(NameNode, AState.Source);
  if TypeName = '' then Exit;
  Target:= Trim(NodeText(RefNode, AState.Source));
  if AParentQualifiedName <> '' then QName:= AParentQualifiedName + '.' + TypeName
  else QName:= TypeName;
  AState.Emit(skTypeAlias, TypeName, QName, AParentSymbolIdx, ADeclTypeNode, Target);
  Result:= True;
end; // function

// Text of a node's `type:` field (field/property/const type, or a proc's
// return type), whitespace-collapsed. Empty when there is no type child.
function TypeTextOf(const ANode: TTSNode; const ASource: TBytes): string;
var
  T        : TTSNode;
  i        : Integer;
  Raw      : string ;
  C        : Char   ;
  PrevSpace: Boolean;
begin
  Result:= '';
  T:= ANode.ChildByField('type');
  if T.IsNull then Exit;
  Raw:= NodeText(T, ASource);
  { collapse runs of whitespace to single spaces so multi-line types read well }
  PrevSpace:= False;
  for i:= 1 to Length(Raw) do
  begin
    C:= Raw[i];
    if (C = #9) or (C = #10) or (C = #13) or (C = ' ') then
    begin
      if not PrevSpace then Result:= Result + ' ';
      PrevSpace:= True;
    end
    else
    begin
      Result:= Result + C;
      PrevSpace:= False;
    end;
  end;
  Result:= Trim(Result);
end; // function

// v0.42: whitespace-collapse any node text to a single readable line.
function CollapseWs(const ARaw: string): string;
var
  i        : Integer;
  C        : Char   ;
  PrevSpace: Boolean;
begin
  Result   := '';
  PrevSpace:= False;
  for i:= 1 to Length(ARaw) do
  begin
    C:= ARaw[i];
    if (C = #9) or (C = #10) or (C = #13) or (C = ' ') then
    begin
      if not PrevSpace then Result:= Result + ' ';
      PrevSpace:= True;
    end
    else
    begin
      Result:= Result + C;
      PrevSpace:= False;
    end;
  end;
  Result:= Trim(Result);
end; // function

// v0.42: full Pascal signature for a declProc node = the parameter list
// (declArgs, including its parentheses) plus the return type, so hover and
// completion can show "(const A: Integer; B: string): Boolean" rather than
// just the return type. Paramless procedures yield ''; paramless functions
// yield ': <ReturnType>'. Whitespace is collapsed so multi-line param lists
// read on one line.
function ProcSignatureOf(const ANode: TTSNode; const ASource: TBytes): string;
var
  ArgsNode: TTSNode;
  ArgsText: string ;
  RetType : string ;
begin
  ArgsText:= '';
  ArgsNode:= ANode.ChildByField('args');
  if not ArgsNode.IsNull then ArgsText:= CollapseWs(NodeText(ArgsNode, ASource));
  RetType:= TypeTextOf(ANode, ASource);
  if RetType <> '' then
  begin
    if ArgsText <> '' then Result:= ArgsText + ': ' + RetType
    else Result:= ': ' + RetType;
  end
  else Result:= ArgsText;
end; // function

// v12 (M1): a declProc is virtually dispatched if it carries a virtual/dynamic/
// override directive -- exposed as `attribute: (procAttribute (kVirtual|kDynamic|
// kOverride))` children of the declProc node.
function ProcIsVirtual(const ANode: TTSNode): Boolean;
var
  i, j : Integer;
  Attr : TTSNode;
  K    : string ;
begin
  Result:= False;
  for i:= 0 to ANode.NamedChildCount - 1 do
  begin
    Attr:= ANode.NamedChild(i);
    if Attr.NodeType <> 'procAttribute' then Continue;
    for j:= 0 to Attr.NamedChildCount - 1 do
    begin
      K:= Attr.NamedChild(j).NodeType;
      if (K = 'kVirtual') or (K = 'kDynamic') or (K = 'kOverride') then Exit(True);
    end;
  end;
end; // function

// v14 (D5, Task 2): emit each formal parameter of a routine as an skParam
// symbol carrying its declared type, parented to the routine. Enables Task 5
// to type a call-site receiver that is a parameter (AFoo.M where AFoo: TFoo).
//
// Grammar shape (discovered by dumping the S-expression of the 'args' field):
//   (declArgs
//     (declArg name: (identifier) name: (identifier)                 // grouped A, B
//              type: (type (typeref (identifier))))                  //   share one type
//     (declArg (kConst) name: (identifier) type: (type ...))         // const/var/out
//     (declArg (kVar) name: (identifier)))                           // untyped -> no type
// So one declArg may carry MULTIPLE name: identifiers (grouped params) that
// share a single type: field; const/var/out appear as leading token children
// (kConst/kVar/kOut), NOT inside the type field; an untyped param (var E) has
// no type: field at all. TypeTextOf reads the type: field and collapses
// whitespace -- it therefore excludes the modifier tokens automatically and
// returns '' for an untyped param.
//
// AParentQualifiedName is the routine's own qualified name (e.g.
// 'params.TThing.Handle'); ARoutineIdx is the routine symbol's index in
// AState.Symbols (its parent).
procedure EmitRoutineParams(const ARoutineNode: TTSNode; const AState: TWalkState; ARoutineIdx: Integer; const ARoutineQualifiedName: string);
var
  ArgsNode : TTSNode;
  DeclArg  : TTSNode;
  Child    : TTSNode;
  TypeText : string ;
  ParamName: string ;
  ParamQN  : string ;
  i, j     : Integer;
begin
  if ARoutineIdx < 0 then Exit;
  ArgsNode:= ARoutineNode.ChildByField('args');
  if ArgsNode.IsNull then Exit;
  for i:= 0 to ArgsNode.NamedChildCount - 1 do
  begin
    DeclArg:= ArgsNode.NamedChild(i);
    if DeclArg.NodeType <> 'declArg' then Continue;
    // One shared type for every name in this declArg (grouped params). Empty
    // when the param is untyped (e.g. an untyped 'var').
    TypeText:= TypeTextOf(DeclArg, AState.Source);
    // Emit one skParam per direct 'identifier' child (the param names). The
    // modifier tokens are kConst/kVar/kOut and the type lives nested under a
    // 'type' child, so only the param-name identifiers match here.
    for j:= 0 to DeclArg.NamedChildCount - 1 do
    begin
      Child:= DeclArg.NamedChild(j);
      if Child.NodeType <> 'identifier' then Continue;
      ParamName:= NodeText(Child, AState.Source);
      if ParamName = '' then Continue;
      if ARoutineQualifiedName <> '' then ParamQN:= ARoutineQualifiedName + '.' + ParamName
      else ParamQN:= ParamName;
      // Range = the param-name identifier; parent = the routine; Signature =
      // the declared type text (empty when untyped).
      AState.Emit(skParam, ParamName, ParamQN, ARoutineIdx, Child, TypeText);
    end;
  end;
end; // procedure

procedure WalkDeclProc(const ANode: TTSNode; const AState: TWalkState; AParentSymbolIdx: Integer; const AParentQualifiedName: string; AAsMethod: Boolean);
var
  NameNode : TTSNode    ;
  FirstTok : TTSNode    ;
  MethName : string     ;
  QName    : string     ;
  Modifiers: string     ;
  Kind     : TSymbolKind;
  RoutineIdx: Integer   ;
begin
  NameNode:= ANode.ChildByField('name');
  if NameNode.IsNull then Exit;
  MethName:= NodeText(NameNode, AState.Source);
  if MethName = '' then Exit;
  // Strip qualified prefix if present (e.g. 'TFoo.DoBar' -> 'DoBar') - happens in
  // free implementations. For interface/class declarations the name is bare.
  if Pos('.', MethName) > 0 then MethName:= Copy(MethName, LastDelimiter('.', MethName) + 1, MaxInt);
  if AAsMethod then Kind:= skMethod
  else
  begin
    // Determine procedure vs function by inspecting the first token child
    Kind:= skProcedure;
    if ANode.ChildCount > 0 then
    begin
      FirstTok:= ANode.Child(0);
      if FirstTok.NodeType      = 'kFunction' then Kind:= skFunction
      else if FirstTok.NodeType = 'kConstructor' then Kind:= skConstructor
      else if FirstTok.NodeType = 'kDestructor' then Kind:= skDestructor;
    end;
  end;
  if AParentQualifiedName <> '' then QName:= AParentQualifiedName + '.' + MethName
  else QName:= MethName;
  { Methods carry their class visibility (UML glyphs); free procs do not. }
  if AAsMethod then Modifiers:= AState.CurrentVisibility
  else Modifiers:= '';
  { v0.42: Signature = full parameter list + return type (Code-Insight style),
    e.g. '(const A: Integer): Boolean'. Was return-type-only before. }
  RoutineIdx:= AState.Emit(Kind, MethName, QName, AParentSymbolIdx, ANode, ProcSignatureOf(ANode, AState.Source), Modifiers, '', AAsMethod and ProcIsVirtual(ANode));
  // v14 (D5, Task 2): emit each formal parameter as an skParam symbol parented
  // to this routine (RoutineIdx). Nested procs never reach WalkDeclProc (their
  // defProc is skipped at RoutineDepth > 0), so their params cannot leak here.
  EmitRoutineParams(ANode, AState, RoutineIdx, QName);
end; // procedure

{ v0.48: does the in-memory symbol list already hold a free routine (proc/func) by
  this name? Used to dedup an implementation-only free routine against a prior
  interface or forward declaration so we never emit a duplicate symbol. }
function FreeRoutineSymbolExists(const AState: TWalkState; const AName: string): Boolean;
var
  i: Integer;
begin
  Result:= False;
  for i:= 0 to AState.Symbols.Count - 1 do
    if (AState.Symbols[i].Kind in [skProcedure, skFunction]) and SameText(AState.Symbols[i].Name, AName) then Exit(True);
end;

{ v9: stamp a routine's implementation body span onto its symbol so "which routine
  contains line N" / context bundles don't need a text-scan. The defProc name is
  'TClass.Method' or 'Foo'; the decl symbol is unit-qualified ('Unit.TClass.Method'),
  so match on the leaf name + a qualified-name suffix. Sets the first not-yet-
  stamped match (overloads in source order).
  v(ADP1 Bug B): name-only matching mis-attaches OVERLOADED methods when the impl
  bodies are ordered differently than the decls -- the scan just grabs whichever
  unstamped same-name candidate it meets first, with no regard for which impl
  actually belongs to which decl, so a wrong body (and its mined <returns>) can
  land on the wrong overload. ASignature (built by the SAME ProcSignatureOf that
  produced the decl's stored Signature) disambiguates: PREFER an unstamped
  candidate whose Name AND Signature both match; FALL BACK to today's exact
  name-only "first unstamped, downto 0" behavior when no signature match exists
  (ASignature = '', a signature-extraction edge case, or a non-overloaded /
  impl-only free routine) -- so the fix is never worse than before. There cannot
  be two unstamped decls sharing both name and signature (that would be a
  duplicate-overload compile error), so a signature match is always unique. }
procedure SetRoutineImplRange(const AState: TWalkState; const AName: string; AStartLine, AEndLine: Integer; const ASignature: string);
var
  i          : Integer;
  Sym        : TSymbol;
  LastSeg    : string ;
  FallbackIdx: Integer;
begin
  if AName = '' then Exit;
  LastSeg:= AName;
  if Pos('.', LastSeg) > 0 then LastSeg:= Copy(LastSeg, LastDelimiter('.', LastSeg) + 1, MaxInt);
  FallbackIdx:= -1;
  for i:= AState.Symbols.Count - 1 downto 0 do
  begin
    Sym:= AState.Symbols[i];
    if (Sym.Kind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor]) and (Sym.ImplStartLine = 0) and SameText(Sym.Name, LastSeg)
       and (SameText(Sym.QualifiedName, AName) or Sym.QualifiedName.EndsWith('.' + AName, True)) then
    begin
      if (ASignature <> '') and SameText(Sym.Signature, ASignature) then
      begin
        Sym.ImplStartLine:= AStartLine;
        Sym.ImplEndLine  := AEndLine;
        AState.Symbols[i]:= Sym;
        Exit;
      end;
      if FallbackIdx < 0 then FallbackIdx:= i;
    end;
  end;
  if FallbackIdx >= 0 then
  begin
    Sym:= AState.Symbols[FallbackIdx];
    Sym.ImplStartLine:= AStartLine;
    Sym.ImplEndLine  := AEndLine;
    AState.Symbols[FallbackIdx]:= Sym;
  end;
end; // procedure

{ v14 (D5, Task 3): find the index of the routine symbol that a defProc's header
  names, so its local vars can be parented to it. The routine symbol was already
  emitted (by WalkDeclProc from the class/interface decl, or as an impl-only free
  routine); this locates it by the same leaf-name + qualified-name-suffix match
  SetRoutineImplRange uses. AImplStartLine (the defProc's start line, already
  stamped onto the symbol by SetRoutineImplRange) disambiguates overloads: prefer
  the symbol whose ImplStartLine matches this body. Returns -1 if none found. }
function FindRoutineSymbolIndex(const AState: TWalkState; const AName: string; AImplStartLine: Integer): Integer;
var
  i      : Integer;
  Sym    : TSymbol;
  LastSeg: string ;
begin
  Result:= -1;
  if AName = '' then Exit;
  LastSeg:= AName;
  if Pos('.', LastSeg) > 0 then LastSeg:= Copy(LastSeg, LastDelimiter('.', LastSeg) + 1, MaxInt);
  for i:= AState.Symbols.Count - 1 downto 0 do
  begin
    Sym:= AState.Symbols[i];
    if (Sym.Kind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor]) and SameText(Sym.Name, LastSeg)
       and (SameText(Sym.QualifiedName, AName) or Sym.QualifiedName.EndsWith('.' + AName, True)) then
    begin
      // Exact-overload match: this defProc's start line was stamped onto its
      // symbol by SetRoutineImplRange. Prefer it; fall back to the first
      // name/qname match (records the candidate) if no line matches.
      if (AImplStartLine > 0) and (Sym.ImplStartLine = AImplStartLine) then Exit(i);
      if Result < 0 then Result:= i;
    end;
  end;
end; // function

{ v14 (D5, Task 3): emit each entry of a routine's local `var` section(s) as an
  skLocalVar symbol parented to the routine (ARoutineIdx), Signature = declared
  type text, so the call resolver (Task 5) can type a receiver that is a local.
  Scans ONLY THIS defProc's DIRECT `declVars` children -- never recurses -- so a
  nested procedure's own `declVars` (which lives inside the nested defProc child,
  not here) cannot leak into the outer routine. Grouped `X, Y: T` emits one symbol
  per name identifier, all sharing the one `type` child (parallel to params). }
procedure EmitRoutineLocals(const ADefProcNode: TTSNode; const AState: TWalkState; ARoutineIdx: Integer; const ARoutineQualifiedName: string);
var
  Section : TTSNode;
  DeclVar : TTSNode;
  Child   : TTSNode;
  TypeText: string ;
  VarName : string ;
  VarQN   : string ;
  i, j, k : Integer;
begin
  if ARoutineIdx < 0 then Exit;
  // Direct children of the defProc: declProc (header), zero+ declVars sections,
  // nested defProc(s), and the block. Process only the declVars sections here.
  for i:= 0 to ADefProcNode.NamedChildCount - 1 do
  begin
    Section:= ADefProcNode.NamedChild(i);
    if Section.NodeType <> 'declVars' then Continue;
    // Each declVars holds a `kVar` token plus one+ declVar entries.
    for j:= 0 to Section.NamedChildCount - 1 do
    begin
      DeclVar:= Section.NamedChild(j);
      if DeclVar.NodeType <> 'declVar' then Continue;
      // One shared type for every name in this declVar (grouped locals).
      TypeText:= TypeTextOf(DeclVar, AState.Source);
      // Ref-gap E: emit a type_use for a local var's declared type
      // (Local: Widget) so a type rename reaches it. EmitTypeUseReference
      // takes the typeref node inside the declVar's 'type' field.
      var LTypeField:= DeclVar.ChildByField('type');
      if not LTypeField.IsNull then
      begin
        var LTyperef:= FindNamedChildOfType(LTypeField, 'typeref');
        if not LTyperef.IsNull then EmitTypeUseReference(LTyperef, AState);
      end;
      // Emit one skLocalVar per direct 'identifier' child (the var names). The
      // type lives under a 'type' child, so only the name identifiers match.
      for k:= 0 to DeclVar.NamedChildCount - 1 do
      begin
        Child:= DeclVar.NamedChild(k);
        if Child.NodeType <> 'identifier' then Continue;
        VarName:= NodeText(Child, AState.Source);
        if VarName = '' then Continue;
        if ARoutineQualifiedName <> '' then VarQN:= ARoutineQualifiedName + '.' + VarName
        else VarQN:= VarName;
        // Range = the var-name identifier; parent = the routine; Signature =
        // the declared type text.
        AState.Emit(skLocalVar, VarName, VarQN, ARoutineIdx, Child, TypeText);
      end;
    end;
  end;
end; // procedure

// v8: walk a Spring4D fluent method-access chain (descend the lhs/entity spine of
// exprDot / exprTpl / exprCall nodes), collect (method, type-arg) links, classify
// via SpringDI, and emit DI facts. Type-arg text is the verbatim typeref source,
// so nested generics ('IDataService<ImcCAUSFAIL>') are preserved. Link order does
// not matter to ClassifyDiChain. Registrations are added to AState.DiBindings
// (persisted to di_bindings); resolutions/unresolved emit di-resolve/di-unresolved
// refs.
procedure TryEmitSpringDI(const AExpr: TTSNode; const AState: TWalkState);
var
  Links: TArray<TDiChainLink>;

  procedure AddLink(const AMethod, ATypeArg: string);
  var
    Lnk: TDiChainLink;
  begin
    Lnk.MethodName:= AMethod;
    Lnk.TypeArg:= Trim(ATypeArg);
    Links:= Links + [Lnk];
  end;

var
  Cur        : TTSNode      ;
  Entity     : TTSNode      ;
  ArgsNode   : TTSNode      ;
  RhsNode    : TTSNode      ;
  Outcome    : TDiOutcome   ;
  Binding    : TDiBinding   ;
  row        : TDiBindingRow;
  ResIntf    : string       ;
  UnresMethod: string       ;
  Guard      : Integer      ;
begin
  Links:= nil;
  Cur  := AExpr;
  Guard:= 0;
  while (not Cur.IsNull) and (Guard < 64) do
  begin
    Inc(Guard);
    if Cur.NodeType      = 'exprCall' then Cur:= Cur.ChildByField('entity')
    else if Cur.NodeType = 'exprTpl' then
    begin
      Entity  := Cur.ChildByField('entity');
      ArgsNode:= Cur.ChildByField('args'  );
      if (not Entity.IsNull) and (Entity.NodeType = 'exprDot') then
      begin
        RhsNode:= Entity.ChildByField('rhs');
        AddLink(NodeText(RhsNode, AState.Source), NodeText(ArgsNode, AState.Source));
        Cur:= Entity.ChildByField('lhs');
      end
      else if (not Entity.IsNull) and (Entity.NodeType = 'identifier') then
      begin
        AddLink(NodeText(Entity, AState.Source), NodeText(ArgsNode, AState.Source));
        Break;
      end
      else Cur:= Entity;
    end // if
    else if Cur.NodeType = 'exprDot' then
    begin
      RhsNode:= Cur.ChildByField('rhs');
      AddLink(NodeText(RhsNode, AState.Source), '');
      Cur:= Cur.ChildByField('lhs');
    end
    else Break;
  end; // while

  if Length(Links) = 0 then Exit;
  Outcome:= ClassifyDiChain(Links, Binding, ResIntf, UnresMethod);
  case Outcome of
    dioRegister:
    begin
      row:= Default(TDiBindingRow);
      row.InterfaceName:= Binding.InterfaceName;
      row.ImplName     := Binding.ImplName;
      row.Lifetime     := Binding.Lifetime;
      row.StartLine:= Integer(AExpr.StartPoint.row   ) + 1;
      row.StartCol := Integer(AExpr.StartPoint.column) + 1;
      row.EndLine  := Integer(AExpr.EndPoint  .row   ) + 1;
      row.EndCol   := Integer(AExpr.EndPoint  .column) + 1;
      AState.DiBindings.Add(row);
    end;
    dioResolve   : AState.EmitRef('di-resolve', ResIntf, AExpr)       ;
    dioUnresolved: AState.EmitRef('di-unresolved', UnresMethod, AExpr);
  end; // case
end; // begin

procedure Walk(const ANode: TTSNode; const AState: TWalkState; AParentSymbolIdx: Integer; const AParentQualifiedName: string);
var
  NodeType : string ;
  i        : Integer;
  IsInClass: Boolean;
begin
  if ANode.IsNull then Exit;
  NodeType:= ANode.NodeType;

  // v8: Spring4D DI edges. Registrations appear as a `statement` (no-paren fluent
  // chain) or `exprCall` (RegisterInstance<T>(...)); resolutions appear as the rhs
  // of an `assignment` or as a `statement`. Extract+classify the chain here;
  // normal recursion below still emits type_use refs for the type arguments.
  if (NodeType = 'statement') and (ANode.NamedChildCount >= 1) then TryEmitSpringDI(ANode.NamedChild(0), AState)
  else if NodeType = 'assignment' then TryEmitSpringDI(ANode.ChildByField('rhs'), AState);

  if NodeType = 'unit' then
  begin
    WalkUnit(ANode, AState);
    Exit;
  end;

  // v0.40.4: .dpr and .dpk roots also carry a top-level declUses.
  // Section is uusProgram or uusPackage respectively. We don't emit a
  // unit symbol here (no moduleName at the .dpr/.dpk top level in our model);
  // just harvest the uses entries.
  if (NodeType = 'program') or (NodeType = 'package') then
  begin
    for i:= 0 to ANode.NamedChildCount - 1 do
    begin
      var SectChild:= ANode.NamedChild(i);
      if SectChild.NodeType = 'declUses' then
      begin
        if NodeType = 'program' then WalkUsesClause(SectChild, AState, uusProgram)
        else WalkUsesClause(SectChild, AState, uusPackage);
      end;
    end;
    for i:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end; // if

  // declType wrapping a class/record/interface/enum declaration. Try each
  // shape in order; the first matching handler returns true and we're done.
  if NodeType = 'declType' then
  begin
    if TryWalkInterface    (ANode, AState, AParentSymbolIdx, AParentQualifiedName) then Exit;
    if TryWalkHelper       (ANode, AState, AParentSymbolIdx, AParentQualifiedName) then Exit; { v15: declHelper is distinct from declClass -- must be tried first or its target typeref gets grabbed by TryWalkAlias }
    if TryWalkClassOrRecord(ANode, AState, AParentSymbolIdx, AParentQualifiedName) then Exit;
    if TryWalkEnum         (ANode, AState, AParentSymbolIdx, AParentQualifiedName) then Exit;
    if TryWalkAlias        (ANode, AState, AParentSymbolIdx, AParentQualifiedName) then Exit; { v11 (M1) }
    // Unknown shape (set, subrange, proc-type, etc.) - fall through to default recurse.
  end;

  // declProc: emit a method (when inside class/record/interface) or a free
  // proc/func otherwise. Then walk children so typerefs in args + return
  // type emit type_use refs.
  if NodeType = 'declProc' then
  begin
    IsInClass:= (AParentSymbolIdx >= 0) and (AParentSymbolIdx < AState.Symbols.Count) and (AState.Symbols[AParentSymbolIdx].Kind in [skClass, skRecord, skInterface]);
    WalkDeclProc(ANode, AState, AParentSymbolIdx, AParentQualifiedName, IsInClass);
    for i:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end;

  // declField: emit a field symbol (always inside a class/record/interface).
  if NodeType = 'declField' then
  begin
    var FNameNode:= ANode.ChildByField('name');
    if not FNameNode.IsNull then
    begin
      var FName:= NodeText(FNameNode, AState.Source);
      if FName <> '' then
      begin
        var FQName: string;
        if AParentQualifiedName <> '' then FQName:= AParentQualifiedName + '.' + FName
        else FQName:= FName;
        AState.Emit(skField, FName, FQName, AParentSymbolIdx, ANode, TypeTextOf(ANode, AState.Source), AState.CurrentVisibility);
      end;
    end;
    // Walk children so the field's type is visited and emits a type_use ref.
    for i:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end; // if

  // declProp: emit a property symbol.
  if NodeType = 'declProp' then
  begin
    var PNameNode:= ANode.ChildByField('name');
    if not PNameNode.IsNull then
    begin
      var PName:= NodeText(PNameNode, AState.Source);
      if PName <> '' then
      begin
        var PQName: string;
        if AParentQualifiedName <> '' then PQName:= AParentQualifiedName + '.' + PName
        else PQName:= PName;
        { v17 (Task 6/R1): derive the read/write accessor shape from the declProp
          grammar's 'getter' (read) / 'setter' (write) fields
          (tree-sitter-delphi13 grammar.js: seq($.kRead, field('getter', $._ref)) /
          seq($.kWrite, field('setter', $._ref))). read only -> 'ro';
          read+write -> 'rw'; write only -> 'wo'; NEITHER (a bare
          'property Color;' redeclaration) -> '' so it inherits the ancestor's
          accessors at proptree time. Presence alone matters here -- the accessor
          identifier itself is irrelevant to writability. }
        var PHasGet:= not ANode.ChildByField('getter').IsNull;
        var PHasSet:= not ANode.ChildByField('setter').IsNull;
        var PAccess: string;
        if PHasGet and PHasSet then PAccess:= 'rw'
        else if PHasGet then PAccess:= 'ro'
        else if PHasSet then PAccess:= 'wo'
        else PAccess:= ''; // bare redeclaration -> NULL -> inherits ancestor's accessors
        AState.Emit(skProperty, PName, PQName, AParentSymbolIdx, ANode, TypeTextOf(ANode, AState.Source), AState.CurrentVisibility, '', False, False, PAccess);
      end;
    end;
    // Walk children so the property's type emits a type_use ref.
    for i:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end; // if

  // declSection: a visibility section inside a class/record/interface body.
  // Record the visibility so the members it contains carry it (UML glyphs),
  // then recurse into those members.
  if NodeType = 'declSection' then
  begin
    AState.CurrentVisibility:= VisibilityOfSection(ANode, AState.Source);
    for i:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end;

  // declConst: emit a constant symbol.  Covers unit-level const sections,
  // class consts, and resourcestrings (all are `declConst` items under a
  // `declConsts` section).  Without this, "where is this const defined?" could
  // never be answered from the index (resolve-uses).
  if NodeType = 'declConst' then
  begin
    var KNameNode:= ANode.ChildByField('name');
    if not KNameNode.IsNull then
    begin
      var KName:= NodeText(KNameNode, AState.Source);
      if KName <> '' then
      begin
        var KQName: string;
        if AParentQualifiedName <> '' then KQName:= AParentQualifiedName + '.' + KName
        else KQName:= KName;
        AState.Emit(skConstDecl, KName, KQName, AParentSymbolIdx, ANode);
      end;
    end;
    // Walk children so a typed const's type emits a type_use ref.
    for i:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end; // if

  // Implementation bodies. A routine declared in the interface (or class) is the
  // source of truth -- its `header:` defProc must NOT emit a duplicate. BUT a
  // TOP-LEVEL free routine defined ONLY in the implementation section has no such
  // declaration, so without this it would never be a symbol at all (query /
  // find-callers returned nothing). v0.48: emit those implementation-only free
  // routines. Nested locals (RoutineDepth > 0) and method bodies (qualified
  // 'TClass.Method' name) are still skipped -- their decl is the source.
  if NodeType = 'defProc' then
  begin
    if AState.RoutineDepth = 0 then
    begin
      var HdrNode:= ANode.ChildByField('header');
      if not HdrNode.IsNull then
      begin
        var HdrNameNode:= HdrNode.ChildByField('name');
        if not HdrNameNode.IsNull then
        begin
          var HdrName:= NodeText(HdrNameNode, AState.Source);
          // Ref-gap E: emit type_use refs for the type sites on a METHOD-impl
          // header (constructor/procedure/function Widget.Use(pParam: Widget): Widget).
          // A method impl header (name is a genericDot, i.e. Class.Method) is
          // NEVER routed through WalkDeclProc below -- that path is gated to free
          // routines (Pos('.')=0) -- so its qualifier, param types, and return
          // type would otherwise go unindexed, and a type-name-prefix rename
          // would leave them on the old name. We handle three sub-sites here:
          //   1. the class QUALIFIER (the 'Widget' before '.Use') -- genericDot lhs;
          //   2. the PARAM types -- walk the 'args' subtree so its typerefs emit;
          //   3. the RETURN type -- walk the 'type' field's typeref.
          // Walk() already emits type_use for every typeref it reaches (and
          // recurses into generics), so routing args/return through it is the
          // DRY way to cover grouped/generic param types too.
          if HdrNameNode.NodeType = 'genericDot' then
          begin
            var QualNode:= HdrNameNode.ChildByField('lhs');
            if (not QualNode.IsNull) and (QualNode.NodeType = 'identifier') then
              AState.EmitRef('type_use', NodeText(QualNode, AState.Source), QualNode);
            var ArgsNode:= HdrNode.ChildByField('args');
            if not ArgsNode.IsNull then Walk(ArgsNode, AState, AParentSymbolIdx, AParentQualifiedName);
            var RetTypeNode:= HdrNode.ChildByField('type');
            if not RetTypeNode.IsNull then Walk(RetTypeNode, AState, AParentSymbolIdx, AParentQualifiedName);
          end;
          if (HdrName <> '') and (Pos('.', HdrName) = 0) and not FreeRoutineSymbolExists(AState, HdrName) then
            WalkDeclProc(HdrNode, AState, AParentSymbolIdx, AParentQualifiedName, False);
          { v9: record this routine's body span on its symbol (decl or the
            impl-only one just emitted above). v(ADP1 Bug B): pass the impl
            header's own signature (built by the same ProcSignatureOf that
            produced the decl's stored Signature) so overloads disambiguate
            by signature, not just name -- see SetRoutineImplRange. }
          if HdrName <> '' then SetRoutineImplRange(AState, HdrName, Integer(ANode.StartPoint.row) + 1, Integer(ANode.EndPoint.row) + 1, ProcSignatureOf(HdrNode, AState.Source));
          { v14 (D5, Task 3): emit this routine's local `var` entries as skLocalVar
            symbols, parented to its (already-emitted) routine symbol. Only at
            RoutineDepth = 0 -- a nested proc is never walked here, so its locals
            do not leak. Uses the routine symbol's own unit-qualified name so the
            local's QualifiedName is 'Unit.TClass.Method.VarName'.
            DEFERRED (D5 fast-follow, T3): EmitRoutineLocals only scans this
            defProc's DIRECT `declVars` children (the classic `var` section
            before `begin`). A Delphi 10.3+ INLINE var -- `var X: T := ...;`
            declared mid-statement inside the `block` -- lives under a different
            node shape further down the body and is NOT visited here, so it is
            never emitted as an skLocalVar today. This is a known gap, not a
            bug: the call resolver (Task 5) still degrades gracefully (an
            inline-var receiver just stays untypable/'ambiguous' rather than
            resolving), so nothing silently gives a wrong answer. Picking up
            inline vars is future work if/when they show up as a real gap in
            receiver-typing coverage. }
          if HdrName <> '' then
          begin
            var RoutineIdx:= FindRoutineSymbolIndex(AState, HdrName, Integer(ANode.StartPoint.row) + 1);
            if RoutineIdx >= 0 then
              EmitRoutineLocals(ANode, AState, RoutineIdx, AState.Symbols[RoutineIdx].QualifiedName);
          end;
        end;
      end;
    end; // if
    var BodyNode:= ANode.ChildByField('body');
    if not BodyNode.IsNull then
    begin
      Inc(AState.RoutineDepth);
      try
        Walk(BodyNode, AState, AParentSymbolIdx, AParentQualifiedName);
      finally
        Dec(AState.RoutineDepth);
      end;
    end;
    Exit;
  end; // if

  // Call expression: emit a reference for the callee name. Walk into args for
  // nested calls.
  if NodeType = 'exprCall' then
  begin
    EmitCallReference(ANode, AState);
    for i:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end;

  // v0.40.5: bare statement-level procedure call (no parens). Pascal accepts
  //   foo;
  //   self.foo;
  //   obj.method;
  // The grammar parses these as `statement -> identifier|exprDot`. Without
  // emitting a ref here, find-callers misses every paren-less call -- the
  // common idiom for stateful procedures (RepointJobHeaderToFolder; etc).
  if NodeType = 'statement' then
  begin
    if ANode.NamedChildCount >= 1 then
    begin
      var ExprChild:= ANode.NamedChild(0);
      var ChildKind:= ExprChild.NodeType;
      if ChildKind      = 'identifier' then AState.EmitRef('call', NodeText(ExprChild, AState.Source), ExprChild)
      else if ChildKind = 'exprDot' then
      begin
        var RhsNode:= ExprChild.ChildByField('rhs');
        if not RhsNode.IsNull then AState.EmitRef('call', NodeText(RhsNode, AState.Source), RhsNode);
      end;
    end;
    for i:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end; // if

  // Type reference: emits a kind='type_use' reference and keeps walking
  // (typerefs can be nested in generic args).
  if NodeType = 'typeref' then
  begin
    EmitTypeUseReference(ANode, AState);
    for i:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end;

  // Ref-gap E: emit a type_use for the RHS type of an is/as test
  // (X is Widget). Gated to operator kIs/kAs so it does NOT fire on
  // arithmetic/comparison exprBinary nodes; RHS must be a bare identifier
  // (a type name), not a nested expression. No Exit -- the default recursion
  // below still walks lhs + children.
  if NodeType = 'exprBinary' then
  begin
    var OpNode:= ANode.ChildByField('operator');
    if (not OpNode.IsNull) and ((OpNode.NodeType = 'kIs') or (OpNode.NodeType = 'kAs')) then
    begin
      var RhsNode:= ANode.ChildByField('rhs');
      if (not RhsNode.IsNull) and (RhsNode.NodeType = 'identifier') then
        AState.EmitRef('type_use', NodeText(RhsNode, AState.Source), RhsNode);
    end;
  end;

  // v0.42: identifier usage references (deep scan only). Captures variable /
  // component / property usages so Find-Usages works beyond calls. Each handler
  // still recurses, so nested expressions are fully covered.
  if AState.EmitUsageRefs then
  begin
    // Member access `obj.Member` -> the BASE identifier is a usage of `obj`
    // (the dxDBGrid1 case). The member itself is captured as call/type_use
    // elsewhere; we don't re-emit it here.
    if NodeType = 'exprDot' then
    begin
      var L:= ANode.ChildByField('lhs');
      if (not L.IsNull) and (L.NodeType = 'identifier') then AState.EmitRef('read', NodeText(L, AState.Source), L);
      // Ref-gap D: capture the MEMBER of a Self.-qualified access (Self.field) as a
      // read of the field. Gated to lhs = Self so we do NOT flood refs with every
      // obj.Method / obj.Prop member access.
      if (not L.IsNull) and (L.NodeType = 'identifier') and SameText(Trim(NodeText(L, AState.Source)), 'Self') then
      begin
        var R:= ANode.ChildByField('rhs');
        if (not R.IsNull) and (R.NodeType = 'identifier') then AState.EmitRef('read', NodeText(R, AState.Source), R);
      end;
      // Ref-gap G: capture the MEMBER of a NON-Self dotted access (obj.Member) as a
      // 'member-access' ref, so the component-conversion applier can find instance-
      // scoped property/event access sites to rewrite. Complement of ref-gap D's
      // Self. gate: lhs must be a plain identifier and NOT Self (Self is D's 'read'),
      // and rhs must be a plain identifier. Chained (a.b.Member), call (f().Member),
      // and indexed (arr[i].Member) receivers are excluded -- each exprDot LEVEL with
      // a plain-identifier lhs emits its own member-access via the recursion below;
      // complex receivers are the future expression stage's problem. A DISTINCT kind
      // ('member-access') keeps existing read/write/type_use consumers untouched.
      if (not L.IsNull) and (L.NodeType = 'identifier')
         and (not SameText(Trim(NodeText(L, AState.Source)), 'Self')) then
      begin
        var RG:= ANode.ChildByField('rhs');
        if (not RG.IsNull) and (RG.NodeType = 'identifier') then
          AState.EmitRef('member-access', NodeText(RG, AState.Source), RG);
      end;
      for i:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
      Exit;
    end;

    // Assignment `X := ...` -> X is written; the RHS recurses as reads.
    if NodeType = 'assignment' then
    begin
      var Lhs:= ANode.ChildByField('lhs');
      if (not Lhs.IsNull) and (Lhs.NodeType = 'identifier') then AState.EmitRef('write', NodeText(Lhs, AState.Source), Lhs);
      // Bug B fix: a bare-identifier RHS (`Result := maxItems;`) is a READ of
      // that symbol, but a lone identifier that IS the whole RHS hits no case
      // in the generic recurse below (it is neither exprDot/exprArgs/etc.), so
      // it previously fell through with NO ref emitted. Handle it here, gated
      // strictly to the assignment's own 'rhs' field (confirmed on this same
      // grammar at line ~1114's `TryEmitSpringDI(ANode.ChildByField('rhs'),
      // ...)` for NodeType='assignment') -- this does NOT touch declaration-
      // name or type-name identifiers, which are never reached through this
      // case (Walk visits them via declVar/declProc/declType/typeref cases,
      // not via 'assignment'.rhs).
      var Rhs:= ANode.ChildByField('rhs');
      if (not Rhs.IsNull) and (Rhs.NodeType = 'identifier') then AState.EmitRef('read', NodeText(Rhs, AState.Source), Rhs);
      for i:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
      Exit;
    end;

    // A bare identifier passed as a call argument is a usage (`Foo(dxDBGrid1)`).
    if NodeType = 'exprArgs' then
    begin
      for i:= 0 to ANode.NamedChildCount - 1 do
      begin
        var Arg:= ANode.NamedChild(i);
        if Arg.NodeType = 'identifier' then AState.EmitRef('read', NodeText(Arg, AState.Source), Arg);
      end;
      for i:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
      Exit;
    end;

    // Custom attribute `[Foo]` usage.
    if NodeType = 'attribute' then
    begin
      var Aid:= FindNamedChildOfType(ANode, 'identifier');
      if not Aid.IsNull then AState.EmitRef('attribute', NodeText(Aid, AState.Source), Aid);
      for i:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
      Exit;
    end;
  end; // if

  // Default: recurse into named children
  for i:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
end; // procedure

type
  TParseReadCtx = class
    Bytes : TBytes;
    Buffer: TBytes;
  end;

  { TDelphi13Parser }

constructor TDelphi13Parser.Create;
begin
  inherited Create;
  FLanguage:= tree_sitter_delphi13;
end;

function TDelphi13Parser.LanguageName: string;
begin
  Result:= 'delphi13';
end;

function TDelphi13Parser.FileExtensions: TArray<string>;
begin
  // v0.42: .inc include files are parsed too. They are fragments (no unit
  // header), so symbols defined in them -- e.g. csmRed in CodeSiteMsgTypes.inc,
  // and many RTL/VCL platform consts -- would otherwise be invisible, because
  // tree-sitter does not expand the $INCLUDE directive into the including
  // unit. Walk() recurses into a fragment root and still fires the decl
  // handlers.
  Result:= ['.pas', '.dpr', '.dpk', '.inc'];
end;

// v10: collect every non-empty string literal for the text index.
// kind: 'resourcestring' if under a resourcestring section; 'const' if under a const section;
// 'format' if it carries a % specifier; else 'literal'. SymbolId left 0 (indexer resolves enclosing symbol).
function HarvestStringLiterals(const ARoot: TTSNode; const ASource: TBytes): TArray<TStringLiteral>;
var
  Acc: TList<TStringLiteral>;

  function DecodeLiteral(const ARaw: string): string;
  begin // strip outer quotes, unescape doubled quotes; leave #nn out of scope here
    Result:= ARaw;
    if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
      Result:= Copy(Result, 2, Length(Result) - 2);
    Result:= StringReplace(Result, '''''', '''', [rfReplaceAll]);
  end;

  function ClassifyKind(const N: TTSNode; const ADecoded: string): string;
  var Anc: TTSNode; AncT: string;
  begin
    Result:= 'literal';
    if Pos('%', ADecoded) > 0 then Result:= 'format';
    Anc:= N.Parent;
    while not Anc.IsNull do
    begin
      AncT:= Anc.NodeType;
      // const items are 'declConst' under a 'declConsts' section; the section's
      // leading text is the 'const' or 'resourcestring' keyword. (Verified vs the
      // working symbol walker, line ~851.)
      if AncT = 'declConsts' then
      begin
        if StartsText('resourcestring', TrimLeft(NodeText(Anc, ASource)))
          then Exit('resourcestring')
          else Exit('const');
      end;
      Anc:= Anc.Parent;
    end;
  end;

  procedure Visit(const N: TTSNode);
  var I: Integer; Lit: TStringLiteral; Raw, Dec: string; P: TTSPoint;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'literalString' then
    begin
      Raw:= NodeText(N, ASource);            // existing helper in this unit
      Dec:= DecodeLiteral(Raw);
      if Dec <> '' then
      begin
        Lit:= Default(TStringLiteral);
        Lit.Source:= 'pas';
        Lit.Kind  := ClassifyKind(N, Dec);
        Lit.Text  := Dec;
        P:= N.StartPoint; Lit.StartLine:= Integer(P.Row)+1; Lit.StartCol:= Integer(P.Column)+1;
        P:= N.EndPoint;   Lit.EndLine  := Integer(P.Row)+1; Lit.EndCol  := Integer(P.Column)+1;
        Acc.Add(Lit);
      end;
    end;
    for I:= 0 to N.ChildCount - 1 do Visit(N.Child(I));
  end;

begin
  Acc:= TList<TStringLiteral>.Create;
  try
    Visit(ARoot);
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

/// <summary>Walks the parse tree collecting ERROR/MISSING node positions into ADiags (max AMaxErrors).</summary>
/// <remarks>Only recurses into subtrees where HasError is set; exits early once the cap is reached.</remarks>
procedure CollectParseErrors(const ARoot: TTSNode; const AFilePath: string; var ADiags: TArray<string>; AMaxErrors, ADepth: Integer);
var
  ChildIdx: Integer;
  Child   : TTSNode;
  Pt      : TTSPoint;
begin
  if ARoot.IsNull then Exit;
  if ADepth > 30 then Exit;
  if Length(ADiags) >= AMaxErrors then Exit;
  if ARoot.IsError or ARoot.IsMissing then
  begin
    Pt:= ARoot.StartPoint;
    ADiags:= ADiags + [Format('%s(%d,%d): parse error [%s]', [AFilePath, Integer(Pt.row) + 1, Integer(Pt.column) + 1, ARoot.NodeType])];
    Exit; { don't descend into ERROR node's children - they are noise }
  end;
  if ARoot.HasError then
    for ChildIdx:= 0 to ARoot.ChildCount - 1 do
    begin
      if Length(ADiags) >= AMaxErrors then Break;
      Child:= ARoot.Child(ChildIdx);
      CollectParseErrors(Child, AFilePath, ADiags, AMaxErrors, ADepth + 1);
    end;
end;

function TDelphi13Parser.Parse(const ASource: TBytes; const AFilePath: string): TParseResult;
var
  Parser: TTSParser ;
  Tree  : TTSTree   ;
  Source: TBytes    ;
  State : TWalkState;
  Root  : TTSNode   ;
begin
  Result:= Default(TParseResult);
  Source:= ASource;
  Tree  := nil;
  Parser:= nil;
  State := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= FLanguage;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes var Remaining: Integer; begin Remaining:= Length(Source)
        - Integer(AByteIndex); if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end; SetLength(Result, Remaining); Move(Source[AByteIndex], Result[0],
          Remaining); ABytesRead:= Remaining; end, TTSInputEncoding.TSInputEncodingUTF8);

    State:= TWalkState.Create(Source);
    State.EmitUsageRefs:= EmitUsageRefs; { v0.42: deep scan }
    Root:= Tree.RootNode;
    if Root.HasError then CollectParseErrors(Root, AFilePath, Result.Diagnostics, 10, 0);
    Walk(Root, State, -1, '');
    Result.Symbols    := State.Symbols    .ToArray;
    Result.References := State.References .ToArray;
    Result.UsesEntries:= State.UsesEntries.ToArray;
    Result.DiBindings := State.DiBindings .ToArray;
    Result.Literals   := HarvestStringLiterals(Root, Source);
  finally
    State.Free;
    Tree.Free;
    Parser.Free;
  end; // try
end; // function

end.
