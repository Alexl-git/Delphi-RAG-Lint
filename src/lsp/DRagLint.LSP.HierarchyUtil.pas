unit DRagLint.LSP.HierarchyUtil;

{ Shared by the call-hierarchy and type-hierarchy features: building a
  Call/TypeHierarchyItem for an indexed symbol and finding the symbol again from
  an item the client hands back. An item carries `data` = (id, path); the lookup
  re-checks name and file, so an item from an older index answers nothing rather
  than a wrong symbol. }

interface

uses
  System.JSON
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.LSP.Context
  ;

/// <summary>Reads an integer member of a JSON object.</summary>
/// <param name="AObj">The object; nil answers False.</param>
/// <param name="AName">The member name.</param>
/// <param name="AValue">Out: the value, 0 when absent or not a number.</param>
/// <returns>True when the member is a number.</returns>
function HierIntField(const AObj: TJSONObject; const AName: string; out AValue: Integer): Boolean;

/// <summary>Builds the LSP item (name, kind, uri, range, selectionRange, data) for a symbol.</summary>
/// <param name="ACtx">The server surface (URI mapping).</param>
/// <param name="AStore">The store that holds ASym.</param>
/// <param name="ASym">The symbol; StartLine must be &gt; 0.</param>
/// <returns>A new object owned by the caller; nil when the symbol has no usable file or position.</returns>
function BuildHierarchyItem(const ACtx: ILspServerContext; const AStore: ISymbolStore; const ASym: TSymbol): TJSONObject;

/// <summary>Finds the symbol a hierarchy item stands for.</summary>
/// <param name="ACtx">The server surface.</param>
/// <param name="AItem">The item the client sent back (its `data` carries id and path).</param>
/// <param name="ASym">Out: the symbol.</param>
/// <param name="AStore">Out: its store.</param>
/// <returns>False when no store holds a symbol of that id, name and file.</returns>
function FindItemSymbol(const ACtx: ILspServerContext; const AItem: TJSONObject; out ASym: TSymbol; out AStore: ISymbolStore): Boolean;

/// <summary>Builds a LSP Range from 0-based coordinates.</summary>
/// <param name="ASLine">Start line.</param>
/// <param name="ASCol">Start character.</param>
/// <param name="AELine">End line.</param>
/// <param name="AECol">End character.</param>
/// <returns>A new object owned by the caller.</returns>
function HierRange(ASLine, ASCol, AELine, AECol: Integer): TJSONObject;

implementation

uses
  System.SysUtils
  , DRagLint.Core.LiveDocs
  ;

const
  LSP_CLASS     = 5;
  LSP_METHOD    = 6;
  LSP_PROPERTY  = 7;
  LSP_FIELD     = 8;
  LSP_CTOR      = 9;
  LSP_ENUM      = 10;
  LSP_INTERFACE = 11;
  LSP_FUNCTION  = 12;
  LSP_STRUCT    = 23;

function HierIntField(const AObj: TJSONObject; const AName: string; out AValue: Integer): Boolean;
begin
  var V: TJSONValue:= nil;
  if AObj <> nil then V:= AObj.GetValue(AName);
  Result:= V is TJSONNumber;
  AValue:= if Result then (V as TJSONNumber).AsInt else 0;
end;

function HierRange(ASLine, ASCol, AELine, AECol: Integer): TJSONObject;
begin
  Result:= TJSONObject.Create;
  try
    var S: TJSONObject:= TJSONObject.Create;
    Result.AddPair('start', S);
    S.AddPair('line', TJSONNumber.Create(ASLine));
    S.AddPair('character', TJSONNumber.Create(ASCol));
    var E: TJSONObject:= TJSONObject.Create;
    Result.AddPair('end', E);
    E.AddPair('line', TJSONNumber.Create(AELine));
    E.AddPair('character', TJSONNumber.Create(AECol));
  except
    on Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;

function LspKindOf(AKind: TSymbolKind): Integer;
begin
  case AKind of
    skMethod                      : Result:= LSP_METHOD;
    skConstructor, skDestructor   : Result:= LSP_CTOR;
    skProperty                    : Result:= LSP_PROPERTY;
    skField                       : Result:= LSP_FIELD;
    skEnum                        : Result:= LSP_ENUM;
    skInterface                   : Result:= LSP_INTERFACE;
    skProcedure, skFunction       : Result:= LSP_FUNCTION;
    skRecord                      : Result:= LSP_STRUCT;
  else
    Result:= LSP_CLASS;
  end;
