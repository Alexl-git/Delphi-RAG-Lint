program ConvRulesModelTests;

{ Self-contained console test runner for the ConvRules.Model DSL model.
  No DUnitX dependency (keeps the utility lean); prints PASS/FAIL per case and
  exits non-zero on any failure so the build/CI can gate on it. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  Winapi.Windows,
  ConvRules.Model in '..\ConvRules.Model.pas',
  ConvRules.Mappings in '..\ConvRules.Mappings.pas',
  ConvRules.Units in '..\ConvRules.Units.pas',
  ConvRules.Casts in '..\ConvRules.Casts.pas',
  ConvRules.CastLib in '..\ConvRules.CastLib.pas',
  ConvRules.BlockFile in '..\ConvRules.BlockFile.pas',
  ConvRules.BlockOps in '..\ConvRules.BlockOps.pas',
  ConvRules.WorkingSet in '..\ConvRules.WorkingSet.pas',
  ConvRules.Engine in '..\ConvRules.Engine.pas',
  ConvRules.Platform in '..\ConvRules.Platform.pas',
  ConvRules.Theme in '..\ConvRules.Theme.pas',
  ConvRules.Usage in '..\ConvRules.Usage.pas';

var
  GPass: Integer = 0;
  GFail: Integer = 0;
  GSkip: Integer = 0;
  { Owns every node handed out by ParseAll, so the fixture can return a plain
    TArray<TRuleNode> the caller never has to free. Created on first use, freed once
    at the end of the run. }
  GParseBook: TRuleBook = nil;

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

{ Case-insensitive count of a name in a bare-name array. }
function CountOf(const AArr: TArray<string>; const AName: string): Integer;
var
  S: string;
begin
  Result := 0;
  for S in AArr do
    if SameText(S, AName) then Inc(Result);
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

{ proptree/2 (engine schema v17): per-leaf is_writable / visibility / member_kind,
  with proptree/1 back-compat defaults (absent is_writable => True; absent
  member_kind => 'property'; absent visibility => ''). }
procedure TestProptree2Fields;
const
  J2 =
    '{'#13#10 +
    '  "schema": "proptree/2",'#13#10 +
    '  "root_type": "TFoo",'#13#10 +
    '  "properties": ['#13#10 +
    '    { "path": "Caption", "type": "string", "declared_in": "U.TFoo", "kind": "scalar",'#13#10 +
    '      "is_class_typed": false, "is_writable": true, "visibility": "published", "member_kind": "property" },'#13#10 +
    '    { "path": "Handle", "type": "HWND", "declared_in": "U.TFoo", "kind": "scalar",'#13#10 +
    '      "is_class_typed": false, "is_writable": false, "visibility": "public", "member_kind": "property" },'#13#10 +
    '    { "path": "FBuf", "type": "TBytes", "declared_in": "U.TFoo", "kind": "scalar",'#13#10 +
    '      "is_class_typed": false, "is_writable": true, "visibility": "public", "member_kind": "field" },'#13#10 +
    '    { "path": "Legacy", "type": "Integer", "declared_in": "U.TFoo", "kind": "scalar",'#13#10 +
    '      "is_class_typed": false }'#13#10 +
    '  ]'#13#10 +
    '}'#13#10;
var
  Tree: TProptree;

  function LeafOf(const P: string): TPropLeaf;
  var x: TPropLeaf;
  begin
    Result := Default(TPropLeaf);
    for x in Tree.Leaves do
      if SameText(x.Path, P) then Exit(x);
  end;

begin
  Tree := ParseProptreeJson(J2);
  Check('proptree2.count', Length(Tree.Leaves) = 4, IntToStr(Length(Tree.Leaves)));
  Check('proptree2.caption.writable', LeafOf('Caption').IsWritable);
  Check('proptree2.caption.vis', LeafOf('Caption').Visibility = 'published', LeafOf('Caption').Visibility);
  Check('proptree2.handle.readonly', not LeafOf('Handle').IsWritable);
  Check('proptree2.field.kind', LeafOf('FBuf').MemberKind = 'field', LeafOf('FBuf').MemberKind);
  Check('proptree2.field.writable', LeafOf('FBuf').IsWritable);
  // proptree/1 back-compat: the field-less "Legacy" leaf gets safe defaults.
  Check('proptree2.compat.writable', LeafOf('Legacy').IsWritable);
  Check('proptree2.compat.kind', LeafOf('Legacy').MemberKind = 'property', LeafOf('Legacy').MemberKind);
  Check('proptree2.compat.vis', LeafOf('Legacy').Visibility = '', '['+LeafOf('Legacy').Visibility+']');
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
  // 1) next to this runner (a co-deployed exe).
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'drag-lint.exe');
  if TFile.Exists(Result) then Exit;
  // 2) THIS checkout's staged exe -- the runner lives at
  //    <root>\src\tools\convrules-editor\tests\, so climb 4 to the root. Prefer this
  //    over a hardcoded path so the tests exercise the exe built from THIS source
  //    (e.g. a worktree), not a stale sibling checkout missing a just-added flag.
  Result := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\..\..\third_party\dll-win64\drag-lint.exe'));
  if TFile.Exists(Result) then Exit;
  // 3) fallback: the canonical main-checkout deploy.
  Result := 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe';
  if TFile.Exists(Result) then Exit;
  Result := '';
end;

{ True if the ORM3 project DB answers a units query -- i.e. it exists AND is at the
  engine's current schema. The v17 exe REFUSES a pre-v17 DB ("index schema v16 < v17
  ... migrate") and returns 0 rows, so ORM3-dependent live tests SKIP (environment not
  ready -- ORM3 awaits a v17 re-index) rather than FAIL, matching the absent-DB policy. }
function Orm3Queryable(const AExe: string): Boolean;
var
  Adapter: TEngineAdapter;
  Units  : TArray<string>;
  Err    : string;
begin
  Result := False;
  if (AExe = '') or not TFile.Exists(ProjectDb) then Exit;
  Adapter := TEngineAdapter.Create(AExe, [ProjectDb]);
  try
    Result := Adapter.ListProjectUnits(Units, Err) and (Length(Units) > 0);
  finally
    Adapter.Free;
  end;
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
  if (not TFile.Exists(ProjectDb)) or (not Orm3Queryable(Exe)) then
    Skip('picker.unit.datasource', 'ORM3 project db absent or pre-v17 (needs re-index)')
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
     or (not TFile.Exists('C:\Projects\DB\ORM3\CLIENT\VARINSP.DFM'))
     or (not Orm3Queryable(Exe)) then
  begin
    Skip('fill.from-unit.varinsp', 'exe / ORM3 db / VARINSP.DFM absent, or ORM3 pre-v17');
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

