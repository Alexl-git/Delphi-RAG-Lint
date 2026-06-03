unit DRagLint.Parser.Delphi13;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  TreeSitter,
  TreeSitterLib,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces;

type
  TDelphi13Parser = class(TInterfacedObject, IParser)
  strict private
    FLanguage: PTSLanguage;
  public
    constructor Create;
    function LanguageName: string;
    function FileExtensions: TArray<string>;
    function Parse(const ASource: TBytes; const AFilePath: string): TParseResult;
  end;

function tree_sitter_delphi13: PTSLanguage; cdecl;
  external 'tree-sitter-delphi13';

implementation

function NodeText(const ANode: TTSNode; const ASource: TBytes): string;
var
  StartIdx, EndIdx, Len: Integer;
begin
  Result := '';
  if ANode.IsNull then
    Exit;
  StartIdx := Integer(ANode.StartByte);
  EndIdx := Integer(ANode.EndByte);
  Len := EndIdx - StartIdx;
  if (Len <= 0) or (StartIdx < 0) or (EndIdx > Length(ASource)) then
    Exit;
  Result := TEncoding.UTF8.GetString(ASource, StartIdx, Len);
end;

function FindNamedChildOfType(const AParent: TTSNode;
  const AType: string): TTSNode;
var
  i: Integer;
  Child: TTSNode;
begin
  // Default(TTSNode) is the null sentinel - ts_node_is_null() returns true
  // for a zero-filled record. Avoid AParent.Child(-1) which casts -1 to
  // UInt32 and trips ERangeError under {$R+}.
  Result := Default(TTSNode);
  for i := 0 to AParent.NamedChildCount - 1 do
  begin
    Child := AParent.NamedChild(i);
    if Child.NodeType = AType then
      Exit(Child);
  end;
end;

