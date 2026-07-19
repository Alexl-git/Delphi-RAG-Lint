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
  ConvRules.Engine in '..\ConvRules.Engine.pas',
  ConvRules.Platform in '..\ConvRules.Platform.pas';

var
  GPass: Integer = 0;
  GFail: Integer = 0;
  GSkip: Integer = 0;

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

{ A test that could not run because its environment precondition (a real index DB
  or the exe) is absent -- recorded as SKIP, not FAIL, so the model-test suite
  still passes on a machine without the big library indexes. }
procedure Skip(const AName, AReason: string);
begin
  Inc(GSkip);
  Writeln('SKIP  ', AName, '  (', AReason, ')');
end;

{ Case-insensitive membership over a bare-name array (what a picker's Items hold). }
function Contains(const AArr: TArray<string>; const AName: string): Boolean;
var
  S: string;
begin
  for S in AArr do
    if SameText(S, AName) then Exit(True);
  Result := False;
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

{ Unknown-type inference: a property inherited from an unresolved parent comes back
  type='unknown' (e.g. TcxButton.Align). When the same-named From property HAS a
  type, adopt it for both -> the pair becomes an identity link, not blocked. }
procedure TestUnknownTypeInference;
var
  f, t: string;
begin
  Check('unknown.detect.word',  IsUnknownType('unknown'));
  Check('unknown.detect.empty', IsUnknownType(''));
  Check('unknown.detect.ci',    IsUnknownType('Unknown'));
  Check('unknown.detect.real',  not IsUnknownType('TAlign'));

  // To side unknown (the real TabcToggleBtn.Align -> TcxButton.Align case).
  f := 'TAlign'; t := 'unknown';
  ResolveUnknownTypes(f, t);
  Check('unknown.infer.to', (f = 'TAlign') and (t = 'TAlign'), Format('[%s/%s]', [f, t]));
  Check('unknown.infer.to.castable', IsCastable(f, t)); // identity now

  // From side unknown (symmetric).
  f := ''; t := 'TColor';
  ResolveUnknownTypes(f, t);
  Check('unknown.infer.from', (f = 'TColor') and (t = 'TColor'), Format('[%s/%s]', [f, t]));

  // Both unknown -> ResolveUnknownTypes can't infer (leaves both as-is), but the
  // pair is still same-named-same-unresolved-parent, so IsCastable's identical-name
  // rule treats it as an identity link. That is the intended, useful outcome: two
  // same-named properties both inherited from an unresolved parent are the same
  // member (both Align from TControl), so the link is allowed.
  f := 'unknown'; t := 'unknown';
  ResolveUnknownTypes(f, t);
  Check('unknown.both.unresolved', IsUnknownType(f) and IsUnknownType(t));
  Check('unknown.both.identity', IsCastable('unknown', 'unknown'));

  // Known-but-different types are NOT touched (no false identity).
  f := 'TAlign'; t := 'TColor';
  ResolveUnknownTypes(f, t);
  Check('unknown.known.untouched', (f = 'TAlign') and (t = 'TColor'));
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

{ ---------------------------------------------------------------------------
  IN-PROCESS PICKER DATASOURCE tests.

  These do NOT poke the DB with a shell `query` -- they drive the SAME code path
  the editor's combo boxes use: a real TEngineAdapter, its ListDescendantsOf /
  ListProjectUnits methods (spawn drag-lint, parse, filter, dedupe). Whatever
  these return is exactly what would populate FCbFrom / FCbTo / FCbUnit. So a
  PASS proves the item survives the exe's own parsing/filtering, not merely that
  the raw DB row exists -- if the code filtered TOvcTable/TTable/VARINSP out, the
  Contains() assert fails here even though the DB has the row.

  The DB sets below are copied from ConvRulesEditor.dpr (FromDbs / ToDbs / the
  project DB the From-Unit picker uses). Skipped (not failed) when the exe or the
  required DBs are absent, so the suite still passes on a lean machine. }
const
  LibWin32  = 'C:\Projects\.drag-lint\library-Win32.sqlite';
  LibWin64  = 'C:\Projects\.drag-lint\library-Win64.sqlite';
  ProjectDb = 'C:\Projects\DB\ORM3\drag-lint.sqlite';

{ Resolve the real drag-lint.exe the editor would use (next to this runner, else
  the deployed dll-win64 copy, else PATH). '' if none found. }
function ResolveExe: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'drag-lint.exe');
  if TFile.Exists(Result) then Exit;
  Result := 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe';
  if TFile.Exists(Result) then Exit;
  Result := '';
end;

procedure TestPickerDatasource;
var
  Exe    : string;
  Adapter: TEngineAdapter;
  FromSet, ToSet, Units: TArray<string>;
  Err    : string;
  OK     : Boolean;
begin
  Exe := ResolveExe;
  if Exe = '' then
  begin
    Skip('picker.datasource', 'drag-lint.exe not found');
    Exit;
  end;

  // --- FROM picker: what FCbFrom would hold ---
  // Editor: ListDescendantsOf('TComponent', GEditorFromDbs=[Win32,Win64,proj]).
  if not (TFile.Exists(LibWin32) and TFile.Exists(LibWin64)) then
    Skip('picker.from.datasource', 'library-Win32/Win64 db(s) absent')
  else
  begin
    Adapter := TEngineAdapter.Create(Exe, [LibWin32, LibWin64, ProjectDb]);
    try
      OK := Adapter.ListDescendantsOf('TComponent', [LibWin32, LibWin64, ProjectDb],
              FromSet, Err);
      Check('picker.from.query.ok', OK, Err);
      Check('picker.from.nonempty', Length(FromSet) > 100,
        Format('only %d classes', [Length(FromSet)]));
      // The three the user reported missing -- assert they SURVIVE the exe's
      // parse+dedupe and reach the combo's Items.
      Check('picker.from.has.TOvcTable', Contains(FromSet, 'TOvcTable'),
        'Orpheus TOvcTable not in FROM datasource');
      Check('picker.from.has.TTable', Contains(FromSet, 'TTable'),
        'BDE TTable not in FROM datasource');
      // Sanity anchors: a plain VCL control + a DevExpress control.
      Check('picker.from.has.TEdit', Contains(FromSet, 'TEdit'));
      Check('picker.from.has.TcxGrid', Contains(FromSet, 'TcxGrid'));
    finally
      Adapter.Free;
    end;
  end;

  // --- TO picker: what FCbTo would hold ---
  // Editor: ListDescendantsOf('TControl', GEditorToDbs=[Win64,proj]).
  if not TFile.Exists(LibWin64) then
    Skip('picker.to.datasource', 'library-Win64 db absent')
  else
  begin
    Adapter := TEngineAdapter.Create(Exe, [LibWin64, ProjectDb]);
    try
      OK := Adapter.ListDescendantsOf('TControl', [LibWin64, ProjectDb], ToSet, Err);
      Check('picker.to.query.ok', OK, Err);
      Check('picker.to.has.TcxGrid', Contains(ToSet, 'TcxGrid'));
      // TTable is non-visual (TComponent, not TControl) -> must NOT be a TO option.
      Check('picker.to.excludes.TTable', not Contains(ToSet, 'TTable'),
        'non-visual TTable leaked into the TO (target control) datasource');
    finally
      Adapter.Free;
    end;
  end;

  // --- From-Unit picker: what FCbUnit would hold ---
  // Editor: ListProjectUnits over the adapter's DBs (project DB carries units).
  if not TFile.Exists(ProjectDb) then
    Skip('picker.unit.datasource', 'ORM3 project db absent')
  else
  begin
    Adapter := TEngineAdapter.Create(Exe, [ProjectDb]);
    try
      OK := Adapter.ListProjectUnits(Units, Err);
      Check('picker.unit.query.ok', OK, Err);
      Check('picker.unit.nonempty', Length(Units) > 100,
        Format('only %d units', [Length(Units)]));
      Check('picker.unit.has.VARINSP', Contains(Units, 'VARINSP'),
        'VARINSP not in From-Unit datasource (reindex CLIENT\VARINSP.PAS)');
    finally
      Adapter.Free;
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  "Fill From-column" datasource -- ListControlTypesInUnit.

  This is the code behind the editor's "Fill From-column" button: given a
  project unit the user picked, it must return the component TYPES declared in
  that unit's form so they can be pre-filled into the grid's From column. The
  bug: for VARINSP it returned [] (nothing appeared). This drives the real
  TEngineAdapter method and asserts the actual components come back. Skipped
  (not failed) when the exe / ORM3 db / VARINSP.DFM are absent. }
