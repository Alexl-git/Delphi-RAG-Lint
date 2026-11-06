program RefTypeHelpersHarness;

{ Console harness for TypeDescendsFrom and StaticTypeLeafOfExpr (DRagLint.Lint.RefTypeRules).
  Usage: RefTypeHelpersHarness <db> [notable]
  Prints one line per question: `LEAF|<expr>|<type or ->` and `DESC|<type>|<ancestor>|<yes|no|unknown>`.
  `notable` drops ref_types first: the no-table degrade. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  TreeSitter,
  DRagLint.Core.Model          in '..\..\..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Core.Interfaces     in '..\..\..\src\core\DRagLint.Core.Interfaces.pas',
  DRagLint.Storage.SQLite      in '..\..\..\src\storage\DRagLint.Storage.SQLite.pas',
  DRagLint.Diagnostics.ParseCache in '..\..\..\src\diagnostics\DRagLint.Diagnostics.ParseCache.pas',
  DRagLint.Lint.RefTypeRules   in '..\..\..\src\lint\DRagLint.Lint.RefTypeRules.pas';

const
  DESCENT_NAMES: array[TDescent] of string = ('unknown', 'no', 'yes');
  { `Ctx>Inner` asks about Inner inside the first Ctx: the use site of a name, where a plain lookup
    would stop at its declaration. }
  EXPRS: array[0..35] of string = ('H.FLeaf', 'H.Make(1)', 'H.Names().Make(2)', 'Zip.Zap',
    'H.Names().FLeaf', 'RhFree().FLeaf', 'RhFree2(1, 2).FLeaf', 'H.Pick(1, 2).Names().Sub.FLeaf',
    'H.Names().NoSuch', 'Zip.Make().Zap', 'RhOne(1).FLeaf',
    'Q', 'RhUse(Q)>Q',
    'W01(Q)>Q', 'W02(Q)>Q', 'W03(Q)>Q', 'W04(Q)>Q', 'W05(FLeaf)>FLeaf', 'W06(H.FLeaf)>H.FLeaf', 'W07(H.FLeaf)>H.FLeaf',
    'W08(TRhLeaf(Q))>TRhLeaf(Q)', 'W09(Q as TRhLeaf)>Q as TRhLeaf', 'W10(Names())>Names()',
    'W11(TRhHolder(Q).FLeaf)>TRhHolder(Q).FLeaf', 'W12(RhFree().FLeaf)>RhFree().FLeaf', 'W13(Self.FLeaf)>Self.FLeaf',
    'W14(TRhLeaf.Create)>TRhLeaf.Create', 'W15(RhFree())>RhFree()', 'W17(Names().FLeaf)>Names().FLeaf',
    'W18(TRhLeaf(Q))>TRhLeaf(Q)', 'W20(TRhMid(1))>TRhMid(1)', 'W23(Names().FLeaf)>Names().FLeaf', 'W99(Q)>Q', 'H.Sub', 'TRhShadow(Q)', 'TRhHolder(Q)');

var
  GSrc: TBytes;

{ The first dot / call / identifier node, outermost first, whose text is AText. }
function FindExpr(const ANode: TTSNode; const AText: string): TTSNode;
begin
  Result:= Default(TTSNode);
  if ANode.IsNull then Exit;
  var NT: string:= ANode.NodeType;
  if (NT = 'exprDot') or (NT = 'exprCall') or (NT = 'identifier') or (NT = 'exprBinary') then
  begin
    var S: Integer:= Integer(ANode.StartByte);
    if TEncoding.UTF8.GetString(GSrc, S, Integer(ANode.EndByte) - S) = AText then Exit(ANode);
  end;
  for var I: Integer:= 0 to Integer(ANode.NamedChildCount) - 1 do
  begin
    Result:= FindExpr(ANode.NamedChild(I), AText);
    if not Result.IsNull then Exit;
  end;
end;

procedure Desc(const AStore: ISymbolStore; const AType, AAncestor: string);
begin
  Writeln('DESC|', AType, '|', AAncestor, '|', DESCENT_NAMES[TypeDescendsFrom(AStore, nil, AType, AAncestor)]);
end;

begin
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(ParamStr(1));
  if SameText(ParamStr(2), 'notable') then
    (Store as TSQLiteSymbolStore).GetConnection.ExecSQL('DROP TABLE IF EXISTS ref_types');
  var FileId: Int64:= 0;
  for var Id: Int64 in Store.GetAllFileIds do
    if Store.GetFilePath(Id).ToLower.EndsWith('urhtypes.pas') then FileId:= Id;
  var PF: TParsedFile:= TAstParseCache.Get(Store.GetFilePath(FileId));
  GSrc:= PF.Src;
  var Reader: TExprTypeReader:= TExprTypeReader.Create(Store, nil, FileId, GSrc);
  try
    for var E: string in EXPRS do
    begin
      var Leaf: string:= '';
      var Sep: Integer:= E.IndexOf('>');
      var N: TTSNode:= if Sep < 0 then FindExpr(PF.Tree.RootNode, E)
                       else FindExpr(FindExpr(PF.Tree.RootNode, E.Substring(0, Sep)), E.Substring(Sep + 1));
      if N.IsNull then Leaf:= '?node'
      else if not Reader.TypeLeafOf(N, Leaf) then Leaf:= '-';
      Writeln('LEAF|', E, '|', Leaf);
    end;
  finally
    Reader.Free;
  end;
  Desc(Store, 'TRhLeaf', 'TRhBase');
  Desc(Store, 'trhleaf', 'TRHMID');
  Desc(Store, 'TRhLeaf', 'TRhLeaf');
  Desc(Store, 'TRhLeaf', 'TRhOther');
  Desc(Store, 'TRhOther', 'TRhBase');
  Desc(Store, 'TRhLibKid', 'TRhNowhere');
  Desc(Store, 'TRhLibKid', 'TRhBase');
  Desc(Store, 'TNoSuchType', 'TRhBase');
end.