type
  TWalkState = class
    Source: TBytes;
    Symbols: TList<TSymbol>;
    References: TList<TReference>;
    UsesEntries: TList<TUnitUse>;  { v0.40.4 }
    { Current member visibility while walking a class/record body -- set by the
      declSection handler ('public'/'private'/'protected'/'published', with a
      'strict ' prefix when applicable) and stamped into each member's
      Modifiers.  Drives the UML visibility glyphs (+/-/#/~) in the graph. }
    CurrentVisibility: string;
    { 'interface' | 'implementation' | '' -- which unit section the current
      symbol lives in; stamped into TSymbol.Section by Emit (agent gap #3:
      tells whether a symbol is usable from another unit). }
    CurrentSection: string;
    constructor Create(const ASource: TBytes);
    destructor Destroy; override;
    function Emit(AKind: TSymbolKind; const AName, AQualifiedName: string;
      AParentSymbolIdx: Integer; const ARangeNode: TTSNode;
      const ASignature: string = ''; const AModifiers: string = ''): Integer;
    procedure EmitRef(const AKind, ANameText: string; const ARangeNode: TTSNode);
    procedure EmitUnitUse(const AUnitName, AInPath: string;
      ASection: TUnitUseSection; const ARangeNode: TTSNode);
  end;

constructor TWalkState.Create(const ASource: TBytes);
begin
  inherited Create;
  Source := ASource;
  Symbols := TList<TSymbol>.Create;
  References := TList<TReference>.Create;
  UsesEntries := TList<TUnitUse>.Create;
end;

destructor TWalkState.Destroy;
begin
  Symbols.Free;
  References.Free;
  UsesEntries.Free;
  inherited;
end;

procedure TWalkState.EmitUnitUse(const AUnitName, AInPath: string;
  ASection: TUnitUseSection; const ARangeNode: TTSNode);
var
  U: TUnitUse;
  Stem: string;
  DotPos: Integer;
begin
  if AUnitName = '' then Exit;
  U.FileId    := -1;  { indexer will fill in from files table }
  U.UnitName  := AUnitName;
  U.Section   := ASection;
  U.InPath    := AInPath;
  U.StartLine := Integer(ARangeNode.StartPoint.row) + 1;
  U.StartCol  := Integer(ARangeNode.StartPoint.column) + 1;
  U.EndLine   := Integer(ARangeNode.EndPoint.row) + 1;
  U.EndCol    := Integer(ARangeNode.EndPoint.column) + 1;
  UsesEntries.Add(U);
  { Suppress hint: Stem reserved for a future normalize-here path. }
  Stem := AUnitName;
  DotPos := LastDelimiter('.', Stem);
  if DotPos > 0 then Stem := Copy(Stem, DotPos + 1, MaxInt);
end;

procedure TWalkState.EmitRef(const AKind, ANameText: string;
  const ARangeNode: TTSNode);
var
  Ref: TReference;
begin
  if ARangeNode.IsNull or (ANameText = '') then
    Exit;
  Ref := Default(TReference);
  Ref.Kind := AKind;
  Ref.NameText := ANameText;
  Ref.SymbolId := 0;  // unresolved at parse time
  Ref.StartLine := Integer(ARangeNode.StartPoint.row) + 1;
  Ref.StartCol := Integer(ARangeNode.StartPoint.column) + 1;
  Ref.EndLine := Integer(ARangeNode.EndPoint.row) + 1;
  Ref.EndCol := Integer(ARangeNode.EndPoint.column) + 1;
  References.Add(Ref);
end;

function TWalkState.Emit(AKind: TSymbolKind; const AName, AQualifiedName: string;
  AParentSymbolIdx: Integer; const ARangeNode: TTSNode;
  const ASignature, AModifiers: string): Integer;
var
  Sym: TSymbol;
begin
  Sym := Default(TSymbol);
  Sym.Kind := AKind;
  Sym.Name := AName;
  Sym.QualifiedName := AQualifiedName;
  Sym.Signature := ASignature;
  Sym.Modifiers := AModifiers;
  Sym.Section := CurrentSection;
  if AParentSymbolIdx >= 0 then
    Sym.ParentId := AParentSymbolIdx
  else
    Sym.ParentId := -1;
  if not ARangeNode.IsNull then
  begin
    Sym.StartLine := Integer(ARangeNode.StartPoint.row) + 1;
    Sym.StartCol := Integer(ARangeNode.StartPoint.column) + 1;
    Sym.EndLine := Integer(ARangeNode.EndPoint.row) + 1;
    Sym.EndCol := Integer(ARangeNode.EndPoint.column) + 1;
  end;
  Symbols.Add(Sym);
  Result := Symbols.Count - 1;
end;

procedure Walk(const ANode: TTSNode; const AState: TWalkState;
  AParentSymbolIdx: Integer; const AParentQualifiedName: string); forward;

// v0.8: every `typeref` node that appears in a parameter type, field type,
// inheritance clause, etc. emits a kind='type_use' reference. This lets
// `find-callers` / LSP references answer "where is type X used?" not just
// "where is method X called?".
procedure EmitTypeUseReference(const ANode: TTSNode; const AState: TWalkState);
var
  Child: TTSNode;
  RefName: string;
begin
  // A typeref is (typeref (identifier "TFoo")) or sometimes
  // (typeref (genericDot lhs: id operator: kDot rhs: id)) for qualified types
  // and (typeref (identifier) (declTypeArgs ...)) for generics. Take the
  // first named-child identifier-shaped thing.
  if ANode.NamedChildCount = 0 then Exit;
  Child := ANode.NamedChild(0);
  if Child.NodeType = 'identifier' then
    RefName := NodeText(Child, AState.Source)
  else if Child.NodeType = 'genericDot' then
  begin
    // qualified: take rhs
    var Rhs := Child.ChildByField('rhs');
    if not Rhs.IsNull then
      RefName := NodeText(Rhs, AState.Source)
    else
      Exit;
    Child := Rhs;
  end
  else
    Exit;
  if RefName = '' then Exit;
  AState.EmitRef('type_use', RefName, Child);
end;

procedure EmitCallReference(const ANode: TTSNode; const AState: TWalkState);
var
  EntityNode, NameNode: TTSNode;
  CalleeName: string;
begin
  EntityNode := ANode.ChildByField('entity');
  if EntityNode.IsNull then
    Exit;
  if EntityNode.NodeType = 'identifier' then
    NameNode := EntityNode
  else if EntityNode.NodeType = 'exprDot' then
  begin
    NameNode := EntityNode.ChildByField('rhs');
    if NameNode.IsNull then
      Exit;
  end
  else
    Exit;
  CalleeName := NodeText(NameNode, AState.Source);
  if CalleeName = '' then
    Exit;
  AState.EmitRef('call', CalleeName, NameNode);
end;

// v0.40.4: extract the literal string body from a `kIn literalString` pair
// inside a declUsesUnit. Strips the surrounding single quotes.
function ExtractInPath(const ALitNode: TTSNode; const ASource: TBytes): string;
begin
  Result := NodeText(ALitNode, ASource);
  if (Length(Result) >= 2) and (Result[1] = '''') and
     (Result[Length(Result)] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

// v0.40.4: walk a declUses node, emitting one TUnitUse per declUsesUnit child.
procedure WalkUsesClause(const ANode: TTSNode; const AState: TWalkState;
  ASection: TUnitUseSection);
var
  I, J:        Integer;
  Child, Sub:  TTSNode;
  ModNode:     TTSNode;
  LitNode:     TTSNode;
  UnitName:    string;
  InPath:      string;
begin
  for I := 0 to ANode.NamedChildCount - 1 do
  begin
    Child := ANode.NamedChild(I);
    if Child.NodeType <> 'declUsesUnit' then Continue;
    ModNode := Default(TTSNode);
    LitNode := Default(TTSNode);
    for J := 0 to Child.NamedChildCount - 1 do
    begin
      Sub := Child.NamedChild(J);
      if      Sub.NodeType = 'moduleName'    then ModNode := Sub
      else if Sub.NodeType = 'literalString' then LitNode := Sub;
    end;
    if ModNode.IsNull then Continue;
    UnitName := Trim(NodeText(ModNode, AState.Source));
    if UnitName = '' then Continue;
    InPath := '';
    if not LitNode.IsNull then InPath := ExtractInPath(LitNode, AState.Source);
    AState.EmitUnitUse(UnitName, InPath, ASection, Child);
  end;
end;

// v0.40.4: walk a unit's interface or implementation section, looking for a
// declUses child and emitting its entries under the appropriate section.
procedure WalkSection(const ASectionNode: TTSNode; const AState: TWalkState;
  ASection: TUnitUseSection);
var
  I:     Integer;
  Child: TTSNode;
begin
  for I := 0 to ASectionNode.NamedChildCount - 1 do
  begin
    Child := ASectionNode.NamedChild(I);
    if Child.NodeType = 'declUses' then
      WalkUsesClause(Child, AState, ASection);
  end;
end;

procedure WalkUnit(const ANode: TTSNode; const AState: TWalkState);
var
  ModNode: TTSNode;
  UnitName: string;
  UnitIdx, i: Integer;
  Child: TTSNode;
begin
  ModNode := FindNamedChildOfType(ANode, 'moduleName');
  if ModNode.IsNull then
    Exit;
  // Take the full text of moduleName so multi-segment unit names like
  // DRagLint.Core.Interfaces are preserved verbatim. Earlier impl grabbed
  // only the first identifier and lost everything after the dot.
  UnitName := Trim(NodeText(ModNode, AState.Source));
  if UnitName = '' then
    Exit;
  AState.CurrentSection := '';        { the unit symbol itself is section-less }
  UnitIdx := AState.Emit(skUnit, UnitName, UnitName, -1, ANode);

  // v0.40.4: explicitly walk interface/implementation children to extract
  // their `declUses` entries under the correct section.
  for i := 0 to ANode.NamedChildCount - 1 do
  begin
    Child := ANode.NamedChild(i);
    if      Child.NodeType = 'interface'      then WalkSection(Child, AState, uusInterface)
    else if Child.NodeType = 'implementation' then WalkSection(Child, AState, uusImplementation);
  end;

  { Stamp each symbol with the unit section it is declared in (gap #3): set
    CurrentSection as we descend into the interface vs implementation child. }
  for i := 0 to ANode.NamedChildCount - 1 do
  begin
    Child := ANode.NamedChild(i);
    if      Child.NodeType = 'interface'      then AState.CurrentSection := 'interface'
    else if Child.NodeType = 'implementation' then AState.CurrentSection := 'implementation';
    Walk(Child, AState, UnitIdx, UnitName);
  end;
  AState.CurrentSection := '';
end;

// Determines whether a declClass node is actually a record (first token is
// kRecord) versus a regular class (kClass). The grammar reuses declClass for
// both shapes; the kind is carried by the leading token child.
function ClassNodeIsRecord(const AClassNode: TTSNode): Boolean;
var
  i: Integer;
  C: TTSNode;
  T: string;
begin
  Result := False;
  for i := 0 to AClassNode.ChildCount - 1 do
  begin
    C := AClassNode.Child(i);
    T := C.NodeType;
    if T = 'kClass' then Exit(False);
    if T = 'kRecord' then Exit(True);
  end;
end;

// Read the visibility of a declSection node ('private'/'protected'/'public'/
// 'published', prefixed 'strict ' when applicable).  Defaults to 'public'.
function VisibilityOfSection(const ANode: TTSNode; const ASource: TBytes): string;
var
  i: Integer;
  C: TTSNode;
  NT, Vis: string;
  IsStrict: Boolean;
begin
  IsStrict := False;
  Vis := '';
  for i := 0 to ANode.NamedChildCount - 1 do
  begin
    C := ANode.NamedChild(i);
    NT := C.NodeType;
    if NT = 'kStrict' then IsStrict := True
    else if NT = 'kPrivate' then Vis := 'private'
    else if NT = 'kProtected' then Vis := 'protected'
    else if NT = 'kPublic' then Vis := 'public'
    else if NT = 'kPublished' then Vis := 'published'
    else if Vis <> '' then Break;  // past the keyword(s), into members
  end;
  if Vis = '' then Vis := 'public';
  if IsStrict and ((Vis = 'private') or (Vis = 'protected')) then
    Result := 'strict ' + Vis
  else
    Result := Vis;
end;

function TryWalkClassOrRecord(const ADeclTypeNode: TTSNode;
  const AState: TWalkState; AParentSymbolIdx: Integer;
  const AParentQualifiedName: string): Boolean;
var
  TypeWrapNode, ClassNode, NameNode: TTSNode;
  TypeName, QName, OldVis: string;
  TypeIdx, i: Integer;
  Kind: TSymbolKind;
begin
  Result := False;
  TypeWrapNode := ADeclTypeNode.ChildByField('type');
  if TypeWrapNode.IsNull then
    Exit;
  ClassNode := FindNamedChildOfType(TypeWrapNode, 'declClass');
  if ClassNode.IsNull then
    Exit;
  NameNode := ADeclTypeNode.ChildByField('name');
  if NameNode.IsNull then
    Exit;
  TypeName := NodeText(NameNode, AState.Source);
  if TypeName = '' then
    Exit;
  if AParentQualifiedName <> '' then
    QName := AParentQualifiedName + '.' + TypeName
  else
    QName := TypeName;
  if ClassNodeIsRecord(ClassNode) then
    Kind := skRecord
  else
    Kind := skClass;
  TypeIdx := AState.Emit(Kind, TypeName, QName, AParentSymbolIdx, ADeclTypeNode);
  { Members before any visibility keyword default to 'public'; declSection
    handlers update it as they are walked.  Save/restore so a nested type does
    not leak its sections to the enclosing one. }
  OldVis := AState.CurrentVisibility;
  AState.CurrentVisibility := 'public';
  for i := 0 to ClassNode.NamedChildCount - 1 do
    Walk(ClassNode.NamedChild(i), AState, TypeIdx, QName);
  AState.CurrentVisibility := OldVis;
  Result := True;
end;

function TryWalkInterface(const ADeclTypeNode: TTSNode;
  const AState: TWalkState; AParentSymbolIdx: Integer;
  const AParentQualifiedName: string): Boolean;
var
  TypeNode, NameNode: TTSNode;
  TypeName, QName, OldVis: string;
  Idx, i: Integer;
begin
  Result := False;
  TypeNode := ADeclTypeNode.ChildByField('type');
  // declIntf is the `type:` child directly - not wrapped in (type).
  if TypeNode.IsNull or (TypeNode.NodeType <> 'declIntf') then
    Exit;
  NameNode := ADeclTypeNode.ChildByField('name');
  if NameNode.IsNull then
    Exit;
  TypeName := NodeText(NameNode, AState.Source);
  if TypeName = '' then
    Exit;
  if AParentQualifiedName <> '' then
    QName := AParentQualifiedName + '.' + TypeName
  else
    QName := TypeName;
  Idx := AState.Emit(skInterface, TypeName, QName, AParentSymbolIdx,
    ADeclTypeNode);
  { All interface members are public. }
  OldVis := AState.CurrentVisibility;
  AState.CurrentVisibility := 'public';
  for i := 0 to TypeNode.NamedChildCount - 1 do
    Walk(TypeNode.NamedChild(i), AState, Idx, QName);
  AState.CurrentVisibility := OldVis;
  Result := True;
end;

function TryWalkEnum(const ADeclTypeNode: TTSNode; const AState: TWalkState;
  AParentSymbolIdx: Integer; const AParentQualifiedName: string): Boolean;
var
  TypeWrapNode, EnumNode, NameNode, ValNode, ValNameNode: TTSNode;
  TypeName, QName, ValName: string;
  EnumIdx, i: Integer;
begin
  Result := False;
  TypeWrapNode := ADeclTypeNode.ChildByField('type');
  if TypeWrapNode.IsNull then
    Exit;
  EnumNode := FindNamedChildOfType(TypeWrapNode, 'declEnum');
  if EnumNode.IsNull then
    Exit;
  NameNode := ADeclTypeNode.ChildByField('name');
  if NameNode.IsNull then
    Exit;
  TypeName := NodeText(NameNode, AState.Source);
  if TypeName = '' then
    Exit;
  if AParentQualifiedName <> '' then
    QName := AParentQualifiedName + '.' + TypeName
  else
    QName := TypeName;
  EnumIdx := AState.Emit(skEnum, TypeName, QName, AParentSymbolIdx, ADeclTypeNode);
  // Emit each enum value as a child symbol
  for i := 0 to EnumNode.NamedChildCount - 1 do
  begin
    ValNode := EnumNode.NamedChild(i);
    if ValNode.NodeType = 'declEnumValue' then
    begin
      ValNameNode := ValNode.ChildByField('name');
      if not ValNameNode.IsNull then
      begin
        ValName := NodeText(ValNameNode, AState.Source);
        if ValName <> '' then
          AState.Emit(skEnumValue, ValName, QName + '.' + ValName, EnumIdx,
            ValNode);
      end;
    end;
  end;
  Result := True;
end;

// Text of a node's `type:` field (field/property/const type, or a proc's
// return type), whitespace-collapsed. Empty when there is no type child.
function TypeTextOf(const ANode: TTSNode; const ASource: TBytes): string;
var
  T: TTSNode;
  i: Integer;
  Raw: string;
  C: Char;
  PrevSpace: Boolean;
begin
  Result := '';
  T := ANode.ChildByField('type');
  if T.IsNull then Exit;
  Raw := NodeText(T, ASource);
  { collapse runs of whitespace to single spaces so multi-line types read well }
  PrevSpace := False;
  for i := 1 to Length(Raw) do
  begin
    C := Raw[i];
    if (C = #9) or (C = #10) or (C = #13) or (C = ' ') then
    begin
      if not PrevSpace then Result := Result + ' ';
      PrevSpace := True;
    end
    else
    begin
      Result := Result + C;
      PrevSpace := False;
    end;
  end;
  Result := Trim(Result);
end;

procedure WalkDeclProc(const ANode: TTSNode; const AState: TWalkState;
  AParentSymbolIdx: Integer; const AParentQualifiedName: string;
  AAsMethod: Boolean);
var
  NameNode, FirstTok: TTSNode;
  MethName, QName, Modifiers: string;
  Kind: TSymbolKind;
begin
  NameNode := ANode.ChildByField('name');
  if NameNode.IsNull then
    Exit;
  MethName := NodeText(NameNode, AState.Source);
  if MethName = '' then
    Exit;
  // Strip qualified prefix if present (e.g. 'TFoo.DoBar' -> 'DoBar') - happens in
  // free implementations. For interface/class declarations the name is bare.
  if Pos('.', MethName) > 0 then
    MethName := Copy(MethName, LastDelimiter('.', MethName) + 1, MaxInt);
  if AAsMethod then
    Kind := skMethod
  else
  begin
    // Determine procedure vs function by inspecting the first token child
    Kind := skProcedure;
    if ANode.ChildCount > 0 then
    begin
      FirstTok := ANode.Child(0);
      if FirstTok.NodeType = 'kFunction' then
        Kind := skFunction
      else if FirstTok.NodeType = 'kConstructor' then
        Kind := skConstructor
      else if FirstTok.NodeType = 'kDestructor' then
        Kind := skDestructor;
    end;
  end;
  if AParentQualifiedName <> '' then
    QName := AParentQualifiedName + '.' + MethName
  else
    QName := MethName;
  { Methods carry their class visibility (UML glyphs); free procs do not. }
  if AAsMethod then
    Modifiers := AState.CurrentVisibility
  else
    Modifiers := '';
  { Signature = the return type (functions); blank for procedures. }
  AState.Emit(Kind, MethName, QName, AParentSymbolIdx, ANode,
    TypeTextOf(ANode, AState.Source), Modifiers);
end;

procedure Walk(const ANode: TTSNode; const AState: TWalkState;
  AParentSymbolIdx: Integer; const AParentQualifiedName: string);
var
  NodeType: string;
  i: Integer;
  IsInClass: Boolean;
begin
  if ANode.IsNull then
    Exit;
  NodeType := ANode.NodeType;

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
    for i := 0 to ANode.NamedChildCount - 1 do
    begin
      var SectChild := ANode.NamedChild(i);
      if SectChild.NodeType = 'declUses' then
      begin
        if NodeType = 'program' then
          WalkUsesClause(SectChild, AState, uusProgram)
        else
          WalkUsesClause(SectChild, AState, uusPackage);
      end;
    end;
    for i := 0 to ANode.NamedChildCount - 1 do
      Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end;

  // declType wrapping a class/record/interface/enum declaration. Try each
  // shape in order; the first matching handler returns true and we're done.
  if NodeType = 'declType' then
  begin
    if TryWalkInterface(ANode, AState, AParentSymbolIdx, AParentQualifiedName) then
      Exit;
    if TryWalkClassOrRecord(ANode, AState, AParentSymbolIdx, AParentQualifiedName) then
      Exit;
    if TryWalkEnum(ANode, AState, AParentSymbolIdx, AParentQualifiedName) then
      Exit;
    // Unknown shape (type alias, set, etc.) - fall through to default recurse.
  end;

  // declProc: emit a method (when inside class/record/interface) or a free
  // proc/func otherwise. Then walk children so typerefs in args + return
  // type emit type_use refs.
  if NodeType = 'declProc' then
  begin
    IsInClass := (AParentSymbolIdx >= 0) and
      (AParentSymbolIdx < AState.Symbols.Count) and
      (AState.Symbols[AParentSymbolIdx].Kind in
       [skClass, skRecord, skInterface]);
    WalkDeclProc(ANode, AState, AParentSymbolIdx, AParentQualifiedName, IsInClass);
    for i := 0 to ANode.NamedChildCount - 1 do
      Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end;

  // declField: emit a field symbol (always inside a class/record/interface).
  if NodeType = 'declField' then
  begin
    var FNameNode := ANode.ChildByField('name');
    if not FNameNode.IsNull then
    begin
      var FName := NodeText(FNameNode, AState.Source);
      if FName <> '' then
      begin
        var FQName: string;
        if AParentQualifiedName <> '' then
          FQName := AParentQualifiedName + '.' + FName
        else
          FQName := FName;
        AState.Emit(skField, FName, FQName, AParentSymbolIdx, ANode,
          TypeTextOf(ANode, AState.Source), AState.CurrentVisibility);
      end;
    end;
    // Walk children so the field's type is visited and emits a type_use ref.
    for i := 0 to ANode.NamedChildCount - 1 do
      Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end;

  // declProp: emit a property symbol.
  if NodeType = 'declProp' then
  begin
    var PNameNode := ANode.ChildByField('name');
    if not PNameNode.IsNull then
    begin
      var PName := NodeText(PNameNode, AState.Source);
      if PName <> '' then
      begin
        var PQName: string;
        if AParentQualifiedName <> '' then
          PQName := AParentQualifiedName + '.' + PName
        else
          PQName := PName;
        AState.Emit(skProperty, PName, PQName, AParentSymbolIdx, ANode,
          TypeTextOf(ANode, AState.Source), AState.CurrentVisibility);
      end;
    end;
    // Walk children so the property's type emits a type_use ref.
    for i := 0 to ANode.NamedChildCount - 1 do
      Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end;

  // declSection: a visibility section inside a class/record/interface body.
  // Record the visibility so the members it contains carry it (UML glyphs),
  // then recurse into those members.
  if NodeType = 'declSection' then
  begin
    AState.CurrentVisibility := VisibilityOfSection(ANode, AState.Source);
    for i := 0 to ANode.NamedChildCount - 1 do
      Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end;

  // declConst: emit a constant symbol.  Covers unit-level const sections,
  // class consts, and resourcestrings (all are `declConst` items under a
  // `declConsts` section).  Without this, "where is this const defined?" could
  // never be answered from the index (resolve-uses).
  if NodeType = 'declConst' then
  begin
    var KNameNode := ANode.ChildByField('name');
    if not KNameNode.IsNull then
    begin
      var KName := NodeText(KNameNode, AState.Source);
      if KName <> '' then
      begin
        var KQName: string;
        if AParentQualifiedName <> '' then
          KQName := AParentQualifiedName + '.' + KName
        else
          KQName := KName;
        AState.Emit(skConstDecl, KName, KQName, AParentSymbolIdx, ANode);
      end;
    end;
    // Walk children so a typed const's type emits a type_use ref.
    for i := 0 to ANode.NamedChildCount - 1 do
      Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end;

  // Implementation bodies: don't emit a duplicate symbol from the `header:`
  // declProc (the interface decl is the source of truth). Walk only the
  // `body:` so call expressions inside produce TReference records.
  if NodeType = 'defProc' then
  begin
    var BodyNode := ANode.ChildByField('body');
    if not BodyNode.IsNull then
      Walk(BodyNode, AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end;

  // Call expression: emit a reference for the callee name. Walk into args for
  // nested calls.
  if NodeType = 'exprCall' then
  begin
    EmitCallReference(ANode, AState);
    for i := 0 to ANode.NamedChildCount - 1 do
      Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
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
      var ExprChild := ANode.NamedChild(0);
      var ChildKind := ExprChild.NodeType;
      if ChildKind = 'identifier' then
        AState.EmitRef('call', NodeText(ExprChild, AState.Source), ExprChild)
      else if ChildKind = 'exprDot' then
      begin
        var RhsNode := ExprChild.ChildByField('rhs');
        if not RhsNode.IsNull then
          AState.EmitRef('call', NodeText(RhsNode, AState.Source), RhsNode);
      end;
    end;
    for i := 0 to ANode.NamedChildCount - 1 do
      Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end;

  // Type reference: emits a kind='type_use' reference and keeps walking
  // (typerefs can be nested in generic args).
  if NodeType = 'typeref' then
  begin
    EmitTypeUseReference(ANode, AState);
    for i := 0 to ANode.NamedChildCount - 1 do
      Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
    Exit;
  end;

  // Default: recurse into named children
  for i := 0 to ANode.NamedChildCount - 1 do
    Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
end;

type
  TParseReadCtx = class
    Bytes: TBytes;
    Buffer: TBytes;
  end;

{ TDelphi13Parser }

constructor TDelphi13Parser.Create;
begin
  inherited Create;
  FLanguage := tree_sitter_delphi13;
end;

function TDelphi13Parser.LanguageName: string;
begin
  Result := 'delphi13';
end;

function TDelphi13Parser.FileExtensions: TArray<string>;
begin
  Result := ['.pas', '.dpr', '.dpk'];
end;

function TDelphi13Parser.Parse(const ASource: TBytes;
  const AFilePath: string): TParseResult;
var
  Parser: TTSParser;
  Tree: TTSTree;
  Source: TBytes;
  State: TWalkState;
  Root: TTSNode;
begin
  Result := Default(TParseResult);
  Source := ASource;
  Tree := nil;
  Parser := nil;
  State := nil;
  try
    Parser := TTSParser.Create;
    Parser.Language := FLanguage;
    Tree := Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint;
        var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining := Length(Source) - Integer(AByteIndex);
        if Remaining <= 0 then
        begin
          ABytesRead := 0;
          SetLength(Result, 0);
          Exit;
        end;
        SetLength(Result, Remaining);
        Move(Source[AByteIndex], Result[0], Remaining);
        ABytesRead := Remaining;
      end,
      TTSInputEncoding.TSInputEncodingUTF8);

    State := TWalkState.Create(Source);
    Root := Tree.RootNode;
    if Root.HasError then
      Result.Diagnostics := ['parse contains syntax errors (Tree.RootNode.HasError = true)'];
    Walk(Root, State, -1, '');
    Result.Symbols := State.Symbols.ToArray;
    Result.References := State.References.ToArray;
    Result.UsesEntries := State.UsesEntries.ToArray;
  finally
    State.Free;
    Tree.Free;
    Parser.Free;
  end;
end;

end.
