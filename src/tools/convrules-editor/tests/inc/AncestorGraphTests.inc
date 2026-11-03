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