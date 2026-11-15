unit DRagLint.V151.CMP.Support;

{ Wave v151 lane CMP -- helpers of DRagLint.V151.CMP (private to the lane).
  Tree helpers over one parsed unit, the class model the component rules read
  (fields, properties, parents per class declared in the unit), the lists of
  well-known VCL / RTL component classes used when no index answers, and a
  reader of resource names in a compiled .res / .dcr file or a .rc script. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Core.Model
  ;

type
  /// <summary>One property declared in a class of the unit.</summary>
  /// <remarks>Names are lower case; an accessor that is not a plain identifier is ''.</remarks>
  TCmpProp = record
    Name       : string;
    Getter     : string;
    Setter     : string;
    TypeLeaf   : string;
    IsPublished: Boolean;
    WriteOnly  : Boolean;   // the dispinterface `writeonly` keyword
    NameNode   : TTSNode;
    SetterNode : TTSNode;
    DefaultNode: TTSNode;   // the value after `default`; null when there is none
  end;

  /// <summary>One class declared in the unit, as the component rules need it.</summary>
  /// <remarks>Owns its collections. Name and Parents are lower-case leaf names (generic
  /// arguments and unit qualifiers cut off).</remarks>
  TCmpClass = class
  public
    Name   : string;
    Display: string;
    Node   : TTSNode;
    Parents: TArray<string>;
    Fields : TDictionary<string, string>;
    Props  : TList<TCmpProp>;
    /// <summary>Creates the empty model.</summary>
    constructor Create;
    /// <summary>Frees the collections.</summary>
    destructor Destroy; override;
  end;

/// <summary>Source text of a node.</summary>
/// <param name="ASrc">The bytes the tree was parsed from.</param>
/// <param name="ANode">Any node; a null node gives ''.</param>
/// <returns>The UTF-8 decoded slice.</returns>
function CmpText(const ASrc: TBytes; const ANode: TTSNode): string;
/// <summary>Source text of a node, lower case, with every blank removed.</summary>
/// <param name="ASrc">The bytes the tree was parsed from.</param>
/// <param name="ANode">Any node.</param>
/// <returns>The normalised text; '' for a null node.</returns>
function CmpLow(const ASrc: TBytes; const ANode: TTSNode): string;
/// <summary>The last dotted segment of a name, generic arguments cut off.</summary>
/// <param name="AName">`Unit.TFoo&lt;T&gt;` or `TFoo`.</param>
/// <returns>`TFoo` (case kept).</returns>
function CmpLeaf(const AName: string): string;
/// <summary>Appends every descendant of ANode (ANode included) whose node type is AType.</summary>
/// <param name="ANode">Root of the walk.</param>
/// <param name="AType">Node type to collect.</param>
/// <param name="AList">Receives the nodes in source order; owned by the caller.</param>
procedure CmpCollect(const ANode: TTSNode; const AType: string; AList: TList<TTSNode>);
/// <summary>Builds a finding that spans AFrom..ATo.</summary>
/// <param name="AFile">The linted file.</param>
/// <param name="ARule">Rule id.</param>
/// <param name="ASeverity">'hint' | 'info' | 'warning' | 'error'.</param>
/// <param name="AMessage">The message.</param>
/// <param name="AFrom">First node of the span.</param>
/// <param name="ATo">Last node of the span.</param>
/// <returns>The finding (1-based lines and columns).</returns>
function CmpFinding(const AFile, ARule, ASeverity, AMessage: string; const AFrom, ATo: TTSNode): TLintFinding;
/// <summary>The value of a numeric literal as written in Delphi (decimal, $hex, with a sign).</summary>
/// <param name="AText">Literal text, e.g. `-5`, `$00FF8000`, `16`.</param>
/// <param name="AValue">Out: the value.</param>
/// <returns>False for a real number or anything that is not an integer literal.</returns>
function CmpIntLiteral(const AText: string; out AValue: Int64): Boolean;
/// <summary>True when ALeaf is a well-known class that descends from TComponent.</summary>
/// <param name="ALeaf">Lower-case leaf class name.</param>
/// <returns>Membership in the built-in list (VCL, RTL, FireDAC base classes).</returns>
/// <remarks>Used when the index does not answer; never a reason to stay silent on its own.</remarks>
function CmpIsKnownComponent(const ALeaf: string): Boolean;
/// <summary>True when ALeaf is a well-known class that descends from TControl.</summary>
/// <param name="ALeaf">Lower-case leaf class name.</param>
/// <returns>Membership in the built-in list of VCL controls and forms.</returns>
function CmpIsKnownControl(const ALeaf: string): Boolean;
/// <summary>Resource names in a compiled resource file (.res / .dcr) or a resource script (.rc).</summary>
/// <param name="APath">The file; a missing or unreadable file gives nil.</param>
/// <returns>Every resource name, upper case; ordinal names are left out.</returns>
/// <remarks>A .res / .dcr is read as the 32-bit resource format (a 32-byte empty header entry,
/// then entries of data size, header size, type, name, padding, five header fields and the
/// DWORD-aligned data). A .rc is read line by line: the first word of a line that names a
/// resource type. Never raises.</remarks>
function CmpResourceNames(const APath: string): TArray<string>;
/// <summary>Collects every class declared in the unit.</summary>
/// <param name="ASrc">The bytes the tree was parsed from.</param>
/// <param name="ARoot">Root node of the unit.</param>
/// <param name="AClasses">Receives one model per class, keyed by lower-case leaf name; the first
/// declaration of a name wins. The dictionary owns the models.</param>
procedure CmpCollectClasses(const ASrc: TBytes; const ARoot: TTSNode; AClasses: TObjectDictionary<string, TCmpClass>);

implementation

uses
  System.Classes
  , System.StrUtils
  , System.IOUtils
  ;

const
  KNOWN_CONTROLS: array[0..63] of string = (
    'tcontrol', 'twincontrol', 'tcustomcontrol', 'tgraphiccontrol', 'tcustompanel', 'tpanel',
    'tcustomform', 'tform', 'tframe', 'tcustomframe', 'tscrollingwincontrol', 'tscrollbox',
    'tbutton', 'tbitbtn', 'tspeedbutton', 'tcustomedit', 'tedit', 'tcustommemo', 'tmemo',
    'trichedit', 'tcustomlabel', 'tlabel', 'tcustomlistbox', 'tlistbox', 'tcustomcombobox',
    'tcombobox', 'tcustomcheckbox', 'tcheckbox', 'tradiobutton', 'tcustomgroupbox', 'tgroupbox',
    'tradiogroup', 'tcustomtreeview', 'ttreeview', 'tcustomlistview', 'tlistview', 'tstatusbar',
    'ttoolbar', 'tpagecontrol', 'ttabsheet', 'ttabcontrol', 'tcustomtabcontrol', 'timage',
    'tpaintbox', 'tshape', 'tbevel', 'tsplitter', 'tprogressbar', 'ttrackbar', 'tupdown',
    'tmaskedit', 'tcustommaskedit', 'tstringgrid', 'tdrawgrid', 'tcustomgrid', 'tcustomdrawgrid',
    'tdbgrid', 'tcustomdbgrid', 'tdbedit', 'tdbnavigator', 'tcustomactioncontrol', 'theadercontrol',
    'tcustomstatictext', 'tstatictext');
  KNOWN_NONVISUAL: array[0..31] of string = (
    'tcomponent', 'tdataset', 'tdatasource', 'tcustomimagelist', 'timagelist', 'tdragimagelist',
    'tmenu', 'tmainmenu', 'tpopupmenu', 'tmenuitem', 'tbasicaction', 'tcontainedaction',
    'tcustomaction', 'taction', 'tcustomactionlist', 'tactionlist', 'ttimer', 'tdatamodule',
    'tcustomconnection', 'tfdcustomconnection', 'tfdconnection', 'tfdrdbmsdataset', 'tfdcustomquery',
    'tfdquery', 'tfdtable', 'tfdmemtable', 'tfdadaptedataset', 'tfddataset', 'tfdtransaction',
    'tcommondialog', 'topendialog', 'tsavedialog');

function CmpText(const ASrc: TBytes; const ANode: TTSNode): string;
var
  S, L: Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  S:= Integer(ANode.StartByte);
  L:= Integer(ANode.EndByte) - S;
  if (L <= 0) or (S < 0) or (S + L > Length(ASrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(ASrc, S, L);
end;

function CmpLow(const ASrc: TBytes; const ANode: TTSNode): string;
var
  B: TStringBuilder;
begin
  B:= TStringBuilder.Create;
  try
    for var Ch: Char in LowerCase(CmpText(ASrc, ANode)) do
      if Ch > ' ' then B.Append(Ch);
    Result:= B.ToString;
  finally
    B.Free;
  end;
end;

function CmpLeaf(const AName: string): string;
begin
  Result:= AName;
  var P: Integer:= Pos('<', Result);
  if P > 0 then Result:= Copy(Result, 1, P - 1);
  P:= LastDelimiter('.', Result);
  if P > 0 then Result:= Copy(Result, P + 1, MaxInt);
  Result:= Trim(Result);
end;

procedure CmpCollect(const ANode: TTSNode; const AType: string; AList: TList<TTSNode>);
begin
  if ANode.IsNull then Exit;
  if ANode.NodeType = AType then AList.Add(ANode);
  for var I: Integer:= 0 to ANode.NamedChildCount - 1 do CmpCollect(ANode.NamedChild(I), AType, AList);
end;

function CmpFinding(const AFile, ARule, ASeverity, AMessage: string; const AFrom, ATo: TTSNode): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId   := ARule;
  Result.Severity := ASeverity;
  Result.Message  := AMessage;
  Result.FilePath := AFile;
  Result.StartLine:= Integer(AFrom.StartPoint.Row) + 1;
  Result.StartCol := Integer(AFrom.StartPoint.Column) + 1;
  Result.EndLine  := Integer(ATo.EndPoint.Row) + 1;
  Result.EndCol   := Integer(ATo.EndPoint.Column) + 1;
end;

function CmpIntLiteral(const AText: string; out AValue: Int64): Boolean;
begin
  var S: string:= Trim(AText);
  var Neg: Boolean:= False;
  if (S <> '') and CharInSet(S[1], ['-', '+']) then
  begin
    Neg:= S[1] = '-';
    S:= Trim(Copy(S, 2, MaxInt));
  end;
  if S = '' then Exit(False);
  if S[1] = '$' then Result:= TryStrToInt64(S, AValue)
  else
  begin
    for var Ch: Char in S do
      if not CharInSet(Ch, ['0'..'9']) then Exit(False);
    Result:= TryStrToInt64(S, AValue);
  end;
  if Result and Neg then AValue:= -AValue;
end;

function CmpIsKnownComponent(const ALeaf: string): Boolean;
begin
  Result:= MatchStr(ALeaf, KNOWN_NONVISUAL) or MatchStr(ALeaf, KNOWN_CONTROLS);
end;

function CmpIsKnownControl(const ALeaf: string): Boolean;
begin
  Result:= MatchStr(ALeaf, KNOWN_CONTROLS);
end;

{ ------------------------------------------------------------ resources }

{ One name or type field of a .res entry header: $FFFF + ordinal, or a
  zero-terminated UTF-16 string. Advances APos; AName is '' for an ordinal. }
function ReadResId(const B: TBytes; var APos: Integer; out AName: string): Boolean;
begin
  AName:= '';
  if APos + 2 > Length(B) then Exit(False);
  if (B[APos] = $FF) and (B[APos + 1] = $FF) then
  begin
    Inc(APos, 4);
    Exit(APos <= Length(B));
  end;
  var SB: TStringBuilder:= TStringBuilder.Create;
  try
    while APos + 1 < Length(B) do
    begin
      var W: Word:= B[APos] or (Word(B[APos + 1]) shl 8);
      Inc(APos, 2);
      if W = 0 then
      begin
        AName:= SB.ToString;
        Exit(True);
      end;
      SB.Append(Char(W));
    end;
  finally
    SB.Free;
  end;
  Result:= False;
end;

function ReadLE32(const B: TBytes; APos: Integer): Cardinal;
begin
  Result:= B[APos] or (Cardinal(B[APos + 1]) shl 8) or (Cardinal(B[APos + 2]) shl 16) or (Cardinal(B[APos + 3]) shl 24);
end;

function ResNamesOfBinary(const B: TBytes): TArray<string>;
const
  ALIGN = 4;
  MIN_HEADER = 8;
var
  Ofs, Next: Integer;
  DataSize, HeaderSize: Cardinal;
  TypeName, ResName: string;
begin
  Result:= nil;
  Ofs:= 0;
  while Ofs + MIN_HEADER <= Length(B) do
  begin
    DataSize  := ReadLE32(B, Ofs);
    HeaderSize:= ReadLE32(B, Ofs + 4);
    if (HeaderSize < MIN_HEADER) or (Int64(Ofs) + HeaderSize + DataSize > Length(B)) then Exit;
    Next:= Ofs + Integer(HeaderSize) + Integer(DataSize);
    if Next mod ALIGN <> 0 then Next:= Next + ALIGN - Next mod ALIGN;
    var P: Integer:= Ofs + MIN_HEADER;
    if ReadResId(B, P, TypeName) and ReadResId(B, P, ResName) and (ResName <> '') then
      Result:= Result + [UpperCase(ResName)];
    if Next <= Ofs then Exit;
    Ofs:= Next;
  end;
end;

function ResNamesOfScript(const APath: string): TArray<string>;
const
  RC_TYPES: array[0..5] of string = ('BITMAP', 'ICON', 'RCDATA', 'PNG', 'IMAGE', 'CURSOR');
begin
  Result:= nil;
  var Lines: TStringList:= TStringList.Create;
  try
    Lines.LoadFromFile(APath);
    for var L: string in Lines do
    begin
      var Parts: TArray<string>:= Trim(L).Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
      if (Length(Parts) >= 2) and MatchText(Parts[1], RC_TYPES) then
        Result:= Result + [UpperCase(Parts[0].DeQuotedString('"'))];
    end;
  finally
    Lines.Free;
  end;
end;

function CmpResourceNames(const APath: string): TArray<string>;
begin
  Result:= nil;
  try
    if not TFile.Exists(APath) then Exit;
    if SameText(ExtractFileExt(APath), '.rc') then Exit(ResNamesOfScript(APath));
    Result:= ResNamesOfBinary(TFile.ReadAllBytes(APath));
  except
    on EInOutError do Result:= nil;
    on EFOpenError do Result:= nil;
    on EEncodingError do Result:= nil;
  end;
end;

{ ------------------------------------------------------------ class model }

constructor TCmpClass.Create;
begin
  inherited Create;
  Fields:= TDictionary<string, string>.Create;
  Props := TList<TCmpProp>.Create;
end;

destructor TCmpClass.Destroy;
begin
  Props.Free;
  Fields.Free;
  inherited Destroy;
end;

function TypeLeafOf(const ASrc: TBytes; const AType: TTSNode): string;
begin
  Result:= '';
  if AType.IsNull then Exit;
  var T: TTSNode:= AType;
  if (T.NodeType = 'type') and (T.NamedChildCount > 0) then T:= T.NamedChild(0);
  if T.NodeType <> 'typeref' then Exit;
  Result:= LowerCase(CmpLeaf(CmpLow(ASrc, T)));
end;

function HasChildOfType(const ANode: TTSNode; const AType: string): Boolean;
begin
  for var I: Integer:= 0 to ANode.NamedChildCount - 1 do
    if ANode.NamedChild(I).NodeType = AType then Exit(True);
  Result:= False;
end;

procedure AddMember(const ASrc: TBytes; const AMember: TTSNode; APublished: Boolean; AClass: TCmpClass);
begin
  if AMember.NodeType = 'declField' then
  begin
    var Ty: TTSNode:= AMember.ChildByField('type');
    var Leaf: string:= TypeLeafOf(ASrc, Ty);
    var TyStart: Integer:= if Ty.IsNull then MaxInt else Integer(Ty.StartByte);
    for var J: Integer:= 0 to AMember.NamedChildCount - 1 do
    begin
      var C: TTSNode:= AMember.NamedChild(J);
      if (C.NodeType = 'identifier') and (Integer(C.StartByte) < TyStart) then
        AClass.Fields.AddOrSetValue(CmpLow(ASrc, C), Leaf);
    end;
  end
  else if AMember.NodeType = 'declProp' then
  begin
    var P: TCmpProp:= Default(TCmpProp);
    P.NameNode   := AMember.ChildByField('name');
    P.Name       := CmpLow(ASrc, P.NameNode);
    P.IsPublished:= APublished;
    P.WriteOnly  := HasChildOfType(AMember, 'kWriteonly');
    P.TypeLeaf   := TypeLeafOf(ASrc, AMember.ChildByField('type'));
    P.DefaultNode:= AMember.ChildByField('defaultValue');
    var G: TTSNode:= AMember.ChildByField('getter');
    if (not G.IsNull) and (G.NodeType = 'identifier') then P.Getter:= CmpLow(ASrc, G)
    else if not G.IsNull then P.Getter:= '?';
    P.SetterNode := AMember.ChildByField('setter');
    if (not P.SetterNode.IsNull) and (P.SetterNode.NodeType = 'identifier') then P.Setter:= CmpLow(ASrc, P.SetterNode)
    else if not P.SetterNode.IsNull then P.Setter:= '?';
    AClass.Props.Add(P);
  end;
end;

procedure CollectMembers(const ASrc: TBytes; const ANode: TTSNode; APublished: Boolean; AClass: TCmpClass);
begin
  for var I: Integer:= 0 to ANode.NamedChildCount - 1 do
  begin
    var C: TTSNode:= ANode.NamedChild(I);
    if C.NodeType = 'declSection' then CollectMembers(ASrc, C, HasChildOfType(C, 'kPublished'), AClass)
    else AddMember(ASrc, C, APublished, AClass);
  end;
end;

procedure CmpCollectClasses(const ASrc: TBytes; const ARoot: TTSNode; AClasses: TObjectDictionary<string, TCmpClass>);
begin
  if ARoot.IsNull then Exit;
  if ARoot.NodeType = 'declType' then
  begin
    var Cls: TTSNode:= Default(TTSNode);
    for var J: Integer:= 0 to ARoot.NamedChildCount - 1 do
    begin
      var C: TTSNode:= ARoot.NamedChild(J);
      if C.NodeType = 'declClass' then Cls:= C;
      if (C.NodeType = 'type') and (C.NamedChildCount > 0) and (C.NamedChild(0).NodeType = 'declClass') then
        Cls:= C.NamedChild(0);
    end;
    var Name: string:= LowerCase(CmpLeaf(CmpLow(ASrc, ARoot.ChildByField('name'))));
    if (not Cls.IsNull) and (Name <> '') and not AClasses.ContainsKey(Name) then
    begin
      var M: TCmpClass:= TCmpClass.Create;
      AClasses.Add(Name, M);
      M.Name   := Name;
      M.Display:= CmpLeaf(Trim(CmpText(ASrc, ARoot.ChildByField('name'))));
      M.Node   := Cls;
      for var J: Integer:= 0 to Cls.NamedChildCount - 1 do
        if Cls.NamedChild(J).NodeType = 'typeref' then
          M.Parents:= M.Parents + [LowerCase(CmpLeaf(CmpLow(ASrc, Cls.NamedChild(J))))];
      { A class with no visibility keyword before its first members is published only
        under $M+; it never matters for the rules that read Published. }
      CollectMembers(ASrc, Cls, False, M);
    end;
  end;
  for var I: Integer:= 0 to ARoot.NamedChildCount - 1 do CmpCollectClasses(ASrc, ARoot.NamedChild(I), AClasses);
end;

end.