{ Live proptree/2: GetProptree at the published surface returns a BOUNDED tree whose
  leaves the parser populated with member_kind, and (published => no fields). Uses
  TcxButton (the user's real target -- fast; other controls can explode without the
  engine's --refs-as-leaves). Skipped when the exe / library-Win64 db is absent. }
procedure TestProptree2Live;
var
  Exe    : string;
  Adapter: TEngineAdapter;
  Tree   : TProptree;
  Err    : string;
  OK, sawField, allKinded: Boolean;
  L      : TPropLeaf;
begin
  Exe := ResolveExe;
  if (Exe = '') or (not TFile.Exists(LibWin64)) then
  begin
    Skip('proptree2.live', 'exe / library-Win64 db absent');
    Exit;
  end;
  Adapter := TEngineAdapter.Create(Exe, [LibWin32, LibWin64, ProjectDb]);
  try
    OK := Adapter.GetProptree('TcxButton', Tree, Err, 'published');
    if not OK or (Length(Tree.Leaves) = 0) then
    begin
      Skip('proptree2.live', 'TcxButton not resolved at published surface (pre-v17 exe?): ' + Err);
      Exit;
    end;
    // Bounded -- a pathological (refs-expanding) tree would be many thousands of leaves.
    Check('proptree2.live.bounded', Length(Tree.Leaves) < 2000,
      Format('%d leaves (unbounded? engine --refs-as-leaves missing)', [Length(Tree.Leaves)]));
    // The parser populated member_kind on every leaf...
    allKinded := True;
    for L in Tree.Leaves do
      if L.MemberKind = '' then allKinded := False;
    Check('proptree2.live.memberkind', allKinded, 'a leaf had empty member_kind');
    // ...and the published surface carries no field members.
    sawField := False;
    for L in Tree.Leaves do
      if SameText(L.MemberKind, 'field') then sawField := True;
    Check('proptree2.live.nofields', not sawField, 'published surface leaked a field member');
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

procedure TestEngineSetDbs;
var
  eng: TEngineAdapter;
begin
  eng := TEngineAdapter.Create('drag-lint.exe', ['a.sqlite']);
  try
    Check('engine.dblist.initial', (Length(eng.DbList) = 1) and (eng.DbList[0] = 'a.sqlite'));
    eng.SetDbs(['x.sqlite', 'y.sqlite']);
    Check('engine.setdbs.count', Length(eng.DbList) = 2);
    Check('engine.setdbs.values', (eng.DbList[0] = 'x.sqlite') and (eng.DbList[1] = 'y.sqlite'));
  finally
    eng.Free;
  end;
end;

{ Platform selection actually re-scopes the FROM picker: TOvcTable (Orpheus) is
  indexed under Win64 only, so a Win64-only FROM DB set lists it and a Win32-only
  set does not -- driven through the exact ListDescendantsOf path the pickers use.
  Skipped (not failed) when the exe or the library DBs are absent. }
procedure TestPlatformRescope;
const
  LibDir    = 'C:\Projects\.drag-lint\';
  ProjectDb = 'C:\Projects\DB\ORM3\drag-lint.sqlite';
var
  Exe: string;
  eng: TEngineAdapter;
  win64Only, win32Only: TArray<string>;
  err: string;
  ok64, ok32: Boolean;
begin
  Exe := ResolveExe;
  if (Exe = '') or (not TFile.Exists(LibDir + 'library-Win64.sqlite'))
     or (not TFile.Exists(LibDir + 'library-Win32.sqlite')) then
  begin
    Skip('platform.rescope', 'exe or library DBs absent');
    Exit;
  end;
  eng := TEngineAdapter.Create(Exe, LibDbsFor(cpBoth, LibDir) + [ProjectDb]);
  try
    ok64 := eng.ListDescendantsOf('TComponent', LibDbsFor(cpWin64, LibDir) + [ProjectDb], win64Only, err);
    ok32 := eng.ListDescendantsOf('TComponent', LibDbsFor(cpWin32, LibDir) + [ProjectDb], win32Only, err);
    Check('platform.rescope.win64.query.ok', ok64, err);
    Check('platform.rescope.win32.query.ok', ok32, err);
    // v17 re-indexed both platform libraries to the SAME corpus (equal counts,
    // Orpheus TOvc* now present in both), so platform rescoping no longer yields
    // distinct sets here -- record SKIP rather than assert stale platform facts.
    if Length(win32Only) = Length(win64Only) then
      Skip('platform.rescope.distinct', 'v17 libraries appear unified (win32 count == win64 count)')
    else
    begin
      Check('platform.rescope.win64.has.TOvcTable', Contains(win64Only, 'TOvcTable'));
      Check('platform.rescope.win32<>win64', Length(win32Only) <> Length(win64Only));
    end;
  finally
    eng.Free;
  end;
end;

{ The picker-side platform DEFAULTS (single-sourced in ConvRules.Platform, consumed
  by both ConvRulesEditor.dpr and ConvRules.MainForm's globals).

  FROM defaulted to cpBoth, which put library-Win32.sqlite -- a 9.5 MB fragment of
  the ~1.9 GB corpus, authoritative for nothing -- FIRST in the DB list that
  `proptree` resolves a qname from (first DB that answers wins). Measured
  2026-07-29 the fragment did not in fact shadow anything (identical leaf counts,
  identical 6180-name descendant lists), so this pins the default rather than a
  truncation claim. cpBoth must remain SELECTABLE -- only the default moved. }
procedure TestPlatformDefaults;
const
  LibDir = 'C:\Lib\';
var
  d: TArray<string>;
  s: string;
  sawWin32, sawWin64: Boolean;
begin
  Check('platform.default.from.win64', DEFAULT_FROM_PLATFORM = cpWin64,
    'FROM default is ' + PlatformToStr(DEFAULT_FROM_PLATFORM)
    + ' -- must not union the library-Win32 fragment');
  Check('platform.default.to.win64', DEFAULT_TO_PLATFORM = cpWin64,
    'TO default is ' + PlatformToStr(DEFAULT_TO_PLATFORM));

  // The DEFAULT FROM db set must not name the fragment at all.
  d := LibDbsFor(DEFAULT_FROM_PLATFORM, LibDir);
  sawWin32 := False; sawWin64 := False;
  for s in d do
  begin
    if Pos('library-Win32', s) > 0 then sawWin32 := True;
    if Pos('library-Win64', s) > 0 then sawWin64 := True;
  end;
  Check('platform.default.from.excludes.win32.fragment', not sawWin32,
    'the default FROM db set still lists library-Win32.sqlite');
  Check('platform.default.from.includes.win64', sawWin64,
    'the default FROM db set does not list library-Win64.sqlite');

  // cpBoth is still reachable: the ABILITY to union deliberately was not removed.
  Check('platform.both.still.parses', ParsePlatform('both', cpWin64) = cpBoth);
  Check('platform.both.still.unions', Length(LibDbsFor(cpBoth, LibDir)) = 2);

  // The platform combos set ItemIndex := Ord(<platform>) over items (Win32,Win64,
  // Both) and read it back as TConvPlatform(ItemIndex). Changing a default only
  // stays consistent while that round-trip holds for the value chosen.
  Check('platform.default.from.itemindex.inrange',
    (Ord(DEFAULT_FROM_PLATFORM) >= Ord(cpWin32)) and (Ord(DEFAULT_FROM_PLATFORM) <= Ord(cpBoth)),
    Format('Ord=%d', [Ord(DEFAULT_FROM_PLATFORM)]));
  Check('platform.default.from.itemindex.roundtrips',
    TConvPlatform(Ord(DEFAULT_FROM_PLATFORM)) = DEFAULT_FROM_PLATFORM);
  Check('platform.default.to.itemindex.roundtrips',
    TConvPlatform(Ord(DEFAULT_TO_PLATFORM)) = DEFAULT_TO_PLATFORM);
end;

{ The engine watchdog must sit ABOVE the slowest call the editor can issue, not
  inside it. At 30000 ms it was below legitimate work on two paths: ValidateText
  (convert-validate) measured 29.83 s -- essentially ON the bound -- and the
  pre-fix proptree call measured 20.11 s warm here and 74-79 s on a colder index.
  Pure: asserts the constant, because the failure mode is a value chosen too small.
  The floor is 3x the slowest measured live call, not the value itself, so tuning
  180000 up or down stays free while a return to 30000 does not. }
procedure TestEngineTimeoutHeadroom;
begin
  Check('engine.timeout.above.slowest.recorded.call', ENGINE_TIMEOUT_MS >= 90000,
    Format('ENGINE_TIMEOUT_MS=%d ms; the slowest call the editor issues measured '
      + '29.83 s (convert-validate) and a pre-fix proptree call took 74-79 s on a '
      + 'cold index, so a watchdog at or below that fires on legitimate work',
      [ENGINE_TIMEOUT_MS]));
end;

{ GetProptree must pass --refs-as-leaves. A TComponent-typed property is a
  REFERENCE to a separate component, not an owned sub-object; recursing into it
  invents targets that cannot be assigned (Action.ActionComponent.Name,
  Action.Components.Tag) and is what made the walk unbounded.

  Checked through the real GetProptree path, by consequence rather than by
  inspecting the command line: with the flag TcxButton has a bare 'Action' leaf and
  NOTHING beneath it (measured 0 'Action.*' paths, vs 8 without the flag), while
  owned TPersistent sub-objects are still expanded -- the latter guards against
  "fixing" the cost with --depth 1, which drops 523 of 696 leaves, all nested.
  Skipped when the exe / library-Win64 db is absent. }
procedure TestProptreeRefsAsLeavesLive;
var
  Exe    : string;
  Adapter: TEngineAdapter;
  Tree   : TProptree;
  Err    : string;
  L      : TPropLeaf;
  nUnder, nNested: Integer;
  sawAction: Boolean;
begin
  Exe := ResolveExe;
  if (Exe = '') or (not TFile.Exists(LibWin64)) then
  begin
    Skip('proptree.refsasleaves', 'exe / library-Win64 db absent');
    Exit;
  end;
  Adapter := TEngineAdapter.Create(Exe, LibDbsFor(DEFAULT_FROM_PLATFORM,
    'C:\Projects\.drag-lint\') + [ProjectDb]);
  try
    if not Adapter.GetProptree('cxButtons.TcxButton', Tree, Err, 'published')
       or (Length(Tree.Leaves) = 0) then
    begin
      Skip('proptree.refsasleaves', 'TcxButton did not resolve: ' + Err);
      Exit;
    end;
    nUnder := 0; nNested := 0; sawAction := False;
    for L in Tree.Leaves do
    begin
      if SameText(L.Path, 'Action') then sawAction := True;
      if L.Path.StartsWith('Action.', True) then Inc(nUnder);
      if Pos('.', L.Path) > 0 then Inc(nNested);
    end;
    Check('proptree.refsasleaves.reference.is.a.leaf', sawAction,
      'no bare "Action" leaf -- expected the reference itself to be emitted');
    Check('proptree.refsasleaves.not.recursed', nUnder = 0,
      Format('%d "Action.*" paths -- --refs-as-leaves is not being passed', [nUnder]));
    Check('proptree.refsasleaves.owned.still.expanded', nNested > 0,
      'no dotted paths at all -- owned sub-objects were flattened away too '
      + '(--depth 1 would do this, and it is not an acceptable substitute)');
  finally
    Adapter.Free;
  end;
end;

{ ACCEPTANCE (the goal the whole proptree effort was for): for a TcxButton TARGET,
  Name, Tag, Left and Top must APPEAR in the To pool and be ASSIGNABLE.

  Driven through the editor's own layers, not a hand-rolled query:
    * appear  = ConvRules.Engine.GetProptree(...,'published') emits the leaf AND
                Leaf.IsWritable -- exactly the two conditions RefreshPool filters
                the To pool on (the rest of RefreshPool is the already-assigned set
                and the user's text/type filters).
    * assignable = ConvRules.Casts.IsCastable(fromType, toType), the predicate
                behind MainForm.CanCast, plus LeafWritable -- the two gates
                AssignFromPool applies before it will create a #link.
  The FROM counterpart is Vcl.StdCtrls.TButton (a plain VCL button -> TcxButton is
  the archetypal conversion); its four properties carry the same declared types.
  Also asserts the types are not 'unknown', which is what a broken cx ancestry used
  to yield for every VCL-inherited property. Skipped when the exe/db are absent. }
procedure TestAcceptanceTcxButtonToPool;
const
  Wanted: array[0..3] of string = ('Name', 'Tag', 'Left', 'Top');
var
  Exe      : string;
  Adapter  : TEngineAdapter;
  ToTree   : TProptree;
  FromTree : TProptree;
  Err      : string;
  i        : Integer;
  L        : TPropLeaf;
  inPool   : Boolean;
  toType   : string;
  fromType : string;
begin
  Exe := ResolveExe;
  if (Exe = '') or (not TFile.Exists(LibWin64)) then
  begin
    Skip('acceptance.tcxbutton', 'exe / library-Win64 db absent');
    Exit;
  end;
  Adapter := TEngineAdapter.Create(Exe, LibDbsFor(DEFAULT_FROM_PLATFORM,
    'C:\Projects\.drag-lint\') + [ProjectDb]);
  try
    if not Adapter.GetProptree('cxButtons.TcxButton', ToTree, Err, 'published')
       or (Length(ToTree.Leaves) = 0) then
    begin
      Skip('acceptance.tcxbutton', 'TcxButton did not resolve: ' + Err);
      Exit;
    end;
    if not Adapter.GetProptree('Vcl.StdCtrls.TButton', FromTree, Err, 'published')
       or (Length(FromTree.Leaves) = 0) then
    begin
      Skip('acceptance.tcxbutton', 'TButton (FROM counterpart) did not resolve: ' + Err);
      Exit;
    end;
    for i := Low(Wanted) to High(Wanted) do
    begin
      // (1) present in the To tree AND writable => RefreshPool puts it in the pool.
      inPool := False; toType := '';
      for L in ToTree.Leaves do
        if SameText(L.Path, Wanted[i]) then
        begin
          toType := L.TypeName;
          inPool := L.IsWritable;
          Break;
        end;
      Check('acceptance.tcxbutton.pool.' + Wanted[i], inPool,
        Format('%s is absent from the TcxButton published surface, or is read-only, '
          + 'so the To pool cannot offer it', [Wanted[i]]));
      Check('acceptance.tcxbutton.type.known.' + Wanted[i],
        not IsUnknownType(toType),
        Format('%s has type "%s" -- an unresolved ancestry loses the type and blocks '
          + 'every cast decision', [Wanted[i], toType]));

      // (2) assignable from the plausible FROM counterpart, via the editor's gate.
      fromType := '';
      for L in FromTree.Leaves do
        if SameText(L.Path, Wanted[i]) then begin fromType := L.TypeName; Break; end;
      Check('acceptance.tcxbutton.from.has.' + Wanted[i], fromType <> '',
        Format('TButton.%s not found -- cannot judge assignability', [Wanted[i]]));
      Check('acceptance.tcxbutton.assignable.' + Wanted[i],
        (fromType <> '') and IsCastable(fromType, toType),
        Format('TButton.%s (%s) -> TcxButton.%s (%s) rejected by IsCastable',
          [Wanted[i], fromType, Wanted[i], toType]));
    end;
  finally
    Adapter.Free;
  end;
end;

{ PropCellText single-sources the 'Path : Type' cell rendering used by the grid's
  From column, the grid's To column and the To pool. The To column showed a BARE
  path until 2026-07-30, so a To leaf's type was invisible exactly where the
  assignment decision is made. These pin the contract the three call sites share,
  including the separator that PathOfGridCell/TypeOfCell split back on. }
procedure TestPropCellText;
var
  s: string;
  p: Integer;
begin
  Check('propcell.path.and.type', PropCellText('Left', 'Integer') = 'Left : Integer',
    PropCellText('Left', 'Integer'));
  Check('propcell.dotted.path.kept',
    PropCellText('Colors.Button.Text', 'TColor') = 'Colors.Button.Text : TColor',
    PropCellText('Colors.Button.Text', 'TColor'));

  // A blank type must NOT leave a dangling ' : ' -- an unresolved ancestor yields
  // an empty type, and 'Left : ' would read as a type named nothing.
  Check('propcell.blank.type.no.separator', PropCellText('Left', '') = 'Left',
    PropCellText('Left', ''));
  Check('propcell.whitespace.type.no.separator', PropCellText('Left', '   ') = 'Left',
    '[' + PropCellText('Left', '   ') + ']');

  // The separator must survive the split the readers perform (PathOfGridCell /
  // TypeOfCell live in the form unit and split on this exact ' : ').
  s := PropCellText('Tag', 'NativeInt');
  p := Pos(' : ', s);
  Check('propcell.separator.roundtrips.path', (p > 0) and (Copy(s, 1, p - 1) = 'Tag'),
    s);
  Check('propcell.separator.roundtrips.type',
    (p > 0) and (Copy(s, p + 3, Length(s)) = 'NativeInt'), s);

  // A path that already contains a colon must not be re-split by the readers at
  // the wrong place: the FIRST ' : ' is the separator.
  Check('propcell.first.separator.wins',
    Pos(' : ', PropCellText('A', 'B')) = 2, PropCellText('A', 'B'));
end;

{ Pure theme model. The IDE stores its theme at HKCU\Software\Embarcadero\BDS\<ver>\
  Theme, value 'Theme' (observed: 'Dark'). Only 'Dark' means dark; every other value,
  including absent/garbage, means light -- a wrong guess here makes the editor unreadable,
  so the default is the safe one. ExamineRowColor derives the used-row marking from the
  ACTIVE window colour, because the old hard-coded $00D8F5D8 is invisible on a dark style. }
procedure TestThemeModel;
begin
  Check('theme.ide.dark',    IdeThemeToMode('Dark')    = tmDark,  'Dark');
  Check('theme.ide.dark.ci', IdeThemeToMode('dArK')    = tmDark,  'case-insensitive');
  Check('theme.ide.light',   IdeThemeToMode('Light')   = tmLight, 'Light');
  Check('theme.ide.gray',    IdeThemeToMode('Gray')    = tmLight, 'Gray is not dark');
  Check('theme.ide.empty',   IdeThemeToMode('')        = tmLight, 'absent -> light');
  Check('theme.ide.garbage', IdeThemeToMode('Zzz')     = tmLight, 'unknown -> light');

  // An explicit preference must WIN over whatever the IDE says.
  Check('theme.pref.light.wins', ResolveThemeMode(tpLight, 'Dark')  = tmLight);
  Check('theme.pref.dark.wins',  ResolveThemeMode(tpDark,  'Light') = tmDark);
  Check('theme.pref.follow',     ResolveThemeMode(tpFollowIde, 'Dark') = tmDark);
  Check('theme.pref.follow.light', ResolveThemeMode(tpFollowIde, 'Light') = tmLight);

  // The marking must DIFFER from the background it sits on, in both modes -- that is
  // the whole contract. Equality here means an invisible highlight.
  Check('theme.examine.light.differs', ExamineRowColor($00FFFFFF, tmLight) <> $00FFFFFF);
  Check('theme.examine.dark.differs',  ExamineRowColor($00202020, tmDark)  <> $00202020);
  Check('theme.examine.modes.differ',
    ExamineRowColor($00FFFFFF, tmLight) <> ExamineRowColor($00FFFFFF, tmDark),
    'light and dark must not produce the same marking');
  Check('theme.examine.light.exact',
    ExamineRowColor($00FFFFFF, tmLight) = $00D8FFD8,
    IntToHex(ExamineRowColor($00FFFFFF, tmLight), 6));

  Check('theme.pref.roundtrip.follow',
    StrToThemePref(ThemePrefToStr(tpFollowIde), tpLight) = tpFollowIde);
  Check('theme.pref.roundtrip.dark',
    StrToThemePref(ThemePrefToStr(tpDark), tpLight) = tpDark);
  Check('theme.pref.unknown.default', StrToThemePref('nonsense', tpFollowIde) = tpFollowIde);
end;

procedure TestUnitDirectives;
const
  SRC =
    '#use imcFOLDERS'#13#10 +
    '#useswap FOLDERDEF -> imcFOLDERS'#13#10 +
    '#useswap ovcTable -> cxGrid, cxGridDBTableView'#13#10;
var
  Book : TRuleBook       ;
  Units: TArray<TRuleNode>;
begin
  Book := TRuleBook.Create;
  try
    Book.LoadFromString(SRC);
    Check('unit.use.kind',  Book.Nodes[0].Kind = rnkUse);
    Check('unit.use.unit',  Book.Nodes[0].UseUnit = 'imcFOLDERS', Book.Nodes[0].UseUnit);
    Check('unit.swap.kind', Book.Nodes[1].Kind = rnkUseSwap);
    Check('unit.swap.old',  Book.Nodes[1].SwapOld = 'FOLDERDEF', Book.Nodes[1].SwapOld);
    Check('unit.swap.new1', (Length(Book.Nodes[1].SwapNew) = 1) and (Book.Nodes[1].SwapNew[0] = 'imcFOLDERS'));
    Check('unit.swap.multi',(Length(Book.Nodes[2].SwapNew) = 2) and (Book.Nodes[2].SwapNew[0] = 'cxGrid')
                            and (Book.Nodes[2].SwapNew[1] = 'cxGridDBTableView'));
    Check('unit.roundtrip', Book.SaveToString = SRC, Format('got %d want %d', [Length(Book.SaveToString), Length(SRC)]));
    Units := Book.UnitNodes;
    Check('unit.gather.count', Length(Units) = 3, IntToStr(Length(Units)));
  finally
    Book.Free;
  end;
end;

procedure TestUnitSets;
var
  Book : TRuleBook        ;
  S    : TUnitSets        ;
  Pairs: TArray<TConvPair> ;
begin
  Book := TRuleBook.Create;
  try
    Book.LoadFromString(
      '#convert A.TFrom -> B.TTo, cxButtons'#13#10 +
      '#use cxButtons'#13#10 +
      '#useswap FOLDERDEF -> imcFOLDERS'#13#10 +
      '#unuse cxButtons'#13#10);
    S := NormalizeUnitSets(Book);
    Check('norm.add.has.cxButtons',    Contains(S.Adds, 'cxButtons'));
    Check('norm.add.has.imcFOLDERS',   Contains(S.Adds, 'imcFOLDERS'));
    Check('norm.add.dedup',            CountOf(S.Adds, 'cxButtons') = 1, IntToStr(CountOf(S.Adds, 'cxButtons')));
    Check('norm.remove.has.FOLDERDEF', Contains(S.Removes, 'FOLDERDEF'));
    Check('norm.conflict.addwins',     Contains(S.Conflicts, 'cxButtons') and not Contains(S.Removes, 'cxButtons'));
  finally
    Book.Free;
  end;

  SetLength(Pairs, 1);
  Pairs[0].FromType := 'Abcbtn.TabcToggleBtn';
  Pairs[0].ToType   := 'cxButtons.TcxButton';
  S := DeriveUnits(Pairs,
    function(const ATypeName: string): string
    begin
      if ATypeName.StartsWith('cxButtons') then Exit('cxButtons');
      if ATypeName.StartsWith('Abcbtn')    then Exit('Abcbtn');
      Result := '';
    end);
  Check('derive.add',    Contains(S.Adds, 'cxButtons'));
  Check('derive.remove', Contains(S.Removes, 'Abcbtn'));
end;

{ DeclaringUnitOf hits the real drag-lint exe + library DB, so it Skips (not
  fails) when the exe or the Win64 library index is absent. }
procedure TestDeclaringUnit;
const
  LibWin64  = 'C:\Projects\.drag-lint\library-Win64.sqlite';
  ProjectDb = 'C:\Projects\DB\ORM3\drag-lint.sqlite';
var
  Exe: string;
  Eng: TEngineAdapter;
  U  : string;
begin
  Exe := ResolveExe;
  if (Exe = '') or not TFile.Exists(LibWin64) then
  begin
    Skip('engine.declaringunit', 'exe or library-Win64 db absent');
    Exit;
  end;
  Eng := TEngineAdapter.Create(Exe, [LibWin64, ProjectDb]);
  try
    U := Eng.DeclaringUnitOf('TcxButton');
    if U = '' then Skip('engine.declaringunit', 'TcxButton not indexed here')
    else Check('engine.declaringunit', SameText(U, 'cxButtons'), U);
  finally
    Eng.Free;
  end;
end;

{ .castlib parse: a well-formed block yields one cast with multi-type accepts, the
  single yield, and the unquoted pas/todo templates. }
procedure TestCastLibParse;
const
  SRC =
    '# a comment'#13#10 +
    'cast AssignGraphic'#13#10 +
    '  accepts TPicture, TBitmap, TGraphic'#13#10 +
    '  yields  TdxSmartGlyph'#13#10 +
    '  dfm     keep-bytes-if-compatible'#13#10 +
    '  pas     ''{dst}.Assign({src});'''#13#10 +
    '  todo    ''do it by hand'''#13#10 +
    'end'#13#10;
var
  D: TArray<TCastDef>;
begin
  D := LoadCastLibText(SRC);
  Check('castlib.count', Length(D) = 1, IntToStr(Length(D)));
  if Length(D) = 0 then Exit;
  Check('castlib.name',   D[0].Name = 'AssignGraphic', D[0].Name);
  Check('castlib.accepts.count', Length(D[0].Accepts) = 3, IntToStr(Length(D[0].Accepts)));
  Check('castlib.accepts.bitmap', Contains(D[0].Accepts, 'TBitmap'));
  Check('castlib.yields',  (Length(D[0].Yields) = 1) and (D[0].Yields[0] = 'TdxSmartGlyph'));
  Check('castlib.dfm',     D[0].Dfm = 'keep-bytes-if-compatible', D[0].Dfm);
  Check('castlib.pas',     D[0].PasTemplate = '{dst}.Assign({src});', D[0].PasTemplate);
  Check('castlib.todo',    D[0].Todo = 'do it by hand', D[0].Todo);
end;

{ Tolerance: blank lines, comments, unknown keys, and a malformed (unclosed) block
  must not stop the good block from parsing. }
procedure TestCastLibTolerant;
const
  SRC =
    'cast Broken'#13#10 +          // no 'end' -> discarded when the next 'cast' starts
    '  accepts TFoo'#13#10 +
    'cast Good'#13#10 +
    ''#13#10 +
    '  # inline comment line'#13#10 +
    '  accepts TA, TB'#13#10 +
    '  yields  TC'#13#10 +
    '  boguskey whatever here'#13#10 +   // unknown key tolerated
    'end'#13#10;
var
  D: TArray<TCastDef>;
begin
  D := LoadCastLibText(SRC);
  Check('castlib.tolerant.count', Length(D) = 1, IntToStr(Length(D)));
  if Length(D) = 0 then Exit;
  Check('castlib.tolerant.name', D[0].Name = 'Good', D[0].Name);
  Check('castlib.tolerant.yields', (Length(D[0].Yields) = 1) and (D[0].Yields[0] = 'TC'));
end;

{ ClassCastFor: matches a pair whose From is accepted AND To is yielded, case-
  insensitively; returns '' for an unbridged pair. }
procedure TestClassCastFor;
var
  D: TArray<TCastDef>;
begin
  D := LoadCastLibText(
    'cast AssignGraphic'#13#10 +
    '  accepts TPicture, TBitmap, TGraphic'#13#10 +
    '  yields  TdxSmartGlyph'#13#10 +
    'end'#13#10);
  Check('castfor.picture',   ClassCastFor(D, 'TPicture', 'TdxSmartGlyph') = 'AssignGraphic');
  Check('castfor.bitmap',    ClassCastFor(D, 'TBitmap',  'TdxSmartGlyph') = 'AssignGraphic');
  Check('castfor.ci',        ClassCastFor(D, 'tpicture', 'tdxsmartglyph') = 'AssignGraphic');
  Check('castfor.wrongto',   ClassCastFor(D, 'TPicture', 'TStrings') = '', 'should be blocked');
  Check('castfor.wrongfrom', ClassCastFor(D, 'TFont',    'TdxSmartGlyph') = '', 'should be blocked');
end;

{ The shipped casts.castlib parses and provides AssignGraphic. Skipped (not failed)
  when the file is not found from the test exe (lean checkout). }
procedure TestCastLibFile;
var
  P: string;
  D: TArray<TCastDef>;
begin
  // test exe lives at <root>\src\tools\convrules-editor\tests\ -> climb 4 to root.
  P := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\..\..\docs\examples\convrules\casts.castlib'));
  if not TFile.Exists(P) then
  begin
    Skip('castlib.file', 'casts.castlib not found: ' + P);
    Exit;
  end;
  D := LoadCastLib(P);
  Check('castlib.file.nonempty', Length(D) > 0, IntToStr(Length(D)));
  Check('castlib.file.assigngraphic',
    ClassCastFor(D, 'TPicture', 'TdxSmartGlyph') = 'AssignGraphic',
    'AssignGraphic (TPicture->TdxSmartGlyph) not resolved from the shipped file');
end;

{ A #link with a class-cast NAME suffix (a single identifier) parses into Cast and
  re-emits byte-faithfully -- the existing DSL slot carries library cast names with no
  grammar change. }
procedure TestClassCastLinkRoundTrip;
var
  Book: TRuleBook;
begin
  Book := TRuleBook.Create;
  try
    Book.LoadFromString('#link Glyph <- Glyph : AssignGraphic'#13#10);
    Check('classcast.link.cast', Book.Nodes[0].Cast = 'AssignGraphic', Book.Nodes[0].Cast);
    Check('classcast.link.from', Book.Nodes[0].LinkFrom = 'Glyph', Book.Nodes[0].LinkFrom);
    Check('classcast.link.reemit',
      Book.Nodes[0].Emit = '#link Glyph <- Glyph : AssignGraphic', Book.Nodes[0].Emit);
  finally
    Book.Free;
  end;
end;

{ Criterion 1a: splitting a .rules text into blocks and rejoining them in order
  reproduces the original byte-for-byte -- including its exact line terminators,
  its blank lines, and a missing final EOL. Tested on synthetic input AND on the
  real shipped sample.rules. }
procedure TestBlockSplitRulesRoundTrip;
const
  SRC =
    '// preamble comment'#13#10 +
    ''#13#10 +
    '#convert A.TFrom -> B.TTo'#13#10 +
    '#link Text <- Text'#13#10 +
    '; semicolon comment'#13#10 +
    ''#13#10 +
    '#convert C.TX -> D.TY, D'#13#10 +
    '#link Color <- Color';            // NOTE: no trailing EOL on purpose
var
  Blocks: TRuleBlocks;
  P     : string;
  Text  : string;
begin
  Blocks := SplitRulesBlocks(SRC);
  Check('blockfile.rules.count', Length(Blocks) = 3, IntToStr(Length(Blocks)));
  Check('blockfile.rules.kind0', Blocks[0].Kind = rbkPreamble, 'block 0 must be the preamble');
  Check('blockfile.rules.kind1', Blocks[1].Kind = rbkConvert, 'block 1 must be a #convert');
  Check('blockfile.rules.header1',
    Blocks[1].Header = '#convert A.TFrom -> B.TTo', Blocks[1].Header);
  Check('blockfile.rules.startline1', Blocks[1].StartLine = 3, IntToStr(Blocks[1].StartLine));
  Check('blockfile.rules.roundtrip', JoinBlocks(Blocks) = SRC,
    Format('got %d bytes, want %d', [Length(JoinBlocks(Blocks)), Length(SRC)]));

  // Edge cases: LF-only input keeps LF (terminators are carried, never detected or
  // rewritten), and empty input yields no blocks rather than one empty one.
  Blocks := SplitRulesBlocks('#convert A.T -> B.T'#10 + '#link P <- Q'#10);
  Check('blockfile.rules.lf.roundtrip',
    JoinBlocks(Blocks) = '#convert A.T -> B.T'#10 + '#link P <- Q'#10,
    'an LF-only file must come back LF-only');
  Check('blockfile.rules.lf.eol', BlockEol(Blocks[0]) = #10, 'BlockEol must report LF');
  Check('blockfile.rules.empty', Length(SplitRulesBlocks('')) = 0, 'empty text = no blocks');
  Check('blockfile.rules.empty.join', JoinBlocks(nil) = '', 'joining nothing yields ''''');

  // ...and against the real file (spec section 11: not only synthetic input).
  P := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\..\..\docs\examples\convrules\sample.rules'));
  if not TFile.Exists(P) then
  begin
    Skip('blockfile.rules.roundtrip.file', 'sample.rules not found: ' + P);
    Exit;
  end;
  Text := TFile.ReadAllText(P, TEncoding.ASCII);
  Blocks := SplitRulesBlocks(Text);
  Check('blockfile.rules.roundtrip.file', JoinBlocks(Blocks) = Text,
    Format('got %d bytes, want %d', [Length(JoinBlocks(Blocks)), Length(Text)]));
  { Sanity check: the assertion holds for the fixture AS COMMITTED (2 #convert blocks).
    A working-tree-only fixture state hides test failures from clean checkouts. }
  Check('blockfile.rules.roundtrip.file.blocks', Length(Blocks) >= 2,
    'sample.rules has at least 2 #convert blocks');
end;

{ Criterion 1b: the same byte-faithful round-trip for .castlib, whose blocks are
  'cast <Name> ... end' / 'enum <Name> ... end'. Content before the first block is
  a preamble; content BETWEEN blocks attaches to the preceding block so nothing is
  orphaned. }
procedure TestBlockSplitCastLibRoundTrip;
const
  SRC =
    '# file header'#13#10 +
    ''#13#10 +
    'cast AssignGraphic'#13#10 +
    '  accepts TPicture, TBitmap'#13#10 +
    '  yields  TdxSmartGlyph'#13#10 +
    'end'#13#10 +
    ''#13#10 +
    'enum ButtonLayout'#13#10 +
    '  ablGlyphLeft -> blGlyphLeft'#13#10 +
    'end'#13#10;
var
  Blocks: TRuleBlocks;
  P, Txt: string;
begin
  Blocks := SplitCastLibBlocks(SRC);
  Check('blockfile.castlib.count', Length(Blocks) = 3, IntToStr(Length(Blocks)));
  Check('blockfile.castlib.kind0', Blocks[0].Kind = rbkPreamble, 'block 0 preamble');
  Check('blockfile.castlib.kind1', Blocks[1].Kind = rbkCast, 'block 1 cast');
  Check('blockfile.castlib.kind2', Blocks[2].Kind = rbkEnum, 'block 2 enum');
  Check('blockfile.castlib.trailing',
    Blocks[1].RawText.EndsWith('end'#13#10 + ''#13#10),
    'the blank line after "end" must attach to the preceding block');
  Check('blockfile.castlib.roundtrip', JoinBlocks(Blocks) = SRC,
    Format('got %d bytes, want %d', [Length(JoinBlocks(Blocks)), Length(SRC)]));

  P := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\..\..\docs\examples\convrules\casts.castlib'));
  if not TFile.Exists(P) then
  begin
    Skip('blockfile.castlib.roundtrip.file', 'casts.castlib not found: ' + P);
    Exit;
  end;
  Txt := TFile.ReadAllText(P, TEncoding.ASCII);
  Check('blockfile.castlib.roundtrip.file',
    JoinBlocks(SplitCastLibBlocks(Txt)) = Txt, 'shipped casts.castlib must round-trip');
end;

{ Criterion 13: WHERE the open file is a .castlib the grid shows cast/enum block
  NAMES in place of #convert type pairs. BlockLabel is what the grid displays. }
procedure TestBlockLabel;
const
  RULES = '#convert Vcl.Graphics.TFont -> Vcl.Graphics.TFont, Vcl.Graphics'#13#10 +
          '#link Color <- Color'#13#10;
  LIB   = '# header'#13#10 +
          'cast AssignGraphic'#13#10 + 'end'#13#10 +
          'enum ButtonLayout'#13#10 + 'end'#13#10;
var
  R, L: TRuleBlocks;
begin
  R := SplitRulesBlocks(RULES);
  L := SplitCastLibBlocks(LIB);
  Check('blocklabel.convert',
    BlockLabel(R[0]) = 'Vcl.Graphics.TFont -> Vcl.Graphics.TFont, Vcl.Graphics',
    BlockLabel(R[0]));
  Check('blocklabel.cast', BlockLabel(L[1]) = 'AssignGraphic', BlockLabel(L[1]));
  Check('blocklabel.enum', BlockLabel(L[2]) = 'ButtonLayout', BlockLabel(L[2]));
  Check('blocklabel.preamble', BlockLabel(L[0]) = '(file header)', BlockLabel(L[0]));
  // extension chosen by file extension, not by sniffing content
  Check('blockfile.byext.castlib',
    Length(SplitBlocksFor('x.castlib', LIB)) = 3, 'castlib grammar by extension');
  Check('blockfile.byext.rules',
    Length(SplitBlocksFor('x.rules', RULES)) = 1, 'rules grammar by extension');
  // Edge case: a file with nothing but a preamble is one preamble block, not zero
  // and not a malformed convert block.
  var Only: TRuleBlocks := SplitRulesBlocks('// just a header'#13#10 + '; nothing else'#13#10);
  Check('blockfile.preamble.only', Length(Only) = 1, IntToStr(Length(Only)));
  Check('blockfile.preamble.only.kind', Only[0].Kind = rbkPreamble, 'must be a preamble');
  Check('blockfile.preamble.only.roundtrip',
    JoinBlocks(Only) = '// just a header'#13#10 + '; nothing else'#13#10, 'must round-trip');
end;

{ Criteria 3 + 4 + 2: split-out REMOVES the selected blocks from the source and
  writes them to the target in their original relative order; copy-out writes them
  and leaves the source unchanged; a moved block keeps its comments, blank lines
  and unrecognised directives verbatim. }
procedure TestBlockOpsSplitAndCopy;
const
  SRC =
    '// file header'#13#10 +
    '#convert A.T1 -> B.T1'#13#10 +
    '#link P <- P'#13#10 +
    '#convert A.T2 -> B.T2'#13#10 +
    '// hand comment inside the moved block'#13#10 +
    '; semicolon comment'#13#10 +
    ''#13#10 +
    '#weird unrecognised directive'#13#10 +
    '#link Q <- Q'#13#10 +
    '#convert A.T3 -> B.T3'#13#10 +
    '#link R <- R'#13#10;
var
  Blocks, Rem, Moved, Copied: TRuleBlocks;
begin
  Blocks := SplitRulesBlocks(SRC);          // [preamble, T1, T2, T3]
  Check('blockops.setup', Length(Blocks) = 4, IntToStr(Length(Blocks)));

  // criterion 3 -- split out blocks 2 and 3 (T2, T3)
  SplitOut(Blocks, [2, 3], Rem, Moved);
  Check('blockops.split.remaining', Length(Rem) = 2, IntToStr(Length(Rem)));
  Check('blockops.split.moved', Length(Moved) = 2, IntToStr(Length(Moved)));
  Check('blockops.split.order',
    (Moved[0].Header = '#convert A.T2 -> B.T2') and
    (Moved[1].Header = '#convert A.T3 -> B.T3'), 'original relative order');
  Check('blockops.split.source.lost.t2',
    Pos('A.T2', JoinBlocks(Rem)) = 0, 'T2 must be gone from the source');
  Check('blockops.split.source.kept.t1',
    Pos('A.T1', JoinBlocks(Rem)) > 0, 'T1 must survive in the source');

  // criterion 2 -- everything inside the moved block survives verbatim
  Check('blockops.split.keeps.slashcomment',
    Pos('// hand comment inside the moved block', Moved[0].RawText) > 0, 'lost //');
  Check('blockops.split.keeps.semicomment',
    Pos('; semicolon comment', Moved[0].RawText) > 0, 'lost ;');
  Check('blockops.split.keeps.blankline',
    Pos(#13#10 + #13#10, Moved[0].RawText) > 0, 'lost blank line');
  Check('blockops.split.keeps.unknown',
    Pos('#weird unrecognised directive', Moved[0].RawText) > 0, 'lost unknown directive');

  // criterion 4 -- copy leaves the source alone
  Copied := CopyOut(Blocks, [1]);
  Check('blockops.copy.count', Length(Copied) = 1, IntToStr(Length(Copied)));
  Check('blockops.copy.header', Copied[0].Header = '#convert A.T1 -> B.T1', Copied[0].Header);
  Check('blockops.copy.source.unchanged', JoinBlocks(Blocks) = SRC,
    'CopyOut must not mutate the source blocks');
end;

{ Criterion 12: WHILE no blocks are selected the Split, Copy and Delete commands
  are disabled. CanOperateOn is the single rule the form's enablement uses. }
procedure TestBlockOpsEnablement;
begin
  Check('blockops.enable.none', not CanOperateOn([]), 'empty selection must disable');
  Check('blockops.enable.one', CanOperateOn([0]), 'one selected block must enable');
  Check('blockops.enable.many', CanOperateOn([1, 4]), 'several selected must enable');
end;

{ Criterion 5: an incoming #link whose target is already linked FROM THE SAME
  source is a duplicate and is skipped. }
procedure TestMergeSkipsDuplicate;
var
  Plan: TMergePlan;
  T, I: TRuleBlocks;
begin
  T := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  I := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  Plan := PlanMerge(T, I);
  Check('merge.dup.count', Length(Plan.Items) = 1, IntToStr(Length(Plan.Items)));
  Check('merge.dup.action', Plan.Items[0].Action = maSkipDuplicate, 'must be a skip');
  Check('merge.dup.noconflict', Plan.ConflictCount = 0, 'a duplicate is not a conflict');
end;

{ Criterion 6: an incoming #link whose target is already linked from a DIFFERENT
  source is a conflict; planning reports it and writes nothing -- neither link is
  merged until a resolution is supplied. }
procedure TestMergeReportsConflict;
var
  Plan: TMergePlan;
  T, I: TRuleBlocks;
  k   : Integer;
  Merged: Boolean;
begin
  T := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  I := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Z'#13#10);
  Plan := PlanMerge(T, I);
  Check('merge.conflict.count', Plan.ConflictCount = 1, IntToStr(Plan.ConflictCount));
  Check('merge.conflict.to', Plan.Items[0].ToPath = 'P', Plan.Items[0].ToPath);
  Check('merge.conflict.existingfrom', Plan.Items[0].ExistingFrom = 'Q',
    Plan.Items[0].ExistingFrom);
  Check('merge.conflict.incomingfrom', Plan.Items[0].IncomingFrom = 'Z',
    Plan.Items[0].IncomingFrom);
  Merged := False;
  for k := 0 to High(Plan.Items) do
    if Plan.Items[k].Action in [maMergeLink, maMergeOther] then Merged := True;
  Check('merge.conflict.nothing.written', not Merged,
    'planning a conflict must not queue either link for writing');
  Check('merge.conflict.target.untouched',
    JoinBlocks(Plan.Target) = '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10,
    'planning must not mutate the target');

  // same target, same source, DIFFERENT cast -> also a conflict (design decision 2)
  T := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  I := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q : Round'#13#10);
  Plan := PlanMerge(T, I);
  Check('merge.conflict.cast', Plan.ConflictCount = 1,
    'a differing cast changes the generated assignment, so it is a conflict');
end;

{ Criterion 7: an already-used SOURCE feeding a NEW target is legal fan-out and is
  merged, not flagged. }
procedure TestMergeAllowsFanOut;
var
  Plan: TMergePlan;
  T, I: TRuleBlocks;
begin
  T := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  I := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link R <- Q'#13#10);
  Plan := PlanMerge(T, I);
  Check('merge.fanout.noconflict', Plan.ConflictCount = 0, 'fan-out is never a conflict');
  Check('merge.fanout.count', Length(Plan.Items) = 1, IntToStr(Length(Plan.Items)));
  Check('merge.fanout.action', Plan.Items[0].Action = maMergeLink, 'must be merged');
  Check('merge.fanout.line', Plan.Items[0].Line = '#link R <- Q', Plan.Items[0].Line);
end;

{ Criterion 8: an incoming block whose header has no counterpart in the target is
  appended WHOLE and verbatim. }
procedure TestMergeAppendsUnmatchedBlock;
var
  Plan: TMergePlan;
  T, I: TRuleBlocks;
begin
  T := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  I := SplitRulesBlocks(
    '#convert X.T -> Y.T'#13#10 +
    '// keep me'#13#10 +
    '#link M <- N'#13#10);
  Plan := PlanMerge(T, I);
  Check('merge.append.count', Length(Plan.Items) = 1, IntToStr(Length(Plan.Items)));
  Check('merge.append.action', Plan.Items[0].Action = maAppendBlock, 'must append whole');
  Check('merge.append.idx', Plan.Items[0].IncomingBlockIdx = 0,
    IntToStr(Plan.Items[0].IncomingBlockIdx));
  Check('merge.append.verbatim',
    Plan.Incoming[Plan.Items[0].IncomingBlockIdx].RawText =
      '#convert X.T -> Y.T'#13#10 + '// keep me'#13#10 + '#link M <- N'#13#10,
    'the appended block keeps its comment');
  // a header that differs only by its units list does NOT match
  T := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  I := SplitRulesBlocks('#convert A.T -> B.T, SomeUnit'#13#10 + '#link P <- Q'#13#10);
  Plan := PlanMerge(T, I);
  Check('merge.append.unitsdiffer', Plan.Items[0].Action = maAppendBlock,
    'a differing units list is a different rule, so it is appended not merged');
end;

{ Criterion 9: composing a working set resolves link collisions in favour of the
  EARLIER file and lists every resolved collision in its report. Compose and merge
  share one code path, so this also proves ApplyMerge. }
procedure TestComposePrecedence;
var
  Inputs: TArray<TComposeInput>;
  Report: TComposeReport;
  Text  : string;
  i     : Integer;
  Found : Boolean;
begin
  SetLength(Inputs, 2);
  Inputs[0].Path   := 'first.rules';
  Inputs[0].Blocks := SplitRulesBlocks(
    '#convert A.T -> B.T'#13#10 +
    '#link P <- Q'#13#10);
  Inputs[1].Path   := 'second.rules';
  Inputs[1].Blocks := SplitRulesBlocks(
    '#convert A.T -> B.T'#13#10 +
    '#link P <- Z'#13#10 +          // collides with first.rules -> earlier wins
    '#link R <- S'#13#10 +          // missing -> merged
    '#convert X.T -> Y.T'#13#10 +   // no counterpart -> appended whole
    '#link M <- N'#13#10);

  Text := Compose(Inputs, Report);

  Check('compose.keeps.earlier', Pos('#link P <- Q', Text) > 0, 'earlier link must survive');
  Check('compose.drops.later', Pos('#link P <- Z', Text) = 0, 'later colliding link must not be written');
  Check('compose.merges.missing', Pos('#link R <- S', Text) > 0, 'missing link must be merged');
  Check('compose.appends.block', Pos('#convert X.T -> Y.T', Text) > 0, 'unmatched block must be appended');
  Check('compose.resolved.count', Report.ResolvedCount = 1, IntToStr(Report.ResolvedCount));
  Check('compose.appended.count', Report.AppendedCount = 1, IntToStr(Report.AppendedCount));

  Found := False;
  for i := 0 to High(Report.Lines) do
    if (Pos('second.rules', Report.Lines[i]) > 0) and (Pos('P', Report.Lines[i]) > 0)
       and (Pos('Z', Report.Lines[i]) > 0) then Found := True;
  Check('compose.report.names.collision', Found,
    'the report must name the file, the target and the losing source');

  // taking the incoming side REPLACES the existing line in place, verbatim
  var Plan: TMergePlan := PlanMerge(Inputs[0].Blocks, Inputs[1].Blocks);
  var Merged: string := JoinBlocks(ApplyMerge(Plan, [mrTakeIncoming]));
  Check('merge.apply.takeincoming', (Pos('#link P <- Z', Merged) > 0)
    and (Pos('#link P <- Q', Merged) = 0), 'mrTakeIncoming must replace the existing link');

  // Edge cases: composing nothing yields nothing; composing ONE file is a no-op that
  // returns it byte-for-byte (there is no second file to merge, so nothing is touched).
  var Empty: TComposeReport;
  Check('compose.empty', Compose(nil, Empty) = '', 'an empty working set composes to ''''');
  var One: TArray<TComposeInput>;
  SetLength(One, 1);
  One[0].Path   := 'solo.rules';
  One[0].Blocks := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  Check('compose.single.identity',
    Compose(One, Empty) = '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10,
    'composing one file must return it unchanged');
  Check('compose.single.noreport', Length(Empty.Lines) = 0, 'a single file reports nothing');
end;

{ Criterion 11: a write makes a rotating backup first and never overwrites one. }
procedure TestBackupRotation;
var
  Dir, P, B1, B2: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'convrules-curation-' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(Dir);
  try
    P := TPath.Combine(Dir, 'book.rules');
    TFile.WriteAllText(P, 'v1'#13#10, TEncoding.ASCII);

    WriteTextWithBackup(P, 'v2'#13#10, B1);
    Check('backup.first.name', B1 = P + '.bak', B1);
    Check('backup.first.content', TFile.ReadAllText(B1) = 'v1'#13#10, 'backup must hold v1');
    Check('backup.first.written', TFile.ReadAllText(P) = 'v2'#13#10, 'file must hold v2');

    WriteTextWithBackup(P, 'v3'#13#10, B2);
    Check('backup.second.name', B2 = P + '.bak.2', B2);
    Check('backup.second.content', TFile.ReadAllText(B2) = 'v2'#13#10, 'second backup holds v2');
    Check('backup.first.preserved', TFile.ReadAllText(B1) = 'v1'#13#10,
      'the first backup must NOT be overwritten');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

{ Criterion 14: IF the backup cannot be written THEN the operation aborts and every
  file is left unmodified. An exclusive read lock on the source makes TFile.Copy
  fail deterministically. }
procedure TestBackupFailureAborts;
var
  Dir, P: string;
  Lock  : TFileStream;
  Bak   : string;
  Raised: Boolean;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'convrules-curation-fail-' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(Dir);
  try
    P := TPath.Combine(Dir, 'book.rules');
    TFile.WriteAllText(P, 'original'#13#10, TEncoding.ASCII);
    Raised := False;
    Lock := TFileStream.Create(P, fmOpenRead or fmShareExclusive);
    try
      try
        WriteTextWithBackup(P, 'replacement'#13#10, Bak);
      except
        on E: Exception do Raised := True;
      end;
    finally
      Lock.Free;
    end;
    Check('backup.fail.raises', Raised, 'a failed backup must raise, not write');
    Check('backup.fail.file.unmodified', TFile.ReadAllText(P) = 'original'#13#10,
      'the target file must be untouched');
    Check('backup.fail.no.backup', not TFile.Exists(P + '.bak'),
      'no backup file may be left behind');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

{ Criterion 10: the composed output is a valid .rules file -- compose two books,
  hand the text to convert-validate and require OK. Skips (does not fail) when the
  drag-lint exe is absent, matching the suite's environment policy. }
procedure TestComposedFileValidates;
var
  Exe   : string;
  WS    : TWorkingSet;
  Rep   : TComposeReport;
  Text  : string;
  Eng   : TEngineAdapter;
  Res   : TValidateResult;
begin
  Exe := ResolveExe;
  if Exe = '' then
  begin
    Skip('compose.validates', 'drag-lint.exe not found');
    Exit;
  end;
  WS := TWorkingSet.Create;
  try
    WS.AddText('first.rules',
      '#convert Vcl.Graphics.TFont -> Vcl.Graphics.TFont'#13#10 +
      '#link Color <- Color'#13#10 +
      '#link Height <- Height'#13#10);
    WS.AddText('second.rules',
      '#convert Vcl.Graphics.TFont -> Vcl.Graphics.TFont'#13#10 +
      '#link Color <- Name'#13#10 +          // collides -> earlier wins
      '#link Size <- Size'#13#10 +           // merged
      '#convert Vcl.StdCtrls.TEdit -> Vcl.StdCtrls.TMemo'#13#10 +
      '#link Text <- Text'#13#10);           // appended whole
    Text := WS.ComposeAll(Rep);
    Check('compose.validates.resolved', Rep.ResolvedCount = 1, IntToStr(Rep.ResolvedCount));

    Eng := TEngineAdapter.Create(Exe, []);
    try
      Res := Eng.ValidateText(Text, '', '');
      Check('compose.validates', Res.OK, 'convert-validate rejected the composed file: '
        + Res.FirstError + ' | text=' + StringReplace(Text, #13#10, '\n', [rfReplaceAll]));
    finally
      Eng.Free;
    end;
  finally
    WS.Free;
  end;
end;

{ Criterion 5 (the maMergeOther half, previously untested): within a matched block,
  a non-#link incoming line new to the target is merged verbatim (maMergeOther); one
  already present -- an EXACT match after trimming -- is not re-added; the header
  line itself is never treated as "other" content; and the dedup is case-SENSITIVE,
  so a duplicate that differs only in case is genuinely new content and must be
  kept, not silently dropped (design decision: "identical" means exact, not
  case-folded -- non-#link content is never dropped). }
procedure TestMergeOtherLines;
var
  Plan: TMergePlan;
  T, I: TRuleBlocks;
  k, OtherCount: Integer;
  SawKeepMeCase, SawDefault, SawExactDup: Boolean;
begin
  T := SplitRulesBlocks(
    '#convert A.T -> B.T'#13#10 +
    '#link P <- Q'#13#10 +
    '// Keep me'#13#10);
  I := SplitRulesBlocks(
    '#convert A.T -> B.T'#13#10 +
    '#link P <- Q'#13#10 +
    '// Keep me'#13#10 +
    '// KEEP ME'#13#10 +
    '#default X = 1'#13#10);
  Plan := PlanMerge(T, I);

  Check('merge.other.itemcount', Length(Plan.Items) = 3, IntToStr(Length(Plan.Items)));

  OtherCount    := 0;
  SawKeepMeCase := False;
  SawDefault    := False;
  SawExactDup   := False;
  for k := 0 to High(Plan.Items) do
    if Plan.Items[k].Action = maMergeOther then
    begin
      Inc(OtherCount);
      if Plan.Items[k].Line = '// KEEP ME' then SawKeepMeCase := True;
      if Plan.Items[k].Line = '#default X = 1' then SawDefault := True;
      if Plan.Items[k].Line = '// Keep me' then SawExactDup := True;
    end;

  Check('merge.other.count', OtherCount = 2, IntToStr(OtherCount));
  Check('merge.other.default.verbatim', SawDefault,
    'a #default line new to the target must merge verbatim');
  Check('merge.other.casediff.kept', SawKeepMeCase,
    'a duplicate differing only in case is not identical -- it must be kept, not deduped');
  Check('merge.other.exactdup.skipped', not SawExactDup,
    'an exact (post-trim) duplicate already in the target must not be re-added');

  // The incoming block's header line must never itself be treated as "other"
  // content. Proven with a header differing only by case from the target's, so a
  // regression that stopped skipping the header line (the i0 index in
  // BlockOtherLines) would surface as a spurious extra item, not silently pass by
  // matching case-insensitively.
  T := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  I := SplitRulesBlocks('#CONVERT A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  Plan := PlanMerge(T, I);
  Check('merge.other.header.excluded', Length(Plan.Items) = 1, IntToStr(Length(Plan.Items)));
  Check('merge.other.header.excluded.action', Plan.Items[0].Action = maSkipDuplicate,
    'only the identical #link should appear; the header must never become a maMergeOther item');
end;

{ ConcatBlocks is documented PURE, so it must not write through to the array it was
  handed. Delphi dynamic arrays are REFERENCES and an element write does NOT
  copy-on-write -- only SetLength uniquifies -- so 'Result := AFirst' followed by
  'Result[High(Result)] := ...' edits the caller's array too. TWorkingSet.Item hands
  out a record whose Blocks field shares the list's array, so the mutation would land
  on the loaded file itself. }
procedure TestConcatBlocksPure;
var
  A, B  : TRuleBlocks;
  Before: string;
  WS    : TWorkingSet;
begin
  // A's last block is deliberately UNTERMINATED -- that is what ConcatBlocks fixes up
  A := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q');
  B := SplitRulesBlocks('#convert X.T -> Y.T'#13#10 + '#link M <- N'#13#10);
  Before := JoinBlocks(A);

  Check('concat.joins',
    JoinBlocks(ConcatBlocks(A, B)) =
      '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10 +
      '#convert X.T -> Y.T'#13#10 + '#link M <- N'#13#10,
    StringReplace(JoinBlocks(ConcatBlocks(A, B)), #13#10, '\n', [rfReplaceAll]));
  Check('concat.input.unmutated', JoinBlocks(A) = Before,
    'ConcatBlocks must not terminate the CALLER''s last block: '
    + StringReplace(JoinBlocks(A), #13#10, '\n', [rfReplaceAll]));

  // and through a working set: the stored blocks must survive a concat unchanged
  WS := TWorkingSet.Create;
  try
    WS.AddText('book.rules', '#convert A.T -> B.T'#13#10 + '#link P <- Q');
    ConcatBlocks(WS.Item(0).Blocks, B);
    Check('concat.workingset.unmutated',
      JoinBlocks(WS.Item(0).Blocks) = '#convert A.T -> B.T'#13#10 + '#link P <- Q',
      'ConcatBlocks must not edit the working set''s stored blocks: '
      + StringReplace(JoinBlocks(WS.Item(0).Blocks), #13#10, '\n', [rfReplaceAll]));
  finally
    WS.Free;
  end;
end;

{ Three counters must agree that "row i of the resolution dialog is the i-th
  maConflict item in PLAN ORDER": ApplyMerge's conflict ordinal, MergeReportLines'
  conflict ordinal, and the dialog's row order. A mismatch would apply the user's
  choice to a DIFFERENT conflict and report a third -- silently wrong data, no
  exception. Every other merge test has at most ONE conflict, where any mismatch is
  invisible; TWO conflicts with DIFFERENT resolutions pin the mapping down. }
procedure TestMergeConflictOrdinals;
var
  T, I  : TRuleBlocks;
  Plan  : TMergePlan;
  Merged: string;
  Rep   : TArray<string>;
  Ords  : TArray<string>;
  k, n  : Integer;
  SawKept, SawTook: Boolean;
begin
  T := SplitRulesBlocks(
    '#convert A.T -> B.T'#13#10 +
    '#link P <- Q'#13#10 +
    '#link R <- S'#13#10);
  I := SplitRulesBlocks(
    '#convert A.T -> B.T'#13#10 +
    '#link P <- Q2'#13#10 +          // conflict ordinal 0
    '#link R <- S2'#13#10);          // conflict ordinal 1
  Plan := PlanMerge(T, I);
  Check('merge.ord.count', Plan.ConflictCount = 2, IntToStr(Plan.ConflictCount));

  // the dialog builds one row per maConflict item in plan order, so a row's
  // position IS its ordinal -- that order is asserted here
  SetLength(Ords, Plan.ConflictCount);
  n := 0;
  for k := 0 to High(Plan.Items) do
    if Plan.Items[k].Action = maConflict then
    begin
      Ords[n] := Plan.Items[k].ToPath;
      Inc(n);
    end;
  Check('merge.ord.order', (Length(Ords) = 2) and (Ords[0] = 'P') and (Ords[1] = 'R'),
    'conflict 0 must be P and conflict 1 must be R');

  // ordinal 0 -> keep existing, ordinal 1 -> take incoming
  Merged := JoinBlocks(ApplyMerge(Plan, [mrKeepExisting, mrTakeIncoming]));
  Check('merge.ord.0.kept',
    (Pos('#link P <- Q'#13#10, Merged) > 0) and (Pos('#link P <- Q2', Merged) = 0),
    'conflict 0 was mrKeepExisting, so P must still come from Q: '
    + StringReplace(Merged, #13#10, '\n', [rfReplaceAll]));
  Check('merge.ord.1.took',
    (Pos('#link R <- S2', Merged) > 0) and (Pos('#link R <- S'#13#10, Merged) = 0),
    'conflict 1 was mrTakeIncoming, so R must now come from S2: '
    + StringReplace(Merged, #13#10, '\n', [rfReplaceAll]));

  // the report must describe the SAME two decisions, not a third pairing
  Rep := MergeReportLines(Plan, [mrKeepExisting, mrTakeIncoming], 'inc.rules');
  SawKept := False;
  SawTook := False;
  for k := 0 to High(Rep) do
  begin
    if (Pos('conflict on P', Rep[k]) > 0) and (Pos('kept earlier', Rep[k]) > 0) then
      SawKept := True;
    if (Pos('conflict on R', Rep[k]) > 0) and (Pos('took incoming', Rep[k]) > 0) then
      SawTook := True;
  end;
  Check('merge.ord.report.0', SawKept,
    'the report must say conflict 0 (P) kept the existing link');
  Check('merge.ord.report.1', SawTook,
    'the report must say conflict 1 (R) took the incoming link');
end;

{ TWorkingSet's header justifies being VCL-free with "so the ordering and composition
  logic is unit-tested headlessly", but only the free file helpers were covered. This
  exercises the class: add/count/item, IndexOfPath (including two SPELLINGS of one
  file), the ordering commands as COMPOSITION PRECEDENCE (criterion 9's user control
  -- moving a file must change which link wins), SetBlocks actually persisting through
  the TList<record> read-modify-write, and Remove. }
procedure TestWorkingSetOps;
var
  WS  : TWorkingSet;
  Rep : TComposeReport;
  Text: string;
begin
  WS := TWorkingSet.Create;
  try
    WS.AddText('C:\books\first.rules',
      '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
    WS.AddText('C:\books\second.rules',
      '#convert A.T -> B.T'#13#10 + '#link P <- Z'#13#10);

    Check('ws.count', WS.Count = 2, IntToStr(WS.Count));
    Check('ws.item.path', WS.Item(1).Path = 'C:\books\second.rules', WS.Item(1).Path);
    Check('ws.item.blocks', Length(WS.Item(0).Blocks) = 1,
      IntToStr(Length(WS.Item(0).Blocks)));

    Check('ws.indexof', WS.IndexOfPath('C:\books\second.rules') = 1,
      IntToStr(WS.IndexOfPath('C:\books\second.rules')));
    Check('ws.indexof.case', WS.IndexOfPath('c:\BOOKS\SECOND.RULES') = 1,
      'path comparison is case-insensitive on Windows');
    Check('ws.indexof.spelling', WS.IndexOfPath('C:\books\sub\..\second.rules') = 1,
      'two spellings of ONE file must resolve to the same entry, or the duplicate-add '
      + 'check, the split-target guard and the write-back sync all miss it');
    Check('ws.indexof.missing', WS.IndexOfPath('C:\books\other.rules') = -1,
      'an unloaded path is not in the set');

    // order IS precedence: the EARLIER file wins the P collision
    Text := WS.ComposeAll(Rep);
    Check('ws.compose.precedence',
      (Pos('#link P <- Q', Text) > 0) and (Pos('#link P <- Z', Text) = 0),
      'the file nearest the top must win: ' + StringReplace(Text, #13#10, '\n', [rfReplaceAll]));

    WS.MoveUp(1);
    Check('ws.moveup.order', WS.Item(0).Path = 'C:\books\second.rules', WS.Item(0).Path);
    Text := WS.ComposeAll(Rep);
    Check('ws.compose.after.moveup',
      (Pos('#link P <- Z', Text) > 0) and (Pos('#link P <- Q', Text) = 0),
      'moving a file up must promote ITS choices -- that is what the button is for: '
      + StringReplace(Text, #13#10, '\n', [rfReplaceAll]));

    WS.MoveDown(0);
    Check('ws.movedown.order', WS.Item(0).Path = 'C:\books\first.rules', WS.Item(0).Path);
    WS.MoveUp(0);                 // already at the top
    WS.MoveDown(WS.Count - 1);    // already at the bottom
    Check('ws.move.edges.noop',
      (WS.Count = 2) and (WS.Item(0).Path = 'C:\books\first.rules'),
      'moving past either end must be a no-op, not a swap or a crash');

    // SetBlocks must really persist: TList<record> hands out a COPY, so editing
    // Item(i).Blocks in place would be silently lost
    WS.SetBlocks(0, DeleteBlocks(WS.Item(0).Blocks, [0]));
    Check('ws.setblocks.persists', Length(WS.Item(0).Blocks) = 0,
      IntToStr(Length(WS.Item(0).Blocks)));

    WS.Remove(0);
    Check('ws.remove.count', WS.Count = 1, IntToStr(WS.Count));
    Check('ws.remove.kept', WS.Item(0).Path = 'C:\books\second.rules', WS.Item(0).Path);
    WS.Remove(99);
    Check('ws.remove.oob.noop', WS.Count = 1, 'an out-of-range Remove is a no-op');
  finally
    WS.Free;
  end;
end;

{ A split/copy/compose that writes to a file which is ALSO in the working set used to
  leave that file's in-memory blocks STALE: the grid hid the moved block, Compose
  folded the stale model (so the file handed to --rules silently omitted the moved
  rule), and the next Delete/Merge on that member saved the stale model back over it.
  SyncFromText is the write-back -- after a successful write the owning entry
  re-splits the EXACT text written, so model and disk agree. }
procedure TestWorkingSetSyncFromText;
var
  WS  : TWorkingSet;
  Rem, Moved: TRuleBlocks;
  NewText: string;
  Rep : TComposeReport;
begin
  WS := TWorkingSet.Create;
  try
    WS.AddText('C:\books\book1.rules',
      '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10 +
      '#convert X.T -> Y.T'#13#10 + '#link M <- N'#13#10);
    WS.AddText('C:\books\book2.rules',
      '#convert C.T -> D.T'#13#10 + '#link R <- S'#13#10);

    // split block 1 of book1 OUT into book2 -- both are in the set
    SplitOut(WS.Item(0).Blocks, [1], Rem, Moved);
    NewText := JoinBlocks(ConcatBlocks(WS.Item(1).Blocks, Moved));  // what gets written

    Check('ws.sync.notinset',
      WS.SyncFromText('C:\books\elsewhere.rules', NewText) = -1,
      'a path outside the set must not be synced onto any entry');
    Check('ws.sync.index', WS.SyncFromText('C:\books\SUB\..\book2.rules', NewText) = 1,
      'the write-back must find the entry whatever the path was spelled like');
    WS.SetBlocks(0, Rem);

    Check('ws.sync.blocks', Length(WS.Item(1).Blocks) = 2,
      IntToStr(Length(WS.Item(1).Blocks)));
    Check('ws.sync.model.matches.disk', JoinBlocks(WS.Item(1).Blocks) = NewText,
      'the in-memory model must equal the text that was written');
    Check('ws.sync.compose.has.moved',
      Pos('#convert X.T -> Y.T', WS.ComposeAll(Rep)) > 0,
      'the moved block must survive composition -- a stale model dropped it silently');
  finally
    WS.Free;
  end;
end;

{ A .castlib and a .rules file are BOTH accepted into the working set (criterion 13
  needs the catalog there so the grid can show cast/enum names), but the merger and
  the composer only speak the .rules grammar. Until they are catalog-aware, a
  cross-grammar merge and a mixed-grammar compose are REFUSED, so the guard is what
  is under test here. }
procedure TestGrammarGuard;
var
  WS: TWorkingSet;
begin
  Check('grammar.rules', GrammarOf('C:\x\book.rules') = rgRules, 'the DSL grammar');
  Check('grammar.castlib', GrammarOf('C:\x\casts.castlib') = rgCastLib, 'the catalog grammar');
  Check('grammar.castlib.case', GrammarOf('C:\x\CASTS.CASTLIB') = rgCastLib,
    'the extension test is case-insensitive, exactly as SplitBlocksFor does it');
  Check('grammar.refind', GrammarOf('C:\x\refind.txt') = rgRules,
    'SplitBlocksFor reads everything that is not .castlib with the DSL grammar');
  Check('grammar.name.differ', GrammarName(rgRules) <> GrammarName(rgCastLib),
    'a refusal message has to be able to name both sides');

  WS := TWorkingSet.Create;
  try
    Check('ws.mixed.empty', not WS.MixedGrammars, 'an empty set is not mixed');
    WS.AddText('a.rules', '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
    Check('ws.mixed.single', not WS.MixedGrammars, 'one file is never mixed');
    WS.AddText('b.rules', '#convert C.T -> D.T'#13#10 + '#link R <- S'#13#10);
    Check('ws.mixed.homogeneous', not WS.MixedGrammars, 'two .rules files compose fine');
    WS.AddText('c.castlib', 'cast Foo'#13#10 + '  accepts TIcon'#13#10 + 'end'#13#10);
    Check('ws.mixed.detected', WS.MixedGrammars,
      'a catalog among .rules files must block Compose, not be emitted as '
      + '''cast ... end'' into a file meant for --rules');
  finally
    WS.Free;
  end;
end;

{ The cross-grammar guard above cannot catch a .castlib merged into a .castlib --
  both sides are the SAME grammar -- yet that is exactly the corruption: a cast/enum
  block's RawText INCLUDES its closing 'end' line, and AppendLinesToBlock appends at
  the very end of RawText, so an incoming body line lands AFTER 'end'. The second
  half of this test PINS that broken behaviour, so the guard cannot later be dropped
  as unnecessary; the first half is the guard itself. }
procedure TestCastLibMergeRefused;
var
  T, I  : TRuleBlocks;
  Plan  : TMergePlan;
  Merged: string;
  pEnd, pNew: Integer;
begin
  Check('grammar.merge.rules', GrammarAcceptsMerge(rgRules),
    'a #convert block has no terminator line, so the merger can append into it');
  Check('grammar.merge.castlib', not GrammarAcceptsMerge(rgCastLib),
    'a cast/enum block carries its own ''end'' line, so an append lands outside the body');

  T := SplitCastLibBlocks('cast Foo'#13#10 + '  accepts TBitmap'#13#10 + 'end'#13#10);
  I := SplitCastLibBlocks('cast Foo'#13#10 + '  accepts TIcon'#13#10   + 'end'#13#10);
  Plan := PlanMerge(T, I);
  Check('castlib.merge.plans.silently', Plan.ConflictCount = 0,
    'nothing warns the user: the incoming body line is planned as ordinary content');

  Merged := JoinBlocks(ApplyMerge(Plan, nil));
  pEnd := Pos('end'#13#10, Merged);
  pNew := Pos('accepts TIcon', Merged);
  Check('castlib.merge.corrupts', (pEnd > 0) and (pNew > pEnd),
    'the incoming body line lands AFTER ''end'', outside the cast block -- this is '
    + 'why a catalog TARGET is refused outright rather than merged: '
    + StringReplace(Merged, #13#10, '\n', [rfReplaceAll]));
end;

{ The split/copy target dialog deliberately has NO overwrite prompt (a backup is
  written instead of clobbering), so an append into an existing book gives the user
  no other signal. The status line says "appended", and appending a #convert header
  the target ALREADY has leaves two blocks for one rule -- dead weight worth warning
  about. DuplicateHeaders is what that warning is built from. }
procedure TestDuplicateHeaders;
var
  Existing: TRuleBlocks;
begin
  Existing := SplitRulesBlocks(
    '// file header'#13#10 +
    '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);

  var Dup: TArray<string> := DuplicateHeaders(Existing, SplitRulesBlocks(
    '#convert a.t -> b.t'#13#10 + '#link P <- Z'#13#10 +
    '#convert X.T -> Y.T'#13#10 + '#link M <- N'#13#10));
  Check('dup.count', Length(Dup) = 1, IntToStr(Length(Dup)));
  Check('dup.header.reported', (Length(Dup) = 1) and (Pos('a.t -> b.t', Dup[0]) > 0),
    'the duplicated header is named so the warning is actionable');

  Check('dup.none', Length(DuplicateHeaders(Existing,
    SplitRulesBlocks('#convert Z.T -> W.T'#13#10 + '#link P <- Q'#13#10))) = 0,
    'a genuinely new header is not a duplicate');
  Check('dup.preamble.ignored', Length(DuplicateHeaders(Existing,
    SplitRulesBlocks('// file header'#13#10))) = 0,
    'a preamble has no header, so it can never be a duplicate');
end;

{ Criteria 1-6: the DFM scanner records the assignments of blocks whose class is the
  From class, at that block's immediate level only, skipping binary blobs and nested
  components -- but descending into nested blocks to find further instances. }
procedure TestScanDfm;
const
  SRC =
    'object Form1: TForm1'#13#10 +
    '  Caption = ''ignored -- wrong class'''#13#10 +
    '  object btnA: TabcToggleBtn'#13#10 +
    '    Left = 4'#13#10 +
    '    Top = 175'#13#10 +
    '    Caption = ''Ac'''#13#10 +
    '    Layout = ablGlyphCenter'#13#10 +
    '    Picture.Data = {'#13#10 +
    '      07544269746D617076080000424D7606'#13#10 +
    '      Width = 999'#13#10 +          // inside the blob: must NOT be recorded
    '      0000200000000100040000000000}'#13#10 +
    '    Columns = <'#13#10 +
    '      item'#13#10 +
    '        Height = 888'#13#10 +       // inside the item list: must NOT be recorded
    '      end>'#13#10 +
    '    object lblChild: TLabel'#13#10 +
    '      Alignment = taLeftJustify'#13#10 +   // child component: NOT the From class
    '    end'#13#10 +
    '  end'#13#10 +
    '  object btnB: TabcToggleBtn'#13#10 +
    '    Hint = ''second instance'''#13#10 +
    '  end'#13#10 +
    'end'#13#10;

  function Has(const A: TArray<string>; const S: string): Boolean;
  var
    X: string;
  begin
    for X in A do
      if SameText(X, S) then Exit(True);
    Result := False;
  end;

var
  U: TArray<string>;
begin
  U := ScanDfmText(SRC, 'TabcToggleBtn');
  Check('usage.dfm.left',      Has(U, 'Left'), 'plain assignment');
  Check('usage.dfm.caption',   Has(U, 'Caption'), 'plain assignment');
  Check('usage.dfm.layout',    Has(U, 'Layout'), 'plain assignment');
  Check('usage.dfm.dotted',    Has(U, 'Picture.Data'), 'dotted path recorded whole');
  Check('usage.dfm.dotroot',   Has(U, 'Picture'), 'dotted path also records its root');
  Check('usage.dfm.blob',      not Has(U, 'Width'), 'a line inside a { } blob is not an assignment');
  Check('usage.dfm.itemlist',  not Has(U, 'Height'), 'a line inside a < > item list is not an assignment');
  Check('usage.dfm.child',     not Has(U, 'Alignment'), 'a nested component is not the From class');
  Check('usage.dfm.sibling',   Has(U, 'Hint'), 'a second instance of the From class is scanned');
  Check('usage.dfm.wrongclass', not Has(U, 'ignored'), 'the outer TForm1 block is not scanned');
  Check('usage.dfm.none', Length(ScanDfmText(SRC, 'TNotPresent')) = 0,
    'no block of the From class yields an empty set');
end;

{ Criteria 7-10: loose '.PropName' matching in a .pas, candidate derivation from the
  From tree, the row test, and case-insensitive de-duplication across files. }
procedure TestScanPasAndMatch;
const
  PAS =
    'procedure TForm1.Go;'#13#10 +
    'begin'#13#10 +
    '  btnA.Caption := ''x'';'#13#10 +
    '  with btnA do Layout := ablGlyphLeft;'#13#10 +   // no dot: NOT matched, by design
    '  Self.CaptionExtra := 1;'#13#10 +                // must not mark Caption used
    '  lbl.Font.Size := 9;'#13#10 +
    'end;'#13#10;

  function Has(const A: TArray<string>; const S: string): Boolean;
  var X: string;
  begin
    for X in A do
      if SameText(X, S) then Exit(True);
    Result := False;
  end;

var
  Cand, U, M: TArray<string>;
begin
  Cand := CandidatesFor(['Caption', 'Layout', 'Font.Size', 'Hint']);
  Check('usage.cand.leaf',   Has(Cand, 'Size'), 'last segment of a dotted path is a candidate');
  Check('usage.cand.full',   Has(Cand, 'Font.Size'), 'the full dotted path is a candidate');
  Check('usage.cand.plain',  Has(Cand, 'Caption'), 'plain names are candidates');

  U := ScanPasText(PAS, Cand);
  Check('usage.pas.hit',      Has(U, 'Caption'), '.Caption is used');
  Check('usage.pas.boundary', not Has(U, 'Hint'), 'Hint never appears');
  Check('usage.pas.suffix',   Has(U, 'Caption'), 'CaptionExtra must not be the only reason');
  Check('usage.pas.nested',   Has(U, 'Size'), '.Size matches through lbl.Font.Size');
  Check('usage.pas.nodot',    not Has(U, 'Layout'),
    'a with-block assignment has no dot, so the loose match cannot see it');

  // criterion 8 in isolation: a longer identifier must not mark the shorter one used
  Check('usage.pas.notprefix',
    not Has(ScanPasText('  x.CaptionExtra := 1;'#13#10, ['Caption']), 'Caption'),
    '.CaptionExtra must not mark Caption used');

  // criterion 9: the row test
  Check('usage.row.exact',  IsRowUsed('Caption', ['caption']), 'case-insensitive exact path');
  Check('usage.row.leaf',   IsRowUsed('Font.Size', ['Size']), 'last segment matches');
  Check('usage.row.full',   IsRowUsed('Font.Size', ['Font.Size']), 'full path matches');
  Check('usage.row.miss',   not IsRowUsed('Font.Size', ['Color']), 'unrelated name does not match');

  // criterion 10: merge de-duplicates case-insensitively
  M := MergeUsage([TArray<string>.Create('Caption', 'Left'),
                   TArray<string>.Create('caption', 'Top')]);
  Check('usage.merge.count', Length(M) = 3, IntToStr(Length(M)));
end;

{ Criterion 11 plus the orchestration: ComputeUsage merges both sources, counts files, and
  reports used names with no From-tree leaf. Also pins criterion 1 against the REAL block
  shape from ORM3\CLIENT\VARINSP.dfm (an ABC5 TabcToggleBtn with a Picture.Data blob),
  copied here as a fixture so the suite never depends on a path outside the repo. }
procedure TestComputeUsage;
const
  REAL_DFM =
    '            object btnEWAcAQL: TabcToggleBtn'#13#10 +
    '              Left = 4'#13#10 +
    '              Top = 175'#13#10 +
    '              Width = 44'#13#10 +
    '              Height = 39'#13#10 +
    '              GroupIndex = 58114708'#13#10 +
    '              Caption = ''Ac'''#13#10 +
    '              Images = imlGlyphList'#13#10 +
    '              Layout = ablGlyphCenter'#13#10 +
    '              Picture.Data = {'#13#10 +
    '                07544269746D617076080000424D760800000000000076000000280000008000'#13#10 +
    '                0000200000000100040000000000000800000000000000000000100000000000}'#13#10 +
    '            end'#13#10;
  PAS = '  btnEWAcAQL.Enabled := True;'#13#10;

  function Has(const A: TArray<string>; const S: string): Boolean;
  var X: string;
  begin
    for X in A do
      if SameText(X, S) then Exit(True);
    Result := False;
  end;

var
  U: TUsageSet;
begin
  U := ComputeUsage([REAL_DFM], [PAS], 'TabcToggleBtn',
    ['Left', 'Top', 'Width', 'Height', 'GroupIndex', 'Caption', 'Images', 'Layout',
     'Picture', 'Picture.Data', 'Enabled', 'Hint']);

  Check('usage.compute.dfmcount', U.DfmCount = 1, IntToStr(U.DfmCount));
  Check('usage.compute.pascount', U.PasCount = 1, IntToStr(U.PasCount));
  Check('usage.compute.dfm',      Has(U.Names, 'GroupIndex'), 'from the DFM');
  Check('usage.compute.pas',      Has(U.Names, 'Enabled'), 'from the PAS');
  Check('usage.compute.blob',     not Has(U.Names, '07544269746D617076080000424D760800000000000076000000280000008000'),
    'hex blob lines are not names');
  Check('usage.compute.unused',   not Has(U.Names, 'Hint'), 'Hint is used nowhere');
  Check('usage.compute.nomissing', Length(U.Missing) = 0,
    'every used name has a From-tree leaf here');

  // criterion 11: a used name with no From-tree leaf is reported
  U := ComputeUsage([REAL_DFM], [], 'TabcToggleBtn', ['Caption']);
  Check('usage.compute.missing', Has(U.Missing, 'GroupIndex'),
    'GroupIndex is assigned in the DFM but absent from the From tree');
  Check('usage.compute.missing.notused', not Has(U.Missing, 'Caption'),
    'a name WITH a leaf is not Missing');
end;

{ Review fix (Important 1 + 2): a terminator character sitting inside a QUOTED literal
  inside a <...> or (...) container must not be mistaken for the container's real
  terminator. For <...> this used to pop the block stack early on a mid-list item's own
  bare 'end', silently dropping every property recorded after the list (criterion the
  reviewer traced: 'Y > Z' inside an item clears SkipTo, 'end' then pops the From-class
  block, 'GroupIndex' after the list is never seen). For (...) -- previously untested at
  all -- the same early clear instead lets a line INSIDE the still-open value be read as
  a real property. Both are fixed by StripQuoted: the terminator search runs over a copy
  of the line with quoted content removed. }
procedure TestScanDfmSkipRobustness;
const
  ANGLE_SRC =
    'object btnA: TabcToggleBtn'#13#10 +
    '  Columns = <'#13#10 +
    '    item'#13#10 +
    '      Caption = ''Y > Z'''#13#10 +   // '>' inside quotes must not close the list
    '    end'#13#10 +
    '    item'#13#10 +
    '      Caption = ''B'''#13#10 +
    '    end>'#13#10 +
    '  GroupIndex = 5'#13#10 +            // must still be recorded
    'end'#13#10;

  PAREN_SRC =
    'object btnA: TabcToggleBtn'#13#10 +
    '  Extra = ('#13#10 +
    '    ''A) B'''#13#10 +                // ')' inside quotes must not close the value
    '    BogusInner = 1'#13#10 +          // looks like an assignment; must NOT be recorded
    '    ''C'')'#13#10 +
    '  Hint = ''after'''#13#10 +          // must still be recorded
    'end'#13#10;

  { Confirms the same-line case is unaffected by the fix: a value that opens AND
    closes its container on one line must not itself trip skip mode. }
  SAMELINE_SRC =
    'object btnA: TabcToggleBtn'#13#10 +
    '  Columns = <>'#13#10 +
    '  Blob = {}'#13#10 +
    '  Hint = ''x'''#13#10 +
    'end'#13#10;

  function Has(const A: TArray<string>; const S: string): Boolean;
  var X: string;
  begin
    for X in A do
      if SameText(X, S) then Exit(True);
    Result := False;
  end;

var
  U: TArray<string>;
begin
  U := ScanDfmText(ANGLE_SRC, 'TabcToggleBtn');
  Check('usage.dfm.skip.angle.quote-defeat',
    Has(U, 'GroupIndex'), 'a > inside a quoted item value must not close the <...> list early');
  Check('usage.dfm.skip.angle.inner-not-recorded',
    not Has(U, 'Caption'), 'assignments inside <...> items are never recorded');

  U := ScanDfmText(PAREN_SRC, 'TabcToggleBtn');
  Check('usage.dfm.skip.paren.quote-defeat',
    not Has(U, 'BogusInner'), 'a ) inside a quoted list value must not close the (...) value early');
  Check('usage.dfm.skip.paren.after-recorded',
    Has(U, 'Hint'), 'the immediate-level property after the list still gets recorded');

  U := ScanDfmText(SAMELINE_SRC, 'TabcToggleBtn');
  Check('usage.dfm.skip.sameline.angle-empty',
    Has(U, 'Blob'), 'Columns = <> must not itself enter skip mode');
  Check('usage.dfm.skip.sameline.brace-empty',
    Has(U, 'Hint'), 'Blob = {} must not itself enter skip mode');
end;

{ Review fix (Important 3): ScanPasText was reworked from an O(candidates x textlength)
  per-candidate scan into a single O(textlength) harvest of every '.Identifier' token
  followed by an O(candidates) membership filter. This pins the boundary case that
  inversion is most likely to get wrong: a '.' as the very last character of the text
  (nothing follows it to harvest) must not raise or hang, and an empty candidate list
  or empty text must still return an empty result. }
procedure TestScanPasEndOfTextSafety;
begin
  Check('usage.pas.eot.trailingdot',
    Length(ScanPasText('x.', ['x'])) = 0, 'a trailing dot with nothing after it harvests nothing');
  Check('usage.pas.eot.emptytext',
    Length(ScanPasText('', ['Caption'])) = 0, 'empty text yields an empty result');
  Check('usage.pas.eot.emptycandidates',
    Length(ScanPasText('a.Caption := 1;', [])) = 0, 'no candidates yields an empty result');
  Check('usage.pas.eot.dotatend.stillfindsearlier',
    Contains(ScanPasText('a.Caption := 1; b.', ['Caption']), 'Caption'),
    'a trailing dot must not stop an earlier real match from being found');
end;

{ Go to definition: the PURE parse behind `query --name <T> --json`.

  Every fixture below is VERBATIM stdout of the shipped exe against
  C:\Projects\.drag-lint\library-Win64.sqlite, captured 2026-07-30. Three facts
  about that contract are load-bearing, and each has its own case, because each
  fails SILENTLY -- a wrong reading yields "not found", or worse a confident jump
  to the wrong file:
    * the payload is a BARE top-level array. There is no "results" envelope object
      wrapped around it.
    * the line field is "start_line". There is no "line".
    * --name is a SUBSTRING match. `--name TNotifyEvent` returns local variables
      called ANotifyEvent and nothing named TNotifyEvent at all; `--name TThread`
      returns an unrelated FIELD called TThread before System.Classes.TThread.
      Taking "the first hit" therefore navigates to the wrong symbol, which is why
      the parser filters on an exact name and ranks type-like kinds first. }
procedure TestQueryLocationParse;
const
  { `query --name TAlignment` -- three exact-name rows, two of them enums. The
    wanted answer is the first TYPE-LIKE row: System.Classes.pas:176. }
  QJ_ALIGNMENT =
    '['#13#10 +
    '  {'#13#10 +
    '    "id": 1308682,'#13#10 +
    '    "kind": "enum",'#13#10 +
    '    "name": "TAlignment",'#13#10 +
    '    "qualified_name": "System.Classes.TAlignment",'#13#10 +
    '    "signature": "",'#13#10 +
    '    "modifiers": "",'#13#10 +
    '    "section": "interface",'#13#10 +
    '    "usable_from_other_units": true,'#13#10 +
    '    "file_id": 4644,'#13#10 +
    '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\source\\rtl\\common\\System.Classes.pas",'#13#10 +
    '    "start_line": 176,'#13#10 +
    '    "start_col": 3,'#13#10 +
    '    "end_line": 176,'#13#10 +
    '    "end_col": 58,'#13#10 +
    '    "impl_start_line": 0,'#13#10 +
    '    "impl_end_line": 0'#13#10 +
    '  },'#13#10 +
    '  {'#13#10 +
    '    "id": 661597,'#13#10 +
    '    "kind": "record",'#13#10 +
    '    "name": "TAlignment",'#13#10 +
    '    "qualified_name": "dxRichEdit.Dialogs.TableStyle.TdxRichEditTableStyleDialogForm.TAlignment",'#13#10 +
    '    "signature": "",'#13#10 +
    '    "modifiers": "",'#13#10 +
    '    "section": "interface",'#13#10 +
    '    "usable_from_other_units": true,'#13#10 +
    '    "file_id": 2715,'#13#10 +
    '    "file": "C:\\Program Files (x86)\\DevExpress\\VCL\\ExpressRichEdit Control\\Sources\\dxRichEdit.Dialogs.TableStyle.pas",'#13#10 +
    '    "start_line": 245,'#13#10 +
    '    "start_col": 7,'#13#10 +
    '    "end_line": 249,'#13#10 +
    '    "end_col": 11,'#13#10 +
    '    "impl_start_line": 0,'#13#10 +
    '    "impl_end_line": 0'#13#10 +
    '  },'#13#10 +
    '  {'#13#10 +
    '    "id": 795949,'#13#10 +
    '    "kind": "enum",'#13#10 +
    '    "name": "TAlignment",'#13#10 +
    '    "qualified_name": "dxSplashForms.TdxSplashFormBase.TAlignment",'#13#10 +
    '    "signature": "",'#13#10 +
    '    "modifiers": "",'#13#10 +
    '    "section": "interface",'#13#10 +
    '    "usable_from_other_units": true,'#13#10 +
    '    "file_id": 3238,'#13#10 +
    '    "file": "C:\\Program Files (x86)\\DevExpress\\VCL\\ExpressSplashForms\\Sources\\dxSplashForms.pas",'#13#10 +
    '    "start_line": 131,'#13#10 +
    '    "start_col": 5,'#13#10 +
    '    "end_line": 131,'#13#10 +
    '    "end_col": 38,'#13#10 +
    '    "impl_start_line": 0,'#13#10 +
    '    "impl_end_line": 0'#13#10 +
    '  }'#13#10 +
    ']'#13#10;

  { `query --name TThread` -- the exe returns an unrelated FIELD named TThread
    BEFORE System.Classes.TThread. "First hit" would open EAppMultiThreaded.pas:67. }
  QJ_THREAD =
    '['#13#10 +
    '  {'#13#10 +
    '    "id": 2119103,'#13#10 +
    '    "kind": "field",'#13#10 +
    '    "name": "TThread",'#13#10 +
    '    "qualified_name": "EAppMultiThreaded.THookedThread.TThread",'#13#10 +
    '    "signature": "TClass",'#13#10 +
    '    "modifiers": "public",'#13#10 +
    '    "section": "implementation",'#13#10 +
    '    "usable_from_other_units": false,'#13#10 +
    '    "file_id": 6707,'#13#10 +
    '    "file": "C:\\Program Files (x86)\\Neos Eureka S.r.l\\EurekaLog 7\\Source\\EAppMultiThreaded.pas",'#13#10 +
    '    "start_line": 67,'#13#10 +
    '    "start_col": 5,'#13#10 +
    '    "end_line": 67,'#13#10 +
    '    "end_col": 21,'#13#10 +
    '    "impl_start_line": 0,'#13#10 +
    '    "impl_end_line": 0'#13#10 +
    '  },'#13#10 +
    '  {'#13#10 +
    '    "id": 1310582,'#13#10 +
    '    "kind": "class",'#13#10 +
    '    "name": "TThread",'#13#10 +
    '    "qualified_name": "System.Classes.TThread",'#13#10 +
    '    "signature": "",'#13#10 +
    '    "modifiers": "",'#13#10 +
    '    "section": "interface",'#13#10 +
    '    "usable_from_other_units": true,'#13#10 +
    '    "file_id": 4644,'#13#10 +
    '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\source\\rtl\\common\\System.Classes.pas",'#13#10 +
    '    "start_line": 1822,'#13#10 +
    '    "start_col": 3,'#13#10 +
    '    "end_line": 2021,'#13#10 +
    '    "end_col": 7,'#13#10 +
    '    "impl_start_line": 0,'#13#10 +
    '    "impl_end_line": 0'#13#10 +
    '  }'#13#10 +
    ']'#13#10;

  { `query --name TNotifyEvent` -- first two of ten rows. NOT ONE of them is named
    TNotifyEvent: the type is a method pointer and the index does not carry it, so
    every hit is the substring ANotifyEvent. This must resolve to nothing. }
  QJ_NOTIFYEVENT_SUBSTRINGONLY =
    '['#13#10 +
    '  {'#13#10 +
    '    "id": 965744,'#13#10 +
    '    "kind": "local_var",'#13#10 +
    '    "name": "ANotifyEvent",'#13#10 +
    '    "qualified_name": "Abcapp.TabcApplicationEvents.AppOnActivate.ANotifyEvent",'#13#10 +
    '    "signature": "TNotifyEvent",'#13#10 +
    '    "modifiers": "",'#13#10 +
    '    "section": "implementation",'#13#10 +
    '    "usable_from_other_units": false,'#13#10 +
    '    "file_id": 4051,'#13#10 +
    '    "file": "C:\\Projects\\ABC5\\ABC5\\Source\\Abcapp.pas",'#13#10 +
    '    "start_line": 322,'#13#10 +
    '    "start_col": 3,'#13#10 +
    '    "end_line": 322,'#13#10 +
    '    "end_col": 15,'#13#10 +
    '    "impl_start_line": 0,'#13#10 +
    '    "impl_end_line": 0'#13#10 +
    '  },'#13#10 +
    '  {'#13#10 +
    '    "id": 965746,'#13#10 +
    '    "kind": "local_var",'#13#10 +
    '    "name": "ANotifyEvent",'#13#10 +
    '    "qualified_name": "Abcapp.TabcApplicationEvents.AppOnDeactivate.ANotifyEvent",'#13#10 +
    '    "signature": "TNotifyEvent",'#13#10 +
    '    "modifiers": "",'#13#10 +
    '    "section": "implementation",'#13#10 +
    '    "usable_from_other_units": false,'#13#10 +
    '    "file_id": 4051,'#13#10 +
    '    "file": "C:\\Projects\\ABC5\\ABC5\\Source\\Abcapp.pas",'#13#10 +
    '    "start_line": 335,'#13#10 +
    '    "start_col": 3,'#13#10 +
    '    "end_line": 335,'#13#10 +
    '    "end_col": 15,'#13#10 +
    '    "impl_start_line": 0,'#13#10 +
    '    "impl_end_line": 0'#13#10 +
    '  }'#13#10 +
    ']'#13#10;

  { `query --name TabcButtonStyle` -- one enum row, the ABC5 type the editor's
    grid actually shows as `Style : TabcButtonStyle`. }
  QJ_ABCBUTTONSTYLE =
    '['#13#10 +
    '  {'#13#10 +
    '    "id": 967081,'#13#10 +
    '    "kind": "enum",'#13#10 +
    '    "name": "TabcButtonStyle",'#13#10 +
    '    "qualified_name": "Abcbtn.TabcButtonStyle",'#13#10 +
    '    "signature": "",'#13#10 +
    '    "modifiers": "",'#13#10 +
    '    "section": "interface",'#13#10 +
    '    "usable_from_other_units": true,'#13#10 +
    '    "file_id": 4055,'#13#10 +
    '    "file": "C:\\Projects\\ABC5\\ABC5\\Source\\Abcbtn.pas",'#13#10 +
    '    "start_line": 33,'#13#10 +
    '    "start_col": 3,'#13#10 +
    '    "end_line": 39,'#13#10 +
    '    "end_col": 71,'#13#10 +
    '    "impl_start_line": 0,'#13#10 +
    '    "impl_end_line": 0'#13#10 +
    '  }'#13#10 +
    ']'#13#10;

  { The two REAL rows `query --name TFontPitch` returns -- the enum in
    System.UITypes and the Vcl.Graphics ALIAS pointing at it -- written here with the
    alias FIRST. The engine happens to emit the enum first today, but that order is
    an artefact of indexing order, not a contract, and only the enum row can yield
    members. So the ranking, not the order, must decide. }
  QJ_FONTPITCH_ALIAS_FIRST =
    '['#13#10 +
    '  {'#13#10 +
    '    "id": 1269016,'#13#10 +
    '    "kind": "type",'#13#10 +
    '    "name": "TFontPitch",'#13#10 +
    '    "qualified_name": "Vcl.Graphics.TFontPitch",'#13#10 +
    '    "signature": "System.UITypes.TFontPitch",'#13#10 +
    '    "modifiers": "",'#13#10 +
    '    "section": "interface",'#13#10 +
    '    "usable_from_other_units": true,'#13#10 +
    '    "file_id": 4558,'#13#10 +
    '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\SOURCE\\VCL\\Vcl.Graphics.pas",'#13#10 +
    '    "start_line": 390,'#13#10 +
    '    "start_col": 3,'#13#10 +
    '    "end_line": 390,'#13#10 +
    '    "end_col": 42,'#13#10 +
    '    "impl_start_line": 0,'#13#10 +
    '    "impl_end_line": 0'#13#10 +
    '  },'#13#10 +
    '  {'#13#10 +
    '    "id": 1348320,'#13#10 +
    '    "kind": "enum",'#13#10 +
    '    "name": "TFontPitch",'#13#10 +
    '    "qualified_name": "System.UITypes.TFontPitch",'#13#10 +
    '    "signature": "",'#13#10 +
    '    "modifiers": "",'#13#10 +
    '    "section": "interface",'#13#10 +
    '    "usable_from_other_units": true,'#13#10 +
    '    "file_id": 4705,'#13#10 +
    '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\source\\rtl\\common\\System.UITypes.pas",'#13#10 +
    '    "start_line": 74,'#13#10 +
    '    "start_col": 3,'#13#10 +
    '    "end_line": 74,'#13#10 +
    '    "end_col": 49,'#13#10 +
    '    "impl_start_line": 0,'#13#10 +
    '    "impl_end_line": 0'#13#10 +
    '  }'#13#10 +
    ']'#13#10;

  { Real zero-hit stdout. The process ALSO exits 1 -- "no hits", not a failure. }
  QJ_NOHITS = '['#13#10 +
              ']'#13#10;
  { RunCapture merges the child's stderr into stdout, and the exe writes this
    note to stderr on every call. The parser must survive it. }
  PREAMBLE = '(loaded defaults from C:\Projects\.drag-lint.json)'#13#10;

  { The real System.Classes.TAlignment row with its "start_line" field DELETED.
    The exe has never been observed to emit a row without one, so this is not a
    captured shape -- it exists to pin the DEFENSIVE branch the DocInsight on
    ParseQueryLocation promises: a chosen row with no usable line still resolves,
    to line 1 of the right file, never to line 0. }
  QJ_ALIGNMENT_NO_START_LINE =
    '['#13#10 +
    '  {'#13#10 +
    '    "id": 1308682,'#13#10 +
    '    "kind": "enum",'#13#10 +
    '    "name": "TAlignment",'#13#10 +
    '    "qualified_name": "System.Classes.TAlignment",'#13#10 +
    '    "signature": "",'#13#10 +
    '    "modifiers": "",'#13#10 +
    '    "section": "interface",'#13#10 +
    '    "usable_from_other_units": true,'#13#10 +
    '    "file_id": 4644,'#13#10 +
    '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\source\\rtl\\common\\System.Classes.pas",'#13#10 +
    '    "start_col": 3,'#13#10 +
    '    "end_line": 176,'#13#10 +
    '    "end_col": 58,'#13#10 +
    '    "impl_start_line": 0,'#13#10 +
    '    "impl_end_line": 0'#13#10 +
    '  }'#13#10 +
    ']'#13#10;
var
  F  : string ;
  Ln : Integer;
  Amb: Integer;
begin
  Check('queryloc.parses.bare.toplevel.array',
    ParseQueryLocation(QJ_ALIGNMENT, 'TAlignment', F, Ln, Amb)
    and SameText(ExtractFileName(F), 'System.Classes.pas'), F);
  Check('queryloc.reads.start_line.not.line',
    ParseQueryLocation(QJ_ALIGNMENT, 'TAlignment', F, Ln, Amb) and (Ln = 176),
    'expected 176, got ' + IntToStr(Ln));
  Check('queryloc.prefers.type.over.field',
    ParseQueryLocation(QJ_THREAD, 'TThread', F, Ln, Amb)
    and SameText(ExtractFileName(F), 'System.Classes.pas') and (Ln = 1822),
    'first hit is an unrelated field; got ' + F + ':' + IntToStr(Ln));
  Check('queryloc.prefers.concrete.over.alias',
    ParseQueryLocation(QJ_FONTPITCH_ALIAS_FIRST, 'TFontPitch', F, Ln, Amb)
    and SameText(ExtractFileName(F), 'System.UITypes.pas') and (Ln = 74),
    'the enum, not the Vcl.Graphics alias to it; got ' + F + ':' + IntToStr(Ln));

  { Ranking settles KIND, never a tie WITHIN a kind tier -- and ties are ordinary.
    All three TAlignment rows are tier 0 (two enums and a record), all are
    section=interface with usable_from_other_units=true, so nothing on the rows can
    separate them; System.Classes wins only because it was indexed first. The count
    is what lets the caller say so instead of presenting a coin-flip as the answer. }
  Check('queryloc.reports.tied.candidates',
    ParseQueryLocation(QJ_ALIGNMENT, 'TAlignment', F, Ln, Amb) and (Amb = 3),
    'three tier-0 rows named TAlignment; got ' + IntToStr(Amb));
  Check('queryloc.unambiguous.reports.one',
    ParseQueryLocation(QJ_THREAD, 'TThread', F, Ln, Amb) and (Amb = 1),
    'only the class is tier 0, so the answer was forced; got ' + IntToStr(Amb));
  Check('queryloc.missing.start_line.clamps.to.one',
    ParseQueryLocation(QJ_ALIGNMENT_NO_START_LINE, 'TAlignment', F, Ln, Amb)
    and SameText(ExtractFileName(F), 'System.Classes.pas') and (Ln = 1),
    'the wire contract treats a missing line as 1, never 0; got ' + IntToStr(Ln));

  Check('queryloc.substring.only.hits.fail',
    not ParseQueryLocation(QJ_NOTIFYEVENT_SUBSTRINGONLY, 'TNotifyEvent', F, Ln, Amb)
    and (Amb = 0), 'ANotifyEvent is a substring hit, not TNotifyEvent');
  Check('queryloc.accepts.qualified.name',
    ParseQueryLocation(QJ_ABCBUTTONSTYLE, 'Abcbtn.TabcButtonStyle', F, Ln, Amb)
    and (Ln = 33), IntToStr(Ln));
  Check('queryloc.tolerates.stderr.preamble',
    ParseQueryLocation(PREAMBLE + QJ_ABCBUTTONSTYLE, 'TabcButtonStyle', F, Ln, Amb)
    and (Ln = 33), 'the loaded-defaults note must not break the parse');
  Check('queryloc.empty.array.fails',
    not ParseQueryLocation(QJ_NOHITS, 'TAlignment', F, Ln, Amb),
    'zero hits must not report success');
  Check('queryloc.garbage.fails',
    not ParseQueryLocation('not json', 'TAlignment', F, Ln, Amb),
    'garbage must not report success');
end;

{ Enum members: the PURE parse of an enum's DECLARATION SOURCE.

  There is no members list in the index and no children query -- an enum row
  carries only kind='enum' plus file + start_line..end_line, and `surface --qname`
  refuses a non-class. So the members come from the declaration text itself, and
  this is the function that reads it. Fixtures are the real source lines the index
  points at. }
procedure TestEnumMembersParse;
const
  { System.Classes.pas:176 -- the ordinary one-line case. }
  ED_SIMPLE =
    '  TAlignment = (taLeftJustify, taRightJustify, taCenter);'#13#10;
  { Abcbtn.pas:33-39 -- 19 members over seven lines. }
  ED_MULTILINE =
    '  TabcButtonStyle = (absAutoDetect, absNew, absWin31, absThin, absThinBlack,'#13#10 +
    '                     absThinGray,'#13#10 +
    '                     absThinHighlight, absMidHighlight, absThickHighlight,'#13#10 +
    '                     absFramed, absFramedBlack, absFramedRaised,'#13#10 +
    '                     absFramedHighlight, absFramedBlackHighlight,'#13#10 +
    '                     absRecessed, absRecessedBlack, absRecessedRaised,'#13#10 +
    '                     absRecessedHighlight, absRecessedBlackHighlight);'#13#10;
  { CSIdWinsock2.pas:2639-2648 -- the hard real case, all in one declaration:
    explicit "= N" values, compiler directives, a // comment, and the SAME member
    appearing in both arms of the $IFDEF. }
  ED_CONDITIONAL =
    '  _RIO_NOTIFICATION_COMPLETION_TYPE = ('#13#10 +
    '    {$IFDEF HAS_ENUM_ELEMENT_VALUES}'#13#10 +
    '    RIO_EVENT_COMPLETION      = 1,'#13#10 +
    '    RIO_IOCP_COMPLETION       = 2'#13#10 +
    '    {$ELSE}'#13#10 +
    '    rnctUnused,   // do not use'#13#10 +
    '    RIO_EVENT_COMPLETION,'#13#10 +
    '    RIO_IOCP_COMPLETION'#13#10 +
    '    {$ENDIF}'#13#10 +
    '  );'#13#10;
  { Abcbtn.pas:68 -- a class. It has '=' and '(' too, so a naive scan would
    happily report TButton as a "member". }
  ED_CLASS =
    '  TabcPicBtn = class(TButton)'#13#10;
var
  M: TArray<string>;
begin
  { Every case re-parses. Asserting against whatever M was left holding by the
    PREVIOUS Check couples the cases together and, worse, makes the negative ones
    ("no directive is a member") pass for free whenever M happens to be empty. }
  Check('enum.members.simple.count',
    ParseEnumMembers(ED_SIMPLE, M) and (Length(M) = 3), IntToStr(Length(M)));
  Check('enum.members.simple.order',
    ParseEnumMembers(ED_SIMPLE, M) and (Length(M) = 3)
    and (M[0] = 'taLeftJustify') and (M[2] = 'taCenter'),
    'declaration order must be preserved');
  Check('enum.members.multiline.count',
    ParseEnumMembers(ED_MULTILINE, M) and (Length(M) = 19), IntToStr(Length(M)));
  Check('enum.members.multiline.ends',
    ParseEnumMembers(ED_MULTILINE, M) and (Length(M) = 19)
    and (M[0] = 'absAutoDetect')
    and (M[18] = 'absRecessedBlackHighlight'), 'first/last member');
  Check('enum.members.strips.explicit.values',
    ParseEnumMembers(ED_CONDITIONAL, M) and Contains(M, 'RIO_EVENT_COMPLETION')
    and not Contains(M, '1'), 'a "= 1" is a value, not a member');
  { The non-empty guard is the point: without it this passes for free on an empty M. }
  Check('enum.members.skips.directives.and.comments',
    ParseEnumMembers(ED_CONDITIONAL, M) and (Length(M) > 0)
    and not Contains(M, 'IFDEF') and not Contains(M, 'ELSE') and not Contains(M, 'do'),
    'compiler directives and // comments are not members');
  Check('enum.members.dedupes.ifdef.arms',
    ParseEnumMembers(ED_CONDITIONAL, M)
    and (CountOf(M, 'RIO_EVENT_COMPLETION') = 1)
    and Contains(M, 'rnctUnused'),
    'both arms contribute, but a member named in both is listed once');
  Check('enum.nonenum.yields.none',
    not ParseEnumMembers(ED_CLASS, M) and (Length(M) = 0),
    'a class has no enum members');
  Check('enum.empty.text.yields.none',
    not ParseEnumMembers('', M) and (Length(M) = 0), 'empty text has no members');
end;

{ End-to-end against the REAL exe and the REAL library index: the two adapter
  verbs the context menu calls. The parse cases above pin the shapes; this pins
  that the arguments, exit codes and source-range read are right too. }
procedure TestGoToDefinitionLive;
var
  Exe, F, Err: string;
  Ln     : Integer;
  Adapter: TEngineAdapter;
  M      : TArray<string>;
begin
  Exe := ResolveExe;
  if (Exe = '') or not TFile.Exists(LibWin64) then
  begin
    Skip('gotodef.live', 'drag-lint.exe or library-Win64 index not found');
    Exit;
  end;
  Adapter := TEngineAdapter.Create(Exe, [LibWin64]);
  try
    Check('gotodef.live.resolves.enum',
      Adapter.ResolveTypeLocation('TAlignment', F, Ln, Err)
      and SameText(ExtractFileName(F), 'System.Classes.pas') and (Ln = 176),
      F + ':' + IntToStr(Ln) + ' ' + Err);
    { Exit code 1 means "no hits", not "the engine broke" -- either way the caller
      must be told, never left with a stale or blank location. }
    Check('gotodef.live.unindexed.reports.reason',
      not Adapter.ResolveTypeLocation('TZzzNotARealTypeXyz', F, Ln, Err)
      and (Err <> ''), 'an unindexed type must fail WITH a reason');
    if Adapter.ResolveTypeLocation('TAlignment', F, Ln, Err) and TFile.Exists(F) then
      Check('gotodef.live.enum.members',
        Adapter.EnumMembersOf('TAlignment', M, Err) and (Length(M) = 3)
        and SameText(M[0], 'taLeftJustify'),
        Err + ' n=' + IntToStr(Length(M)))
    else
      Skip('gotodef.live.enum.members', 'RTL source not on disk');
    { Err too, not just the False: a silent failure would otherwise pass here, and
      the status bar has nothing to show the user when Err is empty. }
    Check('gotodef.live.class.has.no.members',
      not Adapter.EnumMembersOf('TThread', M, Err) and (Err <> '')
      and (Length(M) = 0), 'a class is not an enum, and must say so: Err=' + Err);
  finally
    Adapter.Free;
  end;
end;

{ #mapping declares a reusable enum -> property-value mapping ONCE, narrowed to a source
  enum and one or more target classes; #apply pulls it into a #convert block. One node per
  line -- the model is flat and must stay flat. #apply is NOT #use: #use already means
  "add a unit to the uses clause". }
procedure TestMappingRules;
var
  B: TRuleBook;
  N: TRuleNode;
begin
  B := TRuleBook.Create;
  try
    N := B.ParseLine('#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton, cxButtons.TcxBigButton');
    Check('mapping.kind', N.Kind = rnkMapping);
    Check('mapping.name', N.MapName = 'XYZStyle', N.MapName);
    Check('mapping.fromtype', N.MapFromType = 'XYZ.TXYZButtonStyle', N.MapFromType);
    Check('mapping.totypes.count', Length(N.MapToTypes) = 2, IntToStr(Length(N.MapToTypes)));
    Check('mapping.totypes.second', N.MapToTypes[1] = 'cxButtons.TcxBigButton', N.MapToTypes[1]);

    N := B.ParseLine('#mapping XYZStyle #when Style = stOK -> Default = True, ModalResult = mrOk');
    Check('when.kind', N.Kind = rnkMapping);
    Check('when.name', N.MapName = 'XYZStyle', N.MapName);
    Check('when.from', N.WhenFrom = 'Style', N.WhenFrom);
    Check('when.value', N.WhenValue = 'stOK', N.WhenValue);
    Check('when.not.else', not N.IsElse);
    Check('when.sets.count', Length(N.Sets) = 2, IntToStr(Length(N.Sets)));
    Check('when.sets.0.path', N.Sets[0].ToPath = 'Default', N.Sets[0].ToPath);
    Check('when.sets.0.value', N.Sets[0].Value = 'True', N.Sets[0].Value);
    Check('when.sets.1.path', N.Sets[1].ToPath = 'ModalResult', N.Sets[1].ToPath);

    // Multi-level target paths must survive -- the whole point of the path model.
    N := B.ParseLine('#mapping XYZStyle #when Style = stOK -> Style.ModalResult.Default = True');
    Check('when.nested.path', N.Sets[0].ToPath = 'Style.ModalResult.Default', N.Sets[0].ToPath);

    N := B.ParseLine('#mapping XYZStyle #else -> ModalResult = mrNone');
    Check('else.is.else', N.IsElse);
    Check('else.sets', (Length(N.Sets) = 1) and (N.Sets[0].Value = 'mrNone'));

    N := B.ParseLine('#apply XYZStyle');
    Check('apply.kind', N.Kind = rnkApply);
    Check('apply.name', N.ApplyName = 'XYZStyle', N.ApplyName);

    // #use must NOT be mistaken for #apply.
    N := B.ParseLine('#use FireDAC.Comp.Client');
    Check('use.still.means.unit', N.Kind = rnkUse, 'use must stay a uses-clause directive');
  finally
    B.Free;
  end;
end;

{ An unedited line must come back byte-for-byte; a rule book that rewrites lines it did not
  change makes every diff unreadable. }
procedure TestMappingRoundTrip;
const
  SRC =
    '#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton'#13#10 +
    '#mapping XYZStyle #when Style = stOK -> Default = True, ModalResult = mrOk'#13#10 +
    '#mapping XYZStyle #else -> ModalResult = mrNone'#13#10 +
    '#convert XYZ.TXYZToggleButton -> cxButtons.TcxButton'#13#10 +
    '  #apply XYZStyle'#13#10;
var
  B: TRuleBook;
begin
  B := TRuleBook.Create;
  try
    B.LoadFromString(SRC);
    Check('mapping.roundtrip.exact', B.SaveToString = SRC, 'round-trip altered the text');
  finally
    B.Free;
  end;
end;

{ A '#when' with no '-> sets' must still keep its condition. This is not a
  hypothetical: SplitBareArrow takes out-mode strings, and Delphi finalizes an
  out-mode managed argument to '' BEFORE the callee runs -- so seeding the argument
  with "the original text" and relying on the callee to leave it alone silently
  yields an EMPTY condition. Only a test that omits the arrow can catch that. }
procedure TestMappingWhenWithoutSets;
var
  B: TRuleBook;
  N: TRuleNode;
begin
  B := TRuleBook.Create;
  try
    N := B.ParseLine('#mapping XYZStyle #when Style = stOK');
    Check('when.noarrow.kind', N.Kind = rnkMapping);
    Check('when.noarrow.name', N.MapName = 'XYZStyle', N.MapName);
    Check('when.noarrow.from', N.WhenFrom = 'Style', '[' + N.WhenFrom + ']');
    Check('when.noarrow.value', N.WhenValue = 'stOK', '[' + N.WhenValue + ']');
    Check('when.noarrow.nosets', Length(N.Sets) = 0, IntToStr(Length(N.Sets)));
    { A condition with no '=' either: the path must survive rather than vanish. }
    N := B.ParseLine('#mapping XYZStyle #when Style');
    Check('when.noeq.from', N.WhenFrom = 'Style', '[' + N.WhenFrom + ']');
  finally
    B.Free;
  end;
end;

{ Emit's #mapping/#apply branches only run for an EDITED (Dirty) node -- an untouched
  line returns Raw -- so the round-trip test alone would pass even against a parser
  that never recognised #mapping. This drives Emit directly and pins the canonical
  text of all three #mapping forms plus #apply in the suite, permanently. }
procedure TestMappingEmit;
var
  N   : TRuleNode      ;
  B   : TRuleBook      ;
  Sets: TArray<TSetPair>;

  { Parse a line, mark it edited, and re-emit: the canonical serialization must be a
    FIXPOINT of the canonical source text, or editing one field of an untouched line
    silently reformats it. }
  function ReEmit(const ALine: string): string;
  var Nd: TRuleNode;
  begin
    Nd := B.ParseLine(ALine);
    try
      Nd.Dirty := True;
      Result := Nd.Emit;
    finally
      Nd.Free;
    end;
  end;

begin
  N := TRuleNode.Create;
  try
    N.Kind        := rnkMapping;
    N.Dirty       := True;
    N.MapName     := 'XYZStyle';
    N.MapFromType := 'XYZ.TXYZButtonStyle';
    N.MapToTypes  := TArray<string>.Create('cxButtons.TcxButton', 'cxButtons.TcxBigButton');
    Check('emit.decl', N.Emit =
      '#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton, cxButtons.TcxBigButton',
      N.Emit);
  finally
    N.Free;
  end;

  SetLength(Sets, 2);
  Sets[0].ToPath := 'Default'    ; Sets[0].Value := 'True' ;
  Sets[1].ToPath := 'ModalResult'; Sets[1].Value := 'mrOk' ;

  N := TRuleNode.Create;
  try
    N.Kind      := rnkMapping;
    N.Dirty     := True;
    N.MapName   := 'XYZStyle';
    N.WhenFrom  := 'Style';
    N.WhenValue := 'stOK';
    N.Sets      := Sets;
    Check('emit.when', N.Emit =
      '#mapping XYZStyle #when Style = stOK -> Default = True, ModalResult = mrOk', N.Emit);
  finally
    N.Free;
  end;

  N := TRuleNode.Create;
  try
    N.Kind    := rnkMapping;
    N.Dirty   := True;
    N.MapName := 'XYZStyle';
    N.IsElse  := True;
    N.Sets    := Copy(Sets, 1, 1); // ModalResult = mrOk
    Check('emit.else', N.Emit = '#mapping XYZStyle #else -> ModalResult = mrOk', N.Emit);
  finally
    N.Free;
  end;

  N := TRuleNode.Create;
  try
    N.Kind      := rnkApply;
    N.Dirty     := True;
    N.ApplyName := 'XYZStyle';
    Check('emit.apply', N.Emit = '#apply XYZStyle', N.Emit);
  finally
    N.Free;
  end;

  { parse -> edit -> emit must be a fixpoint for every form. }
  B := TRuleBook.Create;
  try
    Check('emit.fixpoint.decl',
      ReEmit('#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton')
      = '#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton',
      ReEmit('#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton'));
    Check('emit.fixpoint.when',
      ReEmit('#mapping XYZStyle #when Style = stOK -> Default = True, ModalResult = mrOk')
      = '#mapping XYZStyle #when Style = stOK -> Default = True, ModalResult = mrOk',
      ReEmit('#mapping XYZStyle #when Style = stOK -> Default = True, ModalResult = mrOk'));
    Check('emit.fixpoint.else',
      ReEmit('#mapping XYZStyle #else -> ModalResult = mrNone')
      = '#mapping XYZStyle #else -> ModalResult = mrNone',
      ReEmit('#mapping XYZStyle #else -> ModalResult = mrNone'));
    Check('emit.fixpoint.apply',
      ReEmit('#apply XYZStyle') = '#apply XYZStyle', ReEmit('#apply XYZStyle'));
  finally
    B.Free;
  end;
end;

{ A #convert block whose entire body is '#apply' MAPS something -- it pulls in a whole
  #mapping. SaveCompleteToString used to drop any block with no #link, so such a block
  was written to disk as zero bytes and reported as an "empty rule": silent data loss
  in exactly the shape #apply exists to create. A #note-only block is still scratch. }
procedure TestSaveCompleteKeepsApplyOnly;
var
  Book   : TRuleBook;
  dropped: Integer  ;
  outp   : string   ;
begin
  Book := TRuleBook.Create;
  try
    Book.LoadFromString(
      '#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton'#13#10 +
      '#convert XYZ.TXYZToggleButton -> cxButtons.TcxButton'#13#10 +  // #apply only: KEEP
      '  #apply XYZStyle'#13#10 +
      '#convert C.TFoo -> D.TBar'#13#10 +                             // #note only: DROP
      '#note nothing mapped yet'#13#10);
    outp := Book.SaveCompleteToString(dropped);
    Check('savecomplete.apply.dropcount', dropped = 1, IntToStr(dropped));
    Check('savecomplete.apply.keeps.header',
      Pos('#convert XYZ.TXYZToggleButton -> cxButtons.TcxButton', outp) > 0,
      'an #apply-only block was dropped as if empty');
    Check('savecomplete.apply.keeps.body', Pos('#apply XYZStyle', outp) > 0, outp);
    Check('savecomplete.apply.keeps.mapping',
      Pos('#mapping XYZStyle from', outp) > 0, 'the #mapping declaration was lost');
    Check('savecomplete.apply.still.drops.note', Pos('C.TFoo', outp) = 0,
      'a #note-only block is still scratch');
  finally
    Book.Free;
  end;
end;

{ One flattened property-tree leaf. Mapping validation only reads Path and IsWritable,
  so those are what the fixture pins; the rest is filled in plausibly so the record is
  never half-initialised. }
function MakeLeaf(const APath, ATypeName: string; AWritable: Boolean): TPropLeaf;
begin
  Result := Default(TPropLeaf);
  Result.Path       := APath;
  Result.TypeName   := ATypeName;
  Result.Kind       := 'scalar';
  Result.IsWritable := AWritable;
  Result.Visibility := 'published';
  Result.MemberKind := 'property';
end;

{ A TProptree standing in for a real `drag-lint proptree` result, so mapping validation
  is testable with no index, no exe and no process spawn. }
function MakeTreeFixture(const ALeaves: TArray<TPropLeaf>): TProptree;
begin
  Result := Default(TProptree);
  Result.Qname    := 'cxButtons.TcxButton';
  Result.RootType := 'cxButtons.TcxButton';
  Result.Leaves   := ALeaves;
end;

{ Parse a rule-book fragment into the flat node array a validator consumes. The nodes
  belong to GParseBook (program lifetime), never to the caller. }
function ParseAll(const ALines: TArray<string>): TArray<TRuleNode>;
var
  I: Integer;
begin
  if GParseBook = nil then
    GParseBook := TRuleBook.Create;
  SetLength(Result, Length(ALines));
  for I := 0 to High(ALines) do
    Result[I] := GParseBook.Add(GParseBook.ParseLine(ALines[I]));
end;

{ Validation is what makes the mapping trustworthy: an unwritable or absent target is a rule
  that will silently do nothing at apply time. Non-exhaustive is a WARNING, not an error --
  leaving a member unmapped is a legitimate choice. }
procedure TestMappingValidation;
var
  Tree: TProptree;
  Nodes: TArray<TRuleNode>;
  Issues: TArray<TMappingIssue>;

  function HasKind(const A: TArray<TMappingIssue>; K: TMappingIssueKind): Boolean;
  var it: TMappingIssue;
  begin
    for it in A do if it.Kind = K then Exit(True);
    Result := False;
  end;
begin
  Tree := MakeTreeFixture([
    MakeLeaf('Default',     'Boolean',      True),
    MakeLeaf('ModalResult', 'TModalResult', True),
    MakeLeaf('Handle',      'HWND',         False)   // read-only
  ]);

  Nodes := ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton',
    '#mapping M #when Style = stOK -> Default = True'
  ]);
  Issues := ValidateMappings(Nodes, Tree, ['stOK'], 'cxButtons.TcxButton');
  Check('validate.clean', Length(Issues) = 0, 'a valid mapping reported issues');

  Nodes := ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton',
    '#mapping M #when Style = stOK -> Nope = True'
  ]);
  Check('validate.missing.target',
    HasKind(ValidateMappings(Nodes, Tree, ['stOK'], 'cxButtons.TcxButton'), mikTargetMissing));

  Nodes := ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton',
    '#mapping M #when Style = stOK -> Handle = 1'
  ]);
  Check('validate.readonly.target',
    HasKind(ValidateMappings(Nodes, Tree, ['stOK'], 'cxButtons.TcxButton'), mikTargetReadOnly));

  // Applying to a class the mapping never declared.
  Nodes := ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton',
    '#mapping M #when Style = stOK -> Default = True'
  ]);
  Check('validate.totype.not.declared',
    HasKind(ValidateMappings(Nodes, Tree, ['stOK'], 'Vcl.StdCtrls.TButton'), mikToTypeNotDeclared));

  // Two members, one #when, no #else -> WARN, and it must NOT be reported as an error kind.
  Nodes := ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton',
    '#mapping M #when Style = stOK -> Default = True'
  ]);
  Issues := ValidateMappings(Nodes, Tree, ['stOK', 'stCancel'], 'cxButtons.TcxButton');
  Check('validate.nonexhaustive.warns', HasKind(Issues, mikNonExhaustive));
  Check('validate.nonexhaustive.not.fatal',
    not HasKind(Issues, mikTargetMissing), 'a gap must not masquerade as a missing target');

  // An #else closes the gap.
  Nodes := ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton',
    '#mapping M #when Style = stOK -> Default = True',
    '#mapping M #else -> ModalResult = mrNone'
  ]);
  Check('validate.else.closes.gap',
    not HasKind(ValidateMappings(Nodes, Tree, ['stOK','stCancel'], 'cxButtons.TcxButton'),
                mikNonExhaustive));

  Check('validate.apply.undefined',
    HasKind(ValidateMappings(ParseAll(['#apply Ghost']), Tree, [], 'cxButtons.TcxButton'),
            mikUndefined));
end;

{ File-level twin of the nested HasKind inside TestMappingValidation. That procedure is
  plan-mandated text and is kept verbatim, so its private helper is not hoisted out of it;
  the tests below get their own. }
function HasIssueKind(const A: TArray<TMappingIssue>; K: TMappingIssueKind): Boolean;
var
  it: TMappingIssue;
begin
  for it in A do
    if it.Kind = K then Exit(True);
  Result := False;
end;

{ mikBadLiteral is the one kind TestMappingValidation never asserts, so without this the
  whole "is this #when value actually a member of the source enum" check could be inverted
  or deleted and the suite would stay green. A #when on a value the enum does not have is a
  clause that can never fire -- dead rule, silently. }
procedure TestMappingBadLiteral;
var
  Tree  : TProptree            ;
  Issues: TArray<TMappingIssue>;
begin
  Tree := MakeTreeFixture([MakeLeaf('Default', 'Boolean', True)]);

  Issues := ValidateMappings(ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton',
    '#mapping M #when Style = stBogus -> Default = True'
  ]), Tree, ['stOK'], 'cxButtons.TcxButton');
  Check('validate.bad.literal', HasIssueKind(Issues, mikBadLiteral),
    'a #when on a non-member fired no mikBadLiteral');

  // A value that IS a member must not be flagged -- the check must discriminate.
  Issues := ValidateMappings(ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton',
    '#mapping M #when Style = stOK -> Default = True'
  ]), Tree, ['stOK'], 'cxButtons.TcxButton');
  Check('validate.good.literal.not.flagged', not HasIssueKind(Issues, mikBadLiteral),
    'a legitimate enum member was reported as a bad literal');

  // Members unknown (empty list) -> the question is unanswerable, so stay silent rather
  // than flag every literal. This is the guard the doc-comment promises.
  Issues := ValidateMappings(ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton',
    '#mapping M #when Style = stBogus -> Default = True'
  ]), Tree, [], 'cxButtons.TcxButton');
  Check('validate.literal.unknown.members.silent', not HasIssueKind(Issues, mikBadLiteral),
    'an unknown member list must not manufacture bad-literal issues');

  // An '#else' has no literal at all and must never be judged against the member list.
  Issues := ValidateMappings(ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton',
    '#mapping M #else -> Default = True'
  ]), Tree, ['stOK'], 'cxButtons.TcxButton');
  Check('validate.else.has.no.literal', not HasIssueKind(Issues, mikBadLiteral),
    'an #else was judged as if it carried an enum literal');
end;

{ The warning/error split must live in ONE place, or Task 7's OK-button gate re-derives it
  and the two copies eventually disagree. The expected table is indexed BY THE ENUM, so
  adding a kind without classifying it fails to COMPILE (E2072) rather than silently
  defaulting to "error". }
procedure TestMappingIssueSeverity;
const
  EXPECTED: array[TMappingIssueKind] of Boolean = (
    False,   // mikUndefined         -- #apply names a mapping that does not exist
    False,   // mikTargetMissing     -- assignment to a property the class has not got
    False,   // mikTargetReadOnly    -- assignment that cannot happen
    False,   // mikBadLiteral        -- clause that can never fire
    False,   // mikToTypeNotDeclared -- applied outside the mapping's declared contract
    True     // mikNonExhaustive     -- the ONLY warning: an unmapped member is a choice
  );
  NAMES: array[TMappingIssueKind] of string = (
    'mikUndefined', 'mikTargetMissing', 'mikTargetReadOnly', 'mikBadLiteral',
    'mikToTypeNotDeclared', 'mikNonExhaustive'
  );
var
  K       : TMappingIssueKind;
  Warnings: Integer          ;
begin
  Warnings := 0;
  for K := Low(TMappingIssueKind) to High(TMappingIssueKind) do
  begin
    Check('severity.' + NAMES[K], MappingIssueIsWarning(K) = EXPECTED[K],
      NAMES[K] + ' is classified as ' +
      (if MappingIssueIsWarning(K) then 'a warning' else 'an error') + ', expected the opposite');
    if MappingIssueIsWarning(K) then Inc(Warnings);
  end;
  // Counted from the ACTUAL classifier, not the table: a classifier that answers False
  // (or True) for everything fails here as well as above.
  Check('severity.exactly.one.warning', Warnings = 1,
    'expected exactly 1 warning kind, got ' + IntToStr(Warnings));
end;

{ BuildMappingNodes hands OWNERSHIP to the caller (unlike ParseAll, whose nodes belong to
  GParseBook), so a test that builds must free. }
procedure FreeNodes(const ANodes: TArray<TRuleNode>);
var
  N: TRuleNode;
begin
  for N in ANodes do N.Free;
end;

{ The fold/unfold pair is what keeps the mapping EDITOR a thin window: one case per enum
  member to show, one node per physical line to store. Anything the fold drops -- a #when
  on a literal the enum has not got, a member with no assignments -- is either a rule the
  author would never see again or a line that should never have been written. }
procedure TestMappingFold;
var
  Nodes  : TArray<TRuleNode>;
  Cases  : TArray<TMappingCase>;
  Built  : TArray<TRuleNode>;
  Emitted: string;
  N      : TRuleNode;

  function CaseFor(const AMember: string): Integer;
  var
    i: Integer;
  begin
    Result := -1;
    for i := 0 to High(Cases) do
      if (not Cases[i].IsElse) and SameText(Cases[i].Member, AMember) then Exit(i);
  end;

begin
  Nodes := ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton, cxButtons.TcxBigButton',
    '#mapping M #when Style = stOK -> Default = True, ModalResult = mrOk',
    '#mapping M #when Style = stGhost -> Cancel = True',
    '#mapping M #else -> ModalResult = mrNone'
  ]);

  Check('fold.names', (Length(MappingNames(Nodes)) = 1) and (MappingNames(Nodes)[0] = 'M'),
    'one mapping is declared here');
  Check('fold.decl.found', MappingDeclaration(Nodes, 'm') <> nil,
    'the name match is case-insensitive, like the rest of the DSL');
  Check('fold.whenfrom', MappingWhenFrom(Nodes, 'M') = 'Style', MappingWhenFrom(Nodes, 'M'));
  Check('fold.whenvalues',
    string.Join(',', MappingWhenValues(Nodes, 'M')) = 'stOK,stGhost',
    string.Join(',', MappingWhenValues(Nodes, 'M')));

  Cases := MappingCasesOf(Nodes, 'M', ['stOK', 'stCancel']);
  // Every index below is guarded IN THE SAME EXPRESSION, because Check reports and
  // returns -- it does not abort. An unguarded Cases[3] after a length check that merely
  // FAILED would take the whole runner down with exit 2 and no summary line, turning one
  // regression into no results at all.
  Check('fold.case.count', Length(Cases) = 4,
    '2 enum members + the off-list stGhost + the #else, got ' + IntToStr(Length(Cases)));
  Check('fold.member.order', (Length(Cases) > 1)
    and (Cases[0].Member = 'stOK') and (Cases[1].Member = 'stCancel'),
    'cases follow the ENUM declaration order, not the file order');
  Check('fold.sets', (Length(Cases) > 0) and (Length(Cases[0].Sets) = 2),
    'stOK maps two targets');
  Check('fold.unmapped.member.empty', (Length(Cases) > 1) and (Length(Cases[1].Sets) = 0),
    'stCancel has no #when, so its case must come back empty');
  Check('fold.offlist.kept', CaseFor('stGhost') = 2,
    'a #when on a value the enum has not got was dropped instead of shown');
  Check('fold.else.last', (Length(Cases) > 0) and Cases[High(Cases)].IsElse,
    'the #else pseudo-member must sit at the END of the member list');
  Check('fold.else.sets',
    (Length(Cases) > 3) and (Length(Cases[3].Sets) = 1)
    and (Cases[3].Sets[0].ToPath = 'ModalResult'),
    'the #else carries its own assignments');
  Check('fold.whenfrom.blank.when.primary',
    (Length(Cases) > 0) and (Cases[0].WhenFrom = ''),
    'a case reading the mapping''s own source property must not pin it, or renaming that '
    + 'property in one field stops working');

  Built := BuildMappingNodes('M', 'X.TStyle',
    ['cxButtons.TcxButton', 'cxButtons.TcxBigButton'], 'Style', Cases);
  try
    Emitted := '';
    for N in Built do Emitted := Emitted + N.Emit + #13#10;
    Check('unfold.count', Length(Built) = 4, IntToStr(Length(Built)) + ': ' + Emitted);
    Check('unfold.decl.first', (Length(Built) > 0) and
      (Built[0].Emit = '#mapping M from X.TStyle to cxButtons.TcxButton, cxButtons.TcxBigButton'),
      Emitted);
    Check('unfold.when',
      Pos('#mapping M #when Style = stOK -> Default = True, ModalResult = mrOk', Emitted) > 0,
      Emitted);
    Check('unfold.skips.unmapped', Pos('stCancel', Emitted) = 0,
      'a member with no assignments must emit no clause at all');
    Check('unfold.else.last', (Length(Built) > 3)
      and (Built[3].Emit = '#mapping M #else -> ModalResult = mrNone'), Emitted);
  finally
    FreeNodes(Built);
  end;

  // No source type -> NO declaration line, and the target classes go with it. MapFromType
  // is the only thing that marks a node as a declaration (IsDeclaration tests exactly
  // that, and Emit branches on it), so a node holding target classes but no source type
  // would be re-read as a CLAUSE and emitted as '#mapping M #when  =  -> ' -- a line the
  // grammar has not got. The guard belongs here, not in whatever UI happens to call this.
  Built := BuildMappingNodes('M', '', nil, 'Style', Cases);
  try
    Check('unfold.no.decl.without.fromtype',
      (Length(Built) = 3) and (Built[0].WhenValue = 'stOK'), IntToStr(Length(Built)));
  finally
    FreeNodes(Built);
  end;

  // ... and target classes ALONE must not conjure one either: that was the shape that
  // emitted the malformed line.
  Built := BuildMappingNodes('M', '', ['cxButtons.TcxButton'], 'Style', Cases);
  try
    Emitted := '';
    for N in Built do Emitted := Emitted + N.Emit + #13#10;
    Check('unfold.totypes.alone.emit.no.decl', Length(Built) = 3,
      IntToStr(Length(Built)) + ': ' + Emitted);
    Check('unfold.no.malformed.when', Pos('#when  =', Emitted) = 0,
      'a target-classes-only node was emitted through the #when branch: ' + Emitted);
  finally
    FreeNodes(Built);
  end;
end;

{ A mapping may test more than one source property -- the model allows a WhenFrom per
  clause, and ConditionalFromPaths already reports a path per clause. Folding on the VALUE
  alone made '#when Style = stOK' and '#when Kind = stOK' collide: one round-tripped line
  reading Style, the second condition destroyed and its assignments silently re-homed onto
  the first. Nothing warned; the file just came back wrong. }
procedure TestMappingDivergentWhenFrom;
var
  Nodes  : TArray<TRuleNode>;
  Cases  : TArray<TMappingCase>;
  Built  : TArray<TRuleNode>;
  Emitted: string;
  N      : TRuleNode;
begin
  Nodes := ParseAll([
    '#mapping D from X.TStyle to C.TBtn',
    '#mapping D #when Style = stOK -> Default = True',
    '#mapping D #when Kind = stOK -> Cancel = True'
  ]);

  Check('divergent.primary', MappingWhenFrom(Nodes, 'D') = 'Style',
    'the FIRST clause names the primary property, got ' + MappingWhenFrom(Nodes, 'D'));

  Cases := MappingCasesOf(Nodes, 'D', ['stOK']);
  // one member case (Style/stOK) + the divergent Kind/stOK + the #else
  Check('divergent.case.count', Length(Cases) = 3,
    'the two clauses collapsed into one case, got ' + IntToStr(Length(Cases)));
  Check('divergent.primary.case.unpinned',
    (Length(Cases) > 0) and (Cases[0].WhenFrom = '') and (Length(Cases[0].Sets) = 1)
    and (Cases[0].Sets[0].ToPath = 'Default'),
    'the primary case must hold ONLY its own clause''s assignments');
  Check('divergent.case.pins.its.property',
    (Length(Cases) > 1) and (Cases[1].Member = 'stOK') and (Cases[1].WhenFrom = 'Kind')
    and (Length(Cases[1].Sets) = 1) and (Cases[1].Sets[0].ToPath = 'Cancel'),
    'the clause on a different source property must keep it, and keep its own sets');

  Built := BuildMappingNodes('D', 'X.TStyle', ['C.TBtn'], 'Style', Cases);
  try
    Emitted := '';
    for N in Built do Emitted := Emitted + N.Emit + #13#10;
    Check('divergent.roundtrip.style',
      Pos('#mapping D #when Style = stOK -> Default = True', Emitted) > 0, Emitted);
    Check('divergent.roundtrip.kind',
      Pos('#mapping D #when Kind = stOK -> Cancel = True', Emitted) > 0,
      'the second condition was lost: ' + Emitted);
    Check('divergent.no.merge', Pos('Default = True, Cancel = True', Emitted) = 0,
      'the two clauses'' assignments were merged onto one line: ' + Emitted);
  finally
    FreeNodes(Built);
  end;

  // The uniform case still follows the caller's AWhenFrom, or renaming the source
  // property in one field would stop reaching the clauses.
  Nodes := ParseAll([
    '#mapping U from X.TStyle to C.TBtn',
    '#mapping U #when Style = stOK -> Default = True'
  ]);
  Cases := MappingCasesOf(Nodes, 'U', ['stOK']);
  Built := BuildMappingNodes('U', 'X.TStyle', ['C.TBtn'], 'Kind', Cases);
  try
    Emitted := '';
    for N in Built do Emitted := Emitted + N.Emit + #13#10;
    Check('uniform.follows.rename',
      Pos('#mapping U #when Kind = stOK -> Default = True', Emitted) > 0, Emitted);
  finally
    FreeNodes(Built);
  end;
end;

{ What the mapping grid, the To pool and Auto-Match have to agree on: a From leaf an
  applied #mapping decides is NOT unassigned, and the targets that mapping sets are NOT
  free. Three call sites, one answer, so they cannot drift apart. }
procedure TestMappingGridHooks;
var
  Book   : TArray<TRuleNode>;
  Blk    : TArray<TRuleNode>;
  Names  : TArray<string>;
  Conds  : TArray<TConditionalFrom>;
  Targets: TArray<string>;
begin
  Book := ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton',
    '#mapping M #when Style = stOK -> Default = True, ModalResult = mrOk',
    '#mapping M #when Style = stCancel -> Cancel = True',
    '#mapping M #else -> ModalResult = mrNone',
    '#convert X.TBtn -> cxButtons.TcxButton',
    '#apply M'
  ]);
  Blk := ParseAll(['#apply M']);

  Names := AppliedMappingNames(Blk);
  Check('applied.names', (Length(Names) = 1) and (Names[0] = 'M'), 'the block applies M');

  Conds := ConditionalFromPaths(Book, Names);
  Check('cond.one.path', Length(Conds) = 1,
    'every clause reads the same From property, so there is ONE conditional leaf, got '
    + IntToStr(Length(Conds)));
  Check('cond.case.count', ConditionalCasesOf(Conds, 'Style') = 3,
    'two #when plus the #else are three branches of the same decision, got '
    + IntToStr(ConditionalCasesOf(Conds, 'Style')));
  Check('cond.case.count.casing', ConditionalCasesOf(Conds, 'STYLE') = 3,
    'path matching is case-insensitive');
  Check('cond.unrelated.leaf', ConditionalCasesOf(Conds, 'Caption') = 0,
    'a leaf no mapping decides must stay freely assignable');
  Check('cond.needs.apply', Length(ConditionalFromPaths(Book, nil)) = 0,
    'a mapping the block does not #apply must not claim that block''s From leaves');

  Targets := MappedTargetPaths(Book, Names);
  Check('targets.count', Length(Targets) = 3, string.Join(',', Targets));
  Check('targets.deduped', CountOf(Targets, 'ModalResult') = 1,
    'ModalResult is set by two clauses, and must be withheld from the pool once');
  Check('targets.needs.apply', Length(MappedTargetPaths(Book, nil)) = 0,
    'an unapplied mapping must not take leaves out of the pool');
end;


begin
  try
    TestBlockSplitRulesRoundTrip;
    TestBlockSplitCastLibRoundTrip;
    TestBlockLabel;
    TestBlockOpsSplitAndCopy;
    TestBlockOpsEnablement;
    TestMergeSkipsDuplicate;
    TestMergeReportsConflict;
    TestMergeAllowsFanOut;
    TestMergeAppendsUnmatchedBlock;
    TestComposePrecedence;
    TestBackupRotation;
    TestBackupFailureAborts;
    TestComposedFileValidates;
    TestMergeOtherLines;
    TestConcatBlocksPure;
    TestMergeConflictOrdinals;
    TestWorkingSetOps;
    TestWorkingSetSyncFromText;
    TestGrammarGuard;
    TestCastLibMergeRefused;
    TestDuplicateHeaders;
    TestScanDfm;
    TestScanDfmSkipRobustness;
    TestScanPasAndMatch;
    TestScanPasEndOfTextSafety;
    TestComputeUsage;
    TestPlatform;
    TestUnitDirectives;
    TestUnitSets;
    TestDeclaringUnit;
    TestEngineSetDbs;
    TestPlatformRescope;
    TestRoundTrip;
    TestParseKinds;
    TestCastGuard;
    TestBlockHelpers;
    TestEditReemit;
    TestCastClassifier;
    TestCastLibParse;
    TestCastLibTolerant;
    TestClassCastFor;
    TestCastLibFile;
    TestClassCastLinkRoundTrip;
    TestUnknownTypeInference;
    TestProptreeParse;
    TestProptreeNoise;
    TestProptree2Fields;
    TestSaveComplete;
    TestPickerDatasource;
    TestFillFromUnit;
    TestProptreeBareClass;
    TestProptree2Live;
    TestThemeModel;
    TestPropCellText;
    TestPlatformDefaults;
    TestEngineTimeoutHeadroom;
    TestProptreeRefsAsLeavesLive;
    TestAcceptanceTcxButtonToPool;
    TestQueryLocationParse;
    TestEnumMembersParse;
    TestGoToDefinitionLive;
    TestMappingRules;
    TestMappingRoundTrip;
    TestMappingWhenWithoutSets;
    TestMappingEmit;
    TestSaveCompleteKeepsApplyOnly;
    TestMappingValidation;
    TestMappingBadLiteral;
    TestMappingIssueSeverity;
    TestMappingFold;
    TestMappingDivergentWhenFrom;
    TestMappingGridHooks;

    FreeAndNil(GParseBook);

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
