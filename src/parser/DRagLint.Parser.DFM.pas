unit DRagLint.Parser.DFM;

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
  TDFMParser = class(TInterfacedObject, IParser)
  strict private
    FLanguage: PTSLanguage;
  public
    constructor Create;
    function LanguageName: string;
    function FileExtensions: TArray<string>;
    function Parse(const ASource: TBytes; const AFilePath: string): TParseResult;
  end;

function tree_sitter_dfm: PTSLanguage; cdecl;
  external 'tree-sitter-dfm';

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

type
  TDfmState = class
    Source: TBytes;
    Symbols: TList<TSymbol>;
    References: TList<TReference>;
    constructor Create(const ASource: TBytes);
    destructor Destroy; override;
    function Emit(AKind: TSymbolKind; const AName, AQualifiedName,
      ASignature: string; AParentSymbolIdx: Integer;
      const ARangeNode: TTSNode): Integer;
    procedure EmitRef(const AKind, ANameText: string;
      const ARangeNode: TTSNode);
  end;

constructor TDfmState.Create(const ASource: TBytes);
begin
  inherited Create;
  Source := ASource;
  Symbols := TList<TSymbol>.Create;
  References := TList<TReference>.Create;
end;

destructor TDfmState.Destroy;
begin
  Symbols.Free;
  References.Free;
  inherited;
end;

function TDfmState.Emit(AKind: TSymbolKind; const AName, AQualifiedName,
  ASignature: string; AParentSymbolIdx: Integer;
  const ARangeNode: TTSNode): Integer;
var
  Sym: TSymbol;
begin
  Sym := Default(TSymbol);
  Sym.Kind := AKind;
  Sym.Name := AName;
  Sym.QualifiedName := AQualifiedName;
  Sym.Signature := ASignature;
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

procedure TDfmState.EmitRef(const AKind, ANameText: string;
  const ARangeNode: TTSNode);
var
  Ref: TReference;
begin
  if ARangeNode.IsNull or (ANameText = '') then
    Exit;
  Ref := Default(TReference);
  Ref.Kind := AKind;
  Ref.NameText := ANameText;
  Ref.SymbolId := 0;
  Ref.StartLine := Integer(ARangeNode.StartPoint.row) + 1;
  Ref.StartCol := Integer(ARangeNode.StartPoint.column) + 1;
  Ref.EndLine := Integer(ARangeNode.EndPoint.row) + 1;
  Ref.EndCol := Integer(ARangeNode.EndPoint.column) + 1;
  References.Add(Ref);
end;

procedure WalkObject(const ANode: TTSNode; const AState: TDfmState;
  AParentSymbolIdx: Integer; const AParentQualifiedName: string;
  AIsRoot: Boolean); forward;

procedure WalkProperty(const ANode: TTSNode; const AState: TDfmState);
var
  NameNode, ValueNode, NameInner: TTSNode;
  PropName, HandlerName: string;
  i: Integer;
begin
  NameNode := ANode.ChildByField('name');
  ValueNode := ANode.ChildByField('value');
  if NameNode.IsNull then
    Exit;
  // qualified_identifier wraps an identifier (or chain). Take whole text.
  PropName := NodeText(NameNode, AState.Source);
  if PropName = '' then
    Exit;
  // Event bindings: property names starting with "On" whose value is an
  // identifier_value (a method name).
  if not ValueNode.IsNull and (Copy(PropName, 1, 2) = 'On') and
     (ValueNode.NodeType = 'identifier_value') then
  begin
    HandlerName := '';
    for i := 0 to ValueNode.NamedChildCount - 1 do
    begin
      NameInner := ValueNode.NamedChild(i);
      if NameInner.NodeType = 'qualified_identifier' then
      begin
        HandlerName := NodeText(NameInner, AState.Source);
        Break;
      end;
    end;
    if HandlerName <> '' then
      AState.EmitRef('event-binding', HandlerName, ValueNode);
  end;
end;

procedure WalkObject(const ANode: TTSNode; const AState: TDfmState;
  AParentSymbolIdx: Integer; const AParentQualifiedName: string;
  AIsRoot: Boolean);
var
  NameNode, ClassNode, ChildNode: TTSNode;
  ObjName, ObjClass, QName, Signature: string;
  Kind: TSymbolKind;
  Idx, i: Integer;
begin
  NameNode := ANode.ChildByField('name');
  ClassNode := ANode.ChildByField('class');
  if NameNode.IsNull then
    Exit;
  ObjName := NodeText(NameNode, AState.Source);
  if ObjName = '' then
    Exit;
  ObjClass := '';
  if not ClassNode.IsNull then
    ObjClass := NodeText(ClassNode, AState.Source);
  if AParentQualifiedName <> '' then
    QName := AParentQualifiedName + '.' + ObjName
  else
    QName := ObjName;
  Signature := ObjClass;
  if AIsRoot then
    Kind := skForm
  else
    Kind := skComponent;
  Idx := AState.Emit(Kind, ObjName, QName, Signature, AParentSymbolIdx, ANode);
  for i := 0 to ANode.NamedChildCount - 1 do
  begin
    ChildNode := ANode.NamedChild(i);
    if ChildNode.NodeType = 'object' then
      WalkObject(ChildNode, AState, Idx, QName, False)
    else if ChildNode.NodeType = 'property' then
      WalkProperty(ChildNode, AState);
  end;
end;

{ TDFMParser }

constructor TDFMParser.Create;
begin
  inherited Create;
  FLanguage := tree_sitter_dfm;
end;

function TDFMParser.LanguageName: string;
begin
  Result := 'dfm';
end;

function TDFMParser.FileExtensions: TArray<string>;
begin
  Result := ['.dfm'];
end;

function TDFMParser.Parse(const ASource: TBytes;
  const AFilePath: string): TParseResult;
var
  Parser: TTSParser;
  Tree: TTSTree;
  Source: TBytes;
  State: TDfmState;
  Root, Child: TTSNode;
  i: Integer;
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

    State := TDfmState.Create(Source);
    Root := Tree.RootNode;
    if Root.HasError then
      Result.Diagnostics := ['parse contains syntax errors'];
    // source_file -> [object ...]. Top-level objects are forms.
    for i := 0 to Root.NamedChildCount - 1 do
    begin
      Child := Root.NamedChild(i);
      if Child.NodeType = 'object' then
        WalkObject(Child, State, -1, '', True);
    end;
    Result.Symbols := State.Symbols.ToArray;
    Result.References := State.References.ToArray;
  finally
    State.Free;
    Tree.Free;
    Parser.Free;
  end;
end;

end.
