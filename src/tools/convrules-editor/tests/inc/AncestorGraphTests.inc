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
procedure TestAnalyzeAncestors;
const
  LEAF_INH_DFM = 'inherited LeafForm: TLeaf' + AG_CRLF + '  inherited tblX: TTable' + AG_CRLF + '  end' + AG_CRLF + 'end';
  LEAF_OWN_DFM = 'inherited LeafForm: TLeaf' + AG_CRLF + '  object lblMine: TLabel' + AG_CRLF + '  end' + AG_CRLF + 'end';
var
  LInh: TUnitInheritance;

  function Rows: TArray<string>;
  begin
    Result:= ['TLeaf|' + AG_LEAF_PAS + '|TMid', 'TMid|' + AG_MID_PAS + '|TBase', 'TBase|' + AG_BASE_PAS + '|TForm'];
  end;

  function Rd(const ALeafDfm, AMidDfm: string): TDfmTextReader;
  begin
    Result:= FakeReader([ChangeFileExt(AG_LEAF_PAS, '.dfm'), ChangeFileExt(AG_MID_PAS, '.dfm'), ChangeFileExt(AG_BASE_PAS, '.dfm')],
      [ALeafDfm, AMidDfm, AG_BASE_DFM]);
  end;

begin
  LInh:= AnalyzeUnit(AG_LEAF_PAS, AgPairs, FakeLookup(Rows, nil), Rd(LEAF_INH_DFM, AG_MID_DFM), nil);
  Check('ag.analyze.ancestors.root.first', LInh.Known and (Length(LInh.Ancestors) = 2) and SameText(LInh.Ancestors[0].PasPath, AG_BASE_PAS)
    and SameText(LInh.Ancestors[1].PasPath, AG_MID_PAS), LInh.Error);
  Check('ag.analyze.intermediate.converted', (Length(LInh.Ancestors) = 2) and (Length(LInh.Ancestors[1].Types) = 0));
  Check('ag.analyze.verdicts.kept', (Length(LInh.Verdicts) = 1) and (LInh.Verdicts[0].State = asUnconverted));
  LInh:= AnalyzeUnit(AG_LEAF_PAS, AgPairs, FakeLookup(Rows, nil), Rd(LEAF_INH_DFM, AG_MID_OWN_DFM), nil);
  Check('ag.analyze.intermediate.unconverted', (Length(LInh.Ancestors) = 2) and (string.Join(',', LInh.Ancestors[1].Types) = 'TTable'));
  LInh:= AnalyzeUnit(AG_LEAF_PAS, AgPairs, FakeLookup(Rows, nil), Rd(LEAF_OWN_DFM, AG_MID_DFM), nil);
  Check('ag.analyze.no.instance.strict', LInh.Known and (Length(LInh.Verdicts) = 0) and (Length(LInh.Ancestors) = 2)
    and (string.Join(',', LInh.Ancestors[0].Types) = 'TTable'), LInh.Error);
  LInh:= AnalyzeUnit(AG_LEAF_PAS, AgPairs, FakeLookup(['TLeaf|' + AG_LEAF_PAS + '|TForm'], nil), Rd(LEAF_OWN_DFM, AG_MID_DFM), nil);
  Check('ag.analyze.outside.silent', LInh.Known and (Length(LInh.Ancestors) = 0), LInh.Error);
  LInh:= AnalyzeUnit(AG_LEAF_PAS, AgPairs, FakeLookup(['TLeaf|' + AG_LEAF_PAS + '|TMid', 'TMid|' + AG_MID_PAS + '|TBase', 'TBase|!|boom'], nil),
    Rd(LEAF_OWN_DFM, AG_MID_DFM), nil);
  Check('ag.analyze.error.unknown', (not LInh.Known) and (Pos('boom', LInh.Error) > 0) and (Length(LInh.Ancestors) = 0), LInh.Error);
  LInh:= AnalyzeUnit(AG_LEAF_PAS, AgPairs, FakeLookup([], nil), Rd(LEAF_OWN_DFM, AG_MID_DFM), nil);
  Check('ag.analyze.own.not.indexed.e3', LInh.Known and (Length(LInh.Ancestors) = 0));
end;

procedure TestAncestorChainUnion;
var
  LInh: TUnitInheritance;

  function Anc(const APas: string; ADepth: Integer; const ATypes: TArray<string>): TAncestorUnit;
  begin
    Result.PasPath:= APas;
    Result.Depth  := ADepth;
    Result.Types  := ATypes;
  end;

begin
  LInh:= Default(TUnitInheritance);
  LInh.UnitPas  := AG_LEAF_PAS;
  LInh.Known    := True;
  LInh.Ancestors:= [Anc(AG_BASE_PAS, 2, ['TTable']), Anc(AG_MID_PAS, 1, [])];
  Check('ag.chain.graph.only', string.Join(',', AncestorChain(LInh)) = AG_BASE_PAS, string.Join(',', AncestorChain(LInh)));
  LInh.Ancestors[1].Types:= ['TQuery'];
  Check('ag.chain.intermediate.included', string.Join(',', AncestorChain(LInh)) = AG_BASE_PAS + ',' + AG_MID_PAS);
  Check('ag.chain.types.union', string.Join(',', UnconvertedTypes(LInh)) = 'TTable,TQuery');
  Check('ag.chain.note', InheritanceRowNote(LInh, True) = 'descends from Base, which still has TTable -- convert it first (recommended); descends from Mid, which still has TQuery -- convert it first (recommended)',
    InheritanceRowNote(LInh, True));
  // a verdict naming Base: Base is listed once, and the E5 part replaces the ancestor part for it
  SetLength(LInh.Verdicts, 1);
  LInh.Verdicts[0]:= Default(TInstanceVerdict);
  LInh.Verdicts[0].Instance.Name    := 'tblX';
  LInh.Verdicts[0].Instance.TypeName:= 'TTable';
  LInh.Verdicts[0].State            := asUnconverted;
  LInh.Verdicts[0].DeclaringUnit    := 'Base';
  LInh.Verdicts[0].DeclaringPas     := AG_BASE_PAS;
  SetLength(LInh.Verdicts[0].Chain, 1);
  LInh.Verdicts[0].Chain[0].PasPath:= AG_BASE_PAS;
  LInh.Verdicts[0].Chain[0].Depth  := 2;
  Check('ag.chain.dedupe', string.Join(',', AncestorChain(LInh)) = AG_BASE_PAS + ',' + AG_MID_PAS, string.Join(',', AncestorChain(LInh)));
  Check('ag.chain.note.verdict.first', InheritanceRowNote(LInh, True) = 'inherits 1 TTable instance(s) from Base -- convert it first (recommended); descends from Mid, which still has TQuery -- convert it first (recommended)',
    InheritanceRowNote(LInh, True));
  LInh.Ancestors:= nil;
  Check('ag.chain.verdicts.only.unchanged', string.Join(',', AncestorChain(LInh)) = AG_BASE_PAS);
end;
