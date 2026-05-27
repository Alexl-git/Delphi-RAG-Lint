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
  for i := 0 to AParent.NamedChildCount - 1 do
  begin
    Child := AParent.NamedChild(i);
    if Child.NodeType = AType then
      Exit(Child);
  end;
  Result := AParent.Child(-1);
end;

type
  TWalkState = class
    Source: TBytes;
    Symbols: TList<TSymbol>;
    constructor Create(const ASource: TBytes);
    destructor Destroy; override;
    function Emit(AKind: TSymbolKind; const AName, AQualifiedName: string;
      AParentSymbolIdx: Integer; const ARangeNode: TTSNode;
      const ASignature: string = ''; const AModifiers: string = ''): Integer;
  end;

constructor TWalkState.Create(const ASource: TBytes);
begin
  inherited Create;
  Source := ASource;
  Symbols := TList<TSymbol>.Create;
end;

destructor TWalkState.Destroy;
begin
  Symbols.Free;
  inherited;
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

function TryWalkClass(const ADeclTypeNode: TTSNode; const AState: TWalkState;
  AParentSymbolIdx: Integer; const AParentQualifiedName: string): Boolean;
var
  TypeWrapNode, ClassNode, NameNode: TTSNode;
  ClassName, QName: string;
  ClassIdx, i: Integer;
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
  ClassName := NodeText(NameNode, AState.Source);
  if ClassName = '' then
    Exit;
  if AParentQualifiedName <> '' then
    QName := AParentQualifiedName + '.' + ClassName
  else
    QName := ClassName;
  ClassIdx := AState.Emit(skClass, ClassName, QName, AParentSymbolIdx, ADeclTypeNode);
  for i := 0 to ClassNode.NamedChildCount - 1 do
    Walk(ClassNode.NamedChild(i), AState, ClassIdx, QName);
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

  // declType wrapping a class declaration
  if NodeType = 'declType' then
  begin
    if TryWalkClass(ANode, AState, AParentSymbolIdx, AParentQualifiedName) then
      Exit;
    // not a class — fall through and walk normally (could be record/enum/alias)
  end;

  // declProc: emit a method or free proc/func
  if NodeType = 'declProc' then
  begin
    IsInClass := (AParentSymbolIdx >= 0) and
      (AParentSymbolIdx < AState.Symbols.Count) and
      (AState.Symbols[AParentSymbolIdx].Kind = skClass);
    WalkDeclProc(ANode, AState, AParentSymbolIdx, AParentQualifiedName, IsInClass);
    Exit;
  end;

  // Skip implementation method definitions — their declarations were already
  // emitted from the interface section. Phase 1 keeps things minimal.
  if NodeType = 'defProc' then
    Exit;

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
  finally
    State.Free;
    Tree.Free;
    Parser.Free;
  end;
end;

end.
