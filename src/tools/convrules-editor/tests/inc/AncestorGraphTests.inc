{ C8CHAIN: ancestor dependency graph -- plan docs\superpowers\plans\2026-11-03-converter-c8chain.md }
const
  AG_BASE_PAS = 'fx\Base.pas';
  AG_MID_PAS  = 'fx\Mid.pas';
  AG_LEAF_PAS = 'fx\Leaf.pas';
  AG_FRM_PAS  = 'fx\Frm.pas';
  AG_CRLF     = #13#10;
  AG_BASE_DFM = 'object BaseForm: TBase' + AG_CRLF + '  object tblX: TTable' + AG_CRLF + '  end' + AG_CRLF + 'end';
  AG_MID_DFM  = 'inherited MidForm: TMid' + AG_CRLF + 'end';
  AG_MID_OWN_DFM = 'inherited MidForm: TMid' + AG_CRLF + '  object lblOwn: TTable' + AG_CRLF + '  end' + AG_CRLF + 'end';

{ TTable -> TFDTable, TQuery -> TFDQuery. }
function AgPairs: TArray<TTypePair>;
var
  LPair: TTypePair;
begin
  LPair.FromType:= 'TTable';
  LPair.ToType  := 'TFDTable';
  Result:= [LPair];
  LPair.FromType:= 'TQuery';
  LPair.ToType  := 'TFDQuery';
  Result:= Result + [LPair];
end;

function AgField(const AName, AType: string): TFieldDecl;
begin
  Result.Name    := AName;
  Result.TypeName:= AType;
end;

procedure TestAncestorFromTypes;
begin
  Check('ag.from.object', string.Join(',', FromTypesIn(AG_BASE_DFM, [], AgPairs)) = 'TTable');
  Check('ag.from.inherited.and.inline', string.Join(',', FromTypesIn('object F: TX' + AG_CRLF + '  inherited a: TTable' + AG_CRLF + '  end' + AG_CRLF
    + '  inline f: TQuery' + AG_CRLF + '  end' + AG_CRLF + 'end', [], AgPairs)) = 'TTable,TQuery');
  Check('ag.from.fields', string.Join(',', FromTypesIn('', [AgField('qry', 'Bde.DBTables.TQuery'), AgField('lbl', 'TLabel')], AgPairs)) = 'TQuery');
  Check('ag.from.distinct', string.Join(',', FromTypesIn(AG_BASE_DFM, [AgField('t2', 'TTable')], AgPairs)) = 'TTable');
  Check('ag.from.none', Length(FromTypesIn(AG_MID_DFM, [], AgPairs)) = 0);
  Check('ag.from.no.pairs', Length(FromTypesIn(AG_BASE_DFM, [], [])) = 0);
end;
procedure TestAncestorGraphWalk;
var
  G  : TArray<TAncestorUnit>;
  Err: string;

  function Own: TClassInfo;
  begin
    Result:= Default(TClassInfo);
    Result.Found      := True;
    Result.PasPath    := AG_LEAF_PAS;
    Result.ParentClass:= 'TMid';
  end;

  function Paths(const A: TArray<TAncestorUnit>): string;
  begin
    Result:= '';
    for var LUnit: TAncestorUnit in A do
      Result:= Result + (if Result = '' then '' else ',') + LUnit.PasPath;
  end;

  function Rows: TArray<string>;
  begin
    Result:= ['TMid|' + AG_MID_PAS + '|TBase', 'TBase|' + AG_BASE_PAS + '|TForm']; // TForm absent = outside
  end;

  function Reader: TDfmTextReader;
  begin
    Result:= FakeReader([ChangeFileExt(AG_MID_PAS, '.dfm'), ChangeFileExt(AG_BASE_PAS, '.dfm')], [AG_MID_DFM, AG_BASE_DFM]);
  end;

begin
  G:= AncestorGraphOf(Own, [], FakeLookup(Rows, nil), Reader(), AgPairs, Err);
  Check('ag.walk.root.first', (Err = '') and (Paths(G) = AG_BASE_PAS + ',' + AG_MID_PAS), Err + ' ' + Paths(G));
  if Length(G) = 2 then
  begin
    Check('ag.walk.depth', (G[0].Depth = 2) and (G[1].Depth = 1));
    Check('ag.walk.types', (string.Join(',', G[0].Types) = 'TTable') and (Length(G[1].Types) = 0));
  end;
  G:= AncestorGraphOf(Own, [], FakeLookup(['TMid|' + AG_MID_PAS + '|TBase|qry:TQuery', 'TBase|' + AG_BASE_PAS + '|TForm'], nil), Reader(), AgPairs, Err);
  Check('ag.walk.fields.count', (Length(G) = 2) and (string.Join(',', G[1].Types) = 'TQuery'), Err);
  G:= AncestorGraphOf(Own, ['TFrm'], FakeLookup(Rows + ['TFrm|' + AG_FRM_PAS + '|TFrame'], nil),
    FakeReader([ChangeFileExt(AG_MID_PAS, '.dfm'), ChangeFileExt(AG_BASE_PAS, '.dfm'), ChangeFileExt(AG_FRM_PAS, '.dfm')], [AG_MID_DFM, AG_BASE_DFM, AG_BASE_DFM]), AgPairs, Err);
  Check('ag.walk.frame.after.forms', (Paths(G) = AG_FRM_PAS + ',' + AG_BASE_PAS + ',' + AG_MID_PAS) and (G[0].Depth = 3), Paths(G) + ' ' + Err);
  G:= AncestorGraphOf(Own, [], FakeLookup(['TMid|' + AG_MID_PAS + '|TBase', 'TBase|' + AG_BASE_PAS + '|TMid'], nil), Reader(), AgPairs, Err);
  Check('ag.walk.cycle.error', (Length(G) = 0) and (Pos('TMid', Err) > 0), Err);
  G:= AncestorGraphOf(Own, [], FakeLookup(['TMid|' + AG_MID_PAS + '|TBase', 'TBase|!|boom'], nil), Reader(), AgPairs, Err);
  Check('ag.walk.failed.error', (Length(G) = 0) and (Pos('boom', Err) > 0), Err);
  G:= AncestorGraphOf(Own, [], FakeLookup(Rows, nil), FakeReader([ChangeFileExt(AG_BASE_PAS, '.dfm')], [FAKE_UNREADABLE_DFM]), AgPairs, Err);
  Check('ag.walk.unreadable.error', (Length(G) = 0) and (Pos('Base.dfm', Err) > 0), Err);
  G:= AncestorGraphOf(Own, [], FakeLookup(Rows, nil), FakeReader([ChangeFileExt(AG_BASE_PAS, '.dfm')], [BINARY_DFM_SIGNATURE + 'xx']), AgPairs, Err);
  Check('ag.walk.binary.error', (Length(G) = 0) and (Err <> ''), Err);
  G:= AncestorGraphOf(Own, [], FakeLookup(Rows, nil), FakeReader([], []), AgPairs, Err);
  Check('ag.walk.missing.dfm.ok', (Err = '') and (Length(G) = 2) and (Length(G[0].Types) = 0), Err);
  G:= AncestorGraphOf(Own, [], FakeLookup(Rows, nil), Reader(), [], Err);
  Check('ag.walk.no.pairs', (Err = '') and (Length(G) = 2) and (Length(G[0].Types) = 0));
end;