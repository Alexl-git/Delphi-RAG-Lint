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
  // Default(TTSNode) is the null sentinel — ts_node_is_null() returns true
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
    constructor Create(const ASource: TBytes);
    destructor Destroy; override;
    function Emit(AKind: TSymbolKind; const AName, AQualifiedName: string;
      AParentSymbolIdx: Integer; const ARangeNode: TTSNode;
      const ASignature: string = ''; const AModifiers: string = ''): Integer;
    procedure EmitRef(const AKind, ANameText: string; const ARangeNode: TTSNode);
  end;

constructor TWalkState.Create(const ASource: TBytes);
begin
  inherited Create;
  Source := ASource;
  Symbols := TList<TSymbol>.Create;
  References := TList<TReference>.Create;
end;

destructor TWalkState.Destroy;
begin
  Symbols.Free;
  References.Free;
  inherited;
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

procedure WalkUnit(const ANode: TTSNode; const AState: TWalkState);
var
  ModNode, IdNode: TTSNode;
  UnitName: string;
  UnitIdx, i: Integer;
begin
  ModNode := FindNamedChildOfType(ANode, 'moduleName');
  if ModNode.IsNull then
    Exit;
  IdNode := FindNamedChildOfType(ModNode, 'identifier');
  if IdNode.IsNull then
    Exit;
  UnitName := NodeText(IdNode, AState.Source);
  UnitIdx := AState.Emit(skUnit, UnitName, UnitName, -1, ANode);
  for i := 0 to ANode.NamedChildCount - 1 do
    Walk(ANode.NamedChild(i), AState, UnitIdx, UnitName);
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

function TryWalkClassOrRecord(const ADeclTypeNode: TTSNode;
  const AState: TWalkState; AParentSymbolIdx: Integer;
  const AParentQualifiedName: string): Boolean;
var
  TypeWrapNode, ClassNode, NameNode: TTSNode;
  TypeName, QName: string;
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
  for i := 0 to ClassNode.NamedChildCount - 1 do
    Walk(ClassNode.NamedChild(i), AState, TypeIdx, QName);
  Result := True;
end;

function TryWalkInterface(const ADeclTypeNode: TTSNode;
  const AState: TWalkState; AParentSymbolIdx: Integer;
  const AParentQualifiedName: string): Boolean;
var
  TypeNode, NameNode: TTSNode;
  TypeName, QName: string;
  Idx, i: Integer;
begin
  Result := False;
  TypeNode := ADeclTypeNode.ChildByField('type');
  // declIntf is the `type:` child directly — not wrapped in (type).
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
  for i := 0 to TypeNode.NamedChildCount - 1 do
    Walk(TypeNode.NamedChild(i), AState, Idx, QName);
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
  // Strip qualified prefix if present (e.g. 'TFoo.DoBar' -> 'DoBar') — happens in
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
  Modifiers := '';
  AState.Emit(Kind, MethName, QName, AParentSymbolIdx, ANode, '', Modifiers);
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
    // Unknown shape (type alias, set, etc.) — fall through to default recurse.
  end;

  // declProc: emit a method (when inside class/record/interface) or a free
  // proc/func otherwise.
  if NodeType = 'declProc' then
  begin
    IsInClass := (AParentSymbolIdx >= 0) and
      (AParentSymbolIdx < AState.Symbols.Count) and
      (AState.Symbols[AParentSymbolIdx].Kind in
       [skClass, skRecord, skInterface]);
    WalkDeclProc(ANode, AState, AParentSymbolIdx, AParentQualifiedName, IsInClass);
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
        AState.Emit(skField, FName, FQName, AParentSymbolIdx, ANode);
      end;
    end;
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
        AState.Emit(skProperty, PName, PQName, AParentSymbolIdx, ANode);
      end;
    end;
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
  finally
    State.Free;
    Tree.Free;
    Parser.Free;
  end;
end;

end.