procedure TestFillFromUnit;
var
  Exe    : string;
  Adapter: TEngineAdapter;
  Types  : TArray<string>;
  Err    : string;
  OK     : Boolean;
begin
  Exe := ResolveExe;
  if (Exe = '') or (not TFile.Exists(ProjectDb))
     or (not TFile.Exists('C:\Projects\DB\ORM3\CLIENT\VARINSP.DFM')) then
  begin
    Skip('fill.from-unit.varinsp', 'exe / ORM3 db / VARINSP.DFM absent');
    Exit;
  end;
  // The editor passes the FROM db set (both libs + project) as the control set
  // source; ListControlTypesInUnit resolves the unit's file via the adapter DBs.
  Adapter := TEngineAdapter.Create(Exe, [LibWin32, LibWin64, ProjectDb]);
  try
    OK := Adapter.ListControlTypesInUnit('VARINSP', [], Types, Err);
    Check('fill.from-unit.ok', OK, Err);
    // The button was silent because this came back empty. It must not.
    Check('fill.from-unit.nonempty', Length(Types) > 10,
      Format('VARINSP returned only %d types (expected its form components)',
        [Length(Types)]));
    // Concrete components the user can see in the VARINSP form / DFM.
    Check('fill.from-unit.has.TOvcController', Contains(Types, 'TOvcController'));
    Check('fill.from-unit.has.TPanel', Contains(Types, 'TPanel'));
    Check('fill.from-unit.has.TOvcTable', Contains(Types, 'TOvcTable'));
  finally
    Adapter.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Bare class name -> proptree. The pickers hand GetProptree a BARE class name
  (TabcToggleBtn, TcxButton), but `proptree --qname` needs a UNIT-QUALIFIED name
  (Abcbtn.TabcToggleBtn). The bug: GetProptree passed the bare name straight
  through -> "class not found" (which exits 0) -> empty tree -> the editor showed
  "<Class> is not indexed (no properties found)". After the fix GetProptree
  auto-qualifies a bare, unique class name. Skipped when the exe/libs are absent. }