end;

// 0-based column of the symbol name on its start line (StartCol may point at the declaration keyword).
function NameCol(const ASym: TSymbol; const ALines: TArray<string>): Integer;
begin
  Result:= ASym.StartCol - 1;
  if (ASym.StartLine < 1) or (ASym.StartLine > Length(ALines)) or (ASym.Name = '') then Exit;
  var Line: string:= LowerCase(ALines[ASym.StartLine - 1]);
  var Want: string:= LowerCase(ASym.Name);
  var From: Integer:= Result + 1;
  if From < 1 then From:= 1;
  while True do
  begin
    var P: Integer:= Pos(Want, Line, From);
    if P = 0 then Exit;
    var After: Integer:= P + Length(Want);
    var BeforeOk: Boolean:= (P = 1) or not CharInSet(Line[P - 1], ['a'..'z', '0'..'9', '_']);
    var AfterOk : Boolean:= (After > Length(Line)) or not CharInSet(Line[After], ['a'..'z', '0'..'9', '_']);
    if BeforeOk and AfterOk then Exit(P - 1);
    From:= P + 1;
  end;
end;

function BuildHierarchyItem(const ACtx: ILspServerContext; const AStore: ISymbolStore; const ASym: TSymbol): TJSONObject;
begin
  Result:= nil;
  if (AStore = nil) or (ASym.StartLine < 1) or (ASym.Name = '') then Exit;
  var Path: string:= AStore.GetFilePath(ASym.FileId);
  if Path = '' then Exit;
  var Uri: string:= ACtx.FileToUri(Path);
  if Uri = '' then Exit;
  var Lines: TArray<string>;
  try Lines:= TLiveDocuments.ReadLines(Path); except on Exception do Lines:= nil; end; // unreadable: the start column stands in for the name column
  var NCol : Integer:= NameCol(ASym, Lines);
  var SLine: Integer:= ASym.StartLine - 1;
  var ELine: Integer:= ASym.EndLine - 1;
  var ECol : Integer:= ASym.EndCol - 1;
  if (ELine < SLine) or ((ELine = SLine) and (ECol < NCol + Length(ASym.Name))) then
  begin
    ELine:= SLine;
    ECol := NCol + Length(ASym.Name);
  end;
  Result:= TJSONObject.Create;
  try
    Result.AddPair('name', ASym.Name);
    Result.AddPair('kind', TJSONNumber.Create(LspKindOf(ASym.Kind)));
    Result.AddPair('uri', Uri);
    Result.AddPair('range', HierRange(SLine, NCol, ELine, ECol));
    Result.AddPair('selectionRange', HierRange(SLine, NCol, SLine, NCol + Length(ASym.Name)));
    var Data: TJSONObject:= TJSONObject.Create;
    Result.AddPair('data', Data);
    Data.AddPair('id', TJSONNumber.Create(ASym.Id));
    Data.AddPair('path', Path);
  except
    on Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;

function FindItemSymbol(const ACtx: ILspServerContext; const AItem: TJSONObject; out ASym: TSymbol; out AStore: ISymbolStore): Boolean;
begin
  Result:= False;
  ASym  := Default(TSymbol);
  AStore:= nil;
  if AItem = nil then Exit;
  var Data: TJSONObject:= AItem.GetValue('data') as TJSONObject;
  var Name: string:= '';
  if AItem.GetValue('name') <> nil then Name:= AItem.GetValue('name').Value;
  var Path: string:= '';
  if (Data <> nil) and (Data.GetValue('path') <> nil) then Path:= Data.GetValue('path').Value;
  var Id: Integer;
  if (Name = '') or (Path = '') or not HierIntField(Data, 'id', Id) then Exit;
  var Stores: TArray<ISymbolStore>:= ACtx.StoresForFile(Path);
  if Length(Stores) = 0 then Stores:= ACtx.Stores;
  for var S: ISymbolStore in Stores do
  begin
    var Sym: TSymbol:= S.GetSymbolById(Id);
    if (Sym.Id = Id) and SameText(Sym.Name, Name) and SameText(S.GetFilePath(Sym.FileId), Path) then
    begin
      ASym  := Sym;
      AStore:= S;
      Exit(True);
    end;
  end;
end;

end.
