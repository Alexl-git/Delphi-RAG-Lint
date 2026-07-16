program ConvRulesModelTests;

{ Self-contained console test runner for the ConvRules.Model DSL model.
  No DUnitX dependency (keeps the utility lean); prints PASS/FAIL per case and
  exits non-zero on any failure so the build/CI can gate on it. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  ConvRules.Model in '..\ConvRules.Model.pas',
  ConvRules.Casts in '..\ConvRules.Casts.pas',
  ConvRules.Engine in '..\ConvRules.Engine.pas';

var
  GPass: Integer = 0;
  GFail: Integer = 0;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then
  begin
    Inc(GPass);
    Writeln('PASS  ', AName);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL  ', AName, '  ', ADetail);
  end;
end;

{ Round-trip: an untouched file must re-emit byte-faithfully (modulo the canonical
  trailing CRLF the model adds per line). }
procedure TestRoundTrip;
const
  SRC =
    '#convert Unit.TFrom -> Unit.TTo, Unit'#13#10 +
    '// a hand comment'#13#10 +
    '; another comment'#13#10 +
    '#link Text <- Text'#13#10 +
    '#link Style.Font.Size <- Font.Size : IntToStr'#13#10 +
    '#default Caption = ''untitled'''#13#10 +
    '#ignore TabOrder'#13#10 +
    '#remove SessionName'#13#10 +
    '#remove DFM: Origin'#13#10 +
    '#unuse BDE.DBTables'#13#10 +
    '#migrate TTransIsolation -> TFDTxIsolation, FireDAC.Stan.Option'#13#10 +
    'ukModify -> arUpdate'#13#10 +
    '#note candidates: Color, Sub.Color'#13#10 +
    ''#13#10;
var
  Book: TRuleBook;
  Out : string   ;
begin
  Book := TRuleBook.Create;
  try
    Book.LoadFromString(SRC);
    Out := Book.SaveToString;
    Check('roundtrip.byte-faithful', Out = SRC,
      Format('got %d bytes, want %d', [Length(Out), Length(SRC)]));
  finally
    Book.Free;
  end;
end;

procedure TestParseKinds;
var
  Book: TRuleBook;
begin
  Book := TRuleBook.Create;
  try
    Book.LoadFromString(
      '#convert A.TFrom -> B.TTo, B'#13#10 +
      '#link ToP <- FromP'#13#10 +
      '#link ToC <- FromC : IntToStr'#13#10 +
      '#default Cap = ''x'''#13#10 +
      '#ignore Skip'#13#10 +
      '#remove Prop1'#13#10 +
      '#remove DFM: Prop2'#13#10 +
      '#unuse SomeUnit'#13#10 +
      '#note hi'#13#10 +
      '// c'#13#10 +
      'x -> y'#13#10);

    Check('parse.convert.kind',   Book.Nodes[0].Kind = rnkConvert);
    Check('parse.convert.from',   Book.Nodes[0].FromType = 'A.TFrom', Book.Nodes[0].FromType);
    Check('parse.convert.to',     Book.Nodes[0].ToType = 'B.TTo',   Book.Nodes[0].ToType);
    Check('parse.convert.units',  Book.Nodes[0].Units = 'B',        Book.Nodes[0].Units);

    Check('parse.link.kind',      Book.Nodes[1].Kind = rnkLink);
    Check('parse.link.to',        Book.Nodes[1].LinkTo = 'ToP',     Book.Nodes[1].LinkTo);
    Check('parse.link.from',      Book.Nodes[1].LinkFrom = 'FromP', Book.Nodes[1].LinkFrom);
    Check('parse.link.nocast',    Book.Nodes[1].Cast = '',          '['+Book.Nodes[1].Cast+']');

    Check('parse.link.cast',      Book.Nodes[2].Cast = 'IntToStr',  Book.Nodes[2].Cast);
    Check('parse.link.cast.from', Book.Nodes[2].LinkFrom = 'FromC', Book.Nodes[2].LinkFrom);

    Check('parse.default.to',     Book.Nodes[3].DefTo = 'Cap',      Book.Nodes[3].DefTo);
    Check('parse.default.value',  Book.Nodes[3].DefValue = '''x''', Book.Nodes[3].DefValue);

    Check('parse.ignore',         Book.Nodes[4].IgnorePath = 'Skip', Book.Nodes[4].IgnorePath);

    Check('parse.remove.plain',   (Book.Nodes[5].Kind = rnkRemove) and not Book.Nodes[5].RemoveDfmOnly and (Book.Nodes[5].RemoveProp = 'Prop1'));
    Check('parse.remove.dfm',     (Book.Nodes[6].Kind = rnkRemove) and Book.Nodes[6].RemoveDfmOnly and (Book.Nodes[6].RemoveProp = 'Prop2'), Book.Nodes[6].RemoveProp);

    Check('parse.unuse',          Book.Nodes[7].UnuseUnit = 'SomeUnit', Book.Nodes[7].UnuseUnit);
    Check('parse.note',           Book.Nodes[8].NoteText = 'hi',    Book.Nodes[8].NoteText);
    Check('parse.comment',        Book.Nodes[9].Kind = rnkComment);
    Check('parse.pcre',           Book.Nodes[10].Kind = rnkPcre);
  finally
    Book.Free;
  end;
end;

{ A ':' that is NOT a valid cast tail (has a space / dot) must stay in FromPath. }
procedure TestCastGuard;
var
  Book: TRuleBook;
begin
  Book := TRuleBook.Create;
  try
    Book.LoadFromString(
      '#link ToP <- From.Path'#13#10 +          // dotted path, no cast
      '#link ToP <- FromP : Not A Cast'#13#10);  // tail has spaces -> not a cast
    Check('cast.guard.dotted.nocast', Book.Nodes[0].Cast = '', '['+Book.Nodes[0].Cast+']');
    Check('cast.guard.dotted.from',   Book.Nodes[0].LinkFrom = 'From.Path', Book.Nodes[0].LinkFrom);
    Check('cast.guard.spaces.nocast', Book.Nodes[1].Cast = '', '['+Book.Nodes[1].Cast+']');
  finally
    Book.Free;
  end;
end;

procedure TestBlockHelpers;
var
  Book   : TRuleBook;
  Heads  : TArray<Integer>;
  Links  : TArray<TRuleNode>;
begin
  Book := TRuleBook.Create;
  try
    Book.LoadFromString(
      '#convert A -> B'#13#10 +
      '#link a <- a'#13#10 +
      '#link b <- b'#13#10 +
      '#convert C -> D'#13#10 +
      '#link c <- c'#13#10);
    Heads := Book.ConvertHeaders;
    Check('block.headers.count', Length(Heads) = 2, IntToStr(Length(Heads)));
    Links := Book.LinksForBlock(Heads[0]);
    Check('block.links.first', Length(Links) = 2, IntToStr(Length(Links)));
    Links := Book.LinksForBlock(Heads[1]);
    Check('block.links.second', Length(Links) = 1, IntToStr(Length(Links)));
  finally
    Book.Free;
  end;
end;

{ Editing a typed field marks the node Dirty and re-emits from fields. }
procedure TestEditReemit;
var
  Book: TRuleBook;
begin
  Book := TRuleBook.Create;
  try
    Book.LoadFromString('#link ToP <- ???'#13#10);
    Book.Nodes[0].LinkFrom := 'RealSource';
    Book.Nodes[0].Cast     := 'IntToStr';
    Book.Nodes[0].Dirty    := True;
    Check('edit.reemit', Book.Nodes[0].Emit = '#link ToP <- RealSource : IntToStr',
      Book.Nodes[0].Emit);
  finally
    Book.Free;
  end;
end;

procedure TestCastClassifier;
begin
  // identity: same family -> no casts, but IsCastable true
  Check('cast.same.int',   ValidCasts('Integer', 'Int64') = [], 'expected identity');
  Check('cast.same.castable', IsCastable('Integer', 'Int64'));
  Check('cast.same.family', SameFamily('Double', 'Single'));

  // numeric -> string
  Check('cast.int2str',    ValidCasts('Integer', 'string') = [cfIntToStr]);
  Check('cast.float2str',  ValidCasts('Double', 'string') = [cfFloatToStr]);

  // string -> numeric (two options each)
  Check('cast.str2int',    ValidCasts('string', 'Integer') = [cfStrToInt, cfStrToIntDef]);
  Check('cast.str2float',  ValidCasts('string', 'Double') = [cfStrToFloat, cfStrToFloatDef]);

  // widening / narrowing
  Check('cast.int2float',  ValidCasts('Integer', 'Double') = [cfIntToFloat]);
  Check('cast.float2int',  ValidCasts('Double', 'Integer') = [cfTrunc, cfRound]);

  // bool -> string
  Check('cast.bool2str',   ValidCasts('Boolean', 'string') = [cfBoolToStr]);

  // SAME class/enum type is an identity link -> ALWAYS castable, no cast needed
  Check('cast.sameclass.castable', IsCastable('TFont', 'TFont'));
  Check('cast.sameclass.nocast',   ValidCasts('TFont', 'TFont') = []);
  Check('cast.sameenum.castable',  IsCastable('TAlignment', 'TAlignment'));
  Check('cast.sameclass.ci',       IsCastable('tfont', 'TFont')); // case-insensitive

  // DIFFERENT incompatible types -> blocked
  Check('cast.enum.blocked', not IsCastable('TAlignment', 'TColor'));
  Check('cast.class.blocked', not IsCastable('TFont', 'TStrings'));

  // name round-trip
  Check('cast.name.int2str', CastFnName(cfIntToStr) = 'IntToStr', CastFnName(cfIntToStr));
  Check('cast.name.parse',   CastFnFromName('round') = cfRound);
  Check('cast.name.unknown', CastFnFromName('Bogus') = cfNone);
end;

{ Parse a real captured proptree/1 JSON fixture (schema stability + leaf fields). }
procedure TestProptreeParse;
var
  FixturePath: string;
  Json: string;
  Tree: TProptree;
  Found: Boolean;
  L: TPropLeaf;
begin
  FixturePath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'fixtures\proptree-tfont.json');
  if not TFile.Exists(FixturePath) then
    // fixture lives next to the .dpr when run from the tests dir
    FixturePath := 'fixtures\proptree-tfont.json';
  if not TFile.Exists(FixturePath) then
  begin
    Check('proptree.fixture.present', False, 'fixture not found: ' + FixturePath);
    Exit;
  end;
  Json := TFile.ReadAllText(FixturePath);
  Tree := ParseProptreeJson(Json);
  Check('proptree.roottype', Tree.RootType = 'TFont', Tree.RootType);
  Check('proptree.hasleaves', Length(Tree.Leaves) > 0, IntToStr(Length(Tree.Leaves)));
  // every leaf has a path + a declared_in
  Found := True;
  for L in Tree.Leaves do
    if (L.Path = '') or (L.DeclaredIn = '') then Found := False;
  Check('proptree.leaves.wellformed', Found);
  // a known scalar leaf: PixelsPerInch : Integer
  Found := False;
  for L in Tree.Leaves do
    if (L.Path = 'PixelsPerInch') and (L.TypeName = 'Integer') then Found := True;
  Check('proptree.leaf.pixelsperinch', Found);
end;

{ The real bug: drag-lint appends a "(loaded defaults ...)" line AFTER the JSON.
  The parser must tolerate preamble/trailing noise by slicing the JSON object. }
procedure TestProptreeNoise;
const
  NOISY =
    '{'#13#10 +
    '  "schema": "proptree/1",'#13#10 +
    '  "root_type": "TFoo",'#13#10 +
    '  "properties": ['#13#10 +
    '    { "path": "Size", "type": "Integer", "declared_in": "U.TFoo",'#13#10 +
    '      "kind": "scalar", "is_class_typed": false }'#13#10 +
    '  ]'#13#10 +
    '}'#13#10 +
    '(loaded defaults from C:\Projects\.drag-lint.json)'#13#10;
var
  Tree: TProptree;
begin
  Tree := ParseProptreeJson(NOISY);
  Check('proptree.noise.roottype', Tree.RootType = 'TFoo', Tree.RootType);
  Check('proptree.noise.leafcount', Length(Tree.Leaves) = 1, IntToStr(Length(Tree.Leaves)));
  if Length(Tree.Leaves) = 1 then
    Check('proptree.noise.leafpath', Tree.Leaves[0].Path = 'Size', Tree.Leaves[0].Path);
end;

{ Save must DROP #convert blocks with no #link (empty rules), keep complete ones
  and any leading non-block content. }
procedure TestSaveComplete;
var
  Book: TRuleBook;
  dropped: Integer;
  outp: string;
begin
  Book := TRuleBook.Create;
  try
    Book.LoadFromString(
      '// header comment'#13#10 +
      '#convert A.TFrom -> B.TTo'#13#10 +      // complete: has a link
      '#link X <- Y'#13#10 +
      '#convert C.TFoo -> D.TBar'#13#10 +      // EMPTY: no link -> dropped
      '#note nothing mapped yet'#13#10 +
      '#convert E.TA -> F.TB'#13#10 +          // complete
      '#link P <- Q'#13#10);
    outp := Book.SaveCompleteToString(dropped);
    Check('savecomplete.dropcount', dropped = 1, IntToStr(dropped));
    Check('savecomplete.keeps.comment', Pos('// header comment', outp) > 0);
    Check('savecomplete.keeps.first', Pos('#convert A.TFrom -> B.TTo', outp) > 0);
    Check('savecomplete.drops.empty', Pos('C.TFoo', outp) = 0, 'empty rule leaked');
    Check('savecomplete.keeps.last', Pos('#convert E.TA -> F.TB', outp) > 0);
  finally
    Book.Free;
  end;
end;

begin
  try
    TestRoundTrip;
    TestParseKinds;
    TestCastGuard;
    TestBlockHelpers;
    TestEditReemit;
    TestCastClassifier;
    TestProptreeParse;
    TestProptreeNoise;
    TestSaveComplete;

    Writeln('');
    Writeln(Format('model-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
    if GFail > 0 then
      Halt(1);
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message);
      Halt(2);
    end;
  end;
end.