procedure TestProptreeBareClass;
var
  Exe    : string;
  Adapter: TEngineAdapter;
  Tree   : TProptree;
  Err    : string;
  OK     : Boolean;
begin
  Exe := ResolveExe;
  if (Exe = '') or (not TFile.Exists(LibWin64)) then
  begin
    Skip('proptree.bareclass', 'exe / library-Win64 db absent');
    Exit;
  end;
  Adapter := TEngineAdapter.Create(Exe, [LibWin32, LibWin64, ProjectDb]);
  try
    // TabcToggleBtn is Abcbtn.TabcToggleBtn -- the exact class the user picked.
    OK := Adapter.GetProptree('TabcToggleBtn', Tree, Err);
    Check('proptree.bareclass.ok', OK, Err);
    Check('proptree.bareclass.nonempty', Length(Tree.Leaves) > 0,
      Format('TabcToggleBtn resolved to %d leaves (bug: bare name not qualified)',
        [Length(Tree.Leaves)]));
    // An already-qualified name must still work (no double-qualify regression).
    OK := Adapter.GetProptree('Abcbtn.TabcToggleBtn', Tree, Err);
    Check('proptree.qualified.still.ok', OK and (Length(Tree.Leaves) > 0), Err);
  finally
    Adapter.Free;
  end;
end;

procedure TestPlatform;
const
  LibDir = 'C:\Lib\';
var
  d32, d64, dboth: TArray<string>;
begin
  // ParsePlatform: case-insensitive, default fallback.
  Check('platform.parse.win32', ParsePlatform('Win32', cpBoth) = cpWin32);
  Check('platform.parse.win64', ParsePlatform('WIN64', cpBoth) = cpWin64);
  Check('platform.parse.both',  ParsePlatform('both',  cpWin32) = cpBoth);
  Check('platform.parse.empty->default',   ParsePlatform('',    cpWin64) = cpWin64);
  Check('platform.parse.unknown->default', ParsePlatform('arm', cpWin32) = cpWin32);

  // PlatformToStr round-trips the tokens.
  Check('platform.tostr.win32', PlatformToStr(cpWin32) = 'win32');
  Check('platform.tostr.win64', PlatformToStr(cpWin64) = 'win64');
  Check('platform.tostr.both',  PlatformToStr(cpBoth)  = 'both');

  // LibDbsFor: one lib for a single platform, both for cpBoth (Win32 first).
  d32 := LibDbsFor(cpWin32, LibDir);
  Check('platform.libdbs.win32.count', Length(d32) = 1);
  Check('platform.libdbs.win32.path', d32[0] = 'C:\Lib\library-Win32.sqlite');
  d64 := LibDbsFor(cpWin64, LibDir);
  Check('platform.libdbs.win64.path', (Length(d64) = 1) and (d64[0] = 'C:\Lib\library-Win64.sqlite'));
  dboth := LibDbsFor(cpBoth, LibDir);
  Check('platform.libdbs.both.count', Length(dboth) = 2);
  Check('platform.libdbs.both.order', (dboth[0] = 'C:\Lib\library-Win32.sqlite')
                                  and (dboth[1] = 'C:\Lib\library-Win64.sqlite'));
end;

begin
  try
    TestPlatform;
    TestRoundTrip;
    TestParseKinds;
    TestCastGuard;
    TestBlockHelpers;
    TestEditReemit;
    TestCastClassifier;
    TestUnknownTypeInference;
    TestProptreeParse;
    TestProptreeNoise;
    TestSaveComplete;
    TestPickerDatasource;
    TestFillFromUnit;
    TestProptreeBareClass;

    Writeln('');
    Writeln(Format('model-tests: %d pass / %d fail / %d skip / %d total',
      [GPass, GFail, GSkip, GPass + GFail + GSkip]));
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
