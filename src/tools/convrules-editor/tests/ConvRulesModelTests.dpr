program ConvRulesModelTests;

{ Self-contained console test runner for the ConvRules.Model DSL model.
  No DUnitX dependency (keeps the utility lean); prints PASS/FAIL per case and
  exits non-zero on any failure so the build/CI can gate on it. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , System.IOUtils
  , System.Classes
  , System.StrUtils
  , System.Generics.Collections
  , Winapi.Windows
  , ConvRules.Model in '..\ConvRules.Model.pas'  // dl:unit ConvRules.Model accepted -- the tests read BOOK_DEPTH_DEFAULT to pin the model's own default, so the const travels with the unit under test
  , ConvRules.Mappings in '..\ConvRules.Mappings.pas'
  , ConvRules.Units in '..\ConvRules.Units.pas'
  , ConvRules.Casts in '..\ConvRules.Casts.pas'
  , ConvRules.ConvCatalog in '..\ConvRules.ConvCatalog.pas'
  , DRagLint.Convert.CastLib in '..\..\..\report\DRagLint.Convert.CastLib.pas'
  , ConvRules.BlockFile in '..\ConvRules.BlockFile.pas'
  , ConvRules.BlockOps in '..\ConvRules.BlockOps.pas'
  , ConvRules.WorkingSet in '..\ConvRules.WorkingSet.pas'
  , ConvRules.Engine in '..\ConvRules.Engine.pas'
  , ConvRules.Platform in '..\ConvRules.Platform.pas'
  , ConvRules.Theme in '..\ConvRules.Theme.pas'
  , ConvRules.Usage in '..\ConvRules.Usage.pas'
  , ConvRules.FormTypes in '..\ConvRules.FormTypes.pas'
  , ConvRules.RuleCatalog in '..\ConvRules.RuleCatalog.pas'
  , ConvRules.SkipList in '..\ConvRules.SkipList.pas'
  , ConvRules.UnitPick in '..\ConvRules.UnitPick.pas'
  , ConvRules.UsesHarvest in '..\ConvRules.UsesHarvest.pas'
  , ConvRules.UnitStatus in '..\ConvRules.UnitStatus.pas'
  , ConvRules.UnitMask in '..\ConvRules.UnitMask.pas'
  , ConvRules.ConvertRun in '..\ConvRules.ConvertRun.pas'
  , ConvRules.ConvertRunner in '..\ConvRules.ConvertRunner.pas'
  , ConvRules.ValidateScope in '..\ConvRules.ValidateScope.pas'
  , ConvRules.EngineProgress in '..\ConvRules.EngineProgress.pas'  // dl:unit ConvRules.EngineProgress accepted -- the tests read ENGINE_OUTCOME_TIMEOUT / ENGINE_OUTCOME_CANCELLED / PROGRESS_INTERVAL_S to pin the exit-code contract, so the consts travel with the unit under test
  , ConvRules.Inheritance in '..\ConvRules.Inheritance.pas'  // dl:unit ConvRules.Inheritance accepted -- the tests read MAX_CHAIN_DEPTH / OUTSIDE_NO_ANCESTOR / ANALYSIS_CANCELLED / GATE_CANCELLED_TEXT / BINARY_DFM_SIGNATURE to pin the unit's own texts and limits, so the consts travel with the unit under test
  , ConvRules.InheritanceEngine in '..\ConvRules.InheritanceEngine.pas'
  ;

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
end; // procedure

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
    if SameText(S, AName) then
      Exit(True);
  Result:= False;
end;

{ Case-insensitive count of a name in a bare-name array. }
function CountOf(const AArr: TArray<string>; const AName: string): Integer;
var
  S: string;
begin
  Result:= 0;
  for S in AArr do
    if SameText(S, AName) then
      Inc(Result);
end;

{ Round-trip: an untouched file must re-emit byte-faithfully (modulo the canonical
  trailing CRLF the model adds per line). }
procedure TestRoundTrip;
const
  SRC = '#convert Unit.TFrom -> Unit.TTo, Unit'#13#10 + '// a hand comment'#13#10 + '; another comment'#13#10 + '#link Text <- Text'#13#10 +
  '#link Style.Font.Size <- Font.Size : IntToStr'#13#10 + '#default Caption = ''untitled'''#13#10 + '#ignore TabOrder'#13#10 + '#remove SessionName'#13#10 +
  '#remove DFM: Origin'#13#10 + '#unuse BDE.DBTables'#13#10 + '#migrate TTransIsolation -> TFDTxIsolation, FireDAC.Stan.Option'#13#10 + 'ukModify -> arUpdate'#13#10 +
  '#note candidates: Color, Sub.Color'#13#10 + ''#13#10;
var
  Book: TRuleBook;
  Out : string   ;
begin
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(SRC);
    Out:= Book.SaveToString;
    Check('roundtrip.byte-faithful', Out = SRC, Format('got %d bytes, want %d', [Length(Out), Length(SRC)]));
  finally
    Book.Free;
  end;
end;

procedure TestParseKinds;
var
  Book: TRuleBook;
begin
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(
      '#convert A.TFrom -> B.TTo, B'#13#10 + '#link ToP <- FromP'#13#10 + '#link ToC <- FromC : IntToStr'#13#10 + '#default Cap = ''x'''#13#10 + '#ignore Skip'#13#10 +
      '#remove Prop1'#13#10 + '#remove DFM: Prop2'#13#10 + '#unuse SomeUnit'#13#10 + '#note hi'#13#10 + '// c'#13#10 + 'x -> y'#13#10);

    Check('parse.convert.kind', Book.Nodes[0].Kind = rnkConvert);
    Check('parse.convert.from' , Book.Nodes[0].FromType = 'A.TFrom', Book.Nodes[0].FromType);
    Check('parse.convert.to'   , Book.Nodes[0].ToType   = 'B.TTo'  , Book.Nodes[0].ToType  );
    Check('parse.convert.units', Book.Nodes[0].Units    = 'B'      , Book.Nodes[0].Units   );

    Check('parse.link.kind', Book.Nodes[1].Kind = rnkLink);
    Check('parse.link.to'  , Book.Nodes[1].LinkTo   = 'ToP'  , Book.Nodes[1].LinkTo  );
    Check('parse.link.from', Book.Nodes[1].LinkFrom = 'FromP', Book.Nodes[1].LinkFrom);
    Check('parse.link.nocast', Book.Nodes[1].Cast = '', '[' + Book.Nodes[1].Cast + ']');

    Check('parse.link.cast'     , Book.Nodes[2].Cast     = 'IntToStr', Book.Nodes[2].Cast    );
    Check('parse.link.cast.from', Book.Nodes[2].LinkFrom = 'FromC'   , Book.Nodes[2].LinkFrom);

    Check('parse.default.to'   , Book.Nodes[3].DefTo    = 'Cap'  , Book.Nodes[3].DefTo   );
    Check('parse.default.value', Book.Nodes[3].DefValue = '''x''', Book.Nodes[3].DefValue);

    Check('parse.ignore', Book.Nodes[4].IgnorePath = 'Skip', Book.Nodes[4].IgnorePath);

    Check('parse.remove.plain', (Book.Nodes[5].Kind = rnkRemove) and not Book.Nodes[5].RemoveDfmOnly and (Book.Nodes[5].RemoveProp = 'Prop1'));
    Check('parse.remove.dfm', (Book.Nodes[6].Kind = rnkRemove) and Book.Nodes[6].RemoveDfmOnly and (Book.Nodes[6].RemoveProp = 'Prop2'), Book.Nodes[6].RemoveProp);

    Check('parse.unuse', Book.Nodes[7].UnuseUnit = 'SomeUnit', Book.Nodes[7].UnuseUnit);
    Check('parse.note' , Book.Nodes[8].NoteText  = 'hi'      , Book.Nodes[8].NoteText );
    Check('parse.comment', Book.Nodes[9 ].Kind = rnkComment);
    Check('parse.pcre'   , Book.Nodes[10].Kind = rnkPcre   );
  finally
    Book.Free;
  end; // try
end; // procedure

{ A ':' that is NOT a valid cast tail (has a space / dot) must stay in FromPath. }
procedure TestCastGuard;
var
  Book: TRuleBook;
begin
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(
      '#link ToP <- From.Path'#13#10 + // dotted path, no cast
      '#link ToP <- FromP : Not A Cast'#13#10); // tail has spaces -> not a cast
    Check('cast.guard.dotted.nocast', Book.Nodes[0].Cast = '', '[' + Book.Nodes[0].Cast + ']');
    Check('cast.guard.dotted.from', Book.Nodes[0].LinkFrom = 'From.Path', Book.Nodes[0].LinkFrom);
    Check('cast.guard.spaces.nocast', Book.Nodes[1].Cast = '', '[' + Book.Nodes[1].Cast + ']');
  finally
    Book.Free;
  end;
end; // procedure

procedure TestBlockHelpers;
var
  Book  : TRuleBook        ;
  Heads : TArray<Integer>  ;
  Links : TArray<TRuleNode>;
begin
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString( '#convert A -> B'#13#10 + '#link a <- a'#13#10 + '#link b <- b'#13#10 + '#convert C -> D'#13#10 + '#link c <- c'#13#10);
    Heads:= Book.ConvertHeaders;
    Check('block.headers.count', Length(Heads) = 2, IntToStr(Length(Heads)));
    Links:= Book.LinksForBlock(Heads[0]);
    Check('block.links.first', Length(Links) = 2, IntToStr(Length(Links)));
    Links:= Book.LinksForBlock(Heads[1]);
    Check('block.links.second', Length(Links) = 1, IntToStr(Length(Links)));
  finally
    Book.Free;
  end; // try
end; // procedure

{ Editing a typed field marks the node Dirty and re-emits from fields. }
procedure TestEditReemit;
var
  Book: TRuleBook;
begin
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString('#link ToP <- ???'#13#10);
    Book.Nodes[0].LinkFrom:= 'RealSource';
    Book.Nodes[0].Cast    := 'IntToStr';
    Book.Nodes[0].Dirty   := True;
    Check('edit.reemit', Book.Nodes[0].Emit = '#link ToP <- RealSource : IntToStr', Book.Nodes[0].Emit);
  finally
    Book.Free;
  end;
end; // procedure

procedure TestCastClassifier;
begin
  // identity: same family -> no casts, but IsCastable true
  Check('cast.same.int', ValidCasts('Integer', 'Int64') = [], 'expected identity');
  Check('cast.same.castable', IsCastable('Integer', 'Int64' ));
  Check('cast.same.family'  , SameFamily('Double' , 'Single'));

  // numeric -> string
  Check('cast.int2str'  , ValidCasts('Integer', 'string') = [cfIntToStr  ]);
  Check('cast.float2str', ValidCasts('Double' , 'string') = [cfFloatToStr]);

  // string -> numeric (two options each)
  Check('cast.str2int'  , ValidCasts('string', 'Integer') = [cfStrToInt  , cfStrToIntDef  ]);
  Check('cast.str2float', ValidCasts('string', 'Double' ) = [cfStrToFloat, cfStrToFloatDef]);

  // widening / narrowing
  Check('cast.int2float', ValidCasts('Integer', 'Double') = [cfIntToFloat]);
  Check('cast.float2int', ValidCasts('Double', 'Integer') = [cfTrunc, cfRound]);

  // bool -> string
  Check('cast.bool2str', ValidCasts('Boolean', 'string') = [cfBoolToStr]);

  // SAME class/enum type is an identity link -> ALWAYS castable, no cast needed
  Check('cast.sameclass.castable', IsCastable('TFont', 'TFont'));
  Check('cast.sameclass.nocast', ValidCasts('TFont', 'TFont') = []);
  Check('cast.sameenum.castable', IsCastable('TAlignment', 'TAlignment'));
  Check('cast.sameclass.ci'     , IsCastable('tfont'     , 'TFont'     )); // case-insensitive

  // DIFFERENT incompatible types -> blocked
  Check('cast.enum.blocked' , not IsCastable('TAlignment', 'TColor'  ));
  Check('cast.class.blocked', not IsCastable('TFont'     , 'TStrings'));

  // name round-trip
  Check('cast.name.int2str', CastFnName(cfIntToStr) = 'IntToStr', CastFnName(cfIntToStr));
  Check('cast.name.parse'  , CastFnFromName('round') = cfRound);
  Check('cast.name.unknown', CastFnFromName('Bogus') = cfNone );
end; // procedure

{ Unknown-type inference: a property inherited from an unresolved parent comes back
  type='unknown' (e.g. TcxButton.Align). When the same-named From property HAS a
  type, adopt it for both -> the pair becomes an identity link, not blocked. }
procedure TestUnknownTypeInference;
var
  f: string;
  t: string;
begin
  Check('unknown.detect.word' , IsUnknownType('unknown'));
  Check('unknown.detect.empty', IsUnknownType(''       ));
  Check('unknown.detect.ci'   , IsUnknownType('Unknown'));
  Check('unknown.detect.real', not IsUnknownType('TAlign'));

  // To side unknown (the real TabcToggleBtn.Align -> TcxButton.Align case).
  f:= 'TAlign'; t:= 'unknown';
  ResolveUnknownTypes(f, t);
  Check('unknown.infer.to', (f = 'TAlign') and (t = 'TAlign'), Format('[%s/%s]', [f, t]));
  Check('unknown.infer.to.castable', IsCastable(f, t)); // identity now

  // From side unknown (symmetric).
  f:= ''; t:= 'TColor';
  ResolveUnknownTypes(f, t);
  Check('unknown.infer.from', (f = 'TColor') and (t = 'TColor'), Format('[%s/%s]', [f, t]));

  // Both unknown -> ResolveUnknownTypes can't infer (leaves both as-is), but the
  // pair is still same-named-same-unresolved-parent, so IsCastable's identical-name
  // rule treats it as an identity link. That is the intended, useful outcome: two
  // same-named properties both inherited from an unresolved parent are the same
  // member (both Align from TControl), so the link is allowed.
  f:= 'unknown'; t:= 'unknown';
  ResolveUnknownTypes(f, t);
  Check('unknown.both.unresolved', IsUnknownType(f) and IsUnknownType(t));
  Check('unknown.both.identity', IsCastable('unknown', 'unknown'));

  // Known-but-different types are NOT touched (no false identity).
  f:= 'TAlign'; t:= 'TColor';
  ResolveUnknownTypes(f, t);
  Check('unknown.known.untouched', (f = 'TAlign') and (t = 'TColor'));
end; // procedure

{ Parse a real captured proptree/1 JSON fixture (schema stability + leaf fields). }
procedure TestProptreeParse;
var
  FixturePath: string   ;
  Json       : string   ;
  Tree       : TProptree;
  Found      : Boolean  ;
  L          : TPropLeaf;
begin
  FixturePath:= TPath.Combine(ExtractFilePath(ParamStr(0)), 'fixtures\proptree-tfont.json');
  if not TFile.Exists(FixturePath) then
    // fixture lives next to the .dpr when run from the tests dir
    FixturePath:= 'fixtures\proptree-tfont.json';
  if not TFile.Exists(FixturePath) then
  begin
    Check('proptree.fixture.present', False, 'fixture not found: ' + FixturePath);
    Exit;
  end;
  Json:= TFile.ReadAllText(FixturePath);
  Tree:= ParseProptreeJson(Json);
  Check('proptree.roottype', Tree.RootType = 'TFont', Tree.RootType);
  Check('proptree.hasleaves', Length(Tree.Leaves) > 0, IntToStr(Length(Tree.Leaves)));
  // every leaf has a path + a declared_in
  Found:= True;
  for L in Tree.Leaves do
    if (L.Path = '') or (L.DeclaredIn = '') then
      Found:= False;
  Check('proptree.leaves.wellformed', Found);
  // a known scalar leaf: PixelsPerInch : Integer
  Found:= False;
  for L in Tree.Leaves do
    if (L.Path = 'PixelsPerInch') and (L.TypeName = 'Integer') then
      Found:= True;
  Check('proptree.leaf.pixelsperinch', Found);
end; // procedure

{ The real bug: drag-lint appends a "(loaded defaults ...)" line AFTER the JSON.
  The parser must tolerate preamble/trailing noise by slicing the JSON object. }
procedure TestProptreeNoise;
const
  NOISY = '{'#13#10 + '  "schema": "proptree/1",'#13#10 + '  "root_type": "TFoo",'#13#10 + '  "properties": ['#13#10 +
  '    { "path": "Size", "type": "Integer", "declared_in": "U.TFoo",'#13#10 + '      "kind": "scalar", "is_class_typed": false }'#13#10 + '  ]'#13#10 + '}'#13#10 +
  '(loaded defaults from C:\Projects\.drag-lint.json)'#13#10;
var
  Tree: TProptree;
begin
  Tree:= ParseProptreeJson(NOISY);
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
  J2 = '{'#13#10 + '  "schema": "proptree/2",'#13#10 + '  "root_type": "TFoo",'#13#10 + '  "properties": ['#13#10 +
  '    { "path": "Caption", "type": "string", "declared_in": "U.TFoo", "kind": "scalar",'#13#10 +
  '      "is_class_typed": false, "is_writable": true, "visibility": "published", "member_kind": "property" },'#13#10 +
  '    { "path": "Handle", "type": "HWND", "declared_in": "U.TFoo", "kind": "scalar",'#13#10 +
  '      "is_class_typed": false, "is_writable": false, "visibility": "public", "member_kind": "property" },'#13#10 +
  '    { "path": "FBuf", "type": "TBytes", "declared_in": "U.TFoo", "kind": "scalar",'#13#10 +
  '      "is_class_typed": false, "is_writable": true, "visibility": "public", "member_kind": "field" },'#13#10 +
  '    { "path": "Legacy", "type": "Integer", "declared_in": "U.TFoo", "kind": "scalar",'#13#10 + '      "is_class_typed": false }'#13#10 + '  ]'#13#10 + '}'#13#10;
var
  Tree: TProptree;

  function LeafOf(const P: string): TPropLeaf;
  var
    x: TPropLeaf;
  begin
    Result:= Default(TPropLeaf);
    for x in Tree.Leaves do
      if SameText(x.Path, P) then
        Exit(x);
  end;

begin
  Tree:= ParseProptreeJson(J2);
  Check('proptree2.count', Length(Tree.Leaves) = 4, IntToStr(Length(Tree.Leaves)));
  Check('proptree2.caption.writable', LeafOf('Caption').IsWritable);
  Check('proptree2.caption.vis', LeafOf('Caption').Visibility = 'published', LeafOf('Caption').Visibility);
  Check('proptree2.handle.readonly', not LeafOf('Handle').IsWritable);
  Check('proptree2.field.kind', LeafOf('FBuf').MemberKind = 'field', LeafOf('FBuf').MemberKind);
  Check('proptree2.field.writable', LeafOf('FBuf').IsWritable);
  // proptree/1 back-compat: the field-less "Legacy" leaf gets safe defaults.
  Check('proptree2.compat.writable', LeafOf('Legacy').IsWritable);
  Check('proptree2.compat.kind', LeafOf('Legacy').MemberKind = 'property', LeafOf('Legacy').MemberKind);
  Check('proptree2.compat.vis', LeafOf('Legacy').Visibility = '', '[' + LeafOf('Legacy').Visibility + ']');
end; // begin

{ Save must DROP #convert blocks with no #link (empty rules), keep complete ones
  and any leading non-block content. }
procedure TestSaveComplete;
var
  Book   : TRuleBook;
  dropped: Integer  ;
  outp   : string   ;
begin
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(
      '// header comment'#13#10 + '#convert A.TFrom -> B.TTo'#13#10 + // complete: has a link
      '#link X <- Y'#13#10 + '#convert C.TFoo -> D.TBar'#13#10 + // EMPTY: no link -> dropped
      '#note nothing mapped yet'#13#10 + '#convert E.TA -> F.TB'#13#10 + // complete
      '#link P <- Q'#13#10);
    outp:= Book.SaveCompleteToString(dropped);
    Check('savecomplete.dropcount', dropped = 1, IntToStr(dropped));
    Check('savecomplete.keeps.comment', Pos('// header comment'        , outp) > 0);
    Check('savecomplete.keeps.first'  , Pos('#convert A.TFrom -> B.TTo', outp) > 0);
    Check('savecomplete.drops.empty', Pos('C.TFoo', outp) = 0, 'empty rule leaked');
    Check('savecomplete.keeps.last', Pos('#convert E.TA -> F.TB', outp) > 0);
  finally
    Book.Free;
  end; // try
end; // procedure

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
  LibWin32 = 'C:\Projects\.drag-lint\library-Win32.sqlite';
  LibWin64 = 'C:\Projects\.drag-lint\library-Win64.sqlite';
  { ORM3's CLIENT project index. It is per-PROJECT and lives in that project's own
    _D-RAG folder: the union DB this used to name (DB\ORM3\drag-lint.sqlite) was
    DELETED in the 2026-08-11 one-DB-per-project migration. A --db that does not
    exist makes the engine exit 2, so every call carrying it fails; resolve with
    `drag-lint resolve-dbs --in <file.pas>` rather than guessing a path. }
  ProjectDb = 'C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite';

const
  /// <summary>Environment variable naming the engine the live tests run, when no
  /// drag-lint.exe sits beside the runner.</summary>
  TEST_ENGINE_ENV = 'CONVRULES_TEST_ENGINE';

/// <summary>The engine the live tests run, chosen EXPLICITLY.</summary>
/// <param name="ARunnerDir">The test runner's folder.</param>
/// <param name="AEnvExe">The value of CONVRULES_TEST_ENGINE ('' when unset).</param>
/// <param name="AWhy">Why the answer is '' (empty otherwise).</param>
/// <returns>ARunnerDir\drag-lint.exe when it exists, else AEnvExe when it names an
/// existing file, else ''. Never third_party\dll-win64 by default: that folder is the
/// live engine the engine stream rebuilds without warning.</returns>
function ChooseTestEngine(const ARunnerDir, AEnvExe: string; out AWhy: string): string;
begin
  AWhy:= '';
  Result:= TPath.Combine(ARunnerDir, 'drag-lint.exe');
  if TFile.Exists(Result) then
    Exit;
  if AEnvExe <> '' then
  begin
    if TFile.Exists(AEnvExe) then
      Exit(AEnvExe);
    AWhy:= Format('%s names %s, which does not exist', [TEST_ENGINE_ENV, AEnvExe]);
    Exit('');
  end;
  AWhy:= Format('no drag-lint.exe beside the runner (%s) and %s is not set -- copy a ' + 'pinned engine beside the runner or name one; live tests SKIP', [ARunnerDir, TEST_ENGINE_ENV]);
  Result:= '';
end; // function
var
  GEngineWhy: string = '';

{ The engine every live test runs (ChooseTestEngine on this runner's folder and
  CONVRULES_TEST_ENGINE). '' when none was named; GEngineWhy then says why. }
function ResolveExe: string;
begin
  Result:= ChooseTestEngine(ExtractFilePath(ParamStr(0)), GetEnvironmentVariable(TEST_ENGINE_ENV), GEngineWhy);
end; // function
{ True if the ORM3 project DB answers a units query -- i.e. it exists AND is at or above
  the exe's own SCHEMA_VERSION. The gate is `>=`, so a NEWER DB is fine; only an OLDER one
  is refused ("index schema vN < vM ... migrate", 0 rows), in which case ORM3-dependent
  live tests SKIP (environment not ready) rather than FAIL, matching the absent-DB policy.

  SAY THE SCHEMA GENERICALLY, NEVER A HARDCODED VERSION. These messages said "pre-v17"
  from the v17 era until 2026-09-15, by which point the engine wanted v22 and ORM3 sat at
  v21. The skip then reported a version pair that had not been current for months, and a
  session debugging it lost time to a message that named the wrong schema with complete
  confidence. The engine prints the real pair; this text must not compete with it. }
function Orm3Queryable(const AExe: string): Boolean;
var
  Adapter: TEngineAdapter;
  Units  : TArray<string>;
  Err    : string        ;
begin
  Result:= False;
  if (AExe = '') or not TFile.Exists(ProjectDb) then
    Exit;
  Adapter:= TEngineAdapter.Create(AExe, [ProjectDb]);
  try
    Result:= Adapter.ListProjectUnits(Units, Err) and (Length(Units) > 0);
  finally
    Adapter.Free;
  end;
end; // function

procedure TestPickerDatasource;
var
  Exe    : string        ;
  Adapter: TEngineAdapter;
  FromSet: TArray<string>;
  ToSet  : TArray<string>;
  Units  : TArray<string>;
  Err    : string        ;
  OK     : Boolean       ;
begin
  Exe:= ResolveExe;
  if Exe = '' then
  begin
    Skip('picker.datasource', 'drag-lint.exe not found');
    Exit;
  end;

  // --- FROM picker: what FCbFrom would hold ---
  // Editor: ListDescendantsOf('TComponent', GEditorFromDbs=[Win32,Win64,proj]).
  if not (TFile.Exists(LibWin32) and TFile.Exists(LibWin64) and TFile.Exists(ProjectDb)) then
    Skip('picker.from.datasource', 'library-Win32/Win64 or ORM3 project db absent')
  else
  begin
    Adapter:= TEngineAdapter.Create(Exe, [LibWin32, LibWin64, ProjectDb]);
    try
      OK:= Adapter.ListDescendantsOf('TComponent', [LibWin32, LibWin64, ProjectDb], FromSet, Err);
      Check('picker.from.query.ok', OK, Err);
      Check('picker.from.nonempty', Length(FromSet) > 100, Format('only %d classes', [Length(FromSet)]));
      // The three the user reported missing -- assert they SURVIVE the exe's
      // parse+dedupe and reach the combo's Items.
      Check('picker.from.has.TOvcTable', Contains(FromSet, 'TOvcTable'), 'Orpheus TOvcTable not in FROM datasource');
      Check('picker.from.has.TTable'   , Contains(FromSet, 'TTable'   ), 'BDE TTable not in FROM datasource'       );
      // Sanity anchors: a plain VCL control + a DevExpress control.
      Check('picker.from.has.TEdit'  , Contains(FromSet, 'TEdit'  ));
      Check('picker.from.has.TcxGrid', Contains(FromSet, 'TcxGrid'));
    finally
      Adapter.Free;
    end; // try
  end; // else

  // --- TO picker: what FCbTo would hold ---
  // Editor: ListDescendantsOf('TControl', GEditorToDbs=[Win64,proj]).
  if not (TFile.Exists(LibWin64) and TFile.Exists(ProjectDb)) then
    Skip('picker.to.datasource', 'library-Win64 or ORM3 project db absent')
  else
  begin
    Adapter:= TEngineAdapter.Create(Exe, [LibWin64, ProjectDb]);
    try
      OK:= Adapter.ListDescendantsOf('TControl', [LibWin64, ProjectDb], ToSet, Err);
      Check('picker.to.query.ok', OK, Err);
      Check('picker.to.has.TcxGrid', Contains(ToSet, 'TcxGrid'));
      // TTable is non-visual (TComponent, not TControl) -> must NOT be a TO option.
      Check('picker.to.excludes.TTable', not Contains(ToSet, 'TTable'), 'non-visual TTable leaked into the TO (target control) datasource');
    finally
      Adapter.Free;
    end;
  end; // else

  // --- From-Unit picker: what FCbUnit would hold ---
  // Editor: ListProjectUnits over the adapter's DBs (project DB carries units).
  if (not TFile.Exists(ProjectDb)) or (not Orm3Queryable(Exe)) then
    Skip('picker.unit.datasource', 'ORM3 project db absent or below the exe schema (re-index)')
  else
  begin
    Adapter:= TEngineAdapter.Create(Exe, [ProjectDb]);
    try
      OK:= Adapter.ListProjectUnits(Units, Err);
      Check('picker.unit.query.ok', OK, Err);
      Check('picker.unit.nonempty', Length(Units) > 100, Format('only %d units', [Length(Units)]));
      Check('picker.unit.has.VARINSP', Contains(Units, 'VARINSP'), 'VARINSP not in From-Unit datasource (reindex CLIENT\VARINSP.PAS)');
    finally
      Adapter.Free;
    end;
  end; // else
end; // procedure

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
  Exe    : string        ;
  Adapter: TEngineAdapter;
  Types  : TArray<string>;
  Err    : string        ;
  OK     : Boolean       ;
begin
  Exe:= ResolveExe;
  if (Exe = '') or (not TFile.Exists(ProjectDb))
     or (not TFile.Exists('C:\Projects\DB\ORM3\CLIENT\VARINSP.DFM'))
     or (not Orm3Queryable(Exe)) then
  begin
    Skip('fill.from-unit.varinsp', 'exe / ORM3 db / VARINSP.DFM absent, or ORM3 below the exe schema');
    Exit;
  end;
  // The editor passes the FROM db set (both libs + project) as the control set
  // source; ListControlTypesInUnit resolves the unit's file via the adapter DBs.
  Adapter:= TEngineAdapter.Create(Exe, [LibWin32, LibWin64, ProjectDb]);
  try
    OK:= Adapter.ListControlTypesInUnit('VARINSP', [], Types, Err);
    Check('fill.from-unit.ok', OK, Err);
    // The button was silent because this came back empty. It must not.
    Check('fill.from-unit.nonempty', Length(Types) > 10, Format('VARINSP returned only %d types (expected its form components)', [Length(Types)]));
    // Concrete components the user can see in the VARINSP form / DFM.
    Check('fill.from-unit.has.TOvcController', Contains(Types, 'TOvcController'));
    Check('fill.from-unit.has.TPanel'        , Contains(Types, 'TPanel'        ));
    Check('fill.from-unit.has.TOvcTable'     , Contains(Types, 'TOvcTable'     ));
  finally
    Adapter.Free;
  end; // try
end; // procedure

{ ---------------------------------------------------------------------------
  Bare class name -> proptree. The pickers hand GetProptree a BARE class name
  (TabcToggleBtn, TcxButton), but `proptree --qname` needs a UNIT-QUALIFIED name
  (Abcbtn.TabcToggleBtn). The bug: GetProptree passed the bare name straight
  through -> "class not found" (which exits 0) -> empty tree -> the editor showed
  "<Class> is not indexed (no properties found)". After the fix GetProptree
  auto-qualifies a bare, unique class name. Skipped when the exe/libs are absent. }
procedure TestProptreeBareClass;
var
  Exe    : string        ;
  Adapter: TEngineAdapter;
  Tree   : TProptree     ;
  Err    : string        ;
  Note   : string        ;
  OK     : Boolean       ;
begin
  Exe:= ResolveExe;
  if (Exe = '') or (not TFile.Exists(LibWin64)) or (not TFile.Exists(ProjectDb)) then
  begin
    Skip('proptree.bareclass', 'exe / library-Win64 / ORM3 project db absent');
    Exit;
  end;
  Adapter:= TEngineAdapter.Create(Exe, [LibWin32, LibWin64, ProjectDb]);
  try
    // TabcToggleBtn is Abcbtn.TabcToggleBtn -- the exact class the user picked.
    OK:= Adapter.GetProptree('TabcToggleBtn', Tree, Err, Note);
    Check('proptree.bareclass.ok', OK, Err);
    Check('proptree.bareclass.nonempty', Length(Tree.Leaves) > 0, Format('TabcToggleBtn resolved to %d leaves (bug: bare name not qualified)', [Length(Tree.Leaves)]));
    // An already-qualified name must still work (no double-qualify regression).
    OK:= Adapter.GetProptree('Abcbtn.TabcToggleBtn', Tree, Err, Note);
    Check('proptree.qualified.still.ok', OK and (Length(Tree.Leaves) > 0), Err);
  finally
    Adapter.Free;
  end; // try
end; // procedure

{ Live proptree/2: GetProptree at the published surface returns a BOUNDED tree whose
  leaves the parser populated with member_kind, and (published => no fields). Uses
  TcxButton (the user's real target -- fast; other controls can explode without the
  engine's --refs-as-leaves). Skipped when the exe / library-Win64 db is absent. }
procedure TestProptree2Live;
var
  Exe      : string        ;
  Adapter  : TEngineAdapter;
  Tree     : TProptree     ;
  Err      : string        ;
  Note     : string        ;
  OK       : Boolean       ;
  sawField : Boolean       ;
  allKinded: Boolean       ;
  L        : TPropLeaf     ;
begin
  Exe:= ResolveExe;
  if (Exe = '') or (not TFile.Exists(LibWin64)) then
  begin
    Skip('proptree2.live', 'exe / library-Win64 db absent');
    Exit;
  end;
  Adapter:= TEngineAdapter.Create(Exe, [LibWin32, LibWin64, ProjectDb]);
  try
    OK:= Adapter.GetProptree('TcxButton', Tree, Err, Note, 'published');
    if not OK or (Length(Tree.Leaves) = 0) then
    begin
      Skip('proptree2.live', 'TcxButton not resolved at published surface (pre-proptree/2 exe?): ' + Err);
      Exit;
    end;
    // Bounded -- a pathological (refs-expanding) tree would be many thousands of leaves.
    Check('proptree2.live.bounded', Length(Tree.Leaves) < 2000, Format('%d leaves (unbounded? engine --refs-as-leaves missing)', [Length(Tree.Leaves)]));
    // The parser populated member_kind on every leaf...
    allKinded:= True;
    for L in Tree.Leaves do
      if L.MemberKind = '' then
        allKinded:= False;
    Check('proptree2.live.memberkind', allKinded, 'a leaf had empty member_kind');
    // ...and the published surface carries no field members.
    sawField:= False;
    for L in Tree.Leaves do
      if SameText(L.MemberKind, 'field') then
        sawField:= True;
    Check('proptree2.live.nofields', not sawField, 'published surface leaked a field member');
  finally
    Adapter.Free;
  end; // try
end; // procedure

procedure TestPlatform;
const
  LibDir = 'C:\Lib\';
var
  d32  : TArray<string>;
  d64  : TArray<string>;
  dboth: TArray<string>;
begin
  // ParsePlatform: case-insensitive, default fallback.
  Check('platform.parse.win32'           , ParsePlatform('Win32', cpBoth ) = cpWin32);
  Check('platform.parse.win64'           , ParsePlatform('WIN64', cpBoth ) = cpWin64);
  Check('platform.parse.both'            , ParsePlatform('both' , cpWin32) = cpBoth );
  Check('platform.parse.empty->default'  , ParsePlatform(''     , cpWin64) = cpWin64);
  Check('platform.parse.unknown->default', ParsePlatform('arm'  , cpWin32) = cpWin32);

  // PlatformToStr round-trips the tokens.
  Check('platform.tostr.win32', PlatformToStr(cpWin32) = 'win32');
  Check('platform.tostr.win64', PlatformToStr(cpWin64) = 'win64');
  Check('platform.tostr.both' , PlatformToStr(cpBoth ) = 'both' );

  // LibDbsFor: one lib for a single platform, both for cpBoth (Win32 first).
  d32:= LibDbsFor(cpWin32, LibDir);
  Check('platform.libdbs.win32.count', Length(d32) = 1);
  Check('platform.libdbs.win32.path', d32[0] = 'C:\Lib\library-Win32.sqlite');
  d64:= LibDbsFor(cpWin64, LibDir);
  Check('platform.libdbs.win64.path', (Length(d64) = 1) and (d64[0] = 'C:\Lib\library-Win64.sqlite'));
  dboth:= LibDbsFor(cpBoth, LibDir);
  Check('platform.libdbs.both.count', Length(dboth) = 2);
  Check('platform.libdbs.both.order', (dboth[0] = 'C:\Lib\library-Win32.sqlite') and (dboth[1] = 'C:\Lib\library-Win64.sqlite'));
end; // procedure

procedure TestEngineSetDbs;
var
  eng: TEngineAdapter;
begin
  eng:= TEngineAdapter.Create('drag-lint.exe', ['a.sqlite']);
  try
    Check('engine.dblist.initial', (Length(eng.DbList) = 1) and (eng.DbList[0] = 'a.sqlite'));
    eng.SetDbs(['x.sqlite', 'y.sqlite']);
    Check('engine.setdbs.count', Length(eng.DbList) = 2);
    Check('engine.setdbs.values', (eng.DbList[0] = 'x.sqlite') and (eng.DbList[1] = 'y.sqlite'));
  finally
    eng.Free;
  end;
end; // procedure

{ Platform selection actually re-scopes the FROM picker: TOvcTable (Orpheus) is
  indexed under Win64 only, so a Win64-only FROM DB set lists it and a Win32-only
  set does not -- driven through the exact ListDescendantsOf path the pickers use.
  Skipped (not failed) when the exe or the library DBs are absent. }
procedure TestPlatformRescope;
const
  LibDir = 'C:\Projects\.drag-lint\';
  { ORM3's CLIENT project index. It is per-PROJECT and lives in that project's own
    _D-RAG folder: the union DB this used to name (DB\ORM3\drag-lint.sqlite) was
    DELETED in the 2026-08-11 one-DB-per-project migration. A --db that does not
    exist makes the engine exit 2, so every call carrying it fails; resolve with
    `drag-lint resolve-dbs --in <file.pas>` rather than guessing a path. }
  ProjectDb = 'C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite';
var
  Exe      : string        ;
  eng      : TEngineAdapter;
  win64Only: TArray<string>;
  win32Only: TArray<string>;
  Err      : string        ;
  ok64     : Boolean       ;
  ok32     : Boolean       ;
begin
  Exe:= ResolveExe;
  if (Exe = '') or (not TFile.Exists(LibDir + 'library-Win64.sqlite'))
     or (not TFile.Exists(LibDir + 'library-Win32.sqlite'))
     or (not TFile.Exists(ProjectDb)) then
  begin
    Skip('platform.rescope', 'exe, library DBs or ORM3 project db absent');
    Exit;
  end;
  eng:= TEngineAdapter.Create(Exe, LibDbsFor(cpBoth, LibDir) + [ProjectDb]);
  try
    ok64:= eng.ListDescendantsOf('TComponent', LibDbsFor(cpWin64, LibDir) + [ProjectDb], win64Only, Err);
    ok32:= eng.ListDescendantsOf('TComponent', LibDbsFor(cpWin32, LibDir) + [ProjectDb], win32Only, Err);
    Check('platform.rescope.win64.query.ok', ok64, Err);
    Check('platform.rescope.win32.query.ok', ok32, Err);
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
  end; // try
end; // procedure

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
  d       : TArray<string>;
  S       : string        ;
  sawWin32: Boolean       ;
  sawWin64: Boolean       ;
begin
  Check('platform.default.from.win64', DEFAULT_FROM_PLATFORM = cpWin64, 'FROM default is ' + PlatformToStr(DEFAULT_FROM_PLATFORM) + ' -- must not union the library-Win32 fragment');
  Check('platform.default.to.win64', DEFAULT_TO_PLATFORM = cpWin64, 'TO default is ' + PlatformToStr(DEFAULT_TO_PLATFORM));

  // The DEFAULT FROM db set must not name the fragment at all.
  d:= LibDbsFor(DEFAULT_FROM_PLATFORM, LibDir);
  sawWin32:= False; sawWin64:= False;
  for S in d do
  begin
    if Pos('library-Win32', S) > 0 then
      sawWin32:= True;
    if Pos('library-Win64', S) > 0 then
      sawWin64:= True;
  end;
  Check('platform.default.from.excludes.win32.fragment', not sawWin32, 'the default FROM db set still lists library-Win32.sqlite');
  Check('platform.default.from.includes.win64', sawWin64, 'the default FROM db set does not list library-Win64.sqlite');

  // cpBoth is still reachable: the ABILITY to union deliberately was not removed.
  Check('platform.both.still.parses', ParsePlatform('both', cpWin64) = cpBoth);
  Check('platform.both.still.unions', Length(LibDbsFor(cpBoth, LibDir)) = 2);

  // The platform combos set ItemIndex := Ord(<platform>) over items (Win32,Win64,
  // Both) and read it back as TConvPlatform(ItemIndex). Changing a default only
  // stays consistent while that round-trip holds for the value chosen.
  Check(
    'platform.default.from.itemindex.inrange', (Ord(DEFAULT_FROM_PLATFORM) >= Ord(cpWin32)) and (Ord(DEFAULT_FROM_PLATFORM) <= Ord(cpBoth)),
    Format('Ord=%d', [Ord(DEFAULT_FROM_PLATFORM)]));
  Check('platform.default.from.itemindex.roundtrips', TConvPlatform(Ord(DEFAULT_FROM_PLATFORM)) = DEFAULT_FROM_PLATFORM);
  Check('platform.default.to.itemindex.roundtrips'  , TConvPlatform(Ord(DEFAULT_TO_PLATFORM  )) = DEFAULT_TO_PLATFORM  );
end; // procedure

{ The engine watchdog must sit ABOVE the slowest call the editor can issue, not
  inside it. At 30000 ms it was below legitimate work on two paths: ValidateText
  (convert-validate) measured 29.83 s -- essentially ON the bound -- and the
  pre-fix proptree call measured 20.11 s warm here and 74-79 s on a colder index.
  Pure: asserts the constant, because the failure mode is a value chosen too small.
  The floor is 3x the slowest measured live call, not the value itself, so tuning
  180000 up or down stays free while a return to 30000 does not. }
procedure TestEngineTimeoutHeadroom;
begin
  Check(
    'engine.timeout.above.slowest.recorded.call', ENGINE_TIMEOUT_MS >= 90000,
    Format('ENGINE_TIMEOUT_MS=%d ms; the slowest call the editor issues measured ' + '29.83 s (convert-validate) and a pre-fix proptree call took 74-79 s on a ' + 'cold index, so a watchdog at or below that fires on legitimate work', [ENGINE_TIMEOUT_MS])
  );
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
{ A HARD engine failure during class-name resolution must be REPORTED, not swallowed.

  ResolveClassQName calls QueryJsonFor and discards its error: `if not QueryJsonFor(...)
  then Exit;` returns the BARE name unchanged. That treats "zero hits" (exit 1) and
  "the engine could not run" (exit 2, e.g. a --db that does not exist) as the same
  outcome. The bare name then reaches proptree, which -- unlike query -- tolerates a
  nonexistent --db and answers from the rest, so it runs happily and reports
  "class not found: <Type>".

  That is how a DEAD DB PATH surfaced as a message about the CLASS. It cost a whole
  debugging session on 2026-09-09: 12 tests failed naming picker/proptree/class,
  and the actual cause was one stale constant naming an index deleted in August.

  The assertion is not "it fails" -- it already failed. It is that the message names
  the CAUSE. Uses a deliberately absent DB alongside a good one, which is exactly the
  shape that misled us: query refuses the list outright while proptree accepts it. }
{ A unit to convert need not be a MEMBER of the project. The From Unit box accepts
  an absolute path to a loose .pas/.dfm pair, and ListControlTypesInUnit has to read
  that .dfm directly.

  Why this needs its own test: ResolveUnitFile answers by asking the index
  (`query --name`), and a project DB holds only that project's members -- so a
  browsed file resolves to NOTHING. The failure is silent and reads as a property of
  the FORM rather than of the lookup: ListControlTypesInUnit returns True with zero
  types, and the UI reports "No form components found", which is exactly what a
  genuinely empty form looks like. }
{ The conversion catalog: "what can this property become?".

  Every pre-existing cast API answers the PAIR question (is From->To allowed),
  because every existing caller already knew both ends. The user picking a From
  property knows only one, so the catalog is the only thing that can populate a
  list of targets. These cases pin the three sources it merges. }
procedure TestConvCatalog;
var
  Defs : TArray<TCastDef>;
  Enums: TArray<TEnumDef>;
  Opts : TArray<TConvOption>;

  function Find(const ATo: string; out AOpt: TConvOption): Boolean;
  var
    o: TConvOption;
  begin
    for o in Opts do
      if SameText(o.ToType, ATo) then
      begin
        AOpt := o;
        Exit(True);
      end;
    AOpt := Default(TConvOption);
    Result := False;
  end;

var
  Opt: TConvOption;
begin
  // The real shipped library, built inline so the test does not depend on a file.
  SetLength(Defs, 1);
  Defs[0].Name        := 'AssignGraphic';
  Defs[0].Accepts     := ['TPicture', 'TBitmap', 'TGraphic'];
  Defs[0].Yields      := ['TdxSmartGlyph'];
  Defs[0].PasTemplate := '{dst}.Assign({src});';

  SetLength(Enums, 1);
  Enums[0].Name     := 'ButtonLayout';
  Enums[0].FromType := 'Vcl.Buttons.TButtonLayout';
  Enums[0].ToType   := 'dxCore.TdxButtonLayout';

  // 1. An unresolved type cannot be reasoned about -> no options, not a guess.
  Opts := ConversionsFor('', Defs, Enums);
  Check('convcat.empty.type', Length(Opts) = 0, IntToStr(Length(Opts)));
  Opts := ConversionsFor('unknown', Defs, Enums);
  Check('convcat.unknown.type', Length(Opts) = 0, IntToStr(Length(Opts)));

  // 2. A class with no library cast still offers itself: TFont <- TFont is a
  //    legal identity #link, and the pool must not look empty for it.
  // The two follow-up assertions FOLD IN the Find, deliberately. Default(TConvOption)
  // has Kind = ckIdentity (ordinal 0) and CastName = '' -- exactly what identity
  // expects -- so `Find(...); Check(Opt.Kind = ckIdentity)` PASSES when nothing was
  // found at all. Measured: both passed against the empty stub. An assertion that
  // cannot fail is worse than no assertion.
  Opts := ConversionsFor('TFont', Defs, Enums);
  Check('convcat.identity.present', Find('TFont', Opt), 'identity missing');
  Check('convcat.identity.kind', Find('TFont', Opt) and (Opt.Kind = ckIdentity),
    ConvKindLabel(Opt.Kind));
  Check('convcat.identity.nocast', Find('TFont', Opt) and (Opt.CastName = ''),
    Opt.CastName);

  // 3. Scalars come from ConvRules.Casts, and only the ones that REALLY exist.
  Opts := ConversionsFor('Integer', Defs, Enums);
  Check('convcat.int.to.string', Find('string', Opt), 'Integer->string missing');
  Check('convcat.int.to.string.kind', Opt.Kind = ckScalar, ConvKindLabel(Opt.Kind));
  Check('convcat.int.to.double', Find('Double', Opt), 'Integer->Double missing');

  // Boolean converts to string ONLY. Listing Integer/Byte here would be an
  // aspiration: the user could pick a target the engine cannot honour.
  Opts := ConversionsFor('Boolean', Defs, Enums);
  Check('convcat.bool.to.string', Find('string', Opt), 'Boolean->string missing');
  Check('convcat.bool.no.integer', not Find('Integer', Opt),
    'Boolean->Integer is not a real cast and must not be offered');

  // 4. The class cast the owner needs, from BOTH accepted source types.
  Opts := ConversionsFor('TPicture', Defs, Enums);
  Check('convcat.picture.glyph', Find('TdxSmartGlyph', Opt), 'TPicture->TdxSmartGlyph missing');
  Check('convcat.picture.kind', Opt.Kind = ckClass, ConvKindLabel(Opt.Kind));
  Check('convcat.picture.castname', Opt.CastName = 'AssignGraphic', Opt.CastName);
  Check('convcat.picture.detail', Pos('Assign', Opt.Detail) > 0, Opt.Detail);

  Opts := ConversionsFor('TBitmap', Defs, Enums);
  Check('convcat.bitmap.glyph', Find('TdxSmartGlyph', Opt), 'TBitmap->TdxSmartGlyph missing');
  Check('convcat.bitmap.castname', Opt.CastName = 'AssignGraphic', Opt.CastName);

  // 5. Enum casts are matched on the DECLARED from-type of the enum block.
  Opts := ConversionsFor('Vcl.Buttons.TButtonLayout', Defs, Enums);
  Check('convcat.enum.present', Find('dxCore.TdxButtonLayout', Opt), 'enum target missing');
  Check('convcat.enum.kind', Opt.Kind = ckEnum, ConvKindLabel(Opt.Kind));
  Check('convcat.enum.castname', Opt.CastName = 'ButtonLayout', Opt.CastName);

  // 6. The rendered row is what the UI list shows.
  Opts := ConversionsFor('TPicture', Defs, Enums);
  Find('TdxSmartGlyph', Opt);
  Check('convcat.text.hastype', Pos('TdxSmartGlyph', ConvOptionText(Opt)) > 0, ConvOptionText(Opt));
  Check('convcat.text.hascast', Pos('AssignGraphic', ConvOptionText(Opt)) > 0, ConvOptionText(Opt));
end;

procedure TestControlTypesFromNonProjectUnit;
var
  Exe    : string        ;
  Dir    : string        ;
  Pas    : string        ;
  Dfm    : string        ;
  Adapter: TEngineAdapter;
  Types  : TArray<string>;
  Err    : string        ;
  OK     : Boolean       ;
  Found  : Boolean       ;
begin
  Exe:= ResolveExe;
  if Exe = '' then
  begin
    Skip('browseunit.types', 'engine exe absent');
    Exit;
  end;

  Dir:= TPath.Combine(TPath.GetTempPath, 'convrules_browseunit_test');
  TDirectory.CreateDirectory(Dir);
  Pas:= TPath.Combine(Dir, 'LooseUnit.pas');
  Dfm:= TPath.Combine(Dir, 'LooseUnit.dfm');
  try
    TFile.WriteAllText(Pas, 'unit LooseUnit;'#13#10 + 'interface'#13#10 + 'implementation'#13#10 + 'end.'#13#10);
    TFile.WriteAllText(
      Dfm, 'object LooseForm: TLooseForm'#13#10 + '  object Grid1: TOvcTable'#13#10 + '  end'#13#10 + '  object Btn1: TabcToggleBtn'#13#10 + '  end'#13#10 + 'end'#13#10);

    // No --db at all: the point is that this path must NOT need the index.
    Adapter:= TEngineAdapter.Create(Exe, []);
    try
      OK:= Adapter.ListControlTypesInUnit(Pas, nil, Types, Err);
      Check('browseunit.types.ok', OK, 'reading a loose unit must not error: ' + Err);
      // THREE, not two: the ROOT `object LooseForm: TLooseForm` is itself an
      // `object <Name>: <TType>` line, so the form's own class is in the list
      // alongside the two components. That is the documented contract -- every
      // DFM object -- and the pre-existing VARINSP test relies on it too. Pinned
      // here because a first draft of this test asserted 2 and failed against
      // CORRECT code.
      Check('browseunit.types.count', Length(Types) = 3, Format('expected 3 DFM object types (root form + 2 components), got %d', [Length(Types)]));
      Found:= False;
      for var t in Types do
        if SameText(t, 'TOvcTable') then
          Found:= True;
      Check('browseunit.types.names', Found, 'the .dfm component classes must come back for a NON-project unit');
      Found:= False;
      for var t in Types do
        if SameText(t, 'TabcToggleBtn') then
          Found:= True;
      Check('browseunit.types.names.second', Found, 'every component class must come back, not just the first');
    finally
      Adapter.Free;
    end; // try
  finally
    if TFile.Exists(Pas) then
      TFile.Delete(Pas);
    if TFile.Exists(Dfm) then
      TFile.Delete(Dfm);
  end; // try
end; // procedure

procedure TestResolveHardFailureIsReported;
var
  Exe    : string        ;
  Adapter: TEngineAdapter;
  Tree   : TProptree     ;
  Err    : string        ;
  Note   : string        ;
  OK     : Boolean       ;
const
  AbsentDb = 'C:\Projects\NO_SUCH_DB_convrules_resolve_test.sqlite';
begin
  Exe:= ResolveExe;
  if (Exe = '') or (not TFile.Exists(LibWin64)) then
  begin
    Skip('resolve.harderror', 'exe / library-Win64 db absent');
    Exit;
  end;
  if TFile.Exists(AbsentDb) then
  begin
    Skip('resolve.harderror', 'the deliberately-absent db path exists');
    Exit;
  end;
  Adapter:= TEngineAdapter.Create(Exe, [LibWin64, AbsentDb]);
  try
    OK:= Adapter.GetProptree('TabcToggleBtn', Tree, Err, Note);
    Check('resolve.harderror.fails', not OK, 'a broken --db list must not succeed');
    // The whole point: the message must not blame the class for a config fault.
    Check('resolve.harderror.not.classnotfound', Pos('class not found', Err) = 0, 'misleading -- blames the class for a dead --db: ' + Err);
    Check('resolve.harderror.names.cause', Pos('exit 2', Err) > 0, 'error must name the failing engine call: ' + Err);
  finally
    Adapter.Free;
  end;
end; // procedure

procedure TestProptreeRefsAsLeavesLive;
var
  Exe      : string        ;
  Adapter  : TEngineAdapter;
  Tree     : TProptree     ;
  Err      : string        ;
  Note     : string        ;
  L        : TPropLeaf     ;
  nUnder   : Integer       ;
  nNested  : Integer       ;
  sawAction: Boolean       ;
begin
  Exe:= ResolveExe;
  if (Exe = '') or (not TFile.Exists(LibWin64)) then
  begin
    Skip('proptree.refsasleaves', 'exe / library-Win64 db absent');
    Exit;
  end;
  Adapter:= TEngineAdapter.Create(Exe, LibDbsFor(DEFAULT_FROM_PLATFORM, 'C:\Projects\.drag-lint\') + [ProjectDb]);
  try
    if not Adapter.GetProptree('cxButtons.TcxButton', Tree, Err, Note, 'published')
       or (Length(Tree.Leaves) = 0) then
    begin
      Skip('proptree.refsasleaves', 'TcxButton did not resolve: ' + Err);
      Exit;
    end;
    nUnder:= 0; nNested:= 0; sawAction:= False;
    for L in Tree.Leaves do
    begin
      if SameText(L.Path, 'Action') then
        sawAction:= True;
      if L.Path.StartsWith('Action.', True) then
        Inc(nUnder);
      if Pos('.', L.Path) > 0 then
        Inc(nNested);
    end;
    Check('proptree.refsasleaves.reference.is.a.leaf', sawAction, 'no bare "Action" leaf -- expected the reference itself to be emitted');
    Check('proptree.refsasleaves.not.recursed', nUnder = 0, Format('%d "Action.*" paths -- --refs-as-leaves is not being passed', [nUnder]));
    Check(
      'proptree.refsasleaves.owned.still.expanded', nNested > 0,
      'no dotted paths at all -- owned sub-objects were flattened away too ' + '(--depth 1 would do this, and it is not an acceptable substitute)');
  finally
    Adapter.Free;
  end; // try
end; // procedure

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
  Exe      : string        ;
  Adapter  : TEngineAdapter;
  Note     : string        ;
  ToTree   : TProptree     ;
  FromTree : TProptree     ;
  Err      : string        ;
  i        : Integer       ;
  L        : TPropLeaf     ;
  inPool   : Boolean       ;
  ToType   : string        ;
  FromType : string        ;
begin
  Exe:= ResolveExe;
  if (Exe = '') or (not TFile.Exists(LibWin64)) then
  begin
    Skip('acceptance.tcxbutton', 'exe / library-Win64 db absent');
    Exit;
  end;
  Adapter:= TEngineAdapter.Create(Exe, LibDbsFor(DEFAULT_FROM_PLATFORM, 'C:\Projects\.drag-lint\') + [ProjectDb]);
  try
    if not Adapter.GetProptree('cxButtons.TcxButton', ToTree, Err, Note, 'published')
       or (Length(ToTree.Leaves) = 0) then
    begin
      Skip('acceptance.tcxbutton', 'TcxButton did not resolve: ' + Err);
      Exit;
    end;
    if not Adapter.GetProptree('Vcl.StdCtrls.TButton', FromTree, Err, Note, 'published')
       or (Length(FromTree.Leaves) = 0) then
    begin
      Skip('acceptance.tcxbutton', 'TButton (FROM counterpart) did not resolve: ' + Err);
      Exit;
    end;
    for i:= Low(Wanted) to High(Wanted) do
    begin
      // (1) present in the To tree AND writable => RefreshPool puts it in the pool.
      inPool:= False; ToType:= '';
      for L in ToTree.Leaves do
        if SameText(L.Path, Wanted[i]) then
        begin
          ToType:= L.TypeName;
          inPool:= L.IsWritable;
          Break;
        end;
      Check(
        'acceptance.tcxbutton.pool.' + Wanted[i], inPool,
        Format('%s is absent from the TcxButton published surface, or is read-only, ' + 'so the To pool cannot offer it', [Wanted[i]]));
      Check(
        'acceptance.tcxbutton.type.known.' + Wanted[i], not IsUnknownType(ToType),
        Format('%s has type "%s" -- an unresolved ancestry loses the type and blocks ' + 'every cast decision', [Wanted[i], ToType]));

      // (2) assignable from the plausible FROM counterpart, via the editor's gate.
      FromType:= '';
      for L in FromTree.Leaves do
        if SameText(L.Path, Wanted[i]) then begin FromType:= L.TypeName; Break; end;
      Check('acceptance.tcxbutton.from.has.' + Wanted[i], FromType <> '', Format('TButton.%s not found -- cannot judge assignability', [Wanted[i]]));
      Check(
        'acceptance.tcxbutton.assignable.' + Wanted[i], (FromType <> '') and IsCastable(FromType, ToType),
        Format('TButton.%s (%s) -> TcxButton.%s (%s) rejected by IsCastable', [Wanted[i], FromType, Wanted[i], ToType]));
    end; // for
  finally
    Adapter.Free;
  end; // try
end; // procedure

{ PropCellText single-sources the 'Path : Type' cell rendering used by the grid's
  From column, the grid's To column and the To pool. The To column showed a BARE
  path until 2026-07-30, so a To leaf's type was invisible exactly where the
  assignment decision is made. These pin the contract the three call sites share,
  including the separator that PathOfGridCell/TypeOfCell split back on. }
procedure TestPropCellText;
var
  S: string ;
  P: Integer;
begin
  Check('propcell.path.and.type', PropCellText('Left', 'Integer') = 'Left : Integer', PropCellText('Left', 'Integer'));
  Check('propcell.dotted.path.kept', PropCellText('Colors.Button.Text', 'TColor') = 'Colors.Button.Text : TColor', PropCellText('Colors.Button.Text', 'TColor'));

  // A blank type must NOT leave a dangling ' : ' -- an unresolved ancestor yields
  // an empty type, and 'Left : ' would read as a type named nothing.
  Check('propcell.blank.type.no.separator', PropCellText('Left', '') = 'Left', PropCellText('Left', ''));
  Check('propcell.whitespace.type.no.separator', PropCellText('Left', '   ') = 'Left', '[' + PropCellText('Left', '   ') + ']');

  // The separator must survive the split the readers perform (PathOfGridCell /
  // TypeOfCell live in the form unit and split on this exact ' : ').
  S:= PropCellText('Tag', 'NativeInt');
  P:= Pos         (' : ', S          );
  Check('propcell.separator.roundtrips.path', (P > 0) and (Copy(S, 1, P - 1) = 'Tag'), S);
  Check('propcell.separator.roundtrips.type', (P > 0) and (Copy(S, P + 3, Length(S)) = 'NativeInt'), S);

  // A path that already contains a colon must not be re-split by the readers at
  // the wrong place: the FIRST ' : ' is the separator.
  Check('propcell.first.separator.wins', Pos(' : ', PropCellText('A', 'B')) = 2, PropCellText('A', 'B'));
end; // procedure

{ Pure theme model. The IDE stores its theme at HKCU\Software\Embarcadero\BDS\<ver>\
  Theme, value 'Theme' (observed: 'Dark'). Only 'Dark' means dark; every other value,
  including absent/garbage, means light -- a wrong guess here makes the editor unreadable,
  so the default is the safe one. ExamineRowColor derives the used-row marking from the
  ACTIVE window colour, because the old hard-coded $00D8F5D8 is invisible on a dark style. }
procedure TestThemeModel;
begin
  Check('theme.ide.dark'   , IdeThemeToMode('Dark' ) = tmDark , 'Dark'            );
  Check('theme.ide.dark.ci', IdeThemeToMode('dArK' ) = tmDark , 'case-insensitive');
  Check('theme.ide.light'  , IdeThemeToMode('Light') = tmLight, 'Light'           );
  Check('theme.ide.gray'   , IdeThemeToMode('Gray' ) = tmLight, 'Gray is not dark');
  Check('theme.ide.empty'  , IdeThemeToMode(''     ) = tmLight, 'absent -> light' );
  Check('theme.ide.garbage', IdeThemeToMode('Zzz'  ) = tmLight, 'unknown -> light');

  // An explicit preference must WIN over whatever the IDE says.
  Check('theme.pref.light.wins'  , ResolveThemeMode(tpLight    , 'Dark' ) = tmLight);
  Check('theme.pref.dark.wins'   , ResolveThemeMode(tpDark     , 'Light') = tmDark );
  Check('theme.pref.follow'      , ResolveThemeMode(tpFollowIde, 'Dark' ) = tmDark );
  Check('theme.pref.follow.light', ResolveThemeMode(tpFollowIde, 'Light') = tmLight);

  // The marking must DIFFER from the background it sits on, in both modes -- that is
  // the whole contract. Equality here means an invisible highlight.
  Check('theme.examine.light.differs', ExamineRowColor($00FFFFFF, tmLight) <> $00FFFFFF);
  Check('theme.examine.dark.differs' , ExamineRowColor($00202020, tmDark ) <> $00202020);
  Check('theme.examine.modes.differ', ExamineRowColor($00FFFFFF, tmLight) <> ExamineRowColor($00FFFFFF, tmDark), 'light and dark must not produce the same marking');
  Check('theme.examine.light.exact', ExamineRowColor($00FFFFFF, tmLight) = $00D8FFD8, IntToHex(ExamineRowColor($00FFFFFF, tmLight), 6));

  Check('theme.pref.roundtrip.follow', StrToThemePref(ThemePrefToStr(tpFollowIde), tpLight) = tpFollowIde);
  Check('theme.pref.roundtrip.dark'  , StrToThemePref(ThemePrefToStr(tpDark     ), tpLight) = tpDark     );
  Check('theme.pref.unknown.default', StrToThemePref('nonsense', tpFollowIde) = tpFollowIde);
end; // procedure

procedure TestUnitDirectives;
const
  SRC = '#use imcFOLDERS'#13#10 + '#useswap FOLDERDEF -> imcFOLDERS'#13#10 + '#useswap ovcTable -> cxGrid, cxGridDBTableView'#13#10;
var
  Book : TRuleBook        ;
  Units: TArray<TRuleNode>;
begin
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(SRC);
    Check('unit.use.kind', Book.Nodes[0].Kind = rnkUse);
    Check('unit.use.unit', Book.Nodes[0].UseUnit = 'imcFOLDERS', Book.Nodes[0].UseUnit);
    Check('unit.swap.kind', Book.Nodes[1].Kind = rnkUseSwap);
    Check('unit.swap.old', Book.Nodes[1].SwapOld = 'FOLDERDEF', Book.Nodes[1].SwapOld);
    Check('unit.swap.new1', (Length(Book.Nodes[1].SwapNew) = 1) and (Book.Nodes[1].SwapNew[0] = 'imcFOLDERS'));
    Check('unit.swap.multi',(Length(Book.Nodes[2].SwapNew) = 2) and (Book.Nodes[2].SwapNew[0] = 'cxGrid') and (Book.Nodes[2].SwapNew[1] = 'cxGridDBTableView'));
    Check('unit.roundtrip', Book.SaveToString = SRC, Format('got %d want %d', [Length(Book.SaveToString), Length(SRC)]));
    Units:= Book.UnitNodes;
    Check('unit.gather.count', Length(Units) = 3, IntToStr(Length(Units)));
  finally
    Book.Free;
  end; // try
end; // procedure

procedure TestUnitSets;
var
  Book : TRuleBook         ;
  S    : TUnitSets         ;
  Pairs: TArray<TConvPair> ;
begin
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString( '#convert A.TFrom -> B.TTo, cxButtons'#13#10 + '#use cxButtons'#13#10 + '#useswap FOLDERDEF -> imcFOLDERS'#13#10 + '#unuse cxButtons'#13#10);
    S:= NormalizeUnitSets(Book);
    Check('norm.add.has.cxButtons' , Contains(S.Adds, 'cxButtons' ));
    Check('norm.add.has.imcFOLDERS', Contains(S.Adds, 'imcFOLDERS'));
    Check('norm.add.dedup', CountOf(S.Adds, 'cxButtons') = 1, IntToStr(CountOf(S.Adds, 'cxButtons')));
    Check('norm.remove.has.FOLDERDEF', Contains(S.Removes, 'FOLDERDEF'));
    Check('norm.conflict.addwins', Contains(S.Conflicts, 'cxButtons') and not Contains(S.Removes, 'cxButtons'));
  finally
    Book.Free;
  end; // try

  SetLength(Pairs, 1);
  Pairs[0].FromType:= 'Abcbtn.TabcToggleBtn';
  Pairs[0].ToType  := 'cxButtons.TcxButton';
  S:= DeriveUnits(
    Pairs,
    function(const ATypeName: string): string begin if ATypeName.StartsWith('cxButtons') then Exit('cxButtons'); if ATypeName.StartsWith('Abcbtn') then Exit('Abcbtn'); Result:= ''; end
  );
  Check('derive.add'   , Contains(S.Adds   , 'cxButtons'));
  Check('derive.remove', Contains(S.Removes, 'Abcbtn'   ));
end; // procedure

{ MissingUnitNodes: what auto-derive inserts is only what the book does not
  already say, so a replacement made twice adds its unit rules once. }
procedure TestMissingUnitNodes;
var
  Book: TRuleBook;
  S   : TUnitSets;
  M   : TUnitSets;
begin
  S:= Default(TUnitSets);
  S.Adds   := ['CXEDIT', 'cxGrid'];
  S.Removes:= ['ovcef', 'OvcBase'];
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString('#use cxEdit'#13#10 + '#unuse Ovcef'#13#10);
    M:= MissingUnitNodes(Book, S);
    Check('units.missing.adds.skip.present', string.Join(',', M.Adds) = 'cxGrid', string.Join(',', M.Adds));
    Check('units.missing.removes.skip.present', string.Join(',', M.Removes) = 'OvcBase', string.Join(',', M.Removes));
  finally
    Book.Free;
  end; // try
  // Positive control: with nothing in the book, nothing is filtered out.
  Book:= TRuleBook.Create;
  try
    M:= MissingUnitNodes(Book, S);
    Check('units.missing.empty.book.keeps.all', (Length(M.Adds) = 2) and (Length(M.Removes) = 2), Format('%d/%d', [Length(M.Adds), Length(M.Removes)]));
  finally
    Book.Free;
  end; // try
end; // procedure

{ ConvRules.UnitPick: the unit picker's two filters. The form unit is outside
  this runner's closure, so every rule it applies is pinned here. }
procedure TestUnitPickFilter;
var
  All: TArray<string>;
  F  : TUnitFilter   ;
  R  : TArray<string>;
begin
  All:= ['cxGrid', 'cxEdit', 'dxBar', 'System.SysUtils', 'Vcl.Forms', 'CXLIB'];
  F:= Default(TUnitFilter);
  R:= FilterUnits(All, F);
  Check('unitpick.filter.empty.keeps.all', Length(R) = Length(All), IntToStr(Length(R)));

  F.NameText:= 'GRID';
  R:= FilterUnits(All, F);
  Check('unitpick.filter.name.substring.nocase', string.Join(',', R) = 'cxGrid', string.Join(',', R));

  F.NameText:= '';
  F.Search  := 'cx*';
  F.Mode    := usmWildcard;
  R:= FilterUnits(All, F);
  Check('unitpick.filter.wildcard', string.Join(',', R) = 'cxGrid,cxEdit,CXLIB', string.Join(',', R));

  F.NameText:= 'edit';
  R:= FilterUnits(All, F);
  Check('unitpick.filter.name.and.search', string.Join(',', R) = 'cxEdit', string.Join(',', R));

  // A mask is a whole-name match, like a file mask: 'Grid' alone matches nothing.
  F.NameText:= '';
  F.Search  := 'Grid';
  R:= FilterUnits(All, F);
  Check('unitpick.filter.wildcard.wholename', Length(R) = 0, string.Join(',', R));

  F.Search:= '^(dx|vcl)';
  F.Mode  := usmRegex;
  R:= FilterUnits(All, F);
  Check('unitpick.filter.regex.nocase', string.Join(',', R) = 'dxBar,Vcl.Forms', string.Join(',', R));
  Check('unitpick.search.regex.valid', IsValidUnitSearch(F.Search, usmRegex));

  F.Search:= '([';
  Check('unitpick.search.regex.invalid', not IsValidUnitSearch(F.Search, usmRegex));
  R:= FilterUnits(All, F);
  Check('unitpick.filter.regex.invalid.ignored', Length(R) = Length(All), IntToStr(Length(R)));

  F.Search:= '[cx';
  F.Mode  := usmWildcard;
  Check('unitpick.search.wildcard.invalid', not IsValidUnitSearch(F.Search, usmWildcard));
  R:= FilterUnits(All, F);
  Check('unitpick.filter.wildcard.invalid.ignored', Length(R) = Length(All), IntToStr(Length(R)));
  Check('unitpick.search.empty.valid', IsValidUnitSearch('', usmRegex) and IsValidUnitSearch('', usmWildcard));
end; // procedure

{ ConvRules.UnitPick.AddPickedUnit: the replacement picker's accumulator. A
  double-click adds, with no confirmation, so the list itself must refuse the
  noise -- blanks, repeats, and the old unit named as its own replacement. }
procedure TestUnitPickMulti;
var
  R: TArray<string>;
begin
  R:= AddPickedUnit(nil, '  Vcl.Forms ', 'Forms');
  Check('unitpick.multi.add.trims', string.Join(',', R) = 'Vcl.Forms', string.Join(',', R));
  R:= AddPickedUnit(R, 'Vcl.Controls', 'Forms');
  Check('unitpick.multi.add.keeps.order', string.Join(',', R) = 'Vcl.Forms,Vcl.Controls', string.Join(',', R));
  R:= AddPickedUnit(R, 'VCL.FORMS', 'Forms');
  Check('unitpick.multi.add.dedupe.nocase', string.Join(',', R) = 'Vcl.Forms,Vcl.Controls', string.Join(',', R));
  R:= AddPickedUnit(R, '   ', 'Forms');
  Check('unitpick.multi.add.blank.ignored', Length(R) = 2, IntToStr(Length(R)));
  // The reported defect: the replacement must never become (or equal) the old unit.
  R:= AddPickedUnit(R, 'forms', 'Forms');
  Check('unitpick.multi.add.old.refused', string.Join(',', R) = 'Vcl.Forms,Vcl.Controls', string.Join(',', R));
  // Positive control: with no old unit to exclude, the same name is accepted.
  R:= AddPickedUnit(nil, 'Forms', '');
  Check('unitpick.multi.add.no.exclude', string.Join(',', R) = 'Forms', string.Join(',', R));
end; // procedure

{ TRuleBook.Snapshot is the unsaved-changes baseline (Task 3's guard): equal
  snapshots = nothing Save would change. Dirty is NOT that signal -- it is a
  per-node re-emit flag, never cleared by Save and blind to deletions. }
procedure TestBookSnapshot;
const
  SRC     = '#useswap OldA -> NewA' + sLineBreak + '#unuse OldB' + sLineBreak;
  SRC_DEL = '#useswap OldA -> NewA' + sLineBreak;
  SRC_ADD = SRC + '#use NewC' + sLineBreak;
var
  Book : TRuleBook;
  Other: TRuleBook;
  Base : string;
begin
  Book := TRuleBook.Create;
  Other:= TRuleBook.Create;
  try
    Book.LoadFromString(SRC);
    Base:= Book.Snapshot;
    Check('book.snapshot.stable', Book.Snapshot = Base, Base);
    Check('book.snapshot.nonempty', Pos('#unuse OldB', Base) > 0, Base);

    Other.LoadFromString(SRC_DEL);
    Check('book.snapshot.delete.differs', Other.Snapshot <> Base, Other.Snapshot);

    Other.LoadFromString(SRC_ADD);
    Check('book.snapshot.add.differs', Other.Snapshot <> Base, Other.Snapshot);

    // Edit in place: the same book, one node changed and marked for re-emit.
    Book.UnitNodes[0].SwapNew:= ['NewA', 'NewD'];
    Book.UnitNodes[0].Dirty  := True;
    Check('book.snapshot.edit.differs', Book.Snapshot <> Base, Book.Snapshot);
  finally
    Other.Free;
    Book.Free;
  end; // try
end; // procedure

{ ConvRules.ConvertRun -- every decision the Convert tab makes before or after
  an engine call. The tab and the runner only execute what these return. }
procedure TestConvertRun;
var
  Existing: TArray<string>;
  Probe   : TFileProbe;
  Books   : TArray<TBookEntry>;
  Pre     : TPreflight;
  Row     : TApplyRow;
  Errs    : TArray<string>;
  Dir     : string;
  Srcs    : TArray<string>;
  Lock    : TFileStream;
  Raised  : string;
const
  BOOK_COUNT = 3; // convert-only, units-only, mixed
  JSON_EDITS = 3; // edits_count in the first apply/1 document
begin
  // --- SharedBackupPaths: one above the highest existing N; gaps not reused ---
  Existing:= [];
  Probe:= function(const APath: string): Boolean
    begin
      Result:= MatchText(APath, Existing);
    end;
  Srcs:= SharedBackupPaths(['x\A.pas'], Probe);
  Check('convertrun.bck.first', string.Join(',', Srcs) = 'x\A.pas.BCK1', string.Join(',', Srcs));
  Existing:= ['x\A.pas.BCK1', 'x\A.pas.BCK3'];
  Srcs:= SharedBackupPaths(['x\A.pas'], Probe);
  Check('convertrun.bck.above.highest', string.Join(',', Srcs) = 'x\A.pas.BCK4', string.Join(',', Srcs));
  // Another unit's backups never count.
  Srcs:= SharedBackupPaths(['x\B.pas', 'x\B.dfm'], Probe);
  Check('convertrun.bck.per.file', string.Join(',', Srcs) = 'x\B.pas.BCK1,x\B.dfm.BCK1', string.Join(',', Srcs));
  // One N per UNIT: its .pas and .dfm restore points pair up by number.
  Existing:= ['x\X.pas.BCK1', 'x\X.dfm.BCK3'];
  Srcs:= SharedBackupPaths(['x\X.pas', 'x\X.dfm'], Probe);
  Check('convertrun.bck.shared.n', string.Join(',', Srcs) = 'x\X.pas.BCK4,x\X.dfm.BCK4', string.Join(',', Srcs));

  // --- BookKindOfText ---
  Check('convertrun.kind.empty'   , BookKindOfText('// only a comment') = bkEmpty);
  Check('convertrun.kind.convert' , BookKindOfText('#convert A.TX -> B.TY, B' + sLineBreak + '#link P <- P') = bkConvertOnly);
  Check('convertrun.kind.units'   , BookKindOfText('#useswap Forms -> Vcl.Forms') = bkUnitsOnly);
  Check('convertrun.kind.mixed'   , BookKindOfText('#unuse Bde.DBTables' + sLineBreak + '#convert A.TX -> B.TY, B' + sLineBreak + '#link P <- P') = bkMixed);

  // --- MoveEntry: order is application order ---
  SetLength(Books, BOOK_COUNT);
  Books[0].Path:= 'a';
  Books[1].Path:= 'b';
  Books[2].Path:= 'c';
  Books:= MoveEntry(Books, 2, -1);
  Check('convertrun.move.up', (Books[1].Path = 'c') and (Books[2].Path = 'b'), Books[0].Path + Books[1].Path + Books[2].Path);
  Books:= MoveEntry(Books, 0, -1);
  Check('convertrun.move.clamped', Books[0].Path = 'a', Books[0].Path);

  // --- Preflight ---
  SetLength(Books, BOOK_COUNT);
  Books[0].Path:= 'Conv.rules';
  Books[0].Checked:= True;
  Books[0].Kind:= bkConvertOnly;
  Books[1].Path:= 'Units.rules';
  Books[1].Checked:= True;
  Books[1].Kind:= bkUnitsOnly;
  Books[2].Path:= 'Mixed.rules';
  Books[2].Checked:= True;
  Books[2].Kind:= bkMixed;
  // The index is a list of FILE PATHS (the project DB's files table).
  Pre:= Preflight(Books, ['p\U1.pas'], ['p\U1.pas'], False);
  Check('convertrun.pre.ok', Pre.Ok, string.Join(' | ', Pre.Problems));
  Check('convertrun.pre.units.only.skipped', string.Join(',', Pre.Runnable) = 'Conv.rules,Mixed.rules', string.Join(',', Pre.Runnable));
  Check('convertrun.pre.notes', Length(Pre.Notes) = 2, string.Join(' | ', Pre.Notes));
  Pre:= Preflight(Books, ['p\U1.pas'], ['p\U1.pas'], True);
  Check('convertrun.pre.units.supported', Length(Pre.Runnable) = BOOK_COUNT, string.Join(',', Pre.Runnable));
  Pre:= Preflight(Books, ['p\U1.pas', 'p\Loose.pas'], ['P\u1.PAS'], False);
  Check('convertrun.pre.unindexed.refused', (not Pre.Ok) and (Pos('Loose', string.Join(' ', Pre.Problems)) > 0), string.Join(' | ', Pre.Problems));
  Check('convertrun.pre.index.nocase', Pos('U1', string.Join(' ', Pre.Problems)) = 0, string.Join(' | ', Pre.Problems));
  // The migration case: the project indexes ITS OWN U1.pas; a same-named unit
  // from another tree is not indexed -- the engine finds the .dfm by path.
  Pre:= Preflight(Books, ['m2022\U1.pas'], ['p\U1.pas'], False);
  Check('convertrun.pre.same.name.foreign.path', (not Pre.Ok) and (Pos('U1.pas', string.Join(' ', Pre.Problems)) > 0), string.Join(' | ', Pre.Problems));
  Books[0].Checked:= False;
  Books[1].Checked:= False;
  Books[2].Checked:= False;
  Pre:= Preflight(Books, ['p\U1.pas'], ['p\U1.pas'], False);
  Check('convertrun.pre.no.book', not Pre.Ok, string.Join(' | ', Pre.Problems));
  Books[0].Checked:= True;
  Pre:= Preflight(Books, [], ['p\U1.pas'], False);
  Check('convertrun.pre.no.unit', not Pre.Ok, string.Join(' | ', Pre.Problems));

  // --- ParseApplyJson (schema apply/1) ---
  Row:= ParseApplyJson('{"schema":"apply/1","ok":true,"error":"","rule_errors":[],"edits_count":3,' +
    '"converted":["Label1: TLabel -> TStaticText"],"access_sites":[],"creator_sites":[],' +
    '"todos":["t1"],"reemit_notes":["n1"],"warnings":["w1"],"items":[]}');
  Check('convertrun.json.ok', Row.Ok and (Row.EditsCount = JSON_EDITS) and (Length(Row.Converted) = 1));
  Check('convertrun.json.remainder', string.Join(',', Row.Remainder) = 't1,n1,w1', string.Join(',', Row.Remainder));
  Row:= ParseApplyJson('{"schema":"apply/1","ok":false,"error":"","rule_errors":[{"line":7,"message":"link ToPath not found"}],' +
    '"edits_count":0,"converted":[],"access_sites":[],"creator_sites":[],"todos":[],"reemit_notes":[],"warnings":[],"items":[]}');
  Check('convertrun.json.rule.error', (not Row.Ok) and (Pos('line 7', Row.Error) > 0) and (Row.RuleErrorCount = 1), Row.Error);
  Row:= ParseApplyJson('FATAL: something');
  Check('convertrun.json.unparseable', (not Row.Ok) and (Pos('FATAL', Row.Error) > 0), Row.Error);
  // The engine prints "(loaded defaults from ...)" on stderr, and RunCapture merges
  // stderr into the same pipe: the document starts at the first '{'.
  Row:= ParseApplyJson('(loaded defaults from C:\x.json)' + sLineBreak + '{"schema":"apply/1","ok":true,"error":"","rule_errors":[],"edits_count":2,' +
    '"converted":[],"access_sites":[],"creator_sites":[],"todos":[],"reemit_notes":[],"warnings":[],"items":[]}');
  Check('convertrun.json.leading.noise', Row.Ok and (Row.EditsCount = 2), Row.Error);
  // Measured 2026-09-29: the real engine writes that line AFTER the document, so
  // the parse must also stop at the last '}'.
  Row:= ParseApplyJson('{"schema":"apply/1","ok":false,"error":"conversion rules failed validation","rule_errors":[{"line":2,"message":"link ToPath not found"}],' +
    '"edits_count":0,"converted":[],"todos":[],"reemit_notes":[],"warnings":[]}' + sLineBreak + '(loaded defaults from C:\x.json)' + sLineBreak);
  Check('convertrun.json.trailing.noise', (not Row.Ok) and (Row.RuleErrorCount = 1) and (Pos('line 2', Row.Error) > 0), Row.Error);
  // engine 1.20.6 refusal: ok=false, refused=true, reason, file untouched
  // (unreachable[] is always present in 1.20.6 apply/1 and must not disturb the parse)
  Row:= ParseApplyJson('{"schema":"apply/1","ok":false,"refused":true,"reason":"inherited instances of TTable are not converted yet -- unit not changed","rule_errors":[],"edits_count":0,"unreachable":[]}');
  Check('apply.refused.flag', (not Row.Ok) and Row.Refused);
  Check('apply.refused.reason', Row.Error = 'inherited instances of TTable are not converted yet -- unit not changed', Row.Error);
  Row:= ParseApplyJson('{"schema":"apply/1","ok":false,"refused":true,"rule_errors":[]}');
  Check('apply.refused.no.reason', Row.Refused and (Row.Error = 'convert-apply refused the unit and gave no reason'), Row.Error);
  Row:= ParseApplyJson('{"schema":"apply/1","ok":false,"error":"boom","rule_errors":[]}');
  Check('apply.failed.not.refused', (not Row.Ok) and (not Row.Refused) and (Row.Error = 'boom'), Row.Error);
  Row:= ParseApplyJson('{"schema":"apply/1","ok":false,"refused":false,"error":"boom"}');
  Check('apply.refused.false.is.failure', not Row.Refused);
  Check('status.text.refused', ConvertStatusText(csRefused) = 'refused -- not changed');
  Check('status.text.restore.failed.unchanged', ConvertStatusText(csRestoreFailed) = 'FAILED -- NOT restored');

  // --- ExpandSources: .pas / folder / .dpr, deduped case-insensitively ---
  Dir:= TPath.Combine(TPath.GetTempPath, 'convrun-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'U1.pas'), 'unit U1; interface implementation end.', TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(Dir, 'U2.pas'), 'unit U2; interface implementation end.', TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(Dir, 'P.dpr'), 'program P; uses U1 in ''U1.pas'', U2 in ''U2.pas''; begin end.', TEncoding.ASCII);
    Srcs:= ExpandSources([TPath.Combine(Dir, 'U1.pas'), TPath.Combine(Dir, 'P.dpr'), UpperCase(TPath.Combine(Dir, 'u1.pas'))], Errs);
    Check('convertrun.expand.dedupe.nocase', Length(Srcs) = 2, string.Join(' | ', Srcs));
    Check('convertrun.expand.order', SameText(ExtractFileName(Srcs[0]), 'U1.pas') and SameText(ExtractFileName(Srcs[1]), 'U2.pas'), string.Join(' | ', Srcs));
    Srcs:= ExpandSources([Dir], Errs);
    Check('convertrun.expand.folder', Length(Srcs) = 2, string.Join(' | ', Srcs));
    Srcs:= ExpandSources([TPath.Combine(Dir, 'Nope.pas')], Errs);
    Check('convertrun.expand.missing.error', (Length(Srcs) = 0) and (Length(Errs) = 1), string.Join(' | ', Errs));
    // A locked / unreadable .dpr is one AErrors line, never an exception: this
    // runs on Explorer drops, and a bad project must not crash a drop.
    Raised:= '';
    Lock:= TFileStream.Create(TPath.Combine(Dir, 'P.dpr'), fmOpenRead or fmShareExclusive);
    try
      try
        Srcs:= ExpandSources([TPath.Combine(Dir, 'P.dpr')], Errs);
      except  // dl:ok try-except-swallowed@aa6b -- not swallowed: the exception text lands in Raised and the next Check fails on it; catching keeps the rest of the run alive
        on E: Exception do
          Raised:= E.ClassName + ': ' + E.Message;
      end; // try
    finally
      Lock.Free;
    end; // try
    Check('convertrun.expand.unreadable.error', (Raised = '') and (Length(Srcs) = 0) and (Length(Errs) = 1) and (Pos('P.dpr', string.Join(' ', Errs)) > 0), Raised + ' ' + string.Join(' | ', Errs));
  finally
    TDirectory.Delete(Dir, True);
  end; // try
end; // procedure

{ The Convert tab's source rows: an unindexed unit is flagged in the DISPLAY
  only, and an unreadable index flags nothing (unknown is not "indexed"). }
procedure TestConvertSourceRow;
var
  Flagged: Boolean;
  Text   : string;
begin
  // By FULL PATH (ExpandFileName'd, any case), never by unit name.
  Check('unitinindex.nocase', UnitInIndex('src\dmCPData.pas', ['X.pas', 'SRC\DMCPDATA.PAS']));
  Check('unitinindex.normalised', UnitInIndex('src\sub\..\My.Unit.pas', ['src\my.unit.pas']));
  Check('unitinindex.absent', not UnitInIndex('src\Foo.pas', ['src\Bar.pas', 'src\FooX.pas']));
  Check('unitinindex.foreign.path', not UnitInIndex('m2022\DM1.pas', ['client\DM1.pas']));
  Text:= SourceRowText('src\Foo.pas', ['src\Bar.pas'], True, Flagged);
  Check('sourcerow.flagged', Flagged and (Text = 'src\Foo.pas -- not in the project index'), Text);
  Text:= SourceRowText('src\dmCPData.pas', ['SRC\DMCPDATA.PAS'], True, Flagged);
  Check('sourcerow.indexed.plain', (not Flagged) and (Text = 'src\dmCPData.pas'), Text);
  Text:= SourceRowText('src\Foo.pas', nil, False, Flagged);
  Check('sourcerow.unknown.notflagged', (not Flagged) and (Text = 'src\Foo.pas'), Text);
end; // procedure

{ ConvertRunner paths that need no engine answer: a missing unit, a cancel
  between units. The engine adapter points at a non-existent exe, so any call
  that DID reach the engine would fail loudly rather than pass silently. }
procedure TestConvertRunner;
var
  Job   : TConvertJob;
  Rows  : TArray<TConvertRow>;
  Eng   : TEngineAdapter;
  Calls : Integer;
begin
  Eng:= TEngineAdapter.Create('C:\nowhere\drag-lint.exe', []);  // dl:ok hardcoded-absolute-path@4127 -- REVIEWED 2026-09-29 deliberately non-existent exe: any engine call must fail loudly
  try
    Job:= Default(TConvertJob);
    Job.Books:= [];            // no book survives validation -> nothing may run
    Job.Units:= ['C:\nowhere\Gone.pas'];  // dl:ok hardcoded-absolute-path@1575 -- REVIEWED 2026-09-29 deliberately non-existent unit (missing-unit row)
    Rows:= RunConversion(Job, Eng, nil, nil);
    Check('runner.no.books.nothing.runs', Length(Rows) = 0, IntToStr(Length(Rows)));

    Calls:= 0;
    Rows:= RunConversionUnits(Job.Units, ['Book.rules'], Job, Eng,
      procedure(const ARow: TConvertRow; ADone, ATotal: Integer) begin Inc(Calls); end, nil);
    var LNote: string:= '(no row)';
    if Length(Rows) > 0 then
      LNote:= Rows[0].Note;
    Check('runner.missing.unit.row', (Length(Rows) = 1) and (Rows[0].Status = csUnitSkipped) and (Pos('not found', LNote) > 0), LNote);
    Check('runner.missing.unit.progress', Calls = 1, IntToStr(Calls));

    Rows:= RunConversionUnits(['C:\nowhere\A.pas', 'C:\nowhere\B.pas'], ['Book.rules'], Job, Eng, nil,  // dl:ok hardcoded-absolute-path@7c72 -- REVIEWED 2026-09-29 deliberately non-existent units; cancel fires before either is probed
      function: Boolean begin Result:= True; end);
    Check('runner.cancel.between.units', Length(Rows) = 0, IntToStr(Length(Rows)));
  finally
    Eng.Free;
  end; // try
end; // procedure

{ ConvertRunner row integrity and file-I/O faults, with the engine calls faked
  (review fix round 1): a later book's failure rolls back an earlier book's rows
  (and they reach AProgress only in their final status); a backup that cannot
  be taken skips the unit; a restore that cannot be done says so. None of these
  may raise out of RunConversionUnits. }
procedure TestConvertRunnerFaults;
const
  OK_JSON   = '{"schema":"apply/1","ok":true,"error":"","rule_errors":[],"edits_count":1,"converted":[],"todos":[],"reemit_notes":[],"warnings":[]}';
  FAIL_JSON = '{"schema":"apply/1","ok":false,"error":"boom","rule_errors":[],"edits_count":0}';
  REFUSED_JSON = '{"schema":"apply/1","ok":false,"refused":true,"reason":"inherited instances of TTable are not converted yet -- unit not changed","rule_errors":[],"edits_count":0}';
  REFUSED_ERRS_JSON = '{"schema":"apply/1","ok":false,"refused":true,"reason":"inherited instances of TTable are not converted yet -- unit not changed","rule_errors":[{"line":3,"message":"x not found"}],"edits_count":0}';
  ORIG      = 'unit U;' + sLineBreak + 'interface' + sLineBreak + 'implementation' + sLineBreak + 'end.' + sLineBreak;
  TWO_ROWS  = 2;
var
  Dir, PasR, PasL, PasF, Seen, Raised: string;
  PasI, PasJ, PasK, PasS, DfmS, Log: string;
  Rows : TArray<TConvertRow>;
  Calls: Integer;
  Index: TIndexFn;
  Lock : TFileStream;

  function Describe(const ARows: TArray<TConvertRow>): string;
  begin
    Result:= Format('%d rows', [Length(ARows)]);
    for var LRow: TConvertRow in ARows do
      Result:= Result + ' | ' + ExtractFileName(LRow.Book) + '=' + ConvertStatusText(LRow.Status) + ': ' + LRow.Note + ' [' + ExtractFileName(LRow.Backup) + ' ' + ExtractFileName(LRow.BackupDfm) + ']';
  end;

  // A writes into the unit and succeeds; B runs AOnB, then fails without rule_errors.
  function ApplyAThenFailB(const AOnB: TProc<string>): TApplyFn;
  begin
    Result:= function(const AUnitPas, ARulesFile: string; out AJson: string): Integer
      begin
        if SameText(ExtractFileName(ARulesFile), 'A.rules') then
        begin
          TFile.WriteAllText(AUnitPas, 'CONVERTED-A', TEncoding.ASCII);
          AJson := OK_JSON;
          Result:= 0;
          Exit;
        end;
        if Assigned(AOnB) then
          AOnB(AUnitPas);
        AJson := FAIL_JSON;
        Result:= 1;
      end;
  end;

  // Engine 1.20.6 refusals (apply/1 "refused": true), kept out of the main body
  // so its cyclomatic complexity stays under the lint limit.
  procedure CheckRefusals;
  var
    LPas : string;
    LRows: TArray<TConvertRow>;

    // Backups of APas's unit (.pas and .dfm) left in Dir.
    function BackupsLeft(const APas: string): Integer;
    begin
      Result:= Length(TDirectory.GetFiles(Dir, ChangeFileExt(ExtractFileName(APas), '') + '.*.BCK*'));
    end;

  begin
    // --- the FIRST book is refused: nothing changed the unit, so no restore and no backup ---
    LPas:= TPath.Combine(Dir, 'F1.pas');
    TFile.WriteAllText(LPas, ORIG, TEncoding.ASCII);
    TFile.WriteAllText(ChangeFileExt(LPas, '.dfm'), 'object F1: TF1' + sLineBreak + 'end' + sLineBreak, TEncoding.ASCII);
    LRows:= RunConversionUnits([LPas], ['A.rules'],
      function(const AUnitPas, ARulesFile: string; out AJson: string): Integer
      begin
        AJson := REFUSED_JSON;
        Result:= 1;
      end, Index, nil, nil);
    Check('runner.refused.first', (Length(LRows) = 1) and (LRows[0].Status = csRefused)
      and (Pos('inherited instances', LRows[0].Note) > 0) and (TFile.ReadAllText(LPas) = ORIG), Describe(LRows));
    // Owner decision 2 (2026-10-04): an unneeded backup is dropped, as for a skipped book.
    Check('runner.refused.first.drops.backup', (Length(LRows) = 1) and (LRows[0].Backup = '') and (LRows[0].BackupDfm = '')
      and (BackupsLeft(LPas) = 0) and (TFile.ReadAllText(LPas) = ORIG), Describe(LRows) + Format(' | backups left=%d', [BackupsLeft(LPas)]));

    // --- a LATER book is refused: the earlier book's change is rolled back ---
    LPas:= TPath.Combine(Dir, 'F2.pas');
    TFile.WriteAllText(LPas, ORIG, TEncoding.ASCII);
    LRows:= RunConversionUnits([LPas], ['A.rules', 'B.rules'],
      function(const AUnitPas, ARulesFile: string; out AJson: string): Integer
      begin
        if SameText(ExtractFileName(ARulesFile), 'A.rules') then
        begin
          TFile.WriteAllText(AUnitPas, 'CONVERTED-A', TEncoding.ASCII);
          AJson := OK_JSON;
          Result:= 0;
          Exit;
        end;
        AJson := REFUSED_JSON;
        Result:= 1;
      end, Index, nil, nil);
    Check('runner.refused.rolls.back', (Length(LRows) = TWO_ROWS) and (LRows[0].Status = csRolledBack)
      and (Pos('B.rules was refused', LRows[0].Note) > 0) and (LRows[1].Status = csRefused)
      and (TFile.ReadAllText(LPas) = ORIG), Describe(LRows) + ' | pas=' + TFile.ReadAllText(LPas));
    // The restore needed the backup: it is kept and named on the refused row.
    Check('runner.refused.later.keeps.backup', (Length(LRows) = TWO_ROWS) and (LRows[1].Backup <> '') and TFile.Exists(LRows[1].Backup)
      and (BackupsLeft(LPas) = 1) and (TFile.ReadAllText(LPas) = ORIG), Describe(LRows) + Format(' | backups left=%d', [BackupsLeft(LPas)]));

    // --- a refusal that ALSO carries rule_errors is a refusal, not an invalid book:
    // the book stays valid, so the NEXT unit still gets its own apply call ---
    var LPas2: string:= TPath.Combine(Dir, 'F4.pas');
    var LCalls: Integer:= 0;
    LPas:= TPath.Combine(Dir, 'F3.pas');
    TFile.WriteAllText(LPas, ORIG, TEncoding.ASCII);
    TFile.WriteAllText(LPas2, ORIG, TEncoding.ASCII);
    LRows:= RunConversionUnits([LPas, LPas2], ['A.rules'],
      function(const AUnitPas, ARulesFile: string; out AJson: string): Integer
      begin
        Inc(LCalls);
        AJson := REFUSED_ERRS_JSON;
        Result:= 1;
      end, Index, nil, nil);
    Check('runner.refused.with.rule.errors.is.refused', (Length(LRows) = TWO_ROWS) and (LRows[0].Status = csRefused)
      and (LRows[1].Status = csRefused) and (LCalls = TWO_ROWS) and (TFile.ReadAllText(LPas) = ORIG),
      Describe(LRows) + Format(' | calls=%d', [LCalls]));
  end;

begin
  Dir:= TPath.Combine(TPath.GetTempPath, 'convrunner-faults-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    Index:= function(out AOutput: string): Integer
      begin
        AOutput:= '';
        Result := 0;
      end;

    // --- a later book fails: the earlier book's row is rolled back ---
    PasR:= TPath.Combine(Dir, 'R.pas');
    TFile.WriteAllText(PasR, ORIG, TEncoding.ASCII);
    Seen:= '';
    Rows:= RunConversionUnits([PasR], ['A.rules', 'B.rules'], ApplyAThenFailB(nil), Index,
      procedure(const ARow: TConvertRow; ADone, ATotal: Integer)
      begin
        Seen:= Seen + ExtractFileName(ARow.Book) + '=' + ConvertStatusText(ARow.Status) + ';';
      end, nil);
    Check('runner.rollback.row', (Length(Rows) = TWO_ROWS) and (Rows[0].Status = csRolledBack) and (Pos('B.rules', Rows[0].Note) > 0)
      and (Rows[1].Status = csFailedRestored) and (TFile.ReadAllText(PasR) = ORIG), Describe(Rows) + ' | pas=' + TFile.ReadAllText(PasR));
    Check('runner.rollback.progress.order', Seen = 'A.rules=rolled back;B.rules=FAILED -- restored;', Seen);

    CheckRefusals;

    // --- the backup cannot be taken: the unit is skipped, nothing left behind ---
    PasL:= TPath.Combine(Dir, 'L.pas');
    TFile.WriteAllText(PasL, ORIG, TEncoding.ASCII);
    Calls := 0;
    Raised:= '';
    Rows  := nil;  // dl:ok overwrite-before-read@05a7 -- REVIEWED 2026-09-29 read when the call below raises: the check must not report the previous case's rows
    Lock:= TFileStream.Create(PasL, fmOpenRead or fmShareExclusive);
    try
      try
        Rows:= RunConversionUnits([PasL], ['A.rules'],
          function(const AUnitPas, ARulesFile: string; out AJson: string): Integer
          begin
            Inc(Calls);
            AJson := OK_JSON;
            Result:= 0;
          end, Index, nil, nil);
      except  // dl:ok try-except-swallowed@aa6b -- REVIEWED 2026-09-29 not swallowed: the text lands in Raised and the next Check fails on it
        on E: Exception do
          Raised:= E.ClassName + ': ' + E.Message;
      end; // try
    finally
      Lock.Free;
    end; // try
    var LSkipRow  : Boolean:= (Length(Rows) = 1) and (Rows[0].Status = csUnitSkipped) and (Pos('backup failed', Rows[0].Note) > 0);
    var LNoLeftBck: Boolean:= Length(TDirectory.GetFiles(Dir, 'L.pas.BCK*')) = 0;
    Check('runner.backup.failure', (Raised = '') and LSkipRow and (Calls = 0) and LNoLeftBck, Raised + ' ' + Describe(Rows) + Format(' calls=%d', [Calls]));

    // --- the restore itself fails: say so, keep the backup, do not raise ---
    PasF:= TPath.Combine(Dir, 'F.pas');
    TFile.WriteAllText(PasF, ORIG, TEncoding.ASCII);
    Raised:= '';
    Rows  := nil;  // dl:ok overwrite-before-read@05a7 -- REVIEWED 2026-09-29 read when the call below raises: the check must not report the previous case's rows
    try
      try
        Rows:= RunConversionUnits([PasF], ['A.rules', 'B.rules'],
          ApplyAThenFailB(procedure(AUnitPas: string) begin FileSetAttr(AUnitPas, faReadOnly); end), Index, nil, nil);
      except  // dl:ok try-except-swallowed@aa6b -- REVIEWED 2026-09-29 not swallowed: the text lands in Raised and the next Check fails on it
        on E: Exception do
          Raised:= E.ClassName + ': ' + E.Message;
      end; // try
      Check('runner.restore.failure', (Raised = '') and (Length(Rows) = TWO_ROWS) and (Rows[1].Status = csRestoreFailed)
        and (Pos(PasF + '.BCK1', Rows[1].Note) > 0) and TFile.Exists(PasF + '.BCK1'), Raised + ' ' + Describe(Rows));
    finally
      FileSetAttr(PasF, faNormal);
    end; // try

    // --- the index is refreshed BEFORE the unit's first book, not only after ---
    // convert-apply patches the .dfm at the index's line ranges; a unit edited
    // since the last index would be patched in the wrong place.
    PasI:= TPath.Combine(Dir, 'I.pas');
    TFile.WriteAllText(PasI, ORIG, TEncoding.ASCII);
    Log:= '';
    RunConversionUnits([PasI], ['A.rules'],
      function(const AUnitPas, ARulesFile: string; out AJson: string): Integer
      begin
        Log   := Log + 'apply;';
        AJson := OK_JSON;
        Result:= 0;
      end,
      function(out AOutput: string): Integer
      begin
        Log    := Log + 'index;';
        AOutput:= '';
        Result := 0;
      end, nil, nil);
    Check('runner.reindex.before.first.book', Log = 'index;apply;index;', Log);

    // --- that reindex fails: the unit is skipped untouched, the next one still runs ---
    PasJ:= TPath.Combine(Dir, 'J.pas');
    PasK:= TPath.Combine(Dir, 'K.pas');
    TFile.WriteAllText(PasJ, ORIG, TEncoding.ASCII);
    TFile.WriteAllText(PasK, ORIG, TEncoding.ASCII);
    Calls:= 0;
    Rows:= RunConversionUnits([PasJ, PasK], ['A.rules'],
      function(const AUnitPas, ARulesFile: string; out AJson: string): Integer
      begin
        Inc(Calls);
        AJson := OK_JSON;
        Result:= 0;
      end,
      function(out AOutput: string): Integer
      begin
        AOutput:= 'index-boom';
        Result := 1;
      end, nil, nil);
    var LBothSkipped: Boolean:= (Length(Rows) = TWO_ROWS) and (Rows[0].Status = csUnitSkipped) and (Rows[1].Status = csUnitSkipped)
      and (Pos('reindex before apply failed: index-boom', Rows[0].Note) > 0) and SameText(Rows[1].UnitPas, PasK);
    var LNoBck: Boolean:= Length(TDirectory.GetFiles(Dir, 'J.*.BCK*')) + Length(TDirectory.GetFiles(Dir, 'K.*.BCK*')) = 0;
    Check('runner.reindex.before.failure', LBothSkipped and (Calls = 0) and LNoBck and (TFile.ReadAllText(PasJ) = ORIG),
      Describe(Rows) + Format(' calls=%d', [Calls]));

    // --- one backup NUMBER per unit, shared by .pas and .dfm, named on the rows ---
    PasS:= TPath.Combine(Dir, 'S.pas');
    DfmS:= TPath.Combine(Dir, 'S.dfm');
    TFile.WriteAllText(PasS, ORIG, TEncoding.ASCII);
    TFile.WriteAllText(DfmS, 'object S: TS' + sLineBreak + 'end' + sLineBreak, TEncoding.ASCII);
    TFile.WriteAllText(DfmS + '.BCK2', 'an older .dfm backup', TEncoding.ASCII);
    Rows:= RunConversionUnits([PasS], ['A.rules', 'B.rules'], ApplyAThenFailB(nil), Index, nil, nil);
    Check('runner.backup.shared.n', (Length(Rows) = TWO_ROWS) and SameText(Rows[1].Backup, PasS + '.BCK3') and SameText(Rows[1].BackupDfm, DfmS + '.BCK3')
      and TFile.Exists(PasS + '.BCK3') and TFile.Exists(DfmS + '.BCK3'), Describe(Rows));
    Check('runner.rollback.names.both.backups', (Length(Rows) = TWO_ROWS) and (Pos('S.pas.BCK3', Rows[0].Note) > 0) and (Pos('S.dfm.BCK3', Rows[0].Note) > 0), Describe(Rows));
  finally
    TDirectory.Delete(Dir, True);
  end; // try
end; // procedure

{ The real engine on a 3-file fixture (one TLabel, a one-#convert book) -- the
  shape measured converting on 2026-09-29 (dry run 106 s; the bad book 93 s).
  Two jobs, one apply each -- the slowest test in the runner:
    1. ONLY an invalid book: a book-skip row, the unit untouched, and NO .BCK
       left behind (the run's own fresh backup is dropped when nothing changed);
    2. the good book: converted in place, .BCK1 for .pas and .dfm, .dfm still text. }
procedure TestConvertRunnerLive;
const
  LIB64 = 'C:\Projects\.drag-lint\library-Win64.sqlite';  // dl:ok hardcoded-absolute-path@6fd2 -- REVIEWED 2026-09-29 the real Win64 library index; the test Skip()s when it is absent
  DFM_HEAD_CHARS = 40;
var
  Exe, Dir, Db, Dpr, Pas, Dfm, Book, Bad, Output: string;
  Eng : TEngineAdapter;
  Job : TConvertJob;
  Rows: TArray<TConvertRow>;
begin
  Exe:= ResolveExe;
  if (Exe = '') or not TFile.Exists(LIB64) then
  begin
    Skip('runner.live', 'exe or library-Win64 absent');
    Exit;
  end;
  Dir:= TPath.Combine(TPath.GetTempPath, 'convrunner-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    Dpr := TPath.Combine(Dir, 'Fix.dpr');
    Pas := TPath.Combine(Dir, 'FixUnit.pas');
    Dfm := TPath.Combine(Dir, 'FixUnit.dfm');
    Book:= TPath.Combine(Dir, 'Fix.rules');
    Bad := TPath.Combine(Dir, 'Bad.rules');
    Db  := TPath.Combine(Dir, 'Fix.sqlite');
    TFile.WriteAllText(Dpr, 'program Fix;' + sLineBreak + sLineBreak + 'uses' + sLineBreak + '  Vcl.Forms,' + sLineBreak +
      '  FixUnit in ''FixUnit.pas'' {FixForm};' + sLineBreak + sLineBreak + 'begin' + sLineBreak + '  Application.Initialize;' + sLineBreak +
      '  Application.Run;' + sLineBreak + 'end.' + sLineBreak, TEncoding.ASCII);
    TFile.WriteAllText(Pas, 'unit FixUnit;' + sLineBreak + sLineBreak + 'interface' + sLineBreak + sLineBreak + 'uses' + sLineBreak +
      '  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, System.Classes;' + sLineBreak + sLineBreak + 'type' + sLineBreak +
      '  TFixForm = class(TForm)' + sLineBreak + '    Label1: TLabel;' + sLineBreak + '  end;' + sLineBreak + sLineBreak + 'var' + sLineBreak +
      '  FixForm: TFixForm;' + sLineBreak + sLineBreak + 'implementation' + sLineBreak + sLineBreak + '{$R *.dfm}' + sLineBreak + sLineBreak + 'end.' + sLineBreak, TEncoding.ASCII);
    TFile.WriteAllText(Dfm, 'object FixForm: TFixForm' + sLineBreak + '  Left = 0' + sLineBreak + '  Top = 0' + sLineBreak + '  Caption = ''Fix''' + sLineBreak +
      '  object Label1: TLabel' + sLineBreak + '    Left = 8' + sLineBreak + '    Top = 8' + sLineBreak + '    Caption = ''Hello''' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak, TEncoding.ASCII);
    TFile.WriteAllText(Book, '#convert Vcl.StdCtrls.TLabel -> Vcl.StdCtrls.TStaticText, Vcl.StdCtrls' + sLineBreak + '#link Caption <- Caption' + sLineBreak +
      '#link Left <- Left' + sLineBreak + '#link Top <- Top' + sLineBreak, TEncoding.ASCII);
    TFile.WriteAllText(Bad, '#convert Vcl.StdCtrls.TLabel -> Vcl.StdCtrls.TStaticText, Vcl.StdCtrls' + sLineBreak + '#link NoSuchProp <- AlsoNoSuchProp' + sLineBreak, TEncoding.ASCII);
    Eng:= TEngineAdapter.Create(Exe, [Db, LIB64]);
    try
      Check('runner.live.index', Eng.IndexProject(Dpr, Db, Output) = 0, Output);
      // The Convert tab's pre-flight source: the files table, by PATH. The
      // fixture unit must be listed; a same-named file elsewhere must not match.
      var LFiles: TArray<string>;
      var LListed: Boolean:= Eng.ListIndexedFiles([Db], LFiles, Output);
      Check('runner.live.indexed.files', LListed and UnitInIndex(Pas, LFiles) and not UnitInIndex(TPath.Combine(TPath.GetTempPath, 'FixUnit.pas'), LFiles),
        Format('listed=%s n=%d %s', [BoolToStr(LListed, True), Length(LFiles), Output]));
      Job:= Default(TConvertJob);
      Job.Units      := [Pas];
      Job.Dbs        := [Db, LIB64];
      Job.ProjectDb  := Db;
      Job.ProjectFile:= Dpr;

      var LBefore: string:= TFile.ReadAllText(Pas);
      Job.Books:= [Bad];
      Rows:= RunConversion(Job, Eng, nil, nil);
      Check('runner.invalid.book.skipped', (Length(Rows) = 1) and (Rows[0].Status = csBookSkipped) and SameText(Rows[0].Book, Bad), Format('%d rows', [Length(Rows)]));
      Check('runner.invalid.book.unit.untouched', TFile.ReadAllText(Pas) = LBefore);
      Check('runner.invalid.book.no.backup', not TFile.Exists(Pas + '.BCK1') and not TFile.Exists(Dfm + '.BCK1'));

      Job.Books:= [Book];
      Rows:= RunConversion(Job, Eng, nil, nil);
      Check('runner.live.converted', (Length(Rows) = 1) and (Rows[0].Status = csConverted), Format('%d rows', [Length(Rows)]));
      Check('runner.live.pas.changed', Pos('TStaticText', TFile.ReadAllText(Pas)) > 0);
      Check('runner.live.bck1', TFile.Exists(Pas + '.BCK1') and (Pos('TLabel', TFile.ReadAllText(Pas + '.BCK1')) > 0));
      Check('runner.live.dfm.bck1', TFile.Exists(Dfm + '.BCK1'));
      Check('runner.live.dfm.still.text', TFile.ReadAllText(Dfm).StartsWith('object '), Copy(TFile.ReadAllText(Dfm), 1, DFM_HEAD_CHARS));
    finally
      Eng.Free;
    end; // try
  finally
    TDirectory.Delete(Dir, True);
  end; // try
end; // procedure

{ ListUnits answers per DB SET, not per adapter: the picker's project column and
  library column come from separate calls, so a project DB must not surface an
  RTL unit and the library must. Hits the real exe + indexes; Skips without them. }
procedure TestListUnitsPerDb;
const
  LibWin64  = 'C:\Projects\.drag-lint\library-Win64.sqlite';
  ProjectDb = 'C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite';
var
  Exe : string        ;
  eng : TEngineAdapter;
  Proj: TArray<string>;
  Lib : TArray<string>;
  Err : string        ;
begin
  Exe:= ResolveExe;
  if (Exe = '') or not TFile.Exists(LibWin64) or not TFile.Exists(ProjectDb) then
  begin
    Skip('engine.listunits', 'exe, library-Win64 or CLIENT project db absent');
    Exit;
  end;
  // The adapter's own DB set is deliberately BOTH, so a result that ignored the
  // ADbs argument would show up as an RTL unit in the project list.
  eng:= TEngineAdapter.Create(Exe, [LibWin64, ProjectDb]);
  try
    Check('engine.listunits.project.ok', eng.ListUnits([ProjectDb], Proj, Err), Err);
    Check('engine.listunits.library.ok', eng.ListUnits([LibWin64], Lib, Err), Err);
    Check('engine.listunits.project.has.own', Contains(Proj, 'uMain'), IntToStr(Length(Proj)));
    Check('engine.listunits.project.no.rtl', not Contains(Proj, 'System.SysUtils'));
    Check('engine.listunits.library.has.rtl', Contains(Lib, 'System.SysUtils'), IntToStr(Length(Lib)));
  finally
    eng.Free;
  end; // try
end; // procedure

{ The picker's library column per platform, and the one-platform-only note. }
procedure TestUnitPickPlatform;
var
  W32: TArray<string>;
  W64: TArray<string>;
begin
  Check('unitpick.merge.sorted.unique', string.Join(',', MergeUnitLists(['b', 'A'], ['a', 'C'])) = 'A,b,C', string.Join(',', MergeUnitLists(['b', 'A'], ['a', 'C'])));

  W32:= ['Only32', 'Shared'];
  W64:= ['shared', 'Only64'];
  Check('unitpick.lib.win32', string.Join(',', LibraryUnitsFor(cpWin32, W32, W64)) = 'Only32,Shared');
  Check('unitpick.lib.win64', string.Join(',', LibraryUnitsFor(cpWin64, W32, W64)) = 'shared,Only64');
  Check('unitpick.lib.both', string.Join(',', LibraryUnitsFor(cpBoth, W32, W64)) = 'Only32,Only64,Shared', string.Join(',', LibraryUnitsFor(cpBoth, W32, W64)));

  Check('unitpick.gap.only32', PlatformGapNote('Only32', W32, W64) = 'Only32: not in the Win64 library', PlatformGapNote('Only32', W32, W64));
  Check('unitpick.gap.only64.nocase', PlatformGapNote('only64', W32, W64) = 'only64: not in the Win32 library', PlatformGapNote('only64', W32, W64));
  Check('unitpick.gap.shared.silent', PlatformGapNote('SHARED', W32, W64) = '');
  Check('unitpick.gap.neither.silent', PlatformGapNote('MyProjectUnit', W32, W64) = '');
end; // procedure

{ DeclaringUnitOf hits the real drag-lint exe + library DB, so it Skips (not
  fails) when the exe or the Win64 library index is absent. }
procedure TestDeclaringUnit;
const
  LibWin64 = 'C:\Projects\.drag-lint\library-Win64.sqlite';
  { ORM3's CLIENT project index. It is per-PROJECT and lives in that project's own
    _D-RAG folder: the union DB this used to name (DB\ORM3\drag-lint.sqlite) was
    DELETED in the 2026-08-11 one-DB-per-project migration. A --db that does not
    exist makes the engine exit 2, so every call carrying it fails; resolve with
    `drag-lint resolve-dbs --in <file.pas>` rather than guessing a path. }
  ProjectDb = 'C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite';
var
  Exe: string        ;
  eng: TEngineAdapter;
  U  : string        ;
begin
  Exe:= ResolveExe;
  if (Exe = '') or not TFile.Exists(LibWin64) then
  begin
    Skip('engine.declaringunit', 'exe or library-Win64 db absent');
    Exit;
  end;
  eng:= TEngineAdapter.Create(Exe, [LibWin64, ProjectDb]);
  try
    U:= eng.DeclaringUnitOf('TcxButton');
    if U = '' then
      Skip('engine.declaringunit', 'TcxButton not indexed here')
    else
      Check('engine.declaringunit', SameText(U, 'cxButtons'), U);
  finally
    eng.Free;
  end;
end; // procedure

{ .castlib parse: a well-formed block yields one cast with multi-type accepts, the
  single yield, and the unquoted pas/todo templates. }
procedure TestCastLibParse;
const
  SRC = '# a comment'#13#10 + 'cast AssignGraphic'#13#10 + '  accepts TPicture, TBitmap, TGraphic'#13#10 + '  yields  TdxSmartGlyph'#13#10 +
  '  dfm     keep-bytes-if-compatible'#13#10 + '  pas     ''{dst}.Assign({src});'''#13#10 + '  todo    ''do it by hand'''#13#10 + 'end'#13#10;
var
  d: TArray<TCastDef>;
begin
  d:= LoadCastLibText(SRC);
  Check('castlib.count', Length(d) = 1, IntToStr(Length(d)));
  if Length(d) = 0 then
    Exit;
  Check('castlib.name', d[0].Name = 'AssignGraphic', d[0].Name);
  Check('castlib.accepts.count', Length(d[0].Accepts) = 3, IntToStr(Length(d[0].Accepts)));
  Check('castlib.accepts.bitmap', Contains(d[0].Accepts, 'TBitmap'));
  Check('castlib.yields', (Length(d[0].Yields) = 1) and (d[0].Yields[0] = 'TdxSmartGlyph'));
  Check('castlib.dfm' , d[0].Dfm         = 'keep-bytes-if-compatible', d[0].Dfm        );
  Check('castlib.pas' , d[0].PasTemplate = '{dst}.Assign({src});'    , d[0].PasTemplate);
  Check('castlib.todo', d[0].Todo        = 'do it by hand'           , d[0].Todo       );
end; // procedure

{ Tolerance: blank lines, comments, unknown keys, and a malformed (unclosed) block
  must not stop the good block from parsing. }
procedure TestCastLibTolerant;
const
  SRC = 'cast Broken'#13#10 + // no 'end' -> discarded when the next 'cast' starts
  '  accepts TFoo'#13#10 + 'cast Good'#13#10 + ''#13#10 + '  # inline comment line'#13#10 + '  accepts TA, TB'#13#10 + '  yields  TC'#13#10 +
  '  boguskey whatever here'#13#10 + // unknown key tolerated
  'end'#13#10;
var
  d: TArray<TCastDef>;
begin
  d:= LoadCastLibText(SRC);
  Check('castlib.tolerant.count', Length(d) = 1, IntToStr(Length(d)));
  if Length(d) = 0 then
    Exit;
  Check('castlib.tolerant.name', d[0].Name = 'Good', d[0].Name);
  Check('castlib.tolerant.yields', (Length(d[0].Yields) = 1) and (d[0].Yields[0] = 'TC'));
end;

{ ClassCastFor: matches a pair whose From is accepted AND To is yielded, case-
  insensitively; returns '' for an unbridged pair. }
procedure TestClassCastFor;
var
  d: TArray<TCastDef>;
begin
  d:= LoadCastLibText( 'cast AssignGraphic'#13#10 + '  accepts TPicture, TBitmap, TGraphic'#13#10 + '  yields  TdxSmartGlyph'#13#10 + 'end'#13#10);
  Check('castfor.picture', ClassCastFor(d, 'TPicture', 'TdxSmartGlyph') = 'AssignGraphic');
  Check('castfor.bitmap' , ClassCastFor(d, 'TBitmap' , 'TdxSmartGlyph') = 'AssignGraphic');
  Check('castfor.ci'     , ClassCastFor(d, 'tpicture', 'tdxsmartglyph') = 'AssignGraphic');
  Check('castfor.wrongto'  , ClassCastFor(d, 'TPicture', 'TStrings'     ) = '', 'should be blocked');
  Check('castfor.wrongfrom', ClassCastFor(d, 'TFont'   , 'TdxSmartGlyph') = '', 'should be blocked');
end;

{ The shipped casts.castlib parses and provides AssignGraphic. Skipped (not failed)
  when the file is not found from the test exe (lean checkout). }
procedure TestCastLibFile;
var
  P: string          ;
  d: TArray<TCastDef>;
begin
  // test exe lives at <root>\src\tools\convrules-editor\tests\ -> climb 4 to root.
  P:= TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\..\..\docs\examples\convrules\casts.castlib'));
  if not TFile.Exists(P) then
  begin
    Skip('castlib.file', 'casts.castlib not found: ' + P);
    Exit;
  end;
  d:= LoadCastLib(P);
  Check('castlib.file.nonempty', Length(d) > 0, IntToStr(Length(d)));
  Check('castlib.file.assigngraphic', ClassCastFor(d, 'TPicture', 'TdxSmartGlyph') = 'AssignGraphic', 'AssignGraphic (TPicture->TdxSmartGlyph) not resolved from the shipped file');
end; // procedure

{ A #link with a class-cast NAME suffix (a single identifier) parses into Cast and
  re-emits byte-faithfully -- the existing DSL slot carries library cast names with no
  grammar change. }
procedure TestClassCastLinkRoundTrip;
var
  Book: TRuleBook;
begin
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString('#link Glyph <- Glyph : AssignGraphic'#13#10);
    Check('classcast.link.cast'  , Book.Nodes[0].Cast     = 'AssignGraphic'                       , Book.Nodes[0].Cast    );
    Check('classcast.link.from'  , Book.Nodes[0].LinkFrom = 'Glyph'                               , Book.Nodes[0].LinkFrom);
    Check('classcast.link.reemit', Book.Nodes[0].Emit     = '#link Glyph <- Glyph : AssignGraphic', Book.Nodes[0].Emit    );
  finally
    Book.Free;
  end;
end; // procedure

{ Criterion 1a: splitting a .rules text into blocks and rejoining them in order
  reproduces the original byte-for-byte -- including its exact line terminators,
  its blank lines, and a missing final EOL. Tested on synthetic input AND on the
  real shipped sample.rules. }
procedure TestBlockSplitRulesRoundTrip;
const
  SRC = '// preamble comment'#13#10 + ''#13#10 + '#convert A.TFrom -> B.TTo'#13#10 + '#link Text <- Text'#13#10 + '; semicolon comment'#13#10 + ''#13#10 +
  '#convert C.TX -> D.TY, D'#13#10 + '#link Color <- Color'; // NOTE: no trailing EOL on purpose
var
  Blocks: TRuleBlocks;
  P     : string     ;
  Text  : string     ;
begin
  Blocks:= SplitRulesBlocks(SRC);
  Check('blockfile.rules.count', Length(Blocks) = 3, IntToStr(Length(Blocks)));
  Check('blockfile.rules.kind0', Blocks[0].Kind = rbkPreamble, 'block 0 must be the preamble');
  Check('blockfile.rules.kind1', Blocks[1].Kind = rbkConvert , 'block 1 must be a #convert'  );
  Check('blockfile.rules.header1', Blocks[1].Header = '#convert A.TFrom -> B.TTo', Blocks[1].Header);
  Check('blockfile.rules.startline1', Blocks[1].StartLine = 3, IntToStr(Blocks[1].StartLine));
  Check('blockfile.rules.roundtrip', JoinBlocks(Blocks) = SRC, Format('got %d bytes, want %d', [Length(JoinBlocks(Blocks)), Length(SRC)]));

  // Edge cases: LF-only input keeps LF (terminators are carried, never detected or
  // rewritten), and empty input yields no blocks rather than one empty one.
  Blocks:= SplitRulesBlocks('#convert A.T -> B.T'#10 + '#link P <- Q'#10);
  Check('blockfile.rules.lf.roundtrip', JoinBlocks(Blocks) = '#convert A.T -> B.T'#10 + '#link P <- Q'#10, 'an LF-only file must come back LF-only');
  Check('blockfile.rules.lf.eol', BlockEol(Blocks[0]) = #10, 'BlockEol must report LF');
  Check('blockfile.rules.empty', Length(SplitRulesBlocks('')) = 0, 'empty text = no blocks');
  Check('blockfile.rules.empty.join', JoinBlocks(nil) = '', 'joining nothing yields ''''');

  // ...and against the real file (spec section 11: not only synthetic input).
  P:= TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\..\..\convrules\sample.rules'));
  if not TFile.Exists(P) then
  begin
    Skip('blockfile.rules.roundtrip.file', 'sample.rules not found: ' + P);
    Exit;
  end;
  Text:= TFile.ReadAllText(P, TEncoding.ASCII);
  Blocks:= SplitRulesBlocks(Text);
  Check('blockfile.rules.roundtrip.file', JoinBlocks(Blocks) = Text, Format('got %d bytes, want %d', [Length(JoinBlocks(Blocks)), Length(Text)]));
  { Sanity check: the assertion holds for the fixture AS COMMITTED (2 #convert blocks).
    A working-tree-only fixture state hides test failures from clean checkouts. }
  Check('blockfile.rules.roundtrip.file.blocks', Length(Blocks) >= 2, 'sample.rules has at least 2 #convert blocks');
end; // procedure

{ ABlocks[AIndex].RawText, or '' when AIndex is out of range.

  Load-bearing: these helpers are called with indexes that only EXIST once the
  split under test works. Indexing directly cost a whole RED run -- Blocks[1] on
  a one-block array raised EAccessViolation and killed the runner, so every test
  after this one silently never ran. A failing check must fail, not abort. }
function RawTextAt(const ABlocks: TRuleBlocks; AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex > High(ABlocks)) then
    Result:= ''
  else
    Result:= ABlocks[AIndex].RawText;
end;

{ Counts lines in ABlocks[AIndex] whose first token is ADirective, case-insensitively.
  Local to the trailing-block test; a block carries raw text, not parsed lines.
  Out-of-range yields 0 -- see RawTextAt. }
function CountDirectiveIn(const ABlocks: TRuleBlocks; AIndex: Integer; const ADirective: string): Integer;
var
  L: TRawLine;
begin
  Result:= 0;
  for L in SplitRawLines(RawTextAt(ABlocks, AIndex)) do
    if SameText(FirstToken(L.Text), ADirective) then
      Inc(Result);
end;

{ ABlocks[AIndex].Kind, or rbkPreamble when out of range -- a value that is never
  what a kind assertion wants, so an out-of-range read reports FAIL, not a crash. }
function KindAt(const ABlocks: TRuleBlocks; AIndex: Integer): TRuleBlockKind;
begin
  if (AIndex < 0) or (AIndex > High(ABlocks)) then
    Result:= rbkPreamble
  else
    Result:= ABlocks[AIndex].Kind;
end;

{ ABlocks[AIndex].StartLine, or -1 when out of range. }
function StartLineAt(const ABlocks: TRuleBlocks; AIndex: Integer): Integer;
begin
  if (AIndex < 0) or (AIndex > High(ABlocks)) then
    Result:= -1
  else
    Result:= ABlocks[AIndex].StartLine;
end;

{ ABlocks[AIndex].Header, or a marker that no real header equals. }
function HeaderAt(const ABlocks: TRuleBlocks; AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex > High(ABlocks)) then
    Result:= '(no such block)'
  else
    Result:= ABlocks[AIndex].Header;
end;

{ Criterion 5a: file-scope directives that FOLLOW the last #convert are their OWN
  rbkTrailing block, not part of that rule.

  MEASURED in convrules\BDE-to-FireDAC.rules on 2026-09-09: the last #convert is
  at line 605 and its body ends at '#ignore Transliterate' (631), but 43 #migrate
  lines run from 637 to EOF. Until this split existed all 43 lived inside the
  TBatchMove block's RawText, so composing a selection that excluded that ONE
  block silently dropped every enum and type migration in the book.

  The boundary is a BACKWARD scan from EOF over blank / comment / file-scope
  directive lines, stopping at the first body directive. It is deliberately
  conservative: an UNRECOGNISED directive stops the scan, so unclassified text
  keeps the pre-existing behaviour of attaching to the last block rather than
  being moved. #default is body-scope (convrules\sample.rules:7 sits inside a
  #convert), which the negative controls below pin down. }
procedure TestBlockSplitTrailing;
const
  SRC = '#convert A.TFrom -> B.TTo'#13#10 + '#link Text <- Text'#13#10 + '#ignore Handle'#13#10 + ''#13#10 + '// trailing banner'#13#10 + '#migrate TOld -> TNew, U'#13#10 +
  '#remove Ctl3D'#13#10;
  { Negative control 1: ends on a BODY directive -- no trailing block may appear. }
  SRC_NO_TAIL = '#convert A.TFrom -> B.TTo'#13#10 + '#link Text <- Text'#13#10 + '#ignore Handle'#13#10;
  { Negative control 2: a comment tail with NO file-scope directive in it. Splitting
    here would move text for no benefit and change long-standing behaviour. }
  SRC_COMMENT_TAIL = '#convert A.TFrom -> B.TTo'#13#10 + '#link Text <- Text'#13#10 + ''#13#10 + '// just a closing comment'#13#10;
  { Negative control 3: #default is BODY-scope and must not open a trailing block. }
  SRC_DEFAULT_TAIL = '#convert A.TFrom -> B.TTo'#13#10 + '#link Text <- Text'#13#10 + '#default Charset = 1'#13#10;
var
  Blocks     : TRuleBlocks;
  P          : string     ;
  Text       : string     ;
  i          : Integer    ;
  LastConvert: Integer    ;
  Trailing   : Integer    ;
begin
  Blocks:= SplitRulesBlocks(SRC);
  Check('blockfile.trailing.count', Length(Blocks) = 2, IntToStr(Length(Blocks)));
  Check('blockfile.trailing.kind0', KindAt(Blocks, 0) = rbkConvert , 'block 0 must be the #convert');
  Check('blockfile.trailing.kind1', KindAt(Blocks, 1) = rbkTrailing, 'block 1 must be rbkTrailing' );
  Check('blockfile.trailing.header', HeaderAt(Blocks, 1) = '', 'a trailing block has no header, like a preamble: ' + HeaderAt(Blocks, 1));
  Check('blockfile.trailing.startline', StartLineAt(Blocks, 1) = 4, IntToStr(StartLineAt(Blocks, 1)));
  Check('blockfile.trailing.body.keeps.ignore', CountDirectiveIn(Blocks, 0, '#ignore' ) = 1, 'the #ignore stays with its rule');
  Check('blockfile.trailing.takes.migrate'    , CountDirectiveIn(Blocks, 1, '#migrate') = 1, '#migrate belongs to the tail'   );
  Check('blockfile.trailing.takes.remove'     , CountDirectiveIn(Blocks, 1, '#remove' ) = 1, '#remove is file-scope too'      );
  Check('blockfile.trailing.takes.banner', Pos('// trailing banner', RawTextAt(Blocks, 1)) > 0, 'the banner comment introducing the tail travels with it');
  { The load-bearing invariant of this unit, restated for the new kind. }
  Check('blockfile.trailing.roundtrip', JoinBlocks(Blocks) = SRC, Format('got %d bytes, want %d', [Length(JoinBlocks(Blocks)), Length(SRC)]));

  // Negative controls -- without these, a splitter that ALWAYS emits a trailing
  // block would pass every assertion above.
  Blocks:= SplitRulesBlocks(SRC_NO_TAIL);
  Check('blockfile.trailing.none.body', Length(Blocks) = 1, IntToStr(Length(Blocks)));
  Blocks:= SplitRulesBlocks(SRC_COMMENT_TAIL);
  Check('blockfile.trailing.none.comment', Length(Blocks) = 1, IntToStr(Length(Blocks)));
  Check('blockfile.trailing.none.comment.roundtrip', JoinBlocks(Blocks) = SRC_COMMENT_TAIL, 'a comment-only tail is left where it was');
  Blocks:= SplitRulesBlocks(SRC_DEFAULT_TAIL);
  Check('blockfile.trailing.none.default', Length(Blocks) = 1, '#default is body-scope: ' + IntToStr(Length(Blocks)));

  { And against the REAL book this defect was found in. A synthetic fixture that
    passes proves the rule; only the shipped file proves it fires where it matters. }
  P:= TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\..\..\convrules\BDE-to-FireDAC.rules'));
  if not TFile.Exists(P) then
  begin
    Skip('blockfile.trailing.bde', 'BDE-to-FireDAC.rules not found: ' + P);
    Exit;
  end;
  Text:= TFile.ReadAllText(P, TEncoding.ASCII);
  Blocks:= SplitRulesBlocks(Text);
  Check('blockfile.trailing.bde.roundtrip', JoinBlocks(Blocks) = Text, Format('got %d bytes, want %d', [Length(JoinBlocks(Blocks)), Length(Text)]));

  LastConvert:= -1;
  Trailing   := -1;
  for i:= 0 to High(Blocks) do
  begin
    if Blocks[i].Kind = rbkConvert then
      LastConvert:= i;
    if Blocks[i].Kind = rbkTrailing then
      Trailing:= i;
  end;
  Check('blockfile.trailing.bde.exists', Trailing >= 0, 'the BDE book must yield exactly one trailing block');
  Check('blockfile.trailing.bde.is.last', Trailing = High(Blocks), 'the trailing block is the last block: ' + IntToStr(Trailing));
  Check(
    'blockfile.trailing.bde.migrate.count', CountDirectiveIn(Blocks, Trailing, '#migrate') = 43, 'want 43 #migrate, got ' + IntToStr(CountDirectiveIn(Blocks, Trailing, '#migrate'))
  );
  Check(
    'blockfile.trailing.bde.tbatchmove.clean', CountDirectiveIn(Blocks, LastConvert, '#migrate') = 0,
    'TBatchMove must no longer carry the tail: ' + IntToStr(CountDirectiveIn(Blocks, LastConvert, '#migrate')));
  Check(
    'blockfile.trailing.bde.tbatchmove.keeps.ignore', CountDirectiveIn(Blocks, LastConvert, '#ignore') = 10,
    'its own 10 #ignore lines must stay: ' + IntToStr(CountDirectiveIn(Blocks, LastConvert, '#ignore')));
end; // procedure

{ Criterion 1b: the same byte-faithful round-trip for .castlib, whose blocks are
  'cast <Name> ... end' / 'enum <Name> ... end'. Content before the first block is
  a preamble; content BETWEEN blocks attaches to the preceding block so nothing is
  orphaned. }
procedure TestBlockSplitCastLibRoundTrip;
const
  SRC = '# file header'#13#10 + ''#13#10 + 'cast AssignGraphic'#13#10 + '  accepts TPicture, TBitmap'#13#10 + '  yields  TdxSmartGlyph'#13#10 + 'end'#13#10 + ''#13#10 +
  'enum ButtonLayout'#13#10 + '  ablGlyphLeft -> blGlyphLeft'#13#10 + 'end'#13#10;
var
  Blocks: TRuleBlocks;
  P     : string     ;
  Txt   : string     ;
begin
  Blocks:= SplitCastLibBlocks(SRC);
  Check('blockfile.castlib.count', Length(Blocks) = 3, IntToStr(Length(Blocks)));
  Check('blockfile.castlib.kind0', Blocks[0].Kind = rbkPreamble, 'block 0 preamble');
  Check('blockfile.castlib.kind1', Blocks[1].Kind = rbkCast    , 'block 1 cast'    );
  Check('blockfile.castlib.kind2', Blocks[2].Kind = rbkEnum    , 'block 2 enum'    );
  Check('blockfile.castlib.trailing', Blocks[1].RawText.EndsWith('end'#13#10 + ''#13#10), 'the blank line after "end" must attach to the preceding block');
  Check('blockfile.castlib.roundtrip', JoinBlocks(Blocks) = SRC, Format('got %d bytes, want %d', [Length(JoinBlocks(Blocks)), Length(SRC)]));

  P:= TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\..\..\docs\examples\convrules\casts.castlib'));
  if not TFile.Exists(P) then
  begin
    Skip('blockfile.castlib.roundtrip.file', 'casts.castlib not found: ' + P);
    Exit;
  end;
  Txt:= TFile.ReadAllText(P, TEncoding.ASCII);
  Check('blockfile.castlib.roundtrip.file', JoinBlocks(SplitCastLibBlocks(Txt)) = Txt, 'shipped casts.castlib must round-trip');
end; // procedure

{ Criterion 13: WHERE the open file is a .castlib the grid shows cast/enum block
  NAMES in place of #convert type pairs. BlockLabel is what the grid displays. }
procedure TestBlockLabel;
const
  RULES = '#convert Vcl.Graphics.TFont -> Vcl.Graphics.TFont, Vcl.Graphics'#13#10 + '#link Color <- Color'#13#10;
  LIB   = '# header'#13#10 + 'cast AssignGraphic'#13#10 + 'end'#13#10 + 'enum ButtonLayout'#13#10 + 'end'#13#10;
var
  R: TRuleBlocks;
  L: TRuleBlocks;
begin
  R:= SplitRulesBlocks  (RULES);
  L:= SplitCastLibBlocks(LIB  );
  Check('blocklabel.convert' , BlockLabel(R[0]) = 'Vcl.Graphics.TFont -> Vcl.Graphics.TFont, Vcl.Graphics', BlockLabel(R[0]));
  Check('blocklabel.cast'    , BlockLabel(L[1]) = 'AssignGraphic'                                         , BlockLabel(L[1]));
  Check('blocklabel.enum'    , BlockLabel(L[2]) = 'ButtonLayout'                                          , BlockLabel(L[2]));
  Check('blocklabel.preamble', BlockLabel(L[0]) = '(file header)'                                         , BlockLabel(L[0]));
  // extension chosen by file extension, not by sniffing content
  Check('blockfile.byext.castlib', Length(SplitBlocksFor('x.castlib', LIB  )) = 3, 'castlib grammar by extension');
  Check('blockfile.byext.rules'  , Length(SplitBlocksFor('x.rules'  , RULES)) = 1, 'rules grammar by extension'  );
  // Edge case: a file with nothing but a preamble is one preamble block, not zero
  // and not a malformed convert block.
  var Only: TRuleBlocks:= SplitRulesBlocks('// just a header'#13#10 + '; nothing else'#13#10);
  Check('blockfile.preamble.only', Length(Only) = 1, IntToStr(Length(Only)));
  Check('blockfile.preamble.only.kind', Only[0].Kind = rbkPreamble, 'must be a preamble');
  Check('blockfile.preamble.only.roundtrip', JoinBlocks(Only) = '// just a header'#13#10 + '; nothing else'#13#10, 'must round-trip');
end; // procedure

{ Criteria 3 + 4 + 2: split-out REMOVES the selected blocks from the source and
  writes them to the target in their original relative order; a moved block keeps
  its comments, blank lines and unrecognised directives verbatim.

  Copy-out was RETIRED on 2026-09-09: it wrote the selected blocks to a second file
  and left the source intact, which is exactly the duplicate state FindDuplicates
  reports. A rule may be MOVED between books; it may not be COPIED. }
procedure TestBlockOpsSplit;
const
  SRC = '// file header'#13#10 + '#convert A.T1 -> B.T1'#13#10 + '#link P <- P'#13#10 + '#convert A.T2 -> B.T2'#13#10 + '// hand comment inside the moved block'#13#10 +
  '; semicolon comment'#13#10 + ''#13#10 + '#weird unrecognised directive'#13#10 + '#link Q <- Q'#13#10 + '#convert A.T3 -> B.T3'#13#10 + '#link R <- R'#13#10;
var
  Blocks: TRuleBlocks;
  Rem   : TRuleBlocks;
  Moved : TRuleBlocks;
begin
  Blocks:= SplitRulesBlocks(SRC); // [preamble, T1, T2, T3]
  Check('blockops.setup', Length(Blocks) = 4, IntToStr(Length(Blocks)));

  // criterion 3 -- split out blocks 2 and 3 (T2, T3)
  SplitOut(Blocks, [2, 3], Rem, Moved);
  Check('blockops.split.remaining', Length(Rem  ) = 2, IntToStr(Length(Rem  )));
  Check('blockops.split.moved'    , Length(Moved) = 2, IntToStr(Length(Moved)));
  Check('blockops.split.order', (Moved[0].Header = '#convert A.T2 -> B.T2') and (Moved[1].Header = '#convert A.T3 -> B.T3'), 'original relative order');
  Check('blockops.split.source.lost.t2', Pos('A.T2', JoinBlocks(Rem)) = 0, 'T2 must be gone from the source');
  Check('blockops.split.source.kept.t1', Pos('A.T1', JoinBlocks(Rem)) > 0, 'T1 must survive in the source');

  // criterion 2 -- everything inside the moved block survives verbatim
  Check('blockops.split.keeps.slashcomment', Pos('// hand comment inside the moved block', Moved[0].RawText) > 0, 'lost //');
  Check('blockops.split.keeps.semicomment' , Pos('; semicolon comment'                   , Moved[0].RawText) > 0, 'lost ;' );
  Check('blockops.split.keeps.blankline', Pos(#13#10 + #13#10, Moved[0].RawText) > 0, 'lost blank line');
  Check('blockops.split.keeps.unknown', Pos('#weird unrecognised directive', Moved[0].RawText) > 0, 'lost unknown directive');

end; // procedure

{ Criterion 12: WHILE no blocks are selected the Split and Delete commands are
  disabled. CanOperateOn is the single rule the form's enablement uses.

  Task 5d.0 widened it: a HEADERLESS block -- preamble or trailer -- carries
  file-scope content (#mapping / #remove / #unuse / #migrate) that belongs to no
  single rule, so it may not be split out or deleted from the grid either. Before
  rbkTrailing existed this could only reach the preamble; since 0acff42 it could
  delete the 43-line #migrate tail of convrules\BDE-to-FireDAC.rules. }
procedure TestBlockOpsEnablement;
const
  SRC = '// hdr'#13#10 + '#remove X'#13#10 + '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10 + '#migrate U -> V'#13#10;
var
  B: TRuleBlocks;
begin
  B:= SplitRulesBlocks(SRC);
  { Guard the fixture itself: every assertion below is meaningless if the split
    did not produce [preamble, convert, trailing]. }
  Check(
    'blockops.enable.fixture', (Length(B) = 3) and (B[0].Kind = rbkPreamble) and (B[1].Kind = rbkConvert) and (B[2].Kind = rbkTrailing),
    'want [preamble, convert, trailing], got ' + IntToStr(Length(B)) + ' block(s)');

  Check('blockops.enable.none', not CanOperateOn(B, []), 'empty selection must disable');
  Check('blockops.enable.rule', CanOperateOn(B, [1]), 'one selected rule must enable');
  Check('blockops.enable.preamble', not CanOperateOn(B, [0]), 'a preamble is file-scope and must not be splittable or deletable');
  Check('blockops.enable.trailer' , not CanOperateOn(B, [2]), 'a trailer holds #migrate and must not be splittable or deletable');
  Check('blockops.enable.mixed', not CanOperateOn(B, [0, 1]), 'any headerless block in the selection disables the commands');
  Check('blockops.enable.outofrange', not CanOperateOn(B, [99]), 'an out-of-range index is not a selection');
  { Negative controls: a fix that over-applies -- refusing any selection in a
    file that HAS a preamble, or tripping over a repeated index -- fails here. }
  Check('blockops.enable.rule.dup', CanOperateOn(B, [1, 1]), 'a repeated index is still just one selected rule');
end; // procedure

{ Renders a selection as '[a, b, c]' so a failure message names what came back. }
function IdxStr(const A: TArray<Integer>): string;
var
  i: Integer;
begin
  Result:= '[';
  for i:= 0 to High(A) do
  begin
    if i > 0 then
      Result:= Result + ', ';
    Result:= Result + IntToStr(A[i]);
  end;
  Result:= Result + ']';
end;

function IdxEq(const A, B: TArray<Integer>): Boolean;
var
  i: Integer;
begin
  Result:= Length(A) = Length(B);
  if not Result then
    Exit;
  for i:= 0 to High(A) do
    if A[i] <> B[i] then
      Exit(False);
end;

{ Counts lines of AText whose first token is ADirective. }
function CountDirectiveInText(const AText, ADirective: string): Integer;
var
  L: TRawLine;
begin
  Result:= 0;
  for L in SplitRawLines(AText) do
    if SameText(FirstToken(L.Text), ADirective) then
      Inc(Result);
end;

{ Task 5d.1: a file's contribution to a SELECTIVE compose is every headerless
  block plus the selected rule blocks, in file order.

  This is what replaces atomization (owner ruling 2026-09-09): rules stay in
  multi-rule books and a job picks the ones it needs. The preamble travels
  because an #apply inside a selected block names a #mapping declared there; the
  trailer travels because #migrate is file-scope. }
procedure TestBlockOpsSelection;
const
  SRC = '// hdr'#13#10 + '#remove X'#13#10 + '#convert Bde.DBTables.TAlpha -> B.TBeta'#13#10 + '#link P <- Q'#13#10 + '#convert C.TGamma -> D.TDelta'#13#10 +
  '#link R <- S'#13#10 + '#migrate U -> V'#13#10;
  { A book with neither preamble nor trailer -- it must contribute NOTHING when
    nothing is selected, not "everything" via some all-if-empty shortcut. }
  SRC_BARE = '#convert E.TOne -> F.TTwo'#13#10 + '#link K <- L'#13#10;
var
  B   : TRuleBlocks;
  Bare: TRuleBlocks;
  Got : TRuleBlocks;
begin
  B:= SplitRulesBlocks(SRC);
  Check(
    'select.fixture', (Length(B) = 4) and (B[0].Kind = rbkPreamble) and (B[1].Kind = rbkConvert) and (B[2].Kind = rbkConvert) and (B[3].Kind = rbkTrailing),
    'want [preamble, convert, convert, trailing], got ' + IntToStr(Length(B)));

  Got:= SelectForCompose(B, []);
  Check(
    'select.compose.keeps.headerless', (Length(Got) = 2) and (Got[0].Kind = rbkPreamble) and (Got[1].Kind = rbkTrailing),
    'nothing selected must still yield preamble + trailer, got ' + IntToStr(Length(Got)) + ' block(s)');

  Got:= SelectForCompose(B, [1]);
  Check(
    'select.compose.picks.rule', (Length(Got) = 3) and (Pos('#convert Bde.DBTables.TAlpha', JoinBlocks(Got)) > 0) and (Pos('#convert C.TGamma', JoinBlocks(Got)) = 0),
    'only the selected rule travels');

  { Negative control: an implementation that just returns ABlocks passes this one
    and fails the two above -- which is precisely why it is not the RED. }
  Check('select.compose.all.identity', JoinBlocks(SelectForCompose(B, [1, 2])) = SRC, 'selecting every rule block must reproduce the file byte for byte');

  Check(
    'select.compose.headerless.once', JoinBlocks(SelectForCompose(B, [0, 3])) = JoinBlocks(SelectForCompose(B, [])),
    'naming a headerless block in the selection must not duplicate it');
  Check(
    'select.compose.order', Pos('TAlpha', JoinBlocks(SelectForCompose(B, [2, 1]))) < Pos('TGamma', JoinBlocks(SelectForCompose(B, [2, 1]))),
    'blocks travel in FILE order, not selection order');
  Check('select.compose.outofrange', JoinBlocks(SelectForCompose(B, [99])) = JoinBlocks(SelectForCompose(B, [])), 'a stale index selects nothing');

  Bare:= SplitRulesBlocks(SRC_BARE);
  Check('select.compose.no.preamble.file.none', Length(SelectForCompose(Bare, [])) = 0, 'a file with no headerless blocks contributes nothing when nothing is picked');
  Check('select.compose.no.preamble.file.one', Length(SelectForCompose(Bare, [0])) = 1, 'and exactly its rule when picked');

  Check('select.union', IdxEq(UnionSelections(B, [2, 1], [1, 9]), [1, 2]), IdxStr(UnionSelections(B, [2, 1], [1, 9])));
  Check('select.union.empty', IdxEq(UnionSelections(B, [], []), []), 'union of nothing is nothing');

  Check('select.bytype.hit', IdxEq(BlocksConvertingTypes(B, ['TAlpha']), [1]), IdxStr(BlocksConvertingTypes(B, ['TAlpha'])));
  Check('select.bytype.ci', IdxEq(BlocksConvertingTypes(B, ['talpha']), [1]), 'type matching is case-insensitive, as Pascal is');
  Check('select.bytype.qualified', IdxEq(BlocksConvertingTypes(B, ['Bde.DBTables.TAlpha']), [1]), 'a qualified query matches on the bare name');
  Check('select.bytype.many', IdxEq(BlocksConvertingTypes(B, ['TGamma', 'TAlpha']), [1, 2]), IdxStr(BlocksConvertingTypes(B, ['TGamma', 'TAlpha'])));
  { Negative control: a matcher that returns every rule block passes .hit and
    fails here. }
  Check('select.bytype.miss', IdxEq(BlocksConvertingTypes(B, ['TNothing']), []), IdxStr(BlocksConvertingTypes(B, ['TNothing'])));
  Check('select.bytype.never.headerless', IdxEq(BlocksConvertingTypes(B, ['TAlpha', 'TGamma', 'X', 'U']), [1, 2]), 'a preamble or trailer can never be matched by type');

  Check('select.report.zero', Pos('NO rule blocks', SelectionReportLine('x.rules', B, [])) > 0, SelectionReportLine('x.rules', B, []));
  Check('select.report.some', Pos('1 of 2 rule block(s)', SelectionReportLine('x.rules', B, [1])) > 0, SelectionReportLine('x.rules', B, [1]));
end; // procedure

{ The same, against the real book. A synthetic fixture proves the rule; only the
  shipped corpus proves it fires where the defect actually lives. }
procedure TestBlockOpsSelectionCorpus;
var
  P   : string         ;
  Text: string         ;
  B   : TRuleBlocks    ;
  All : TArray<Integer>;
  i   : Integer        ;
begin
  P:= TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\..\..\convrules\BDE-to-FireDAC.rules'));
  if not TFile.Exists(P) then
  begin
    Skip('select.bde', 'BDE-to-FireDAC.rules not found: ' + P);
    Exit;
  end;
  Text:= TFile.ReadAllText(P, TEncoding.ASCII);
  B:= SplitRulesBlocks(Text);

  Check('select.bde.blocks', Length(B) = 12, IntToStr(Length(B)));
  Check('select.bde.trailer.start', (B[11].StartLine = 632) and (B[10].EndLine = 631), Format('trailer starts %d, TBatchMove ends %d', [B[11].StartLine, B[10].EndLine]));

  { Nothing selected: 145 preamble + 76 trailer. }
  Check('select.bde.none.lines', Length(SplitRawLines(JoinBlocks(SelectForCompose(B, [])))) = 221, IntToStr(Length(SplitRawLines(JoinBlocks(SelectForCompose(B, []))))));
  Check(
    'select.bde.none.content',
    (CountDirectiveInText(JoinBlocks(SelectForCompose(B, [])), '#convert') = 0) and (CountDirectiveInText(JoinBlocks(SelectForCompose(B, [])), '#migrate') = 43),
    'file-scope only: no rules, all 43 #migrate');

  { TDatabase is the block that carries '#apply BdeTransIsolation' (line 173) --
    NOT TQuery, as the parent plan wrongly said. 145 + 39 + 76 = 260. }
  Check('select.bde.tdatabase.lines', Length(SplitRawLines(JoinBlocks(SelectForCompose(B, [2])))) = 260, IntToStr(Length(SplitRawLines(JoinBlocks(SelectForCompose(B, [2]))))));
  Check('select.bde.tdatabase.carries.apply', Pos('#apply BdeTransIsolation', JoinBlocks(SelectForCompose(B, [2]))) > 0, 'the selected rule keeps its #apply');
  Check(
    'select.bde.tdatabase.carries.mapping', Pos('#mapping BdeTransIsolation from', JoinBlocks(SelectForCompose(B, [2]))) > 0,
    'and the preamble brought the declaration that #apply names');
  Check('select.bde.tbatchmove.lines', Length(SplitRawLines(JoinBlocks(SelectForCompose(B, [10])))) = 248, IntToStr(Length(SplitRawLines(JoinBlocks(SelectForCompose(B, [10]))))));

  SetLength(All, 10);
  for i:= 0 to 9 do
    All[i]:= i + 1;
  Check('select.bde.all.identity', JoinBlocks(SelectForCompose(B, All)) = Text, 'selecting all 10 rules must reproduce the book byte for byte');

  Check(
    'select.bde.bytype', IdxEq(BlocksConvertingTypes(B, ['TDatabase', 'TBatchMove', 'TLabel']), [2, 10]), IdxStr(BlocksConvertingTypes(B, ['TDatabase', 'TBatchMove', 'TLabel'])));
end; // procedure

function StrsEq(const A, B: TArray<string>): Boolean;
var
  i: Integer;
begin
  Result:= Length(A) = Length(B);
  if not Result then
    Exit;
  for i:= 0 to High(A) do
    if not SameText(A[i], B[i]) then
      Exit(False);
end;

{ Task 5d.2: every '#apply <Name>' in a COMPOSED text must have its
  '#mapping <Name> from ... to ...' declaration in the same text.

  This is the consumer MappingCatalogFromText and FindDuplicateMappings were
  written for. It runs on the composed output, not on a source book, because a
  composed job book is a GENERATED artifact handed to --rules: a #mapping carried
  into it is not a second authored copy, but an #apply whose declaration stayed
  behind in a book that is not in the working set is one the engine cannot apply. }
procedure TestApplyIntegrity;
const
  DECL  = '#mapping M from E.TEnum to B.TTo'#13#10;
  CONV  = '#convert A.T -> B.T'#13#10;
  APPLY = '#apply M'#13#10;
var
  R: TApplyIntegrity;
begin
  R:= CheckApplyIntegrity(CONV + APPLY);
  Check('apply.check.unsatisfied', StrsEq(R.Unsatisfied, ['M']) and not R.OK, 'an #apply with no declaration must be reported');
  Check('apply.check.summary.names.it', Pos('M', R.Summary) > 0, R.Summary);

  { Negative control: a check that flags every #apply fails here. }
  R:= CheckApplyIntegrity(DECL + CONV + APPLY);
  Check('apply.check.ok', R.OK and (R.Summary = ''), 'a declared mapping satisfies its #apply: ' + R.Summary);

  { A #when/#else CLAUSE repeats the name but is not a declaration -- the model
    marks the declaration with MapFromType <> ''. }
  R:= CheckApplyIntegrity('#mapping M #when X = a -> Y = b'#13#10 + CONV + APPLY);
  Check('apply.check.clause.is.not.decl', StrsEq(R.Unsatisfied, ['M']), 'a clause line is a USE of the name, not a declaration of it');

  R:= CheckApplyIntegrity(DECL + CONV + '#apply m'#13#10);
  Check('apply.check.ci', R.OK, 'names compare case-insensitively, as Pascal does');

  R:= CheckApplyIntegrity(CONV + APPLY + APPLY);
  Check('apply.check.dedup', Length(R.Unsatisfied) = 1, 'one missing name reported once, however often it is applied');

  R:= CheckApplyIntegrity(CONV + '#apply B'#13#10 + '#apply A'#13#10);
  Check('apply.check.order', StrsEq(R.Unsatisfied, ['B', 'A']), 'reported in first-appearance order, not sorted');

  R:= CheckApplyIntegrity(DECL + '#mapping M from E.TEnum to C.TOther'#13#10 + CONV + APPLY);
  Check(
    'apply.check.dup.decl', (Length(R.Unsatisfied) = 0) and (Length(R.DuplicateMappings) = 1) and not R.OK,
    'the #apply is satisfied, but two declarations of one name is still a defect');

  { Negative controls: nothing to check means OK, not "suspicious". }
  R:= CheckApplyIntegrity('');
  Check('apply.check.empty', R.OK, 'empty text is fine');
  R:= CheckApplyIntegrity(CONV + '#link P <- Q'#13#10);
  Check('apply.check.no.apply.no.mapping', R.OK, 'a book with no #apply is fine');
end; // procedure

{ The same against the real book, including the RED the parent plan got wrong. }
procedure TestApplyIntegrityCorpus;
var
  P   : string     ;
  Text: string     ;
  B   : TRuleBlocks;
begin
  P:= TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\..\..\convrules\BDE-to-FireDAC.rules'));
  if not TFile.Exists(P) then
  begin
    Skip('apply.check.bde', 'BDE-to-FireDAC.rules not found: ' + P);
    Exit;
  end;
  Text:= TFile.ReadAllText(P, TEncoding.ASCII);
  B:= SplitRulesBlocks(Text);

  Check('apply.check.bde.whole', CheckApplyIntegrity(Text).OK, 'the shipped book must be self-consistent: ' + CheckApplyIntegrity(Text).Summary);

  { THE RED, corrected. The parent plan said "the TQuery block, #apply
    BdeTransIsolation at line 173, excluding its preamble". Both halves were
    wrong: line 173 is in the TDatabase block (166-204), TQuery (320-421) has no
    #apply at all, and a selection can never exclude the preamble because it
    always travels. Dropping block 0 from the JOIN is how the state is reached. }
  Check(
    'apply.check.bde.no.preamble', StrsEq(CheckApplyIntegrity(JoinBlocks(Copy(B, 1, 11))).Unsatisfied, ['BdeTransIsolation', 'BdeBatchMode']),
    'without the preamble both #apply names are unsatisfied, in line order (173, 609)');

  Check(
    'apply.check.bde.tdatabase.alone', StrsEq(CheckApplyIntegrity(JoinBlocks(Copy(B, 2, 1))).Unsatisfied, ['BdeTransIsolation']),
    'the TDatabase block alone strands the name it applies');

  { And the point of the whole design: with the preamble travelling, a selected
    block IS satisfiable. This makes ruling 3 falsifiable rather than asserted. }
  Check('apply.check.bde.selected.ok', CheckApplyIntegrity(JoinBlocks(SelectForCompose(B, [2]))).OK, 'SelectForCompose carried the declaration that TDatabase applies');
  Check('apply.check.bde.selected.tbatchmove.ok', CheckApplyIntegrity(JoinBlocks(SelectForCompose(B, [10]))).OK, 'and the one TBatchMove applies');
end; // procedure

{ Task 5d.3: the selection lives in the WORKING SET, not in the grid.

  The grid is rebuilt on every file switch, so a selection held there would be
  lost the moment the user looked at another book -- which is exactly the job
  this feature exists to support (pick rules across several books for one
  migration). Indexes are POSITIONAL, so every block-list change resets them. }
procedure TestWorkingSetSelection;
const
  SRC_A = '// hdr'#13#10 + '#remove X'#13#10 + '#convert Bde.DBTables.TAlpha -> B.TBeta'#13#10 + '#link P <- Q'#13#10 + '#convert C.TGamma -> D.TDelta'#13#10 +
  '#link R <- S'#13#10 + '#migrate U -> V'#13#10;
  { No preamble, no trailer: under a selective compose with nothing checked this
    file must contribute NOTHING. }
  SRC_B = '#convert E.TOne -> F.TTwo'#13#10 + '#link K <- L'#13#10;
var
  WS : TWorkingSet   ;
  Rep: TComposeReport;
  t  : string        ;
  W  : string        ;
  n  : Integer       ;
begin
  WS:= TWorkingSet.Create;
  try
    WS.AddText('a.rules', SRC_A);
    WS.AddText('b.rules', SRC_B);
    Check('ws.sel.default.none', not WS.AnySelected, 'a fresh set has no selection');

    WS.SetSelected(0, [1]);
    Check('ws.sel.persists', IdxEq(WS.Selected(0), [1]), IdxStr(WS.Selected(0)));
    Check('ws.sel.any', WS.AnySelected, 'AnySelected must see it');

    WS.SetSelected(0, [0, 1, 3]);
    Check('ws.sel.drops.headerless', IdxEq(WS.Selected(0), [1]), 'preamble and trailer are never selectable: ' + IdxStr(WS.Selected(0)));

    { Positional indexes: any block-list change must clear the selection, or a
      stale index silently points at a different rule. }
    WS.SetSelected(0, [1]);
    WS.SetBlocks(0, SplitRulesBlocks(SRC_A));
    Check('ws.sel.reset.on.setblocks', Length(WS.Selected(0)) = 0, 'SetBlocks must reset the selection');
    WS.SetSelected(0, [1]);
    WS.SyncFromText('a.rules', SRC_A);
    Check('ws.sel.reset.on.sync', Length(WS.Selected(0)) = 0, 'SyncFromText must reset it too');

    { A selection belongs to its FILE, so reordering the set carries it along. }
    WS.SetSelected(1, [0]);
    WS.MoveUp(1);
    Check('ws.sel.follows.moveup', IdxEq(WS.Selected(0), [0]) and (Length(WS.Selected(1)) = 0), 'the selection travels with its file, not with its position');
    WS.MoveDown(0);

    { NEGATIVE CONTROL, and the convention: nothing checked means the whole set,
      which is what Compose did before selections existed. }
    WS.ClearSelection;
    Check('ws.sel.clear', not WS.AnySelected, 'ClearSelection must empty it');
    t:= WS.ComposeSelected(Rep);
    W:= WS.ComposeAll     (Rep);
    Check('ws.compose.selected.none.is.whole', t = W, 'with nothing selected, ComposeSelected IS ComposeAll');

    WS.SetSelected(0, [1]);
    t:= WS.ComposeSelected(Rep);
    Check('ws.compose.selected.picks', (Pos('#convert Bde.DBTables.TAlpha', t) > 0) and (Pos('#convert C.TGamma', t) = 0), 'only the checked rule of a.rules travels');
    Check('ws.compose.selected.headerless.travel', (Pos('#remove X', t) > 0) and (Pos('#migrate U -> V', t) > 0), 'a.rules'' file-scope directives travel with it');
    { b.rules has NO headerless blocks and nothing checked, so it contributes
      nothing at all -- not "everything" via an all-if-empty shortcut. }
    Check('ws.compose.selected.unselected.file.empty', Pos('#convert E.TOne', t) = 0, 'an unselected file with no file-scope content contributes nothing');
    Check('ws.compose.selected.report', Pos('a.rules: 1 of 2 rule block(s)', string.Join(#10, Rep.Lines)) > 0, string.Join(' | ', Rep.Lines));

    WS.ClearSelection;
    n:= WS.SelectByTypes(['TAlpha']);
    Check('ws.sel.bytype', (n = 1) and IdxEq(WS.Selected(0), [1]), Format('n=%d sel=%s', [n, IdxStr(WS.Selected(0))]));
    Check('ws.sel.bytype.idempotent', WS.SelectByTypes(['TAlpha']) = 0, 'selecting the same type again adds nothing');
    { Negative control: a matcher that selects everything passes .bytype. }
    WS.ClearSelection;
    Check('ws.sel.bytype.miss', WS.SelectByTypes(['TNothing']) = 0, 'an unmatched type selects nothing');
    Check('ws.sel.bytype.miss.none', not WS.AnySelected, 'and changes nothing');
  finally
    WS.Free;
  end; // try
end; // procedure

{ 5d.3 against the real book: by-type selection composes a job that is smaller
  than the book and still passes the #apply integrity check. }
procedure TestWorkingSetSelectionCorpus;
var
  WS : TWorkingSet   ;
  Rep: TComposeReport;
  P  : string        ;
  t  : string        ;
  n  : Integer       ;
begin
  P:= TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\..\..\convrules\BDE-to-FireDAC.rules'));
  if not TFile.Exists(P) then
  begin
    Skip('ws.sel.bde', 'BDE-to-FireDAC.rules not found: ' + P);
    Exit;
  end;
  WS:= TWorkingSet.Create;
  try
    WS.AddFile(P);
    n:= WS.SelectByTypes(['TDatabase', 'TSession']);
    Check('ws.sel.bde.bytype', (n = 2) and IdxEq(WS.Selected(0), [1, 2]), Format('n=%d sel=%s', [n, IdxStr(WS.Selected(0))]));

    t:= WS.ComposeSelected(Rep);
    { 145 preamble + 20 TSession + 39 TDatabase + 76 trailer. }
    Check('ws.sel.bde.lines', Length(SplitRawLines(t)) = 280, IntToStr(Length(SplitRawLines(t))));
    Check('ws.sel.bde.integrity', CheckApplyIntegrity(t).OK, 'the composed job must be self-consistent: ' + CheckApplyIntegrity(t).Summary);
    Check('ws.sel.bde.smaller', Length(SplitRawLines(t)) < 707, 'and it must actually be a SUBSET of the book');
  finally
    WS.Free;
  end; // try
end; // procedure

{ Task 5b: '#tag <Name>' is a first-class node kind.

  UNBLOCKED 2026-09-09: the engine tolerates and skips #tag (their c856075),
  deployed as build_date 2026-09-09 10:54:29, so a tagged book validates clean
  and the owner's "no tagged file until it is deployed" rule is satisfied.

  A tag labels the ENCLOSING #convert block. It is parsed, not merely carried:
  the round-trip already worked via rnkUnknown/Raw, so a test that only asserted
  the file survives a save would have passed before this change existed. }
procedure TestTagDirective;
var
  Book: TRuleBook;
  SRC : string   ;
begin
  SRC:= '#convert A.TFrom -> B.TTo'#13#10 + '#tag BDEtoFireDAC'#13#10 + '#tag Modernisation2026'#13#10 + '#link P <- Q'#13#10;
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(SRC);
    Check('parse.kind.tag', Book.Nodes[1].Kind = rnkTag, 'a #tag line must parse as rnkTag, not rnkUnknown');
    Check('parse.tag.name', Book.Nodes[1].TagName = 'BDEtoFireDAC', Book.Nodes[1].TagName);
    { One tag per line, so a rule may carry several -- the reason the DSL does
      not take a comma list is that an editor can then append one tag without
      rewriting an existing line, and a diff shows one added line. }
    Check('parse.tag.second', (Book.Nodes[2].Kind = rnkTag) and (Book.Nodes[2].TagName = 'Modernisation2026'), Book.Nodes[2].TagName);
    Check('parse.tag.emit', Book.Nodes[1].Emit = '#tag BDEtoFireDAC', Book.Nodes[1].Emit);
    { The load-bearing guarantee: parsing a tag must not disturb the book. }
    Check('parse.tag.roundtrip', Book.SaveToString = SRC, 'a tagged book must round-trip byte for byte');
    { NEGATIVE CONTROLS: neither a bare '#tag' nor a look-alike may become one. }
    Check('parse.tag.not.other', Book.Nodes[3].Kind = rnkLink, 'the #link after the tags is still a #link');
  finally
    Book.Free;
  end; // try

  Book:= TRuleBook.Create;
  try
    Book.LoadFromString('#convert A.T -> B.T'#13#10 + '#tagged X'#13#10);
    Check('parse.tag.prefix.not.matched', Book.Nodes[1].Kind <> rnkTag, '#tagged is not #tag -- a prefix match would swallow it');
  finally
    Book.Free;
  end;

  Book:= TRuleBook.Create;
  try
    Book.LoadFromString('#convert A.T -> B.T'#13#10 + '#tag'#13#10);
    Check('parse.tag.bare.name.empty', Book.Nodes[1].TagName = '', 'a nameless #tag carries no name; the ENGINE reports it, we do not invent one');
  finally
    Book.Free;
  end;
end; // procedure

{ Task 5c: the catalog carries each rule's tags, and the on-disk index is v2.

  Tags are read FROM the .rules books on every scan -- the index CACHES them, it
  does not own them. A v1 index is refused whole rather than read as "these rules
  have no tags", which would silently under-report and make a tagged rule
  unfindable by the selection that exists to find it. }
procedure TestCatalogTags;
const
  SRC = '#convert A.TAlpha -> B.TBeta'#13#10 + '#tag BDEtoFireDAC'#13#10 + '#tag Modernisation2026'#13#10 + '#link P <- Q'#13#10 + '#convert C.TGamma -> D.TDelta'#13#10 +
  '#link R <- S'#13#10;
var
  Cat: TRuleCatalog;
  Sel: TRuleCatalog;
  Txt: string      ;
begin
  Cat:= CatalogFromText(SRC, 'x.rules');
  Check('catalog.tags.count', Length(Cat) = 2, IntToStr(Length(Cat)));
  Check(
    'catalog.tags.first', (Length(Cat[0].Tags) = 2) and SameText(Cat[0].Tags[0], 'BDEtoFireDAC') and SameText(Cat[0].Tags[1], 'Modernisation2026'),
    'the first rule carries both of its tags');
  { LEAK GUARD: the scan loop reuses one Entry record, so tags from the previous
    rule must not bleed into the next one. This is the defect a naive field-add
    introduces, and it would look like "the second rule is tagged too". }
  Check('catalog.tags.no.leak', Length(Cat[1].Tags) = 0, 'an untagged rule must have NO tags: ' + IntToStr(Length(Cat[1].Tags)));

  { The block-level and working-set wrappers must agree with the catalog, or the
    UI would select a different set from the one the catalog reports. }
  Check('blocks.withtag.hit', IdxEq(BlocksWithTag(SplitRulesBlocks(SRC), 'BDEtoFireDAC'), [0]), IdxStr(BlocksWithTag(SplitRulesBlocks(SRC), 'BDEtoFireDAC')));
  Check('blocks.withtag.miss' , Length(BlocksWithTag(SplitRulesBlocks(SRC), 'Nope')) = 0, 'an unknown tag matches no block'               );
  Check('blocks.withtag.empty', Length(BlocksWithTag(SplitRulesBlocks(SRC), ''    )) = 0, 'an empty tag matches NOTHING, never everything');

  Sel:= SelectByTag(Cat, 'BDEtoFireDAC');
  Check('catalog.tags.select', (Length(Sel) = 1) and SameText(Sel[0].FromType, 'A.TAlpha'), IntToStr(Length(Sel)));
  Check('catalog.tags.select.ci', Length(SelectByTag(Cat, 'bdetofiredac')) = 1, 'tag matching is case-insensitive, as Pascal is');
  { NEGATIVE CONTROL: a selector that returns everything passes .select. }
  Check('catalog.tags.select.miss', Length(SelectByTag(Cat, 'Nope')) = 0, IntToStr(Length(SelectByTag(Cat, 'Nope'))));
  Check('catalog.tags.select.empty', Length(SelectByTag(Cat, '')) = 0, 'an empty tag selects nothing rather than everything');

  { The index round-trips tags, and announces itself as v2. }
  Txt:= CatalogToIndexText(Cat);
  Check('catalog.index.v2.header', Pos('catalog v2', Txt) > 0, Copy(Txt, 1, 40));
  Check(
    'catalog.index.v2.roundtrip', (Length(CatalogFromIndexText(Txt)) = 2) and (Length(CatalogFromIndexText(Txt)[0].Tags) = 2) and (Length(CatalogFromIndexText(Txt)[1].Tags) = 0),
    'tags must survive a write/read of the index');

  { A v1 index is REFUSED WHOLE, not read as untagged. Reading it would report
    every rule as tagless and make by-tag selection silently find nothing. }
  Check(
    'catalog.index.v1.refused', Length(CatalogFromIndexText('# drag-lint convrules catalog v1'#13#10 + 'A.TAlpha'#9'B.TBeta'#9'x.rules'#9'1'#13#10)) = 0,
    'a v1 index must be refused, not partially understood');
end; // procedure

{ Criterion 5: an incoming #link whose target is already linked FROM THE SAME
  source is a duplicate and is skipped. }
procedure TestMergeSkipsDuplicate;
var
  Plan: TMergePlan ;
  t   : TRuleBlocks;
  i   : TRuleBlocks;
begin
  t:= SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  i:= SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  Plan:= PlanMerge(t, i);
  Check('merge.dup.count', Length(Plan.Items) = 1, IntToStr(Length(Plan.Items)));
  Check('merge.dup.action', Plan.Items[0].Action = maSkipDuplicate, 'must be a skip');
  Check('merge.dup.noconflict', Plan.ConflictCount = 0, 'a duplicate is not a conflict');
end;

{ Criterion 6: an incoming #link whose target is already linked from a DIFFERENT
  source is a conflict; planning reports it and writes nothing -- neither link is
  merged until a resolution is supplied. }
procedure TestMergeReportsConflict;
var
  Plan  : TMergePlan ;
  t     : TRuleBlocks;
  i     : TRuleBlocks;
  k     : Integer    ;
  Merged: Boolean    ;
begin
  t:= SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  i:= SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Z'#13#10);
  Plan:= PlanMerge(t, i);
  Check('merge.conflict.count', Plan.ConflictCount = 1, IntToStr(Plan.ConflictCount));
  Check('merge.conflict.to'          , Plan.Items[0].ToPath       = 'P', Plan.Items[0].ToPath      );
  Check('merge.conflict.existingfrom', Plan.Items[0].ExistingFrom = 'Q', Plan.Items[0].ExistingFrom);
  Check('merge.conflict.incomingfrom', Plan.Items[0].IncomingFrom = 'Z', Plan.Items[0].IncomingFrom);
  Merged:= False;
  for k:= 0 to High(Plan.Items) do
    if Plan.Items[k].Action in [maMergeLink, maMergeOther] then
      Merged:= True;
  Check('merge.conflict.nothing.written', not Merged, 'planning a conflict must not queue either link for writing');
  Check('merge.conflict.target.untouched', JoinBlocks(Plan.Target) = '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10, 'planning must not mutate the target');

  // same target, same source, DIFFERENT cast -> also a conflict (design decision 2)
  t:= SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10        );
  i:= SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q : Round'#13#10);
  Plan:= PlanMerge(t, i);
  Check('merge.conflict.cast', Plan.ConflictCount = 1, 'a differing cast changes the generated assignment, so it is a conflict');
end; // procedure

{ Criterion 7: an already-used SOURCE feeding a NEW target is legal fan-out and is
  merged, not flagged. }
procedure TestMergeAllowsFanOut;
var
  Plan: TMergePlan ;
  t   : TRuleBlocks;
  i   : TRuleBlocks;
begin
  t:= SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  i:= SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link R <- Q'#13#10);
  Plan:= PlanMerge(t, i);
  Check('merge.fanout.noconflict', Plan.ConflictCount = 0, 'fan-out is never a conflict');
  Check('merge.fanout.count', Length(Plan.Items) = 1, IntToStr(Length(Plan.Items)));
  Check('merge.fanout.action', Plan.Items[0].Action = maMergeLink, 'must be merged');
  Check('merge.fanout.line', Plan.Items[0].Line = '#link R <- Q', Plan.Items[0].Line);
end;

{ Criterion 8: an incoming block whose header has no counterpart in the target is
  appended WHOLE and verbatim. }
procedure TestMergeAppendsUnmatchedBlock;
var
  Plan: TMergePlan ;
  t   : TRuleBlocks;
  i   : TRuleBlocks;
begin
  t:= SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  i:= SplitRulesBlocks( '#convert X.T -> Y.T'#13#10 + '// keep me'#13#10 + '#link M <- N'#13#10);
  Plan:= PlanMerge(t, i);
  Check('merge.append.count', Length(Plan.Items) = 1, IntToStr(Length(Plan.Items)));
  Check('merge.append.action', Plan.Items[0].Action = maAppendBlock, 'must append whole');
  Check('merge.append.idx', Plan.Items[0].IncomingBlockIdx = 0, IntToStr(Plan.Items[0].IncomingBlockIdx));
  Check(
    'merge.append.verbatim', Plan.Incoming[Plan.Items[0].IncomingBlockIdx].RawText = '#convert X.T -> Y.T'#13#10 + '// keep me'#13#10 + '#link M <- N'#13#10,
    'the appended block keeps its comment');
  // a header that differs only by its units list does NOT match
  t:= SplitRulesBlocks('#convert A.T -> B.T'#13#10           + '#link P <- Q'#13#10);
  i:= SplitRulesBlocks('#convert A.T -> B.T, SomeUnit'#13#10 + '#link P <- Q'#13#10);
  Plan:= PlanMerge(t, i);
  Check('merge.append.unitsdiffer', Plan.Items[0].Action = maAppendBlock, 'a differing units list is a different rule, so it is appended not merged');
end; // procedure

{ Criterion 9: composing a working set resolves link collisions in favour of the
  EARLIER file and lists every resolved collision in its report. Compose and merge
  share one code path, so this also proves ApplyMerge. }
procedure TestComposePrecedence;
var
  Inputs: TArray<TComposeInput>;
  Report: TComposeReport       ;
  Text  : string               ;
  i     : Integer              ;
  Found : Boolean              ;
begin
  SetLength(Inputs, 2);
  Inputs[0].Path:= 'first.rules';
  Inputs[0].Blocks:= SplitRulesBlocks( '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  Inputs[1].Path:= 'second.rules';
  Inputs[1].Blocks:= SplitRulesBlocks(
    '#convert A.T -> B.T'#13#10 + '#link P <- Z'#13#10 + // collides with first.rules -> earlier wins
    '#link R <- S'#13#10 + // missing -> merged
    '#convert X.T -> Y.T'#13#10 + // no counterpart -> appended whole
    '#link M <- N'#13#10);

  Text:= Compose(Inputs, Report);

  Check('compose.keeps.earlier', Pos('#link P <- Q', Text) > 0, 'earlier link must survive');
  Check('compose.drops.later', Pos('#link P <- Z', Text) = 0, 'later colliding link must not be written');
  Check('compose.merges.missing', Pos('#link R <- S'       , Text) > 0, 'missing link must be merged'     );
  Check('compose.appends.block' , Pos('#convert X.T -> Y.T', Text) > 0, 'unmatched block must be appended');
  Check('compose.resolved.count', Report.ResolvedCount = 1, IntToStr(Report.ResolvedCount));
  Check('compose.appended.count', Report.AppendedCount = 1, IntToStr(Report.AppendedCount));

  Found:= False;
  for i:= 0 to High(Report.Lines) do
    if (Pos('second.rules', Report.Lines[i]) > 0) and (Pos('P', Report.Lines[i]) > 0)
       and (Pos('Z', Report.Lines[i]) > 0) then Found:= True;
  Check('compose.report.names.collision', Found, 'the report must name the file, the target and the losing source');

  // taking the incoming side REPLACES the existing line in place, verbatim
  var Plan: TMergePlan:= PlanMerge(Inputs[0].Blocks, Inputs[1].Blocks);
  var Merged: string:= JoinBlocks(ApplyMerge(Plan, [mrTakeIncoming])) ;
  Check('merge.apply.takeincoming', (Pos('#link P <- Z', Merged) > 0) and (Pos('#link P <- Q', Merged) = 0), 'mrTakeIncoming must replace the existing link');

  // Edge cases: composing nothing yields nothing; composing ONE file is a no-op that
  // returns it byte-for-byte (there is no second file to merge, so nothing is touched).
  var Empty: TComposeReport;
  Check('compose.empty', Compose(nil, Empty) = '', 'an empty working set composes to ''''');
  var One: TArray<TComposeInput>;
  SetLength(One, 1);
  One[0].Path:= 'solo.rules';
  One[0].Blocks:= SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  Check('compose.single.identity', Compose(One, Empty) = '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10, 'composing one file must return it unchanged');
  Check('compose.single.noreport', Length(Empty.Lines) = 0, 'a single file reports nothing');
end; // procedure

{ Criterion 11: a write makes a rotating backup first and never overwrites one. }
procedure TestBackupRotation;
var
  Dir: string;
  P  : string;
  B1 : string;
  B2 : string;
begin
  Dir:= TPath.Combine(TPath.GetTempPath, 'convrules-curation-' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(Dir);
  try
    P:= TPath.Combine(Dir, 'book.rules');
    TFile.WriteAllText(P, 'v1'#13#10, TEncoding.ASCII);

    WriteTextWithBackup(P, 'v2'#13#10, B1);
    Check('backup.first.name', B1 = P + '.bak', B1);
    Check('backup.first.content', TFile.ReadAllText(B1) = 'v1'#13#10, 'backup must hold v1');
    Check('backup.first.written', TFile.ReadAllText(P ) = 'v2'#13#10, 'file must hold v2'  );

    WriteTextWithBackup(P, 'v3'#13#10, B2);
    Check('backup.second.name', B2 = P + '.bak.2', B2);
    Check('backup.second.content' , TFile.ReadAllText(B2) = 'v2'#13#10, 'second backup holds v2'                  );
    Check('backup.first.preserved', TFile.ReadAllText(B1) = 'v1'#13#10, 'the first backup must NOT be overwritten');
  finally
    TDirectory.Delete(Dir, True);
  end; // try
end; // procedure

{ Criterion 14: IF the backup cannot be written THEN the operation aborts and every
  file is left unmodified. An exclusive read lock on the source makes TFile.Copy
  fail deterministically. }
procedure TestBackupFailureAborts;
var
  Dir   : string     ;
  P     : string     ;
  Lock  : TFileStream;
  Bak   : string     ;
  Raised: Boolean    ;
begin
  Dir:= TPath.Combine(TPath.GetTempPath, 'convrules-curation-fail-' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(Dir);
  try
    P:= TPath.Combine(Dir, 'book.rules');
    TFile.WriteAllText(P, 'original'#13#10, TEncoding.ASCII);
    Raised:= False;
    Lock:= TFileStream.Create(P, fmOpenRead or fmShareExclusive);
    try
      try
        WriteTextWithBackup(P, 'replacement'#13#10, Bak);
      except
        on E: Exception do Raised:= True;
      end;
    finally
      Lock.Free;
    end;
    Check('backup.fail.raises', Raised, 'a failed backup must raise, not write');
    Check('backup.fail.file.unmodified', TFile.ReadAllText(P) = 'original'#13#10, 'the target file must be untouched');
    Check('backup.fail.no.backup', not TFile.Exists(P + '.bak'), 'no backup file may be left behind');
  finally
    TDirectory.Delete(Dir, True);
  end; // try
end; // procedure

{ Criterion 10: the composed output is a valid .rules file -- compose two books,
  hand the text to convert-validate and require OK. Skips (does not fail) when the
  drag-lint exe is absent, matching the suite's environment policy. }
procedure TestComposedFileValidates;
var
  Exe  : string         ;
  WS   : TWorkingSet    ;
  Rep  : TComposeReport ;
  Text : string         ;
  eng  : TEngineAdapter ;
  Res  : TValidateResult;
begin
  Exe:= ResolveExe;
  if Exe = '' then
  begin
    Skip('compose.validates', 'drag-lint.exe not found');
    Exit;
  end;
  WS:= TWorkingSet.Create;
  try
    WS.AddText('first.rules', '#convert Vcl.Graphics.TFont -> Vcl.Graphics.TFont'#13#10 + '#link Color <- Color'#13#10 + '#link Height <- Height'#13#10);
    WS.AddText('second.rules', '#convert Vcl.Graphics.TFont -> Vcl.Graphics.TFont'#13#10 + '#link Color <- Name'#13#10 + // collides -> earlier wins
      '#link Size <- Size'#13#10 + // merged
      '#convert Vcl.StdCtrls.TEdit -> Vcl.StdCtrls.TMemo'#13#10 + '#link Text <- Text'#13#10); // appended whole
    Text:= WS.ComposeAll(Rep);
    Check('compose.validates.resolved', Rep.ResolvedCount = 1, IntToStr(Rep.ResolvedCount));

    eng:= TEngineAdapter.Create(Exe, []);
    try
      Res:= eng.ValidateText(Text, '', '');
      Check('compose.validates', Res.OK, 'convert-validate rejected the composed file: ' + Res.FirstError + ' | text=' + StringReplace(Text, #13#10, '\n', [rfReplaceAll]));
    finally
      eng.Free;
    end;
  finally
    WS.Free;
  end; // try
end; // procedure

{ Criterion 5 (the maMergeOther half, previously untested): within a matched block,
  a non-#link incoming line new to the target is merged verbatim (maMergeOther); one
  already present -- an EXACT match after trimming -- is not re-added; the header
  line itself is never treated as "other" content; and the dedup is case-SENSITIVE,
  so a duplicate that differs only in case is genuinely new content and must be
  kept, not silently dropped (design decision: "identical" means exact, not
  case-folded -- non-#link content is never dropped). }
procedure TestMergeOtherLines;
var
  Plan         : TMergePlan ;
  t            : TRuleBlocks;
  i            : TRuleBlocks;
  k            : Integer    ;
  OtherCount   : Integer    ;
  SawKeepMeCase: Boolean    ;
  SawDefault   : Boolean    ;
  SawExactDup  : Boolean    ;
begin
  t:= SplitRulesBlocks( '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10 + '// Keep me'#13#10);
  i:= SplitRulesBlocks( '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10 + '// Keep me'#13#10 + '// KEEP ME'#13#10 + '#default X = 1'#13#10);
  Plan:= PlanMerge(t, i);

  Check('merge.other.itemcount', Length(Plan.Items) = 3, IntToStr(Length(Plan.Items)));

  OtherCount   := 0;
  SawKeepMeCase:= False;
  SawDefault   := False;
  SawExactDup  := False;
  for k:= 0 to High(Plan.Items) do
    if Plan.Items[k].Action = maMergeOther then
    begin
      Inc(OtherCount);
      if Plan.Items[k].Line = '// KEEP ME' then
        SawKeepMeCase:= True;
      if Plan.Items[k].Line = '#default X = 1' then
        SawDefault:= True;
      if Plan.Items[k].Line = '// Keep me' then
        SawExactDup:= True;
    end;

  Check('merge.other.count', OtherCount = 2, IntToStr(OtherCount));
  Check('merge.other.default.verbatim', SawDefault, 'a #default line new to the target must merge verbatim');
  Check('merge.other.casediff.kept', SawKeepMeCase, 'a duplicate differing only in case is not identical -- it must be kept, not deduped');
  Check('merge.other.exactdup.skipped', not SawExactDup, 'an exact (post-trim) duplicate already in the target must not be re-added');

  // The incoming block's header line must never itself be treated as "other"
  // content. Proven with a header differing only by case from the target's, so a
  // regression that stopped skipping the header line (the i0 index in
  // BlockOtherLines) would surface as a spurious extra item, not silently pass by
  // matching case-insensitively.
  t:= SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  i:= SplitRulesBlocks('#CONVERT A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  Plan:= PlanMerge(t, i);
  Check('merge.other.header.excluded', Length(Plan.Items) = 1, IntToStr(Length(Plan.Items)));
  Check('merge.other.header.excluded.action', Plan.Items[0].Action = maSkipDuplicate, 'only the identical #link should appear; the header must never become a maMergeOther item');
end; // procedure

{ ConcatBlocks is documented PURE, so it must not write through to the array it was
  handed. Delphi dynamic arrays are REFERENCES and an element write does NOT
  copy-on-write -- only SetLength uniquifies -- so 'Result := AFirst' followed by
  'Result[High(Result)] := ...' edits the caller's array too. TWorkingSet.Item hands
  out a record whose Blocks field shares the list's array, so the mutation would land
  on the loaded file itself. }
procedure TestConcatBlocksPure;
var
  A     : TRuleBlocks;
  B     : TRuleBlocks;
  Before: string     ;
  WS    : TWorkingSet;
begin
  // A's last block is deliberately UNTERMINATED -- that is what ConcatBlocks fixes up
  A:= SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'      );
  B:= SplitRulesBlocks('#convert X.T -> Y.T'#13#10 + '#link M <- N'#13#10);
  Before:= JoinBlocks(A);

  Check(
    'concat.joins', JoinBlocks(ConcatBlocks(A, B)) = '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10 + '#convert X.T -> Y.T'#13#10 + '#link M <- N'#13#10,
    StringReplace(JoinBlocks(ConcatBlocks(A, B)), #13#10, '\n', [rfReplaceAll]));
  Check('concat.input.unmutated', JoinBlocks(A) = Before, 'ConcatBlocks must not terminate the CALLER''s last block: ' + StringReplace(JoinBlocks(A), #13#10, '\n', [rfReplaceAll]));

  // and through a working set: the stored blocks must survive a concat unchanged
  WS:= TWorkingSet.Create;
  try
    WS.AddText('book.rules', '#convert A.T -> B.T'#13#10 + '#link P <- Q');
    ConcatBlocks(WS.Item(0).Blocks, B);
    Check(
      'concat.workingset.unmutated', JoinBlocks(WS.Item(0).Blocks) = '#convert A.T -> B.T'#13#10 + '#link P <- Q',
      'ConcatBlocks must not edit the working set''s stored blocks: ' + StringReplace(JoinBlocks(WS.Item(0).Blocks), #13#10, '\n', [rfReplaceAll]));
  finally
    WS.Free;
  end;
end; // procedure

{ Three counters must agree that "row i of the resolution dialog is the i-th
  maConflict item in PLAN ORDER": ApplyMerge's conflict ordinal, MergeReportLines'
  conflict ordinal, and the dialog's row order. A mismatch would apply the user's
  choice to a DIFFERENT conflict and report a third -- silently wrong data, no
  exception. Every other merge test has at most ONE conflict, where any mismatch is
  invisible; TWO conflicts with DIFFERENT resolutions pin the mapping down. }
procedure TestMergeConflictOrdinals;
var
  t      : TRuleBlocks   ;
  i      : TRuleBlocks   ;
  Plan   : TMergePlan    ;
  Merged : string        ;
  Rep    : TArray<string>;
  Ords   : TArray<string>;
  k      : Integer       ;
  n      : Integer       ;
  SawKept: Boolean       ;
  SawTook: Boolean       ;
begin
  t:= SplitRulesBlocks( '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10 + '#link R <- S'#13#10);
  i:= SplitRulesBlocks(
    '#convert A.T -> B.T'#13#10 + '#link P <- Q2'#13#10 + // conflict ordinal 0
    '#link R <- S2'#13#10); // conflict ordinal 1
  Plan:= PlanMerge(t, i);
  Check('merge.ord.count', Plan.ConflictCount = 2, IntToStr(Plan.ConflictCount));

  // the dialog builds one row per maConflict item in plan order, so a row's
  // position IS its ordinal -- that order is asserted here
  SetLength(Ords, Plan.ConflictCount);
  n:= 0;
  for k:= 0 to High(Plan.Items) do
    if Plan.Items[k].Action = maConflict then
    begin
      Ords[n]:= Plan.Items[k].ToPath;
      Inc(n);
    end;
  Check('merge.ord.order', (Length(Ords) = 2) and (Ords[0] = 'P') and (Ords[1] = 'R'), 'conflict 0 must be P and conflict 1 must be R');

  // ordinal 0 -> keep existing, ordinal 1 -> take incoming
  Merged:= JoinBlocks(ApplyMerge(Plan, [mrKeepExisting, mrTakeIncoming]));
  Check(
    'merge.ord.0.kept', (Pos('#link P <- Q'#13#10, Merged) > 0) and (Pos('#link P <- Q2', Merged) = 0),
    'conflict 0 was mrKeepExisting, so P must still come from Q: ' + StringReplace(Merged, #13#10, '\n', [rfReplaceAll]));
  Check(
    'merge.ord.1.took', (Pos('#link R <- S2', Merged) > 0) and (Pos('#link R <- S'#13#10, Merged) = 0),
    'conflict 1 was mrTakeIncoming, so R must now come from S2: ' + StringReplace(Merged, #13#10, '\n', [rfReplaceAll]));

  // the report must describe the SAME two decisions, not a third pairing
  Rep:= MergeReportLines(Plan, [mrKeepExisting, mrTakeIncoming], 'inc.rules');
  SawKept:= False;
  SawTook:= False;
  for k:= 0 to High(Rep) do
  begin
    if (Pos('conflict on P', Rep[k]) > 0) and (Pos('kept earlier', Rep[k]) > 0) then
      SawKept:= True;
    if (Pos('conflict on R', Rep[k]) > 0) and (Pos('took incoming', Rep[k]) > 0) then
      SawTook:= True;
  end;
  Check('merge.ord.report.0', SawKept, 'the report must say conflict 0 (P) kept the existing link');
  Check('merge.ord.report.1', SawTook, 'the report must say conflict 1 (R) took the incoming link');
end; // procedure

{ TWorkingSet's header justifies being VCL-free with "so the ordering and composition
  logic is unit-tested headlessly", but only the free file helpers were covered. This
  exercises the class: add/count/item, IndexOfPath (including two SPELLINGS of one
  file), the ordering commands as COMPOSITION PRECEDENCE (criterion 9's user control
  -- moving a file must change which link wins), SetBlocks actually persisting through
  the TList<record> read-modify-write, and Remove. }
procedure TestWorkingSetOps;
var
  WS  : TWorkingSet   ;
  Rep : TComposeReport;
  Text: string        ;
begin
  WS:= TWorkingSet.Create;
  try
    WS.AddText('C:\books\first.rules' , '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
    WS.AddText('C:\books\second.rules', '#convert A.T -> B.T'#13#10 + '#link P <- Z'#13#10);

    Check('ws.count', WS.Count = 2, IntToStr(WS.Count));
    Check('ws.item.path', WS.Item(1).Path = 'C:\books\second.rules', WS.Item(1).Path);
    Check('ws.item.blocks', Length(WS.Item(0).Blocks) = 1, IntToStr(Length(WS.Item(0).Blocks)));

    Check('ws.indexof', WS.IndexOfPath('C:\books\second.rules') = 1, IntToStr(WS.IndexOfPath('C:\books\second.rules')));
    Check('ws.indexof.case', WS.IndexOfPath('c:\BOOKS\SECOND.RULES') = 1, 'path comparison is case-insensitive on Windows');
    Check(
      'ws.indexof.spelling', WS.IndexOfPath('C:\books\sub\..\second.rules') = 1,
      'two spellings of ONE file must resolve to the same entry, or the duplicate-add ' + 'check, the split-target guard and the write-back sync all miss it');
    Check('ws.indexof.missing', WS.IndexOfPath('C:\books\other.rules') = -1, 'an unloaded path is not in the set');

    // order IS precedence: the EARLIER file wins the P collision
    Text:= WS.ComposeAll(Rep);
    Check(
      'ws.compose.precedence', (Pos('#link P <- Q', Text) > 0) and (Pos('#link P <- Z', Text) = 0),
      'the file nearest the top must win: ' + StringReplace(Text, #13#10, '\n', [rfReplaceAll]));

    WS.MoveUp(1);
    Check('ws.moveup.order', WS.Item(0).Path = 'C:\books\second.rules', WS.Item(0).Path);
    Text:= WS.ComposeAll(Rep);
    Check(
      'ws.compose.after.moveup', (Pos('#link P <- Z', Text) > 0) and (Pos('#link P <- Q', Text) = 0),
      'moving a file up must promote ITS choices -- that is what the button is for: ' + StringReplace(Text, #13#10, '\n', [rfReplaceAll]));

    WS.MoveDown(0);
    Check('ws.movedown.order', WS.Item(0).Path = 'C:\books\first.rules', WS.Item(0).Path);
    WS.MoveUp(0); // already at the top
    WS.MoveDown(WS.Count - 1); // already at the bottom
    Check('ws.move.edges.noop', (WS.Count = 2) and (WS.Item(0).Path = 'C:\books\first.rules'), 'moving past either end must be a no-op, not a swap or a crash');

    // SetBlocks must really persist: TList<record> hands out a COPY, so editing
    // Item(i).Blocks in place would be silently lost
    WS.SetBlocks(0, DeleteBlocks(WS.Item(0).Blocks, [0]));
    Check('ws.setblocks.persists', Length(WS.Item(0).Blocks) = 0, IntToStr(Length(WS.Item(0).Blocks)));

    WS.Remove(0);
    Check('ws.remove.count', WS.Count = 1, IntToStr(WS.Count));
    Check('ws.remove.kept', WS.Item(0).Path = 'C:\books\second.rules', WS.Item(0).Path);
    WS.Remove(99);
    Check('ws.remove.oob.noop', WS.Count = 1, 'an out-of-range Remove is a no-op');
  finally
    WS.Free;
  end; // try
end; // procedure

{ A split/copy/compose that writes to a file which is ALSO in the working set used to
  leave that file's in-memory blocks STALE: the grid hid the moved block, Compose
  folded the stale model (so the file handed to --rules silently omitted the moved
  rule), and the next Delete/Merge on that member saved the stale model back over it.
  SyncFromText is the write-back -- after a successful write the owning entry
  re-splits the EXACT text written, so model and disk agree. }
procedure TestWorkingSetSyncFromText;
var
  WS     : TWorkingSet   ;
  Rem    : TRuleBlocks   ;
  Moved  : TRuleBlocks   ;
  NewText: string        ;
  Rep    : TComposeReport;
begin
  WS:= TWorkingSet.Create;
  try
    WS.AddText('C:\books\book1.rules', '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10 + '#convert X.T -> Y.T'#13#10 + '#link M <- N'#13#10);
    WS.AddText('C:\books\book2.rules', '#convert C.T -> D.T'#13#10 + '#link R <- S'#13#10);

    // split block 1 of book1 OUT into book2 -- both are in the set
    SplitOut(WS.Item(0).Blocks, [1], Rem, Moved);
    NewText:= JoinBlocks(ConcatBlocks(WS.Item(1).Blocks, Moved)); // what gets written

    Check('ws.sync.notinset', WS.SyncFromText('C:\books\elsewhere.rules', NewText) = -1, 'a path outside the set must not be synced onto any entry');
    Check('ws.sync.index', WS.SyncFromText('C:\books\SUB\..\book2.rules', NewText) = 1, 'the write-back must find the entry whatever the path was spelled like');
    WS.SetBlocks(0, Rem);

    Check('ws.sync.blocks', Length(WS.Item(1).Blocks) = 2, IntToStr(Length(WS.Item(1).Blocks)));
    Check('ws.sync.model.matches.disk', JoinBlocks(WS.Item(1).Blocks) = NewText, 'the in-memory model must equal the text that was written');
    Check('ws.sync.compose.has.moved', Pos('#convert X.T -> Y.T', WS.ComposeAll(Rep)) > 0, 'the moved block must survive composition -- a stale model dropped it silently');
  finally
    WS.Free;
  end; // try
end; // procedure

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
  Check('grammar.castlib.case', GrammarOf('C:\x\CASTS.CASTLIB') = rgCastLib, 'the extension test is case-insensitive, exactly as SplitBlocksFor does it');
  Check('grammar.refind', GrammarOf('C:\x\refind.txt') = rgRules, 'SplitBlocksFor reads everything that is not .castlib with the DSL grammar');
  Check('grammar.name.differ', GrammarName(rgRules) <> GrammarName(rgCastLib), 'a refusal message has to be able to name both sides');

  WS:= TWorkingSet.Create;
  try
    Check('ws.mixed.empty', not WS.MixedGrammars, 'an empty set is not mixed');
    WS.AddText('a.rules', '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
    Check('ws.mixed.single', not WS.MixedGrammars, 'one file is never mixed');
    WS.AddText('b.rules', '#convert C.T -> D.T'#13#10 + '#link R <- S'#13#10);
    Check('ws.mixed.homogeneous', not WS.MixedGrammars, 'two .rules files compose fine');
    WS.AddText('c.castlib', 'cast Foo'#13#10 + '  accepts TIcon'#13#10 + 'end'#13#10);
    Check('ws.mixed.detected', WS.MixedGrammars, 'a catalog among .rules files must block Compose, not be emitted as ' + '''cast ... end'' into a file meant for --rules');
  finally
    WS.Free;
  end; // try
end; // procedure

{ The cross-grammar guard above cannot catch a .castlib merged into a .castlib --
  both sides are the SAME grammar -- yet that is exactly the corruption: a cast/enum
  block's RawText INCLUDES its closing 'end' line, and AppendLinesToBlock appends at
  the very end of RawText, so an incoming body line lands AFTER 'end'. The second
  half of this test PINS that broken behaviour, so the guard cannot later be dropped
  as unnecessary; the first half is the guard itself. }
procedure TestCastLibMergeRefused;
var
  t     : TRuleBlocks;
  i     : TRuleBlocks;
  Plan  : TMergePlan ;
  Merged: string     ;
  pEnd  : Integer    ;
  pNew  : Integer    ;
begin
  Check('grammar.merge.rules', GrammarAcceptsMerge(rgRules), 'a #convert block has no terminator line, so the merger can append into it');
  Check('grammar.merge.castlib', not GrammarAcceptsMerge(rgCastLib), 'a cast/enum block carries its own ''end'' line, so an append lands outside the body');

  t:= SplitCastLibBlocks('cast Foo'#13#10 + '  accepts TBitmap'#13#10 + 'end'#13#10);
  i:= SplitCastLibBlocks('cast Foo'#13#10 + '  accepts TIcon'#13#10   + 'end'#13#10);
  Plan:= PlanMerge(t, i);
  Check('castlib.merge.plans.silently', Plan.ConflictCount = 0, 'nothing warns the user: the incoming body line is planned as ordinary content');

  Merged:= JoinBlocks(ApplyMerge(Plan, nil));
  pEnd:= Pos('end'#13#10    , Merged);
  pNew:= Pos('accepts TIcon', Merged);
  Check(
    'castlib.merge.corrupts', (pEnd > 0) and (pNew > pEnd),
    'the incoming body line lands AFTER ''end'', outside the cast block -- this is '
      + 'why a catalog TARGET is refused outright rather than merged: '
      + StringReplace(Merged, #13#10, '\n', [rfReplaceAll])
  );
end; // procedure

{ The split/copy target dialog deliberately has NO overwrite prompt (a backup is
  written instead of clobbering), so an append into an existing book gives the user
  no other signal. The status line says "appended", and appending a #convert header
  the target ALREADY has leaves two blocks for one rule -- dead weight worth warning
  about. DuplicateHeaders is what that warning is built from. }
procedure TestDuplicateHeaders;
var
  Existing: TRuleBlocks;
begin
  Existing:= SplitRulesBlocks( '// file header'#13#10 + '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);

  var Dup: TArray<string>:= DuplicateHeaders(Existing, SplitRulesBlocks( '#convert a.t -> b.t'#13#10 + '#link P <- Z'#13#10 + '#convert X.T -> Y.T'#13#10 + '#link M <- N'#13#10));
  Check('dup.count', Length(Dup) = 1, IntToStr(Length(Dup)));
  Check('dup.header.reported', (Length(Dup) = 1) and (Pos('a.t -> b.t', Dup[0]) > 0), 'the duplicated header is named so the warning is actionable');

  Check('dup.none', Length(DuplicateHeaders(Existing, SplitRulesBlocks('#convert Z.T -> W.T'#13#10 + '#link P <- Q'#13#10))) = 0, 'a genuinely new header is not a duplicate');
  Check('dup.preamble.ignored', Length(DuplicateHeaders(Existing, SplitRulesBlocks('// file header'#13#10))) = 0, 'a preamble has no header, so it can never be a duplicate');
end;

{ Criteria 1-6: the DFM scanner records the assignments of blocks whose class is the
  From class, at that block's immediate level only, skipping binary blobs and nested
  components -- but descending into nested blocks to find further instances. }
procedure TestScanDfm;
const
  SRC = 'object Form1: TForm1'#13#10 + '  Caption = ''ignored -- wrong class'''#13#10 + '  object btnA: TabcToggleBtn'#13#10 + '    Left = 4'#13#10 + '    Top = 175'#13#10 +
  '    Caption = ''Ac'''#13#10 + '    Layout = ablGlyphCenter'#13#10 + '    Picture.Data = {'#13#10 + '      07544269746D617076080000424D7606'#13#10 +
  '      Width = 999'#13#10 + // inside the blob: must NOT be recorded
  '      0000200000000100040000000000}'#13#10 + '    Columns = <'#13#10 + '      item'#13#10 + '        Height = 888'#13#10 + // inside the item list: must NOT be recorded
  '      end>'#13#10 + '    object lblChild: TLabel'#13#10 + '      Alignment = taLeftJustify'#13#10 + // child component: NOT the From class
  '    end'#13#10 + '  end'#13#10 + '  object btnB: TabcToggleBtn'#13#10 + '    Hint = ''second instance'''#13#10 + '  end'#13#10 + 'end'#13#10;

  function Has(const A: TArray<string>; const S: string): Boolean;
  var
    x: string;
  begin
    for x in A do
      if SameText(x, S) then
        Exit(True);
    Result:= False;
  end;

var
  U: TArray<string>;
begin
  U:= ScanDfmText(SRC, 'TabcToggleBtn');
  Check('usage.dfm.left'   , Has(U, 'Left'        ), 'plain assignment'                 );
  Check('usage.dfm.caption', Has(U, 'Caption'     ), 'plain assignment'                 );
  Check('usage.dfm.layout' , Has(U, 'Layout'      ), 'plain assignment'                 );
  Check('usage.dfm.dotted' , Has(U, 'Picture.Data'), 'dotted path recorded whole'       );
  Check('usage.dfm.dotroot', Has(U, 'Picture'     ), 'dotted path also records its root');
  Check('usage.dfm.blob'    , not Has(U, 'Width'    ), 'a line inside a { } blob is not an assignment'     );
  Check('usage.dfm.itemlist', not Has(U, 'Height'   ), 'a line inside a < > item list is not an assignment');
  Check('usage.dfm.child'   , not Has(U, 'Alignment'), 'a nested component is not the From class'          );
  Check('usage.dfm.sibling', Has(U, 'Hint'), 'a second instance of the From class is scanned');
  Check('usage.dfm.wrongclass', not Has(U, 'ignored'), 'the outer TForm1 block is not scanned');
  Check('usage.dfm.none', Length(ScanDfmText(SRC, 'TNotPresent')) = 0, 'no block of the From class yields an empty set');
end; // begin

{ Criteria 7-10: loose '.PropName' matching in a .pas, candidate derivation from the
  From tree, the row test, and case-insensitive de-duplication across files. }
procedure TestScanPasAndMatch;
const
  Pas = 'procedure TForm1.Go;'#13#10 + 'begin'#13#10 + '  btnA.Caption := ''x'';'#13#10 + '  with btnA do Layout := ablGlyphLeft;'#13#10 + // no dot: NOT matched, by design
  '  Self.CaptionExtra := 1;'#13#10 + // must not mark Caption used
  '  lbl.Font.Size := 9;'#13#10 + 'end;'#13#10;

  function Has(const A: TArray<string>; const S: string): Boolean;
  var
    x: string;
  begin
    for x in A do
      if SameText(x, S) then
        Exit(True);
    Result:= False;
  end;

var
  Cand: TArray<string>;
  U   : TArray<string>;
  M   : TArray<string>;
begin
  Cand:= CandidatesFor(['Caption', 'Layout', 'Font.Size', 'Hint']);
  Check('usage.cand.leaf' , Has(Cand, 'Size'     ), 'last segment of a dotted path is a candidate');
  Check('usage.cand.full' , Has(Cand, 'Font.Size'), 'the full dotted path is a candidate'         );
  Check('usage.cand.plain', Has(Cand, 'Caption'  ), 'plain names are candidates'                  );

  U:= ScanPasText(Pas, Cand);
  Check('usage.pas.hit', Has(U, 'Caption'), '.Caption is used');
  Check('usage.pas.boundary', not Has(U, 'Hint'), 'Hint never appears');
  Check('usage.pas.suffix', Has(U, 'Caption'), 'CaptionExtra must not be the only reason');
  Check('usage.pas.nested', Has(U, 'Size'   ), '.Size matches through lbl.Font.Size'     );
  Check('usage.pas.nodot', not Has(U, 'Layout'), 'a with-block assignment has no dot, so the loose match cannot see it');

  // criterion 8 in isolation: a longer identifier must not mark the shorter one used
  Check('usage.pas.notprefix', not Has(ScanPasText('  x.CaptionExtra := 1;'#13#10, ['Caption']), 'Caption'), '.CaptionExtra must not mark Caption used');

  // criterion 9: the row test
  Check('usage.row.exact', IsRowUsed('Caption'  , ['caption'  ]), 'case-insensitive exact path');
  Check('usage.row.leaf' , IsRowUsed('Font.Size', ['Size'     ]), 'last segment matches'       );
  Check('usage.row.full' , IsRowUsed('Font.Size', ['Font.Size']), 'full path matches'          );
  Check('usage.row.miss', not IsRowUsed('Font.Size', ['Color']), 'unrelated name does not match');

  // criterion 10: merge de-duplicates case-insensitively
  M:= MergeUsage([TArray<string>.Create('Caption', 'Left'), TArray<string>.Create('caption', 'Top')]);
  Check('usage.merge.count', Length(M) = 3, IntToStr(Length(M)));
end; // begin

{ Criterion 11 plus the orchestration: ComputeUsage merges both sources, counts files, and
  reports used names with no From-tree leaf. Also pins criterion 1 against the REAL block
  shape from ORM3\CLIENT\VARINSP.dfm (an ABC5 TabcToggleBtn with a Picture.Data blob),
  copied here as a fixture so the suite never depends on a path outside the repo. }
procedure TestComputeUsage;
const
  REAL_DFM = '            object btnEWAcAQL: TabcToggleBtn'#13#10 + '              Left = 4'#13#10 + '              Top = 175'#13#10 + '              Width = 44'#13#10 +
  '              Height = 39'#13#10 + '              GroupIndex = 58114708'#13#10 + '              Caption = ''Ac'''#13#10 + '              Images = imlGlyphList'#13#10 +
  '              Layout = ablGlyphCenter'#13#10 + '              Picture.Data = {'#13#10 +
  '                07544269746D617076080000424D760800000000000076000000280000008000'#13#10 +
  '                0000200000000100040000000000000800000000000000000000100000000000}'#13#10 + '            end'#13#10;
  Pas = '  btnEWAcAQL.Enabled := True;'#13#10;

  function Has(const A: TArray<string>; const S: string): Boolean;
  var
    x: string;
  begin
    for x in A do
      if SameText(x, S) then
        Exit(True);
    Result:= False;
  end;

var
  U: TUsageSet;
begin
  U:= ComputeUsage(
    [REAL_DFM], [Pas], 'TabcToggleBtn', ['Left', 'Top', 'Width', 'Height', 'GroupIndex', 'Caption', 'Images', 'Layout', 'Picture', 'Picture.Data', 'Enabled', 'Hint']);

  Check('usage.compute.dfmcount', U.DfmCount = 1, IntToStr(U.DfmCount));
  Check('usage.compute.pascount', U.PasCount = 1, IntToStr(U.PasCount));
  Check('usage.compute.dfm', Has(U.Names, 'GroupIndex'), 'from the DFM');
  Check('usage.compute.pas', Has(U.Names, 'Enabled'   ), 'from the PAS');
  Check('usage.compute.blob', not Has(U.Names, '07544269746D617076080000424D760800000000000076000000280000008000'), 'hex blob lines are not names');
  Check('usage.compute.unused', not Has(U.Names, 'Hint'), 'Hint is used nowhere');
  Check('usage.compute.nomissing', Length(U.Missing) = 0, 'every used name has a From-tree leaf here');

  // THE VARINSP DEFECT, end to end at the level the grid calls. Before the receiver
  // filter this returned 'Popup' in Names -- the green mark the user could not explain,
  // because F7Actions is a TdxBarPopupMenu and no TabcToggleBtn on the form sets Popup.
  // ComputeUsage must derive the receivers ('btnEWAcAQL') from the .dfm it was handed.
  U:= ComputeUsage([REAL_DFM], ['  F7Actions.Popup(400,300);'#13#10], 'TabcToggleBtn', ['Caption', 'Popup']);
  Check('usage.compute.rcv.foreign', not Has(U.Names, 'Popup'), 'another class''s .Popup is not a use of ours');
  Check('usage.compute.rcv.loose', Has(U.Loose, 'Popup'), 'and it is reported as loose, not silently dropped');
  Check('usage.compute.rcv.control', Has(ComputeUsage([REAL_DFM], ['  btnEWAcAQL.Popup(400,300);'#13#10], 'TabcToggleBtn', ['Caption', 'Popup']).Names, 'Popup'),
    'POSITIVE CONTROL: the SAME call on one of OUR instances IS a use');
  Check('usage.compute.rcv.dfmwins', not Has(ComputeUsage([REAL_DFM], ['  Other.Caption := ''x'';'#13#10], 'TabcToggleBtn', ['Caption']).Loose, 'Caption'),
    'a name the .dfm confirmed is never also reported as loose');

  // criterion 11: a used name with no From-tree leaf is reported
  U:= ComputeUsage([REAL_DFM], [], 'TabcToggleBtn', ['Caption']);
  Check('usage.compute.missing', Has(U.Missing, 'GroupIndex'), 'GroupIndex is assigned in the DFM but absent from the From tree');
  Check('usage.compute.missing.notused', not Has(U.Missing, 'Caption'), 'a name WITH a leaf is not Missing');
end; // begin

{ The receiver-blindness defect, MEASURED on ORM3\CLIENT\VARINSP (2026-09-15): the grid
  marked 'Popup' used on TabcToggleBtn although no TabcToggleBtn on that form sets it. The
  two hits were 'F7Actions.Popup(400,300)' -- a TdxBarPopupMenu at VARINSP.PAS:16903, a
  different class entirely -- and a COMMENTED-OUT line at :11103.

  EVERY negative case below is paired with a POSITIVE CONTROL over the same fixture. A
  case that asserts only "the false hit is gone" also passes when the scan finds nothing
  at all -- including when it is switched off entirely -- so on its own it would be
  incapable of failing for the reason it names. The control proves the fixture can still
  produce the hit, which makes the negative a statement about the RULE. }
procedure TestScanPasReceiverAndComments;
var
  Loose: TArray<string>;
  U    : TArray<string>;
begin
  // --- comments are not code ---
  U:= ScanPasText('  // btnA.Popup := 1;'#13#10, ['Popup'], ['btnA'], Loose);
  Check('usage.pas.rcv.linecomment', not Contains(U, 'Popup'), 'a // line comment is not a use');
  U:= ScanPasText('  btnA.Popup := 1;'#13#10, ['Popup'], ['btnA'], Loose);
  Check('usage.pas.rcv.linecomment.control', Contains(U, 'Popup'), 'POSITIVE CONTROL: the same line uncommented IS a use');

  U:= ScanPasText('  { btnA.Popup := 1; }'#13#10, ['Popup'], ['btnA'], Loose);
  Check('usage.pas.rcv.bracecomment', not Contains(U, 'Popup'), 'a brace comment is not a use');
  U:= ScanPasText('  (* btnA.Popup := 1; *)'#13#10, ['Popup'], ['btnA'], Loose);
  Check('usage.pas.rcv.parencomment', not Contains(U, 'Popup'), 'a (* *) comment is not a use');

  // --- a string literal is not code either ---
  U:= ScanPasText('  S := ''btnA.Popup'';'#13#10, ['Popup'], ['btnA'], Loose);
  Check('usage.pas.rcv.stringlit', not Contains(U, 'Popup'), 'a name inside a string literal is not a use');
  U:= ScanPasText('  S := btnA.Popup;'#13#10, ['Popup'], ['btnA'], Loose);
  Check('usage.pas.rcv.stringlit.control', Contains(U, 'Popup'), 'POSITIVE CONTROL: the same line unquoted IS a use');

  // --- the receiver decides, and the rejected name is REPORTED, not discarded ---
  U:= ScanPasText('  F7Actions.Popup(400,300);'#13#10, ['Popup'], ['btnA'], Loose);
  Check('usage.pas.rcv.wrongreceiver', not Contains(U, 'Popup'), 'another class''s .Popup is not a use of ours');
  Check('usage.pas.rcv.wrongreceiver.loose', Contains(Loose, 'Popup'), 'and it is reported as loose rather than silently dropped');
  U:= ScanPasText('  F7Actions.Popup(400,300);'#13#10, ['Popup'], ['F7Actions'], Loose);
  Check('usage.pas.rcv.wrongreceiver.control', Contains(U, 'Popup'), 'POSITIVE CONTROL: the SAME text hits when that receiver is ours');

  // --- receiver forms that must still be credited ---
  U:= ScanPasText('  Self.btnA.Popup := 1;'#13#10, ['Popup'], ['btnA'], Loose);
  Check('usage.pas.rcv.chain', Contains(U, 'Popup'), 'the last link of a chain is the receiver');
  U:= ScanPasText('  TabcToggleBtn(Sender).Popup := 1;'#13#10, ['Popup'], ['btnA', 'TabcToggleBtn'], Loose);
  Check('usage.pas.rcv.cast', Contains(U, 'Popup'), 'a cast to the From class is a known receiver');

  // --- no receivers known: the filter is OFF, and says so by leaving Loose empty ---
  U:= ScanPasText('  F7Actions.Popup(400,300);'#13#10, ['Popup'], [], Loose);
  Check('usage.pas.rcv.nofilter', Contains(U, 'Popup'), 'with no known instance names every hit is confirmed');
  Check('usage.pas.rcv.nofilter.noloose', Length(Loose) = 0, 'and nothing is held back as loose');

  // --- unchanged by design: a with-block assignment has no dot to find ---
  U:= ScanPasText('  with btnA do Popup := 1;'#13#10, ['Popup'], ['btnA'], Loose);
  Check('usage.pas.rcv.withblock', not Contains(U, 'Popup'), 'a with-block still has no dot, unchanged and by design');
end; // begin

{ The instance names a .dfm declares for one class -- the receivers the .pas scan trusts. }
procedure TestScanDfmInstanceNames;
const
  SRC = 'object Form1: TForm1'#13#10 + '  object btnA: TabcToggleBtn'#13#10 + '    Caption = ''A'''#13#10 + '  end'#13#10 + '  object pnl: TPanel'#13#10 +
  '    object btnB: TabcToggleBtn'#13#10 + '      Caption = ''B'''#13#10 + '    end'#13#10 + '  end'#13#10 + 'end'#13#10;
var
  N: TArray<string>;
begin
  N:= ScanDfmInstanceNames(SRC, 'TabcToggleBtn');
  Check('usage.dfm.inst.count', Length(N) = 2, IntToStr(Length(N)));
  Check('usage.dfm.inst.top'   , Contains(N, 'btnA'), 'a top-level instance is found'         );
  Check('usage.dfm.inst.nested', Contains(N, 'btnB'), 'a nested instance is found too'        );
  Check('usage.dfm.inst.other' , not Contains(N, 'pnl'), 'an instance of another class is not');
  Check('usage.dfm.inst.none', Length(ScanDfmInstanceNames(SRC, 'TNotPresent')) = 0, 'a class with no block yields nothing');
end; // begin

{ Harvesting the units a form actually uses is what turns the Unit Rules tab from a blank
  page into a work list. Both clauses count; a unit used only in the implementation still
  has to be converted. }
procedure TestScanUsesClauses;
const
  SRC = 'unit Foo;'#13#10 + 'interface'#13#10 + 'uses'#13#10 + '  Winapi.Windows, FLDRDEF,'#13#10 + '  DBTables;'#13#10 + 'implementation'#13#10 +
  'uses BDEConst, Vcl.Forms;'#13#10 + 'end.'#13#10;
var
  U: TArray<string>                     ;
  function Has(const n: string): Boolean;
  var
    S: string;
  begin
    for S in U do if SameText(S, n) then Exit(True);
    Result:= False;
  end;
begin
  U:= ScanUsesClauses(SRC);
  Check('uses.interface.harvested'     , Has('FLDRDEF'       ), 'FLDRDEF'                             );
  Check('uses.multiline.harvested'     , Has('DBTables'      ), 'DBTables (second line of the clause)');
  Check('uses.implementation.harvested', Has('BDEConst'      ), 'BDEConst'                            );
  Check('uses.dotted.kept.whole'       , Has('Winapi.Windows'), 'a dotted unit is ONE name'           );
  Check('uses.count', Length(U) = 5, IntToStr(Length(U)));

  // 'uses' inside a comment or a string must not create phantom units.
  Check('uses.in.comment.ignored', Length(ScanUsesClauses('// uses Ghost;'#13#10'implementation'#13#10)) = 0, 'comment');
end; // begin

{ Pins the exact edges ScanUsesClauses's DocInsight claims -- both the things it DOES
  handle (the three Delphi comment forms, string literals, identifiers that merely
  CONTAIN 'uses', a qualified '.Uses' member, the .dpr 'unit in file' form,
  case-insensitive de-duplication) and the two things it deliberately does NOT: brace
  comments do not nest (which is Delphi's own rule, not a bug), and no IFDEF arm is
  ever evaluated, so a disabled arm's units are harvested too. Making a known-imperfect
  behaviour visible in the suite is the point: it cannot then change unnoticed. }
procedure TestScanUsesClausesLimits;

  function Names(const ASrc: string): string;
  begin
    Result:= string.Join(',', ScanUsesClauses(ASrc));
  end;

begin
  Check('uses.brace.comment.ignored', Names('{ uses Ghost; }'#13#10      ) = '', Names('{ uses Ghost; }'      ));
  Check('uses.starcomment.ignored'  , Names('(* uses Ghost; *)'#13#10    ) = '', Names('(* uses Ghost; *)'    ));
  Check('uses.string.ignored'       , Names('S := ''uses Ghost;'';'#13#10) = '', Names('S := ''uses Ghost;'';'));
  // Also written to DISCRIMINATE: a scanner matching 'uses' as a prefix/substring of a
  // token harvests 'Ghost' from the argument list behind the bogus keyword. The obvious
  // 'MyUses := 1;' form would have passed either way (':= 1' harvests nothing).
  Check('uses.prefixed.identifier.ignored', Names('procedure UsesFoo(A, Ghost: Integer);'#13#10) = '', Names('procedure UsesFoo(A, Ghost: Integer);'));
  Check('uses.suffixed.identifier.ignored', Names('MyUses(A, Ghost);'#13#10) = '', Names('MyUses(A, Ghost);'));
  // Written so it DISCRIMINATES: drop the '.'-guard and this harvests a phantom 'Ghost'
  // (the clause after the bogus keyword runs to the ';'). 'X.Uses := 1;' would have
  // passed either way, because ':= 1' has no leading identifier to harvest.
  Check('uses.qualified.member.ignored', Names('Call(A.Uses, Ghost);'#13#10         ) = ''       , Names('Call(A.Uses, Ghost);'         ));
  Check('uses.dpr.in.file.form'        , Names('uses Foo in ''Foo.pas'', Bar;'#13#10) = 'Foo,Bar', Names('uses Foo in ''Foo.pas'', Bar;'));
  Check(
    'uses.dedup.case.insensitive', Names('uses Foo;'#13#10'implementation'#13#10'uses FOO, Bar;'#13#10) = 'Foo,Bar', Names('uses Foo;'#13#10'implementation'#13#10'uses FOO, Bar;')
  );

  // LIMITATION (and Delphi's own rule): '{' comments do not nest, so the FIRST '}'
  // closes the comment and what follows it is real code.
  Check('uses.brace.comments.do.not.nest', Names('{ outer { inner } uses Ghost; }'#13#10) = 'Ghost', Names('{ outer { inner } uses Ghost; }'));

  // LIMITATION: no conditional compilation is evaluated -- a disabled arm still
  // contributes its units. For a candidate work list that over-reports on purpose.
  Check('uses.ifdef.arm.still.harvested', Names('{$IFDEF NEVER}'#13#10'uses Ghost;'#13#10'{$ENDIF}'#13#10) = 'Ghost', Names('{$IFDEF NEVER}'#13#10'uses Ghost;'#13#10'{$ENDIF}'));
end; // begin

{ The Unit Rules tab marks each used unit with the clause it was written in, so the
  scan has to carry a section. ScanUsesClauses is now a FLATTEN over the sectioned
  scan -- one scanner, two consumers -- so the last check here is a positive control
  on that refactor: it fails if the delegation changed order or contents. }
procedure TestScanUsesClausesSections;

  function Sections(const ASrc: string): string;
  var
    R  : TUsedUnitRef ;
    Acc: TArray<string>;
  begin
    Acc:= nil;
    for R in ScanUsesClausesSectioned(ASrc) do
      Acc:= Acc + [R.UnitName + '=' + R.Section];
    Result:= string.Join(',', Acc);
  end;

const
  SRC = 'unit U;'#13#10 + 'interface'#13#10 + 'uses Alpha, Beta;'#13#10 + 'implementation'#13#10 + 'uses Gamma;'#13#10 + 'end.'#13#10;
  BOTH = 'uses Foo;'#13#10 + 'implementation'#13#10 + 'uses FOO, Bar;'#13#10;
  QUAL = 'uses Alpha;'#13#10 + 'X := A.Implementation;'#13#10 + 'uses Beta;'#13#10;
  CMNT = 'uses Alpha;'#13#10 + '{ implementation }'#13#10 + 'uses Beta;'#13#10;
begin
  Check('uses.section.both.clauses', Sections(SRC) = 'Alpha=interface,Beta=interface,Gamma=implementation', Sections(SRC));

  { First occurrence wins, so a unit in BOTH clauses keeps 'interface'. Written to
    DISCRIMINATE: a scan that appended unconditionally would emit a SECOND row,
    'Foo=implementation', and the tab would show the same unit twice. }
  Check('uses.section.first.wins', Sections(BOTH) = 'Foo=interface,Bar=implementation', Sections(BOTH));

  { The latch is keyword-only. Both of these would flip the section on a scanner that
    matched the token without the '.'-guard / without SkipNonCode, and every unit
    after them would be mislabelled 'implementation'. }
  Check('uses.section.qualified.implementation.ignored', Sections(QUAL) = 'Alpha=interface,Beta=interface', Sections(QUAL));
  Check('uses.section.commented.implementation.ignored', Sections(CMNT) = 'Alpha=interface,Beta=interface', Sections(CMNT));

  // POSITIVE CONTROL on the refactor: the flat scan must answer exactly as before.
  Check('uses.flat.delegation.unchanged', string.Join(',', ScanUsesClauses(SRC)) = 'Alpha,Beta,Gamma', string.Join(',', ScanUsesClauses(SRC)));
end; // begin

{ ScanClassesDeclared shipped in 6cfaa158 with NO test and returned [] for EVERY
  input: the backtrack to the '=' started at the last letter of the keyword just
  read, never at the character before it. Measured 2026-09-17 on the real file
  (VARINSP.PAS, 'TVarInspDlg = class(TForm)') and on 'type TDlg = class(TForm) end;'
  alike -- both 0. The first case here is that minimal shape; the VARINSP case
  keeps the file's own tabs, and the enum + const declared BEFORE the class, so a
  scanner that is thrown by an earlier '=' is caught. }
procedure TestScanClassesDeclared;

  function Names(const ASrc: string): string;
  begin
    Result:= string.Join(',', ScanClassesDeclared(ASrc));
  end;

const
  MINIMAL = 'type'#13#10 + '  TDlg = class(TForm)'#13#10 + '  end;'#13#10;
  VARINSP = 'unit VARINSP;'#13#10 + 'interface'#13#10 + 'type'#13#10 + #9'TMachineState = (msON, msOFF, msNone);'#13#10 + 'const'#13#10
    + #9'MAXREADINGS = 8000;'#13#10 + 'type'#13#10 + #9'TRectangleAround = record'#13#10 + #9#9'Box: Integer;'#13#10 + #9'end;'#13#10 + 'type'#13#10
    + #9'TsgDXFImageAccess = class(TsgCADImage);'#13#10 + 'type'#13#10 + #9'TVarInspDlg = class(TForm)'#13#10 + #9#9'Timer1: TTimer;'#13#10 + #9'end;'#13#10
    + 'implementation'#13#10 + 'end.'#13#10;
  KINDS   = 'type'#13#10 + '  IFoo = interface'#13#10 + '  end;'#13#10 + '  TRec = record'#13#10 + '  end;'#13#10 + '  TGen<T> = class'#13#10 + '  end;'#13#10;
  GUARDED = 'type'#13#10 + '  TA = class'#13#10 + '  end;'#13#10 + 'var X: TObject;'#13#10 + 'begin X := Y.class; end;'#13#10;
begin
  Check('classes.minimal', Names(MINIMAL) = 'TDlg', Names(MINIMAL));
  Check('classes.varinsp.shape', Names(VARINSP) = 'TRectangleAround,TsgDXFImageAccess,TVarInspDlg', Names(VARINSP));
  Check('classes.kinds.and.generic.stripped', Names(KINDS) = 'IFoo,TRec,TGen', Names(KINDS));
  Check('classes.qualified.class.ignored', Names(GUARDED) = 'TA', Names(GUARDED));
  // POSITIVE CONTROL: an enum is not a class, and text with no type keyword yields [].
  Check('classes.none', Names('type TMode = (a, b);'#13#10) = '', Names('type TMode = (a, b);'#13#10));
end; // begin

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
  ANGLE_SRC = 'object btnA: TabcToggleBtn'#13#10 + '  Columns = <'#13#10 + '    item'#13#10 + '      Caption = ''Y > Z'''#13#10 + // '>' inside quotes must not close the list
  '    end'#13#10 + '    item'#13#10 + '      Caption = ''B'''#13#10 + '    end>'#13#10 + '  GroupIndex = 5'#13#10 + // must still be recorded
  'end'#13#10;

  PAREN_SRC = 'object btnA: TabcToggleBtn'#13#10 + '  Extra = ('#13#10 + '    ''A) B'''#13#10 + // ')' inside quotes must not close the value
  '    BogusInner = 1'#13#10 + // looks like an assignment; must NOT be recorded
  '    ''C'')'#13#10 + '  Hint = ''after'''#13#10 + // must still be recorded
  'end'#13#10;

  { Confirms the same-line case is unaffected by the fix: a value that opens AND
    closes its container on one line must not itself trip skip mode. }
  SAMELINE_SRC = 'object btnA: TabcToggleBtn'#13#10 + '  Columns = <>'#13#10 + '  Blob = {}'#13#10 + '  Hint = ''x'''#13#10 + 'end'#13#10;

  function Has(const A: TArray<string>; const S: string): Boolean;
  var
    x: string;
  begin
    for x in A do
      if SameText(x, S) then
        Exit(True);
    Result:= False;
  end;

var
  U: TArray<string>;
begin
  U:= ScanDfmText(ANGLE_SRC, 'TabcToggleBtn');
  Check('usage.dfm.skip.angle.quote-defeat', Has(U, 'GroupIndex'), 'a > inside a quoted item value must not close the <...> list early');
  Check('usage.dfm.skip.angle.inner-not-recorded', not Has(U, 'Caption'), 'assignments inside <...> items are never recorded');

  U:= ScanDfmText(PAREN_SRC, 'TabcToggleBtn');
  Check('usage.dfm.skip.paren.quote-defeat', not Has(U, 'BogusInner'), 'a ) inside a quoted list value must not close the (...) value early');
  Check('usage.dfm.skip.paren.after-recorded', Has(U, 'Hint'), 'the immediate-level property after the list still gets recorded');

  U:= ScanDfmText(SAMELINE_SRC, 'TabcToggleBtn');
  Check('usage.dfm.skip.sameline.angle-empty', Has(U, 'Blob'), 'Columns = <> must not itself enter skip mode');
  Check('usage.dfm.skip.sameline.brace-empty', Has(U, 'Hint'), 'Blob = {} must not itself enter skip mode'   );
end; // begin

{ Review fix (Important 3): ScanPasText was reworked from an O(candidates x textlength)
  per-candidate scan into a single O(textlength) harvest of every '.Identifier' token
  followed by an O(candidates) membership filter. This pins the boundary case that
  inversion is most likely to get wrong: a '.' as the very last character of the text
  (nothing follows it to harvest) must not raise or hang, and an empty candidate list
  or empty text must still return an empty result. }
procedure TestScanPasEndOfTextSafety;
begin
  Check('usage.pas.eot.trailingdot', Length(ScanPasText('x.', ['x'])) = 0, 'a trailing dot with nothing after it harvests nothing');
  Check('usage.pas.eot.emptytext', Length(ScanPasText('', ['Caption'])) = 0, 'empty text yields an empty result');
  Check('usage.pas.eot.emptycandidates', Length(ScanPasText('a.Caption := 1;', [])) = 0, 'no candidates yields an empty result');
  Check(
    'usage.pas.eot.dotatend.stillfindsearlier', Contains(ScanPasText('a.Caption := 1; b.', ['Caption']), 'Caption'),
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
const { `query --name TAlignment` -- three exact-name rows, two of them enums. The
    wanted answer is the first TYPE-LIKE row: System.Classes.pas:176. }
  QJ_ALIGNMENT = '['#13#10 + '  {'#13#10 + '    "id": 1308682,'#13#10 + '    "kind": "enum",'#13#10 + '    "name": "TAlignment",'#13#10 +
  '    "qualified_name": "System.Classes.TAlignment",'#13#10 + '    "signature": "",'#13#10 + '    "modifiers": "",'#13#10 + '    "section": "interface",'#13#10 +
  '    "usable_from_other_units": true,'#13#10 + '    "file_id": 4644,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\source\\rtl\\common\\System.Classes.pas",'#13#10 + '    "start_line": 176,'#13#10 +
  '    "start_col": 3,'#13#10 + '    "end_line": 176,'#13#10 + '    "end_col": 58,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  },'#13#10 +
  '  {'#13#10 + '    "id": 661597,'#13#10 + '    "kind": "record",'#13#10 + '    "name": "TAlignment",'#13#10 +
  '    "qualified_name": "dxRichEdit.Dialogs.TableStyle.TdxRichEditTableStyleDialogForm.TAlignment",'#13#10 + '    "signature": "",'#13#10 + '    "modifiers": "",'#13#10 +
  '    "section": "interface",'#13#10 + '    "usable_from_other_units": true,'#13#10 + '    "file_id": 2715,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\DevExpress\\VCL\\ExpressRichEdit Control\\Sources\\dxRichEdit.Dialogs.TableStyle.pas",'#13#10 + '    "start_line": 245,'#13#10 +
  '    "start_col": 7,'#13#10 + '    "end_line": 249,'#13#10 + '    "end_col": 11,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  },'#13#10 +
  '  {'#13#10 + '    "id": 795949,'#13#10 + '    "kind": "enum",'#13#10 + '    "name": "TAlignment",'#13#10 +
  '    "qualified_name": "dxSplashForms.TdxSplashFormBase.TAlignment",'#13#10 + '    "signature": "",'#13#10 + '    "modifiers": "",'#13#10 + '    "section": "interface",'#13#10 +
  '    "usable_from_other_units": true,'#13#10 + '    "file_id": 3238,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\DevExpress\\VCL\\ExpressSplashForms\\Sources\\dxSplashForms.pas",'#13#10 + '    "start_line": 131,'#13#10 + '    "start_col": 5,'#13#10 +
  '    "end_line": 131,'#13#10 + '    "end_col": 38,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  }'#13#10 + ']'#13#10;

  { `query --name TThread` -- the exe returns an unrelated FIELD named TThread
    BEFORE System.Classes.TThread. "First hit" would open EAppMultiThreaded.pas:67. }
  QJ_THREAD = '['#13#10 + '  {'#13#10 + '    "id": 2119103,'#13#10 + '    "kind": "field",'#13#10 + '    "name": "TThread",'#13#10 +
  '    "qualified_name": "EAppMultiThreaded.THookedThread.TThread",'#13#10 + '    "signature": "TClass",'#13#10 + '    "modifiers": "public",'#13#10 +
  '    "section": "implementation",'#13#10 + '    "usable_from_other_units": false,'#13#10 + '    "file_id": 6707,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\Neos Eureka S.r.l\\EurekaLog 7\\Source\\EAppMultiThreaded.pas",'#13#10 + '    "start_line": 67,'#13#10 + '    "start_col": 5,'#13#10 +
  '    "end_line": 67,'#13#10 + '    "end_col": 21,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  },'#13#10 + '  {'#13#10 +
  '    "id": 1310582,'#13#10 + '    "kind": "class",'#13#10 + '    "name": "TThread",'#13#10 + '    "qualified_name": "System.Classes.TThread",'#13#10 +
  '    "signature": "",'#13#10 + '    "modifiers": "",'#13#10 + '    "section": "interface",'#13#10 + '    "usable_from_other_units": true,'#13#10 + '    "file_id": 4644,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\source\\rtl\\common\\System.Classes.pas",'#13#10 + '    "start_line": 1822,'#13#10 +
  '    "start_col": 3,'#13#10 + '    "end_line": 2021,'#13#10 + '    "end_col": 7,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  }'#13#10 +
  ']'#13#10;

  { `query --name TNotifyEvent` -- first two of ten rows. NOT ONE of them is named
    TNotifyEvent: the type is a method pointer and the index does not carry it, so
    every hit is the substring ANotifyEvent. This must resolve to nothing. }
  QJ_NOTIFYEVENT_SUBSTRINGONLY = '['#13#10 + '  {'#13#10 + '    "id": 965744,'#13#10 + '    "kind": "local_var",'#13#10 + '    "name": "ANotifyEvent",'#13#10 +
  '    "qualified_name": "Abcapp.TabcApplicationEvents.AppOnActivate.ANotifyEvent",'#13#10 + '    "signature": "TNotifyEvent",'#13#10 + '    "modifiers": "",'#13#10 +
  '    "section": "implementation",'#13#10 + '    "usable_from_other_units": false,'#13#10 + '    "file_id": 4051,'#13#10 +
  '    "file": "C:\\Projects\\ABC5\\ABC5\\Source\\Abcapp.pas",'#13#10 + '    "start_line": 322,'#13#10 + '    "start_col": 3,'#13#10 + '    "end_line": 322,'#13#10 +
  '    "end_col": 15,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  },'#13#10 + '  {'#13#10 + '    "id": 965746,'#13#10 +
  '    "kind": "local_var",'#13#10 + '    "name": "ANotifyEvent",'#13#10 + '    "qualified_name": "Abcapp.TabcApplicationEvents.AppOnDeactivate.ANotifyEvent",'#13#10 +
  '    "signature": "TNotifyEvent",'#13#10 + '    "modifiers": "",'#13#10 + '    "section": "implementation",'#13#10 + '    "usable_from_other_units": false,'#13#10 +
  '    "file_id": 4051,'#13#10 + '    "file": "C:\\Projects\\ABC5\\ABC5\\Source\\Abcapp.pas",'#13#10 + '    "start_line": 335,'#13#10 + '    "start_col": 3,'#13#10 +
  '    "end_line": 335,'#13#10 + '    "end_col": 15,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  }'#13#10 + ']'#13#10;

  { `query --name TabcButtonStyle` -- one enum row, the ABC5 type the editor's
    grid actually shows as `Style : TabcButtonStyle`. }
  QJ_ABCBUTTONSTYLE = '['#13#10 + '  {'#13#10 + '    "id": 967081,'#13#10 + '    "kind": "enum",'#13#10 + '    "name": "TabcButtonStyle",'#13#10 +
  '    "qualified_name": "Abcbtn.TabcButtonStyle",'#13#10 + '    "signature": "",'#13#10 + '    "modifiers": "",'#13#10 + '    "section": "interface",'#13#10 +
  '    "usable_from_other_units": true,'#13#10 + '    "file_id": 4055,'#13#10 + '    "file": "C:\\Projects\\ABC5\\ABC5\\Source\\Abcbtn.pas",'#13#10 +
  '    "start_line": 33,'#13#10 + '    "start_col": 3,'#13#10 + '    "end_line": 39,'#13#10 + '    "end_col": 71,'#13#10 + '    "impl_start_line": 0,'#13#10 +
  '    "impl_end_line": 0'#13#10 + '  }'#13#10 + ']'#13#10;

  { The two REAL rows `query --name TFontPitch` returns -- the enum in
    System.UITypes and the Vcl.Graphics ALIAS pointing at it -- written here with the
    alias FIRST. The engine happens to emit the enum first today, but that order is
    an artefact of indexing order, not a contract, and only the enum row can yield
    members. So the ranking, not the order, must decide. }
  QJ_FONTPITCH_ALIAS_FIRST = '['#13#10 + '  {'#13#10 + '    "id": 1269016,'#13#10 + '    "kind": "type",'#13#10 + '    "name": "TFontPitch",'#13#10 +
  '    "qualified_name": "Vcl.Graphics.TFontPitch",'#13#10 + '    "signature": "System.UITypes.TFontPitch",'#13#10 + '    "modifiers": "",'#13#10 +
  '    "section": "interface",'#13#10 + '    "usable_from_other_units": true,'#13#10 + '    "file_id": 4558,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\SOURCE\\VCL\\Vcl.Graphics.pas",'#13#10 + '    "start_line": 390,'#13#10 + '    "start_col": 3,'#13#10 +
  '    "end_line": 390,'#13#10 + '    "end_col": 42,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  },'#13#10 + '  {'#13#10 +
  '    "id": 1348320,'#13#10 + '    "kind": "enum",'#13#10 + '    "name": "TFontPitch",'#13#10 + '    "qualified_name": "System.UITypes.TFontPitch",'#13#10 +
  '    "signature": "",'#13#10 + '    "modifiers": "",'#13#10 + '    "section": "interface",'#13#10 + '    "usable_from_other_units": true,'#13#10 + '    "file_id": 4705,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\source\\rtl\\common\\System.UITypes.pas",'#13#10 + '    "start_line": 74,'#13#10 + '    "start_col": 3,'#13#10 +
  '    "end_line": 74,'#13#10 + '    "end_col": 49,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  }'#13#10 + ']'#13#10;

  { Real zero-hit stdout. The process ALSO exits 1 -- "no hits", not a failure. }
  QJ_NOHITS = '['#13#10 + ']'#13#10;
  { RunCapture merges the child's stderr into stdout, and the exe writes this
    note to stderr on every call. The parser must survive it. }
  PREAMBLE = '(loaded defaults from C:\Projects\.drag-lint.json)'#13#10;

  { The real System.Classes.TAlignment row with its "start_line" field DELETED.
    The exe has never been observed to emit a row without one, so this is not a
    captured shape -- it exists to pin the DEFENSIVE branch the DocInsight on
    ParseQueryLocation promises: a chosen row with no usable line still resolves,
    to line 1 of the right file, never to line 0. }
  QJ_ALIGNMENT_NO_START_LINE = '['#13#10 + '  {'#13#10 + '    "id": 1308682,'#13#10 + '    "kind": "enum",'#13#10 + '    "name": "TAlignment",'#13#10 +
  '    "qualified_name": "System.Classes.TAlignment",'#13#10 + '    "signature": "",'#13#10 + '    "modifiers": "",'#13#10 + '    "section": "interface",'#13#10 +
  '    "usable_from_other_units": true,'#13#10 + '    "file_id": 4644,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\source\\rtl\\common\\System.Classes.pas",'#13#10 + '    "start_col": 3,'#13#10 + '    "end_line": 176,'#13#10 +
  '    "end_col": 58,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  }'#13#10 + ']'#13#10;
var
  f  : string ;
  Ln : Integer;
  Amb: Integer;
begin
  Check('queryloc.parses.bare.toplevel.array', ParseQueryLocation(QJ_ALIGNMENT, 'TAlignment', f, Ln, Amb) and SameText(ExtractFileName(f), 'System.Classes.pas'), f);
  Check('queryloc.reads.start_line.not.line', ParseQueryLocation(QJ_ALIGNMENT, 'TAlignment', f, Ln, Amb) and (Ln = 176), 'expected 176, got ' + IntToStr(Ln));
  Check(
    'queryloc.prefers.type.over.field', ParseQueryLocation(QJ_THREAD, 'TThread', f, Ln, Amb) and SameText(ExtractFileName(f), 'System.Classes.pas') and (Ln = 1822),
    'first hit is an unrelated field; got ' + f + ':' + IntToStr(Ln));
  Check(
    'queryloc.prefers.concrete.over.alias',
    ParseQueryLocation(QJ_FONTPITCH_ALIAS_FIRST, 'TFontPitch', f, Ln, Amb) and SameText(ExtractFileName(f), 'System.UITypes.pas') and (Ln = 74),
    'the enum, not the Vcl.Graphics alias to it; got ' + f + ':' + IntToStr(Ln));

  { Ranking settles KIND, never a tie WITHIN a kind tier -- and ties are ordinary.
    All three TAlignment rows are tier 0 (two enums and a record), all are
    section=interface with usable_from_other_units=true, so nothing on the rows can
    separate them; System.Classes wins only because it was indexed first. The count
    is what lets the caller say so instead of presenting a coin-flip as the answer. }
  Check('queryloc.reports.tied.candidates', ParseQueryLocation(QJ_ALIGNMENT, 'TAlignment', f, Ln, Amb) and (Amb = 3), 'three tier-0 rows named TAlignment; got ' + IntToStr(Amb));
  Check(
    'queryloc.unambiguous.reports.one', ParseQueryLocation(QJ_THREAD, 'TThread', f, Ln, Amb) and (Amb = 1),
    'only the class is tier 0, so the answer was forced; got ' + IntToStr(Amb));
  Check(
    'queryloc.missing.start_line.clamps.to.one',
    ParseQueryLocation(QJ_ALIGNMENT_NO_START_LINE, 'TAlignment', f, Ln, Amb) and SameText(ExtractFileName(f), 'System.Classes.pas') and (Ln = 1),
    'the wire contract treats a missing line as 1, never 0; got ' + IntToStr(Ln));

  Check(
    'queryloc.substring.only.hits.fail', not ParseQueryLocation(QJ_NOTIFYEVENT_SUBSTRINGONLY, 'TNotifyEvent', f, Ln, Amb) and (Amb = 0),
    'ANotifyEvent is a substring hit, not TNotifyEvent');
  Check('queryloc.accepts.qualified.name', ParseQueryLocation(QJ_ABCBUTTONSTYLE, 'Abcbtn.TabcButtonStyle', f, Ln, Amb) and (Ln = 33), IntToStr(Ln));
  Check(
    'queryloc.tolerates.stderr.preamble', ParseQueryLocation(PREAMBLE + QJ_ABCBUTTONSTYLE, 'TabcButtonStyle', f, Ln, Amb) and (Ln = 33),
    'the loaded-defaults note must not break the parse');
  Check('queryloc.empty.array.fails', not ParseQueryLocation(QJ_NOHITS , 'TAlignment', f, Ln, Amb), 'zero hits must not report success');
  Check('queryloc.garbage.fails'    , not ParseQueryLocation('not json', 'TAlignment', f, Ln, Amb), 'garbage must not report success'  );
end; // begin

{ VCL-PREFERRED TIE-BREAK: which of several EQUALLY-RANKED declarations wins.

  TypeKindTier settles concrete-vs-alias and nothing else, so a bare `TEdit` still
  arrived at two class rows and took whichever the engine happened to list first --
  FMX.Edit.TEdit. This is a VCL tool: an FMX property tree for a VCL form is a wrong
  answer, not a taste. Measured against library-Win64.sqlite on 2026-08-02, 298 names
  resolved FMX-first, TEdit / TButton / TLabel / TForm / TPanel among them.

  The tie-break is a strict ORDER, applied ONLY among rows already tied at the winning
  kind tier, first difference wins, and an exhausted order keeps the first row:
    1. not FireMonkey, before FMX.*
    2. top-level, before a type nested inside another type
    3. System.* then Vcl.* then everything else
  One fixture per step below, so no step can be dropped without a FAIL.

  Fixtures are REAL `drag-lint query --name ... --json` output captured from
  C:\Projects\.drag-lint\library-Win64.sqlite on 2026-08-02, reduced to the exact-name
  rows (SelectQuerySymbol drops the substring rows before ranking, so they change
  nothing here). Two are re-ordered, which is stated on the fixture: engine row order
  is not contractual, and a rule that only works in one listing order is not a rule. }
procedure TestQuerySymbolTieBreak;
const
  QJ_TEDIT = '['#13#10 + '  {'#13#10 + '    "id": 1931967,'#13#10 + '    "kind": "class",'#13#10 + '    "name": "TEdit",'#13#10 +
  '    "qualified_name": "FMX.Edit.TEdit",'#13#10 + '    "signature": "",'#13#10 + '    "modifiers": "",'#13#10 + '    "section": "interface",'#13#10 +
  '    "usable_from_other_units": true,'#13#10 + '    "file_id": 5755,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\source\\fmx\\FMX.Edit.pas",'#13#10 + '    "start_line": 650,'#13#10 + '    "start_col": 3,'#13#10 +
  '    "end_line": 743,'#13#10 + '    "end_col": 7,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  },'#13#10 + '  {'#13#10 +
  '    "id": 1286269,'#13#10 + '    "kind": "class",'#13#10 + '    "name": "TEdit",'#13#10 + '    "qualified_name": "Vcl.StdCtrls.TEdit",'#13#10 + '    "signature": "",'#13#10 +
  '    "modifiers": "",'#13#10 + '    "section": "interface",'#13#10 + '    "usable_from_other_units": true,'#13#10 + '    "file_id": 4597,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\SOURCE\\VCL\\Vcl.StdCtrls.pas",'#13#10 + '    "start_line": 368,'#13#10 + '    "start_col": 3,'#13#10 +
  '    "end_line": 443,'#13#10 + '    "end_col": 7,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  }'#13#10 + ']'#13#10;

  QJ_TCOLOR = '['#13#10 + '  {'#13#10 + '    "id": 176146,'#13#10 + '    "kind": "type",'#13#10 + '    "name": "TColor",'#13#10 +
  '    "qualified_name": "Spring.Logging.TColor",'#13#10 + '    "signature": "Graphics.TColor",'#13#10 + '    "modifiers": "",'#13#10 + '    "section": "interface",'#13#10 +
  '    "usable_from_other_units": true,'#13#10 + '    "file_id": 1045,'#13#10 + '    "file": "C:\\Projects\\spring4d\\Source\\Base\\Logging\\Spring.Logging.pas",'#13#10 +
  '    "start_line": 50,'#13#10 + '    "start_col": 3,'#13#10 + '    "end_line": 50,'#13#10 + '    "end_col": 28,'#13#10 + '    "impl_start_line": 0,'#13#10 +
  '    "impl_end_line": 0'#13#10 + '  },'#13#10 + '  {'#13#10 + '    "id": 1268754,'#13#10 + '    "kind": "type",'#13#10 + '    "name": "TColor",'#13#10 +
  '    "qualified_name": "Vcl.Graphics.TColor",'#13#10 + '    "signature": "System.UITypes.TColor",'#13#10 + '    "modifiers": "",'#13#10 + '    "section": "interface",'#13#10 +
  '    "usable_from_other_units": true,'#13#10 + '    "file_id": 4558,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\SOURCE\\VCL\\Vcl.Graphics.pas",'#13#10 + '    "start_line": 37,'#13#10 + '    "start_col": 3,'#13#10 +
  '    "end_line": 37,'#13#10 + '    "end_col": 34,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  }'#13#10 + ']'#13#10;

  QJ_TGLYPH = '['#13#10 + '  {'#13#10 + '    "id": 1945956,'#13#10 + '    "kind": "class",'#13#10 + '    "name": "TGlyph",'#13#10 +
  '    "qualified_name": "FMX.ImgList.TGlyph",'#13#10 + '    "signature": "",'#13#10 + '    "modifiers": "",'#13#10 + '    "section": "interface",'#13#10 +
  '    "usable_from_other_units": true,'#13#10 + '    "file_id": 5788,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\source\\fmx\\FMX.ImgList.pas",'#13#10 + '    "start_line": 435,'#13#10 + '    "start_col": 3,'#13#10 +
  '    "end_line": 532,'#13#10 + '    "end_col": 7,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  },'#13#10 + '  {'#13#10 +
  '    "id": 1262675,'#13#10 + '    "kind": "class",'#13#10 + '    "name": "TGlyph",'#13#10 + '    "qualified_name": "Vcl.ExtCtrls.TEditButton.TGlyph",'#13#10 +
  '    "signature": "",'#13#10 + '    "modifiers": "",'#13#10 + '    "section": "interface",'#13#10 + '    "usable_from_other_units": true,'#13#10 + '    "file_id": 4553,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\SOURCE\\VCL\\Vcl.ExtCtrls.pas",'#13#10 + '    "start_line": 1544,'#13#10 + '    "start_col": 7,'#13#10 +
  '    "end_line": 1555,'#13#10 + '    "end_col": 11,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  }'#13#10 + ']'#13#10;

  QJ_TMENUBARITEM = '['#13#10 + '  {'#13#10 + '    "id": 1267121,'#13#10 + '    "kind": "record",'#13#10 + '    "name": "TMenuBarItem",'#13#10 +
  '    "qualified_name": "Vcl.Forms.TFormStyleHook.TMainMenuBarStyleHook.TMenuBarItem",'#13#10 + '    "signature": "",'#13#10 + '    "modifiers": "",'#13#10 +
  '    "section": "interface",'#13#10 + '    "usable_from_other_units": true,'#13#10 + '    "file_id": 4556,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\SOURCE\\VCL\\Vcl.Forms.pas",'#13#10 + '    "start_line": 2173,'#13#10 + '    "start_col": 7,'#13#10 +
  '    "end_line": 2178,'#13#10 + '    "end_col": 11,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  },'#13#10 + '  {'#13#10 +
  '    "id": 1662704,'#13#10 + '    "kind": "class",'#13#10 + '    "name": "TMenuBarItem",'#13#10 +
  '    "qualified_name": "Winapi.Microsoft.UI.Xaml.ControlsRT.TMenuBarItem",'#13#10 + '    "signature": "",'#13#10 + '    "modifiers": "",'#13#10 +
  '    "section": "interface",'#13#10 + '    "usable_from_other_units": true,'#13#10 + '    "file_id": 4946,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\source\\rtl\\win\\winrt\\Winapi.Microsoft.UI.Xaml.ControlsRT.pas",'#13#10 + '    "start_line": 25327,'#13#10 +
  '    "start_col": 3,'#13#10 + '    "end_line": 25338,'#13#10 + '    "end_col": 6,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  },'#13#10 +
  '  {'#13#10 + '    "id": 1723961,'#13#10 + '    "kind": "class",'#13#10 + '    "name": "TMenuBarItem",'#13#10 +
  '    "qualified_name": "Winapi.UI.Xaml.ControlsRT.TMenuBarItem",'#13#10 + '    "signature": "",'#13#10 + '    "modifiers": "",'#13#10 + '    "section": "interface",'#13#10 +
  '    "usable_from_other_units": true,'#13#10 + '    "file_id": 4976,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\source\\rtl\\win\\winrt\\Winapi.UI.Xaml.ControlsRT.pas",'#13#10 + '    "start_line": 28377,'#13#10 +
  '    "start_col": 3,'#13#10 + '    "end_line": 28388,'#13#10 + '    "end_col": 6,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  }'#13#10 +
  ']'#13#10;

  QJ_EOLEERROR_VCL_FIRST = '['#13#10 + '  {'#13#10 + '    "id": 1279619,'#13#10 + '    "kind": "class",'#13#10 + '    "name": "EOleError",'#13#10 +
  '    "qualified_name": "Vcl.OleAuto.EOleError",'#13#10 + '    "signature": "",'#13#10 + '    "modifiers": "",'#13#10 + '    "section": "interface",'#13#10 +
  '    "usable_from_other_units": true,'#13#10 + '    "file_id": 4577,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\SOURCE\\VCL\\Vcl.OleAuto.pas",'#13#10 + '    "start_line": 180,'#13#10 + '    "start_col": 3,'#13#10 +
  '    "end_line": 180,'#13#10 + '    "end_col": 32,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  },'#13#10 + '  {'#13#10 +
  '    "id": 1350850,'#13#10 + '    "kind": "class",'#13#10 + '    "name": "EOleError",'#13#10 + '    "qualified_name": "System.Win.ComObj.EOleError",'#13#10 +
  '    "signature": "",'#13#10 + '    "modifiers": "",'#13#10 + '    "section": "interface",'#13#10 + '    "usable_from_other_units": true,'#13#10 + '    "file_id": 4712,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\source\\rtl\\common\\System.Win.ComObj.pas",'#13#10 + '    "start_line": 405,'#13#10 +
  '    "start_col": 3,'#13#10 + '    "end_line": 405,'#13#10 + '    "end_col": 32,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  }'#13#10 +
  ']'#13#10;

  QJ_TDRAGTARGET = '['#13#10 + '  {'#13#10 + '    "id": 1750749,'#13#10 + '    "kind": "class",'#13#10 + '    "name": "TDragTarget",'#13#10 +
  '    "qualified_name": "DesignIntf.TDragTarget",'#13#10 + '    "signature": "",'#13#10 + '    "modifiers": "",'#13#10 + '    "section": "interface",'#13#10 +
  '    "usable_from_other_units": true,'#13#10 + '    "file_id": 4995,'#13#10 +
  '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\source\\ToolsAPI\\DesignIntf.pas",'#13#10 + '    "start_line": 1310,'#13#10 + '    "start_col": 3,'#13#10 +
  '    "end_line": 1319,'#13#10 + '    "end_col": 7,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  },'#13#10 + '  {'#13#10 +
  '    "id": 1253915,'#13#10 + '    "kind": "type",'#13#10 + '    "name": "TDragTarget",'#13#10 + '    "qualified_name": "Vcl.Controls.TDragTarget",'#13#10 +
  '    "signature": "Pointer",'#13#10 + '    "modifiers": "",'#13#10 + '    "section": "interface",'#13#10 + '    "usable_from_other_units": true,'#13#10 +
  '    "file_id": 4545,'#13#10 + '    "file": "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\SOURCE\\VCL\\Vcl.Controls.pas",'#13#10 + '    "start_line": 869,'#13#10 +
  '    "start_col": 5,'#13#10 + '    "end_line": 869,'#13#10 + '    "end_col": 27,'#13#10 + '    "impl_start_line": 0,'#13#10 + '    "impl_end_line": 0'#13#10 + '  }'#13#10 +
  ']'#13#10;

var
  Sym: TQuerySymbol;
  Amb: Integer     ;
begin
  { Step 1. Both rows are tier-0 classes; FMX is listed FIRST by the real engine. }
  Check(
    'tiebreak.vcl.beats.fmx', SelectQuerySymbol(ParseQuerySymbols(QJ_TEDIT), 'TEdit', Sym, Amb) and SameText(Sym.QualifiedName, 'Vcl.StdCtrls.TEdit'),
    'a VCL tool must not answer TEdit with FireMonkey; got ' + Sym.QualifiedName);
  { The tie-break picks a side; it does NOT make the ambiguity go away. The count is
    still what the editor shows the user, unchanged from before this rule existed. }
  Check(
    'tiebreak.still.reports.the.tie', SelectQuerySymbol(ParseQuerySymbols(QJ_TEDIT), 'TEdit', Sym, Amb) and (Amb = 2),
    'two class rows are still two class rows; got ' + IntToStr(Amb));
  { And asking for FMX BY NAME still gets FMX -- the preference is for the BARE name
    only, never a veto on what the caller explicitly requested. }
  Check(
    'tiebreak.qualified.request.wins', SelectQuerySymbol(ParseQuerySymbols(QJ_TEDIT), 'FMX.Edit.TEdit', Sym, Amb) and SameText(Sym.QualifiedName, 'FMX.Edit.TEdit') and (Amb = 1),
    'an explicit qualified request is not a tie; got ' + Sym.QualifiedName);

  { Step 3, third-party arm. The plan's own case: TColor came back Spring.Logging. }
  Check(
    'tiebreak.vcl.beats.thirdparty', SelectQuerySymbol(ParseQuerySymbols(QJ_TCOLOR), 'TColor', Sym, Amb) and SameText(Sym.QualifiedName, 'Vcl.Graphics.TColor') and (Amb = 2),
    'TColor in a VCL form is Vcl.Graphics.TColor; got ' + Sym.QualifiedName);

  { Step 1 ABOVE step 2: FMX loses even to a type nested inside a VCL class. Both
    answers are poor, but only one of them is reachable from a VCL form at all. }
  Check(
    'tiebreak.fmx.loses.even.to.a.nested.decl',
    SelectQuerySymbol(ParseQuerySymbols(QJ_TGLYPH), 'TGlyph', Sym, Amb) and SameText(Sym.QualifiedName, 'Vcl.ExtCtrls.TEditButton.TGlyph'),
    'FMX ranks last, below a nested non-FMX row; got ' + Sym.QualifiedName);

  { Step 2 ABOVE step 3: a top-level Winapi class beats a record nested in a VCL
    style hook. Ordering the library preference FIRST instead would pick the nested
    Vcl row here -- measured on the real index, that ordering promotes a nested type
    over a top-level one for 10 names, which is the only way this change was measured
    to make any answer worse. Hence nesting outranks the library preference. }
  Check(
    'tiebreak.toplevel.beats.nested.vcl',
    SelectQuerySymbol(ParseQuerySymbols(QJ_TMENUBARITEM), 'TMenuBarItem', Sym, Amb) and SameText(Sym.QualifiedName, 'Winapi.Microsoft.UI.Xaml.ControlsRT.TMenuBarItem'),
    'a nested type is rarely what a bare name means; got ' + Sym.QualifiedName);

  { Step 3, RTL arm. Vcl.OleAuto.EOleError is a re-export of the System.Win.ComObj
    class; both rows are section=interface with usable_from_other_units=true, so no
    row attribute separates them. Measured: in ALL 35 names where a System.* and a
    Vcl.* declaration tie at the same kind tier, the Vcl row is the re-export or a
    unit-local copy -- so System.* outranks Vcl.*. Vcl.* is listed FIRST here. }
  Check(
    'tiebreak.system.beats.vcl.reexport',
    SelectQuerySymbol(ParseQuerySymbols(QJ_EOLEERROR_VCL_FIRST), 'EOleError', Sym, Amb) and SameText(Sym.QualifiedName, 'System.Win.ComObj.EOleError'),
    'the RTL declares it; Vcl.OleAuto re-exports it; got ' + Sym.QualifiedName);

  { The tie-break is INSIDE a tier and can never reach across one. Vcl.Controls
    declares TDragTarget as an alias (kind=type, tier 1) while DesignIntf declares the
    class (tier 0), so the class wins although the library preference points the other
    way. Without this, "prefer Vcl" would start beating "a real declaration outranks
    an alias to it" -- and only the concrete row can yield enum members. }
  Check(
    'tiebreak.kind.tier.still.outranks.it',
    SelectQuerySymbol(ParseQuerySymbols(QJ_TDRAGTARGET), 'TDragTarget', Sym, Amb) and SameText(Sym.QualifiedName, 'DesignIntf.TDragTarget') and (Amb = 1),
    'tiering comes first and is untouched; got ' + Sym.QualifiedName);
end; // begin

{ Enum members: the PURE parse of an enum's DECLARATION SOURCE.

  There is no members list in the index and no children query -- an enum row
  carries only kind='enum' plus file + start_line..end_line, and `surface --qname`
  refuses a non-class. So the members come from the declaration text itself, and
  this is the function that reads it. Fixtures are the real source lines the index
  points at. }
procedure TestEnumMembersParse;
const { System.Classes.pas:176 -- the ordinary one-line case. }
  ED_SIMPLE = '  TAlignment = (taLeftJustify, taRightJustify, taCenter);'#13#10;
  { Abcbtn.pas:33-39 -- 19 members over seven lines. }
  ED_MULTILINE = '  TabcButtonStyle = (absAutoDetect, absNew, absWin31, absThin, absThinBlack,'#13#10 + '                     absThinGray,'#13#10 +
  '                     absThinHighlight, absMidHighlight, absThickHighlight,'#13#10 + '                     absFramed, absFramedBlack, absFramedRaised,'#13#10 +
  '                     absFramedHighlight, absFramedBlackHighlight,'#13#10 + '                     absRecessed, absRecessedBlack, absRecessedRaised,'#13#10 +
  '                     absRecessedHighlight, absRecessedBlackHighlight);'#13#10;
  { CSIdWinsock2.pas:2639-2648 -- the hard real case, all in one declaration:
    explicit "= N" values, compiler directives, a // comment, and the SAME member
    appearing in both arms of the $IFDEF. }
  ED_CONDITIONAL = '  _RIO_NOTIFICATION_COMPLETION_TYPE = ('#13#10 + '    {$IFDEF HAS_ENUM_ELEMENT_VALUES}'#13#10 + '    RIO_EVENT_COMPLETION      = 1,'#13#10 +
  '    RIO_IOCP_COMPLETION       = 2'#13#10 + '    {$ELSE}'#13#10 + '    rnctUnused,   // do not use'#13#10 + '    RIO_EVENT_COMPLETION,'#13#10 + '    RIO_IOCP_COMPLETION'#13#10 +
  '    {$ENDIF}'#13#10 + '  );'#13#10;
  { Abcbtn.pas:68 -- a class. It has '=' and '(' too, so a naive scan would
    happily report TButton as a "member". }
  ED_CLASS = '  TabcPicBtn = class(TButton)'#13#10;
var
  M: TArray<string>;
begin
  { Every case re-parses. Asserting against whatever M was left holding by the
    PREVIOUS Check couples the cases together and, worse, makes the negative ones
    ("no directive is a member") pass for free whenever M happens to be empty. }
  Check('enum.members.simple.count', ParseEnumMembers(ED_SIMPLE, M) and (Length(M) = 3), IntToStr(Length(M)));
  Check('enum.members.simple.order', ParseEnumMembers(ED_SIMPLE, M) and (Length(M) = 3) and (M[0] = 'taLeftJustify') and (M[2] = 'taCenter'), 'declaration order must be preserved');
  Check('enum.members.multiline.count', ParseEnumMembers(ED_MULTILINE, M) and (Length(M) = 19), IntToStr(Length(M)));
  Check(
    'enum.members.multiline.ends', ParseEnumMembers(ED_MULTILINE, M) and (Length(M) = 19) and (M[0] = 'absAutoDetect') and (M[18] = 'absRecessedBlackHighlight'),
    'first/last member');
  Check(
    'enum.members.strips.explicit.values', ParseEnumMembers(ED_CONDITIONAL, M) and Contains(M, 'RIO_EVENT_COMPLETION') and not Contains(M, '1'), 'a "= 1" is a value, not a member'
  );
  { The non-empty guard is the point: without it this passes for free on an empty M. }
  Check(
    'enum.members.skips.directives.and.comments',
    ParseEnumMembers(ED_CONDITIONAL, M) and (Length(M) > 0) and not Contains(M, 'IFDEF') and not Contains(M, 'ELSE') and not Contains(M, 'do'),
    'compiler directives and // comments are not members');
  Check(
    'enum.members.dedupes.ifdef.arms', ParseEnumMembers(ED_CONDITIONAL, M) and (CountOf(M, 'RIO_EVENT_COMPLETION') = 1) and Contains(M, 'rnctUnused'),
    'both arms contribute, but a member named in both is listed once');
  Check('enum.nonenum.yields.none'   , not ParseEnumMembers(ED_CLASS, M) and (Length(M) = 0), 'a class has no enum members');
  Check('enum.empty.text.yields.none', not ParseEnumMembers(''      , M) and (Length(M) = 0), 'empty text has no members'  );
end; // procedure

{ End-to-end against the REAL exe and the REAL library index: the two adapter
  verbs the context menu calls. The parse cases above pin the shapes; this pins
  that the arguments, exit codes and source-range read are right too. }
procedure TestGoToDefinitionLive;
var
  Exe    : string        ;
  f      : string        ;
  Err    : string        ;
  Ln     : Integer       ;
  Adapter: TEngineAdapter;
  M      : TArray<string>;
begin
  Exe:= ResolveExe;
  if (Exe = '') or not TFile.Exists(LibWin64) then
  begin
    Skip('gotodef.live', 'drag-lint.exe or library-Win64 index not found');
    Exit;
  end;
  Adapter:= TEngineAdapter.Create(Exe, [LibWin64]);
  try
    Check(
      'gotodef.live.resolves.enum', Adapter.ResolveTypeLocation('TAlignment', f, Ln, Err) and SameText(ExtractFileName(f), 'System.Classes.pas') and (Ln = 176),
      f + ':' + IntToStr(Ln) + ' ' + Err);
    { Exit code 1 means "no hits", not "the engine broke" -- either way the caller
      must be told, never left with a stale or blank location. }
    Check('gotodef.live.unindexed.reports.reason', not Adapter.ResolveTypeLocation('TZzzNotARealTypeXyz', f, Ln, Err) and (Err <> ''), 'an unindexed type must fail WITH a reason');
    if Adapter.ResolveTypeLocation('TAlignment', f, Ln, Err) and TFile.Exists(f) then
      Check('gotodef.live.enum.members', Adapter.EnumMembersOf('TAlignment', M, Err) and (Length(M) = 3) and SameText(M[0], 'taLeftJustify'), Err + ' n=' + IntToStr(Length(M)))
    else
      Skip('gotodef.live.enum.members', 'RTL source not on disk');
    { Err too, not just the False: a silent failure would otherwise pass here, and
      the status bar has nothing to show the user when Err is empty. }
    Check(
      'gotodef.live.class.has.no.members', not Adapter.EnumMembersOf('TThread', M, Err) and (Err <> '') and (Length(M) = 0), 'a class is not an enum, and must say so: Err=' + Err);

    { LIVE corroboration of the VCL-preferred tie-break -- the fixture tests in
      TestQuerySymbolTieBreak are the specification; these two prove the real index
      and the real exe behave the way the fixtures say. Before the tie-break, both
      of these answered FireMonkey. }
    Check(
      'gotodef.live.vcl.beats.fmx', Adapter.ResolveTypeLocation('TEdit', f, Ln, Err) and SameText(ExtractFileName(f), 'Vcl.StdCtrls.pas'),
      'a bare TEdit must land in the VCL; got ' + f + ' ' + Err);
    { DeclaringUnitOf goes through ResolveClassQName, which is the OTHER caller of
      SelectQuerySymbol -- so this is what proves the qualification path (and with it
      all eight GetProptree call sites) inherits the same preference. }
    Check(
      'declaringunit.live.vcl.beats.fmx', SameText(Adapter.DeclaringUnitOf('TButton'), 'Vcl.StdCtrls'),
      'ResolveClassQName must inherit the tie-break; got ' + Adapter.DeclaringUnitOf('TButton'));
    Check(
      'declaringunit.live.tlabel', SameText(Adapter.DeclaringUnitOf('TLabel'), 'Vcl.StdCtrls'),
      'TLabel answered FMX.StdCtrls before the tie-break; got ' + Adapter.DeclaringUnitOf('TLabel'));
    { TColor is the third-party arm, live: every row is kind='type' (one tier), so
      only the family rank separates them, and the first one the engine lists is
      Spring.Logging.TColor.

      REVISED 2026-08-03, after the schema-v19 --force-reparse rebuilt the library
      indexes. That rebuild added a THIRD row this assertion had never seen:

        type  TColor  Spring.Logging.TColor : Graphics.TColor
        type  TColor  System.UITypes.TColor : -$7FFFFFFF-1..$7FFFFFFF
        type  TColor  Vcl.Graphics.TColor   : System.UITypes.TColor

      With only Spring.Logging and Vcl.Graphics present, FAM_VCL beat FAM_OTHER and
      the answer was Vcl.Graphics. Now that the real declaration is indexed,
      FAM_SYSTEM (0) outranks FAM_VCL (1) -- which is exactly what UnitFamilyRank's
      header specifies, and for exactly the reason it gives: Vcl.Graphics.TColor is
      an ALIAS of System.UITypes.TColor, and a real declaration outranks an alias to
      it. So the ranking did not change; the index stopped under-reporting. Do NOT
      "fix" this by moving FAM_VCL ahead of FAM_SYSTEM -- that would reverse the
      documented decision for every RTL type the VCL re-exports (PColor, INT32, ...),
      not just this one.

      The two assertions above still pin the VCL-over-FMX preference, which is the
      one this tool actually depends on: TEdit and TLabel have no System.* row. }
    Check(
      'gotodef.live.tcolor.is.system', Adapter.ResolveTypeLocation('TColor', f, Ln, Err) and SameText(ExtractFileName(f), 'System.UITypes.pas'),
      'TColor resolves to its real declaration, System.UITypes.TColor -- ' + 'Vcl.Graphics.TColor is an alias of it; got ' + f + ' ' + Err);
  finally
    Adapter.Free;
  end; // try
end; // procedure

{ #mapping declares a reusable enum -> property-value mapping ONCE, narrowed to a source
  enum and one or more target classes; #apply pulls it into a #convert block. One node per
  line -- the model is flat and must stay flat. #apply is NOT #use: #use already means
  "add a unit to the uses clause". }
procedure TestMappingRules;
var
  B: TRuleBook;
  n: TRuleNode;
begin
  B:= TRuleBook.Create;
  try
    n:= B.ParseLine('#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton, cxButtons.TcxBigButton');
    Check('mapping.kind', n.Kind = rnkMapping);
    Check('mapping.name'    , n.MapName     = 'XYZStyle'           , n.MapName    );
    Check('mapping.fromtype', n.MapFromType = 'XYZ.TXYZButtonStyle', n.MapFromType);
    Check('mapping.totypes.count', Length(n.MapToTypes) = 2, IntToStr(Length(n.MapToTypes)));
    Check('mapping.totypes.second', n.MapToTypes[1] = 'cxButtons.TcxBigButton', n.MapToTypes[1]);

    n:= B.ParseLine('#mapping XYZStyle #when Style = stOK -> Default = True, ModalResult = mrOk');
    Check('when.kind', n.Kind = rnkMapping);
    Check('when.name' , n.MapName   = 'XYZStyle', n.MapName  );
    Check('when.from' , n.WhenFrom  = 'Style'   , n.WhenFrom );
    Check('when.value', n.WhenValue = 'stOK'    , n.WhenValue);
    Check('when.not.else', not n.IsElse);
    Check('when.sets.count', Length(n.Sets) = 2, IntToStr(Length(n.Sets)));
    Check('when.sets.0.path' , n.Sets[0].ToPath = 'Default'    , n.Sets[0].ToPath);
    Check('when.sets.0.value', n.Sets[0].Value  = 'True'       , n.Sets[0].Value );
    Check('when.sets.1.path' , n.Sets[1].ToPath = 'ModalResult', n.Sets[1].ToPath);

    // Multi-level target paths must survive -- the whole point of the path model.
    n:= B.ParseLine('#mapping XYZStyle #when Style = stOK -> Style.ModalResult.Default = True');
    Check('when.nested.path', n.Sets[0].ToPath = 'Style.ModalResult.Default', n.Sets[0].ToPath);

    n:= B.ParseLine('#mapping XYZStyle #else -> ModalResult = mrNone');
    Check('else.is.else', n.IsElse);
    Check('else.sets', (Length(n.Sets) = 1) and (n.Sets[0].Value = 'mrNone'));

    n:= B.ParseLine('#apply XYZStyle');
    Check('apply.kind', n.Kind = rnkApply);
    Check('apply.name', n.ApplyName = 'XYZStyle', n.ApplyName);

    // #use must NOT be mistaken for #apply.
    n:= B.ParseLine('#use FireDAC.Comp.Client');
    Check('use.still.means.unit', n.Kind = rnkUse, 'use must stay a uses-clause directive');
  finally
    B.Free;
  end; // try
end; // procedure

{ An unedited line must come back byte-for-byte; a rule book that rewrites lines it did not
  change makes every diff unreadable. }
procedure TestMappingRoundTrip;
const
  SRC = '#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton'#13#10 + '#mapping XYZStyle #when Style = stOK -> Default = True, ModalResult = mrOk'#13#10 +
  '#mapping XYZStyle #else -> ModalResult = mrNone'#13#10 + '#convert XYZ.TXYZToggleButton -> cxButtons.TcxButton'#13#10 + '  #apply XYZStyle'#13#10;
var
  B: TRuleBook;
begin
  B:= TRuleBook.Create;
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
  n: TRuleNode;
begin
  B:= TRuleBook.Create;
  try
    n:= B.ParseLine('#mapping XYZStyle #when Style = stOK');
    Check('when.noarrow.kind', n.Kind = rnkMapping);
    Check('when.noarrow.name', n.MapName = 'XYZStyle', n.MapName);
    Check('when.noarrow.from' , n.WhenFrom  = 'Style', '[' + n.WhenFrom  + ']');
    Check('when.noarrow.value', n.WhenValue = 'stOK' , '[' + n.WhenValue + ']');
    Check('when.noarrow.nosets', Length(n.Sets) = 0, IntToStr(Length(n.Sets)));
    { A condition with no '=' either: the path must survive rather than vanish. }
    n:= B.ParseLine('#mapping XYZStyle #when Style');
    Check('when.noeq.from', n.WhenFrom = 'Style', '[' + n.WhenFrom + ']');
  finally
    B.Free;
  end; // try
end; // procedure

{ Emit's #mapping/#apply branches only run for an EDITED (Dirty) node -- an untouched
  line returns Raw -- so the round-trip test alone would pass even against a parser
  that never recognised #mapping. This drives Emit directly and pins the canonical
  text of all three #mapping forms plus #apply in the suite, permanently. }
procedure TestMappingEmit;
var
  n   : TRuleNode       ;
  B   : TRuleBook       ;
  Sets: TArray<TSetPair>;

  { Parse a line, mark it edited, and re-emit: the canonical serialization must be a
    FIXPOINT of the canonical source text, or editing one field of an untouched line
    silently reformats it. }
  function ReEmit(const ALine: string): string;
  var
    Nd: TRuleNode;
  begin
    Nd:= B.ParseLine(ALine);
    try
      Nd.Dirty:= True;
      Result:= Nd.Emit;
    finally
      Nd.Free;
    end;
  end;

begin
  n:= TRuleNode.Create;
  try
    n.Kind       := rnkMapping;
    n.Dirty      := True;
    n.MapName    := 'XYZStyle';
    n.MapFromType:= 'XYZ.TXYZButtonStyle';
    n.MapToTypes:= TArray<string>.Create('cxButtons.TcxButton', 'cxButtons.TcxBigButton');
    Check('emit.decl', n.Emit = '#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton, cxButtons.TcxBigButton', n.Emit);
  finally
    n.Free;
  end;

  SetLength(Sets, 2);
  Sets[0].ToPath:= 'Default'    ; Sets[0].Value:= 'True';
  Sets[1].ToPath:= 'ModalResult'; Sets[1].Value:= 'mrOk';

  n:= TRuleNode.Create;
  try
    n.Kind     := rnkMapping;
    n.Dirty    := True;
    n.MapName  := 'XYZStyle';
    n.WhenFrom := 'Style';
    n.WhenValue:= 'stOK';
    n.Sets     := Sets;
    Check('emit.when', n.Emit = '#mapping XYZStyle #when Style = stOK -> Default = True, ModalResult = mrOk', n.Emit);
  finally
    n.Free;
  end; // try

  n:= TRuleNode.Create;
  try
    n.Kind   := rnkMapping;
    n.Dirty  := True;
    n.MapName:= 'XYZStyle';
    n.IsElse := True;
    n.Sets:= Copy(Sets, 1, 1); // ModalResult = mrOk
    Check('emit.else', n.Emit = '#mapping XYZStyle #else -> ModalResult = mrOk', n.Emit);
  finally
    n.Free;
  end;

  n:= TRuleNode.Create;
  try
    n.Kind     := rnkApply;
    n.Dirty    := True;
    n.ApplyName:= 'XYZStyle';
    Check('emit.apply', n.Emit = '#apply XYZStyle', n.Emit);
  finally
    n.Free;
  end;

  { parse -> edit -> emit must be a fixpoint for every form. }
  B:= TRuleBook.Create;
  try
    Check(
      'emit.fixpoint.decl', ReEmit('#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton') = '#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton',
      ReEmit('#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton'));
    Check(
      'emit.fixpoint.when',
      ReEmit('#mapping XYZStyle #when Style = stOK -> Default = True, ModalResult = mrOk') = '#mapping XYZStyle #when Style = stOK -> Default = True, ModalResult = mrOk',
      ReEmit('#mapping XYZStyle #when Style = stOK -> Default = True, ModalResult = mrOk'));
    Check(
      'emit.fixpoint.else', ReEmit('#mapping XYZStyle #else -> ModalResult = mrNone') = '#mapping XYZStyle #else -> ModalResult = mrNone',
      ReEmit('#mapping XYZStyle #else -> ModalResult = mrNone'));
    Check('emit.fixpoint.apply', ReEmit('#apply XYZStyle') = '#apply XYZStyle', ReEmit('#apply XYZStyle'));
  finally
    B.Free;
  end; // try
end; // begin

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
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(
      '#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton'#13#10 + '#convert XYZ.TXYZToggleButton -> cxButtons.TcxButton'#13#10 + // #apply only: KEEP
      '  #apply XYZStyle'#13#10 + '#convert C.TFoo -> D.TBar'#13#10 + // #note only: DROP
      '#note nothing mapped yet'#13#10);
    outp:= Book.SaveCompleteToString(dropped);
    Check('savecomplete.apply.dropcount', dropped = 1, IntToStr(dropped));
    Check('savecomplete.apply.keeps.header', Pos('#convert XYZ.TXYZToggleButton -> cxButtons.TcxButton', outp) > 0, 'an #apply-only block was dropped as if empty');
    Check('savecomplete.apply.keeps.body', Pos('#apply XYZStyle', outp) > 0, outp);
    Check('savecomplete.apply.keeps.mapping', Pos('#mapping XYZStyle from', outp) > 0, 'the #mapping declaration was lost');
    Check('savecomplete.apply.still.drops.note', Pos('C.TFoo', outp) = 0, 'a #note-only block is still scratch');
  finally
    Book.Free;
  end; // try
end; // procedure

{ "Does this block map anything" had TWO answers on this branch: SaveCompleteToString
  rescued [rnkLink, rnkApply] while the rules list's completeness percentage counted
  [rnkLink, rnkIgnore]. An #apply-only block therefore read as 0 % while being a finished
  rule, and an #ignore-only block read as 100 % and was then dropped on save as "empty".
  TRuleBook.BlockMapsSomething is now the single answer, and this pins its membership:
  #link, #apply and #ignore each DECIDE the fate of a source property; #note (and a bare
  block) decide nothing. A #mapping is deliberately NOT a member -- it is a declaration
  and maps nothing until an #apply names it. }
procedure TestBlockMapsSomething;
var
  Book: TRuleBook      ;
  Hdrs: TArray<Integer>;
begin
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(
      '#convert A.T1 -> B.T1'#13#10 + '#link X <- Y'#13#10 + '#convert A.T2 -> B.T2'#13#10 + '#apply M'#13#10 + '#convert A.T3 -> B.T3'#13#10 + '#ignore Foo'#13#10 +
      '#convert A.T4 -> B.T4'#13#10 + '#note nothing mapped yet'#13#10 + '#convert A.T5 -> B.T5'#13#10 + '#mapping M from E to B.T5'#13#10);
    Hdrs:= Book.ConvertHeaders;
    Check('blockmaps.headers', Length(Hdrs) = 5, IntToStr(Length(Hdrs)));
    // Every index below is guarded by the SAME length test in the same expression: an
    // unguarded index would abort the runner with exit 2 and no summary line.
    Check('blockmaps.link', (Length(Hdrs) = 5) and TRuleBook.BlockMapsSomething(Book.NodesInBlock(Hdrs[0])));
    Check('blockmaps.apply', (Length(Hdrs) = 5) and TRuleBook.BlockMapsSomething(Book.NodesInBlock(Hdrs[1])), 'an #apply-only block maps something');
    Check('blockmaps.ignore', (Length(Hdrs) = 5) and TRuleBook.BlockMapsSomething(Book.NodesInBlock(Hdrs[2])), 'an #ignore is an authored decision about a source property');
    Check('blockmaps.note', (Length(Hdrs) = 5) and not TRuleBook.BlockMapsSomething(Book.NodesInBlock(Hdrs[3])), 'a #note-only block is annotation, not a rule');
    Check(
      'blockmaps.mappingonly', (Length(Hdrs) = 5) and not TRuleBook.BlockMapsSomething(Book.NodesInBlock(Hdrs[4])), 'a #mapping DECLARATION maps nothing until an #apply names it');
    Check('blockmaps.emptyarray', not TRuleBook.BlockMapsSomething(nil));
  finally
    Book.Free;
  end; // try
end; // procedure

{ The other half of the same disagreement: an #ignore-only block used to show 100 %
  complete in the rules list and then be silently dropped on save as an empty rule.
  Now that both sides read BlockMapsSomething it is KEPT. The #note-only block in the
  same fixture is still scratch, so this does not simply rescue everything. }
procedure TestSaveCompleteKeepsIgnoreOnly;
var
  Book   : TRuleBook;
  dropped: Integer  ;
  outp   : string   ;
begin
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(
      '#convert A.TFrom -> B.TTo'#13#10 + // #ignore only: KEEP
      '#ignore Caption'#13#10 + '#convert C.TFoo -> D.TBar'#13#10 + // #note only: DROP
      '#note nothing mapped yet'#13#10);
    outp:= Book.SaveCompleteToString(dropped);
    Check('savecomplete.ignore.dropcount', dropped = 1, IntToStr(dropped));
    Check('savecomplete.ignore.keeps.header', Pos('#convert A.TFrom -> B.TTo', outp) > 0, 'an #ignore-only block was dropped as if empty');
    Check('savecomplete.ignore.keeps.body'  , Pos('#ignore Caption'          , outp) > 0, outp                                           );
    Check('savecomplete.ignore.still.drops.note', Pos('C.TFoo', outp) = 0, 'a #note-only block is still scratch');
  finally
    Book.Free;
  end; // try
end; // procedure

{ The mapping splice used to be index arithmetic in the VCL layer -- collect indices,
  delete descending, insert at Idx[0] -- which the console suite cannot link, and BOTH
  data-loss bugs this feature shipped with were in that seam. It now lives in
  TRuleBook.ReplaceMapping, so it can be pinned:
    * a mapping that already exists is replaced IN PLACE, so one written inside a
      #convert block stays inside that block;
    * a name not yet present goes ABOVE the first #convert -- file scope;
    * a book with no #convert at all takes it at the top;
    * [] deletes the mapping outright.
  Ownership: ParseLine hands out unowned nodes and ReplaceMapping takes them, so nothing
  here is freed twice and nothing leaks. }
procedure TestReplaceMapping;
var
  Book : TRuleBook        ;
  Nodes: TArray<TRuleNode>;
  Body : TArray<TRuleNode>;
  outp : string           ;
begin
  { --- existing mapping, inside a block: replaced in place --- }
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString( '#convert A.TFrom -> B.TTo'#13#10 + '#link X <- Y'#13#10 + '#mapping M from E.TOld to B.TTo'#13#10 + '#mapping M #when a -> P = 1'#13#10 + '#apply M'#13#10);
    Nodes:= Book.MappingNodesNamed('M');
    Check('replacemapping.found.before', Length(Nodes) = 2, IntToStr(Length(Nodes)));
    Check('replacemapping.found.other', Length(Book.MappingNodesNamed('Nope')) = 0);
    Check('replacemapping.found.blank', Length(Book.MappingNodesNamed(''    )) = 0);

    // TWO replacement lines, because a real mapping is always a declaration plus its
    // clauses -- and their ORDER is load-bearing: a clause emitted before its
    // declaration is not the same mapping.
    Book.ReplaceMapping('M', [Book.ParseLine('#mapping M from E.TNew to B.TTo'), Book.ParseLine('#mapping M #when b -> P = 2')]);
    outp:= Book.SaveToString;
    Check('replacemapping.new.written', Pos('#mapping M from E.TNew to B.TTo', outp) > 0, outp);
    Check('replacemapping.old.gone'   , Pos('E.TOld' , outp) = 0, 'the old line survived'                                                 );
    Check('replacemapping.clause.gone', Pos('#when a', outp) = 0, 'the mapping is rewritten as ONE unit -- stale clauses must not survive');
    Check('replacemapping.count.after', Length(Book.MappingNodesNamed('M')) = 2, IntToStr(Length(Book.MappingNodesNamed('M'))));
    Check(
      'replacemapping.order.preserved', (Pos('E.TNew', outp) > 0) and (Pos('#when b', outp) > 0) and (Pos('E.TNew', outp) < Pos('#when b', outp)),
      'the replacement lines were inserted out of order');

    // In place: it went back where the old lines were, which is INSIDE the block, and
    // the block's other nodes kept their order (#link before it, #apply after).
    Body:= Book.NodesInBlock(0);
    Check('replacemapping.inblock.len', Length(Body) = 4, IntToStr(Length(Body)));
    Check(
      'replacemapping.inblock.order', (Length(Body) = 4) and (Body[0].Kind = rnkLink) and (Body[1].Kind = rnkMapping) and (Body[2].Kind = rnkMapping) and (Body[3].Kind = rnkApply),
      'the splice reordered the block');

    // [] deletes the mapping outright, leaving the rest of the block untouched.
    Book.ReplaceMapping('M', []);
    Check('replacemapping.delete', Length(Book.MappingNodesNamed('M')) = 0);
    Check('replacemapping.delete.keeps.link', Pos('#link X <- Y', Book.SaveToString) > 0);
    Check('replacemapping.delete.keeps.apply', Pos('#apply M', Book.SaveToString) > 0, 'deleting the declaration must not delete the #apply that names it');
  finally
    Book.Free;
  end; // try

  { --- name not present: lands above the FIRST #convert, i.e. at file scope --- }
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString( '// lead comment'#13#10 + '#convert A.TFrom -> B.TTo'#13#10 + '#link X <- Y'#13#10);
    Book.ReplaceMapping('N', [Book.ParseLine('#mapping N from E.T to B.TTo')]);
    Check('replacemapping.new.name.count', Length(Book.MappingNodesNamed('N')) = 1);
    Check(
      'replacemapping.new.name.pos', (Book.Nodes.Count > 2) and (Book.Nodes[1].Kind = rnkMapping) and (Book.Nodes[2].Kind = rnkConvert),
      'a brand-new mapping must sit ABOVE the first #convert, not inside a block');
    // Header sits at index 2 now (comment, mapping, convert, link).
    Body:= Book.NodesInBlock(2);
    Check('replacemapping.new.name.notinblock', (Length(Body) = 1) and (Body[0].Kind = rnkLink), 'the block body must still be just its #link');
  finally
    Book.Free;
  end; // try

  { --- no #convert anywhere: the top of the file is the only file scope --- }
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString('// only a comment'#13#10);
    Book.ReplaceMapping('N', [Book.ParseLine('#mapping N from E.T to B.T')]);
    Check('replacemapping.noconvert.pos', (Book.Nodes.Count > 0) and (Book.Nodes[0].Kind = rnkMapping), 'with no #convert header the mapping goes to the top');
    Check('replacemapping.noconvert.comment.kept', Pos('// only a comment', Book.SaveToString) > 0);
  finally
    Book.Free;
  end;
end; // procedure

{ One flattened property-tree leaf. Mapping validation only reads Path and IsWritable,
  so those are what the fixture pins; the rest is filled in plausibly so the record is
  never half-initialised. }
function MakeLeaf(const APath, ATypeName: string; AWritable: Boolean): TPropLeaf;
begin
  Result:= Default(TPropLeaf);
  Result.Path      := APath;
  Result.TypeName  := ATypeName;
  Result.Kind      := 'scalar';
  Result.IsWritable:= AWritable;
  Result.Visibility:= 'published';
  Result.MemberKind:= 'property';
end;

{ A TProptree standing in for a real `drag-lint proptree` result, so mapping validation
  is testable with no index, no exe and no process spawn. }
function MakeTreeFixture(const ALeaves: TArray<TPropLeaf>): TProptree;
begin
  Result:= Default(TProptree);
  Result.Qname   := 'cxButtons.TcxButton';
  Result.RootType:= 'cxButtons.TcxButton';
  Result.Leaves  := ALeaves;
end;

{ Parse a rule-book fragment into the flat node array a validator consumes. The nodes
  belong to GParseBook (program lifetime), never to the caller. }
function ParseAll(const ALines: TArray<string>): TArray<TRuleNode>;
var
  i: Integer;
begin
  if GParseBook = nil then
    GParseBook:= TRuleBook.Create;
  SetLength(Result, Length(ALines));
  for i:= 0 to High(ALines) do
    Result[i]:= GParseBook.Add(GParseBook.ParseLine(ALines[i]));
end;

{ Validation is what makes the mapping trustworthy: an unwritable or absent target is a rule
  that will silently do nothing at apply time. Non-exhaustive is a WARNING, not an error --
  leaving a member unmapped is a legitimate choice. }
procedure TestMappingValidation;
var
  Tree  : TProptree            ;
  Nodes : TArray<TRuleNode>    ;
  Issues: TArray<TMappingIssue>;

  function HasKind(const A: TArray<TMappingIssue>; k: TMappingIssueKind): Boolean;
  var
    it: TMappingIssue;
  begin
    for it in A do if it.Kind = k then Exit(True);
    Result:= False;
  end;
begin
  Tree:= MakeTreeFixture([
      MakeLeaf('Default', 'Boolean', True), MakeLeaf('ModalResult', 'TModalResult', True), MakeLeaf('Handle', 'HWND', False) // read-only
    ]);

  Nodes:= ParseAll([ '#mapping M from X.TStyle to cxButtons.TcxButton', '#mapping M #when Style = stOK -> Default = True' ]);
  Issues:= ValidateMappings(Nodes, Tree, ['stOK'], 'cxButtons.TcxButton');
  Check('validate.clean', Length(Issues) = 0, 'a valid mapping reported issues');

  Nodes:= ParseAll([ '#mapping M from X.TStyle to cxButtons.TcxButton', '#mapping M #when Style = stOK -> Nope = True' ]);
  Check('validate.missing.target', HasKind(ValidateMappings(Nodes, Tree, ['stOK'], 'cxButtons.TcxButton'), mikTargetMissing));

  Nodes:= ParseAll([ '#mapping M from X.TStyle to cxButtons.TcxButton', '#mapping M #when Style = stOK -> Handle = 1' ]);
  Check('validate.readonly.target', HasKind(ValidateMappings(Nodes, Tree, ['stOK'], 'cxButtons.TcxButton'), mikTargetReadOnly));

  // Applying to a class the mapping never declared.
  Nodes:= ParseAll([ '#mapping M from X.TStyle to cxButtons.TcxButton', '#mapping M #when Style = stOK -> Default = True' ]);
  Check('validate.totype.not.declared', HasKind(ValidateMappings(Nodes, Tree, ['stOK'], 'Vcl.StdCtrls.TButton'), mikToTypeNotDeclared));

  // Two members, one #when, no #else -> WARN, and it must NOT be reported as an error kind.
  Nodes:= ParseAll([ '#mapping M from X.TStyle to cxButtons.TcxButton', '#mapping M #when Style = stOK -> Default = True' ]);
  Issues:= ValidateMappings(Nodes, Tree, ['stOK', 'stCancel'], 'cxButtons.TcxButton');
  Check('validate.nonexhaustive.warns', HasKind(Issues, mikNonExhaustive));
  Check('validate.nonexhaustive.not.fatal', not HasKind(Issues, mikTargetMissing), 'a gap must not masquerade as a missing target');

  // An #else closes the gap.
  Nodes:= ParseAll([ '#mapping M from X.TStyle to cxButtons.TcxButton', '#mapping M #when Style = stOK -> Default = True', '#mapping M #else -> ModalResult = mrNone' ]);
  Check('validate.else.closes.gap', not HasKind(ValidateMappings(Nodes, Tree, ['stOK','stCancel'], 'cxButtons.TcxButton'), mikNonExhaustive));

  Check('validate.apply.undefined', HasKind(ValidateMappings(ParseAll(['#apply Ghost']), Tree, [], 'cxButtons.TcxButton'), mikUndefined));
end; // begin

{ File-level twin of the nested HasKind inside TestMappingValidation. That procedure is
  plan-mandated text and is kept verbatim, so its private helper is not hoisted out of it;
  the tests below get their own. }
function HasIssueKind(const A: TArray<TMappingIssue>; k: TMappingIssueKind): Boolean;
var
  it: TMappingIssue;
begin
  for it in A do
    if it.Kind = k then
      Exit(True);
  Result:= False;
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
  Tree:= MakeTreeFixture([MakeLeaf('Default', 'Boolean', True)]);

  Issues:= ValidateMappings(
    ParseAll([ '#mapping M from X.TStyle to cxButtons.TcxButton', '#mapping M #when Style = stBogus -> Default = True' ]), Tree, ['stOK'], 'cxButtons.TcxButton');
  Check('validate.bad.literal', HasIssueKind(Issues, mikBadLiteral), 'a #when on a non-member fired no mikBadLiteral');
  // Detected AND advisory -- both halves pinned together so neither can be dropped on its
  // own. The member list this was judged against comes from an index that often cannot
  // see the enum, so the CHECK may be the thing that is wrong; an editor must show this
  // and still allow the save. Reported always, blocking never.
  Check('validate.bad.literal.is.advisory', HasIssueKind(Issues, mikBadLiteral) and MappingIssueIsWarning(mikBadLiteral), 'a bad literal must be REPORTED and left NON-BLOCKING');

  // A value that IS a member must not be flagged -- the check must discriminate.
  Issues:= ValidateMappings(
    ParseAll([ '#mapping M from X.TStyle to cxButtons.TcxButton', '#mapping M #when Style = stOK -> Default = True' ]), Tree, ['stOK'], 'cxButtons.TcxButton');
  Check('validate.good.literal.not.flagged', not HasIssueKind(Issues, mikBadLiteral), 'a legitimate enum member was reported as a bad literal');

  // Members unknown (empty list) -> the question is unanswerable, so stay silent rather
  // than flag every literal. This is the guard the doc-comment promises.
  Issues:= ValidateMappings(ParseAll([ '#mapping M from X.TStyle to cxButtons.TcxButton', '#mapping M #when Style = stBogus -> Default = True' ]), Tree, [], 'cxButtons.TcxButton');
  Check('validate.literal.unknown.members.silent', not HasIssueKind(Issues, mikBadLiteral), 'an unknown member list must not manufacture bad-literal issues');

  // An '#else' has no literal at all and must never be judged against the member list.
  Issues:= ValidateMappings(ParseAll([ '#mapping M from X.TStyle to cxButtons.TcxButton', '#mapping M #else -> Default = True' ]), Tree, ['stOK'], 'cxButtons.TcxButton');
  Check('validate.else.has.no.literal', not HasIssueKind(Issues, mikBadLiteral), 'an #else was judged as if it carried an enum literal');
end; // procedure

{ The warning/error split must live in ONE place, or Task 7's OK-button gate re-derives it
  and the two copies eventually disagree. The expected table is indexed BY THE ENUM, so
  adding a kind without classifying it fails to COMPILE (E2072) rather than silently
  defaulting to "error". }
procedure TestMappingIssueSeverity;
const
  EXPECTED: array[TMappingIssueKind] of Boolean = (
    False, // mikUndefined         -- #apply names a mapping that does not exist
    False, // mikTargetMissing     -- assignment to a property the class has not got
    False, // mikTargetReadOnly    -- assignment that cannot happen
    True, // mikBadLiteral        -- WARNING: the member list this was judged against
    //                         comes from an index that often cannot see the enum
    //                         (method-pointer types are not indexed at all,
    //                         TColor resolves ambiguously), so a correct literal
    //                         can be flagged. Report it; never block a save on it.
    False, // mikToTypeNotDeclared -- applied outside the mapping's declared contract
    True // mikNonExhaustive     -- WARNING: an unmapped member is an authoring choice
  );
  Names: array[TMappingIssueKind] of string = ( 'mikUndefined', 'mikTargetMissing', 'mikTargetReadOnly', 'mikBadLiteral', 'mikToTypeNotDeclared', 'mikNonExhaustive' );
var
  k       : TMappingIssueKind;
  Warnings: Integer          ;
begin
  Warnings:= 0;
  for k:= Low(TMappingIssueKind) to High(TMappingIssueKind) do
  begin
    Check(
      'severity.' + Names[k], MappingIssueIsWarning(k) = EXPECTED[k],
      Names[k] + ' is classified as ' + (if MappingIssueIsWarning(k) then 'a warning' else 'an error') + ', expected the opposite');
    if MappingIssueIsWarning(k) then
      Inc(Warnings);
  end;
  // Counted from the ACTUAL classifier, not the table: a classifier that answers False
  // (or True) for everything fails here as well as above.
  Check('severity.exactly.two.warnings', Warnings = 2, 'expected exactly 2 warning kinds, got ' + IntToStr(Warnings));
end; // procedure

{ BuildMappingNodes hands OWNERSHIP to the caller (unlike ParseAll, whose nodes belong to
  GParseBook), so a test that builds must free. }
procedure FreeNodes(const ANodes: TArray<TRuleNode>);
var
  n: TRuleNode;
begin
  for n in ANodes do
    n.Free;
end;

{ The fold/unfold pair is what keeps the mapping EDITOR a thin window: one case per enum
  member to show, one node per physical line to store. Anything the fold drops -- a #when
  on a literal the enum has not got, a member with no assignments -- is either a rule the
  author would never see again or a line that should never have been written. }
procedure TestMappingFold;
var
  Nodes  : TArray<TRuleNode>   ;
  Cases  : TArray<TMappingCase>;
  Built  : TArray<TRuleNode>   ;
  Emitted: string              ;
  n      : TRuleNode           ;

  function CaseFor(const AMember: string): Integer;
  var
    i: Integer;
  begin
    Result:= -1;
    for i:= 0 to High(Cases) do
      if (not Cases[i].IsElse) and SameText(Cases[i].Member, AMember) then
        Exit(i);
  end;

begin
  Nodes:= ParseAll([
      '#mapping M from X.TStyle to cxButtons.TcxButton, cxButtons.TcxBigButton', '#mapping M #when Style = stOK -> Default = True, ModalResult = mrOk',
      '#mapping M #when Style = stGhost -> Cancel = True', '#mapping M #else -> ModalResult = mrNone']);

  Check('fold.names', (Length(MappingNames(Nodes)) = 1) and (MappingNames(Nodes)[0] = 'M'), 'one mapping is declared here');
  Check('fold.decl.found', MappingDeclaration(Nodes, 'm') <> nil, 'the name match is case-insensitive, like the rest of the DSL');
  Check('fold.whenfrom', MappingWhenFrom(Nodes, 'M') = 'Style', MappingWhenFrom(Nodes, 'M'));
  Check('fold.whenvalues', string.Join(',', MappingWhenValues(Nodes, 'M')) = 'stOK,stGhost', string.Join(',', MappingWhenValues(Nodes, 'M')));

  Cases:= MappingCasesOf(Nodes, 'M', ['stOK', 'stCancel']);
  // Every index below is guarded IN THE SAME EXPRESSION, because Check reports and
  // returns -- it does not abort. An unguarded Cases[3] after a length check that merely
  // FAILED would take the whole runner down with exit 2 and no summary line, turning one
  // regression into no results at all.
  Check('fold.case.count', Length(Cases) = 4, '2 enum members + the off-list stGhost + the #else, got ' + IntToStr(Length(Cases)));
  Check('fold.member.order', (Length(Cases) > 1) and (Cases[0].Member = 'stOK') and (Cases[1].Member = 'stCancel'), 'cases follow the ENUM declaration order, not the file order');
  Check('fold.sets', (Length(Cases) > 0) and (Length(Cases[0].Sets) = 2), 'stOK maps two targets');
  Check('fold.unmapped.member.empty', (Length(Cases) > 1) and (Length(Cases[1].Sets) = 0), 'stCancel has no #when, so its case must come back empty');
  Check('fold.offlist.kept', CaseFor('stGhost') = 2, 'a #when on a value the enum has not got was dropped instead of shown');
  Check('fold.else.last', (Length(Cases) > 0) and Cases[High(Cases)].IsElse, 'the #else pseudo-member must sit at the END of the member list');
  Check('fold.else.sets', (Length(Cases) > 3) and (Length(Cases[3].Sets) = 1) and (Cases[3].Sets[0].ToPath = 'ModalResult'), 'the #else carries its own assignments');
  Check(
    'fold.whenfrom.blank.when.primary', (Length(Cases) > 0) and (Cases[0].WhenFrom = ''),
    'a case reading the mapping''s own source property must not pin it, or renaming that ' + 'property in one field stops working');

  Built:= BuildMappingNodes('M', 'X.TStyle', ['cxButtons.TcxButton', 'cxButtons.TcxBigButton'], 'Style', Cases);
  try
    Emitted:= '';
    for n in Built do
      Emitted:= Emitted + n.Emit + #13#10;
    Check('unfold.count', Length(Built) = 4, IntToStr(Length(Built)) + ': ' + Emitted);
    Check('unfold.decl.first', (Length(Built) > 0) and (Built[0].Emit = '#mapping M from X.TStyle to cxButtons.TcxButton, cxButtons.TcxBigButton'), Emitted);
    Check('unfold.when', Pos('#mapping M #when Style = stOK -> Default = True, ModalResult = mrOk', Emitted) > 0, Emitted);
    Check('unfold.skips.unmapped', Pos('stCancel', Emitted) = 0, 'a member with no assignments must emit no clause at all');
    Check('unfold.else.last', (Length(Built) > 3) and (Built[3].Emit = '#mapping M #else -> ModalResult = mrNone'), Emitted);
  finally
    FreeNodes(Built);
  end; // try

  // No source type -> NO declaration line, and the target classes go with it. MapFromType
  // is the only thing that marks a node as a declaration (IsDeclaration tests exactly
  // that, and Emit branches on it), so a node holding target classes but no source type
  // would be re-read as a CLAUSE and emitted as '#mapping M #when  =  -> ' -- a line the
  // grammar has not got. The guard belongs here, not in whatever UI happens to call this.
  Built:= BuildMappingNodes('M', '', nil, 'Style', Cases);
  try
    Check('unfold.no.decl.without.fromtype', (Length(Built) = 3) and (Built[0].WhenValue = 'stOK'), IntToStr(Length(Built)));
  finally
    FreeNodes(Built);
  end;

  // ... and target classes ALONE must not conjure one either: that was the shape that
  // emitted the malformed line.
  Built:= BuildMappingNodes('M', '', ['cxButtons.TcxButton'], 'Style', Cases);
  try
    Emitted:= '';
    for n in Built do
      Emitted:= Emitted + n.Emit + #13#10;
    Check('unfold.totypes.alone.emit.no.decl', Length(Built) = 3, IntToStr(Length(Built)) + ': ' + Emitted);
    Check('unfold.no.malformed.when', Pos('#when  =', Emitted) = 0, 'a target-classes-only node was emitted through the #when branch: ' + Emitted);
  finally
    FreeNodes(Built);
  end;
end; // begin

{ A mapping may test more than one source property -- the model allows a WhenFrom per
  clause, and ConditionalFromPaths already reports a path per clause. Folding on the VALUE
  alone made '#when Style = stOK' and '#when Kind = stOK' collide: one round-tripped line
  reading Style, the second condition destroyed and its assignments silently re-homed onto
  the first. Nothing warned; the file just came back wrong. }
procedure TestMappingDivergentWhenFrom;
var
  Nodes  : TArray<TRuleNode>   ;
  Cases  : TArray<TMappingCase>;
  Built  : TArray<TRuleNode>   ;
  Emitted: string              ;
  n      : TRuleNode           ;
begin
  Nodes:= ParseAll([ '#mapping D from X.TStyle to C.TBtn', '#mapping D #when Style = stOK -> Default = True', '#mapping D #when Kind = stOK -> Cancel = True' ]);

  Check('divergent.primary', MappingWhenFrom(Nodes, 'D') = 'Style', 'the FIRST clause names the primary property, got ' + MappingWhenFrom(Nodes, 'D'));

  Cases:= MappingCasesOf(Nodes, 'D', ['stOK']);
  // one member case (Style/stOK) + the divergent Kind/stOK + the #else
  Check('divergent.case.count', Length(Cases) = 3, 'the two clauses collapsed into one case, got ' + IntToStr(Length(Cases)));
  Check(
    'divergent.primary.case.unpinned', (Length(Cases) > 0) and (Cases[0].WhenFrom = '') and (Length(Cases[0].Sets) = 1) and (Cases[0].Sets[0].ToPath = 'Default'),
    'the primary case must hold ONLY its own clause''s assignments');
  Check(
    'divergent.case.pins.its.property',
    (Length(Cases) > 1) and (Cases[1].Member = 'stOK') and (Cases[1].WhenFrom = 'Kind') and (Length(Cases[1].Sets) = 1) and (Cases[1].Sets[0].ToPath = 'Cancel'),
    'the clause on a different source property must keep it, and keep its own sets');

  Built:= BuildMappingNodes('D', 'X.TStyle', ['C.TBtn'], 'Style', Cases);
  try
    Emitted:= '';
    for n in Built do
      Emitted:= Emitted + n.Emit + #13#10;
    Check('divergent.roundtrip.style', Pos('#mapping D #when Style = stOK -> Default = True', Emitted) > 0, Emitted);
    Check('divergent.roundtrip.kind', Pos('#mapping D #when Kind = stOK -> Cancel = True', Emitted) > 0, 'the second condition was lost: ' + Emitted);
    Check('divergent.no.merge', Pos('Default = True, Cancel = True', Emitted) = 0, 'the two clauses'' assignments were merged onto one line: ' + Emitted);
  finally
    FreeNodes(Built);
  end;

  // The uniform case still follows the caller's AWhenFrom, or renaming the source
  // property in one field would stop reaching the clauses.
  Nodes:= ParseAll([ '#mapping U from X.TStyle to C.TBtn', '#mapping U #when Style = stOK -> Default = True' ]);
  Cases:= MappingCasesOf(Nodes, 'U', ['stOK']);
  Built:= BuildMappingNodes('U', 'X.TStyle', ['C.TBtn'], 'Kind', Cases);
  try
    Emitted:= '';
    for n in Built do
      Emitted:= Emitted + n.Emit + #13#10;
    Check('uniform.follows.rename', Pos('#mapping U #when Kind = stOK -> Default = True', Emitted) > 0, Emitted);
  finally
    FreeNodes(Built);
  end;
end; // procedure

{ What the mapping grid, the To pool and Auto-Match have to agree on: a From leaf an
  applied #mapping decides is NOT unassigned, and the targets that mapping sets are NOT
  free. Three call sites, one answer, so they cannot drift apart. }
{ ConvRules.FormTypes -- the form-types panel's harvest and its pure filter
  predicates. Shapes are taken from ORM3 CLIENT\VARINSP.dfm: nested objects, an
  'inherited' frame header, a collection item carrying a '[0]' index, and a
  Caption whose LITERAL contains something that looks like an object header. }
const
  FT_DFM = 'object VARINSPForm: TVARINSPForm'#13#10 + '  Caption = ''Variance Inspector'''#13#10 + '  object Panel1: TPanel'#13#10 + '    object lblA: TLabel'#13#10 +
  '      Caption = ''object fake: TNotReal'''#13#10 + '    end'#13#10 + '    object lblB: TLabel'#13#10 + '    end'#13#10 + '    object tbl: TOvcTable'#13#10 + '    end'#13#10 +
  '  end'#13#10 + '  inherited Frame1: TMyFrame'#13#10 + '  end'#13#10 + '  object col1: TcxGridDBColumn [0]'#13#10 + '  end'#13#10 + 'end'#13#10;

function FtFind(const ARows: TFormTypeRows; const AName: string; Out ARow: TFormTypeRow): Boolean;
var
  R: TFormTypeRow;
begin
  Result:= False;
  for R in ARows do
    if SameText(R.TypeName, AName) then
    begin ARow:= R; Exit(True); end;
end;

function FtCountOf(const ARows: TFormTypeRows; const AName: string): Integer;
var
  R: TFormTypeRow;
begin
  if FtFind(ARows, AName, R) then
    Result:= R.Count
  else
    Result:= -1;
end;

procedure TestFormTypesScan;
var
  Rows  : TFormTypeRows;
  Merged: TFormTypeRows;
  Row   : TFormTypeRow ;
  Names : string       ;
  R     : TFormTypeRow ;
begin
  Rows:= ScanDfmTypes(FT_DFM);

  Check('formtypes.scan.distinct', Length(Rows) = 6, Format('expected 6 distinct types, got %d', [Length(Rows)]));
  Check('formtypes.scan.count.label', FtCountOf(Rows, 'TLabel') = 2, Format('TLabel count = %d', [FtCountOf(Rows, 'TLabel')]));
  Check('formtypes.scan.count.panel', FtCountOf(Rows, 'TPanel') = 1);
  Check('formtypes.scan.root', FtCountOf(Rows, 'TVARINSPForm') = 1, 'the root form type counts like any other');

  // 'inherited Frame1: TMyFrame' is a real header DFMs use for inherited forms.
  Check('formtypes.scan.inherited', FtCountOf(Rows, 'TMyFrame') = 1);

  // A collection item writes a '[0]' index after the type -- it is not part of it.
  Check('formtypes.scan.index.stripped', FtCountOf(Rows, 'TcxGridDBColumn') = 1, 'the [0] index must not end up in the type name');

  // The one that a naive line scan gets wrong: a Caption LITERAL containing what
  // looks like an object header. If this counts, the scanner is reading strings.
  Check('formtypes.scan.literal.ignored', FtCountOf(Rows, 'TNotReal') = -1, 'a type named inside a quoted literal must NOT be harvested');

  // Name-ascending, case-insensitive -- so a family (every TOvc*) sits together.
  Names:= '';
  for R in Rows do
    Names:= Names + R.TypeName + ' ';
  Check('formtypes.scan.sorted', Trim(Names) = 'TcxGridDBColumn TLabel TMyFrame TOvcTable TPanel TVARINSPForm', Trim(Names));

  Check('formtypes.scan.empty' , Length(ScanDfmTypes(''      )) = 0, 'empty text'                                      );
  Check('formtypes.scan.binary', Length(ScanDfmTypes(#0#1#2#3)) = 0, 'a binary .dfm yields nothing rather than raising');

  // Only TypeName/Count are the harvest's business; decoration comes later.
  if FtFind(Rows, 'TOvcTable', Row) then
  begin
    Check('formtypes.scan.undecorated.visual', Row.Visual = tvkUnknown);
    Check('formtypes.scan.undecorated.flags', (not Row.Ruled) and (not Row.Skipped) and (Row.Origin = roDfm));
  end
  else
    Check('formtypes.scan.undecorated.visual', False, 'TOvcTable missing');

  // Merging two forms sums the shared type and keeps the union.
  Merged:= MergeFormTypes([Rows, ScanDfmTypes(FT_DFM)]);
  Check('formtypes.merge.union', Length(Merged) = 6, Format('expected 6, got %d', [Length(Merged)]));
  Check('formtypes.merge.sums', FtCountOf(Merged, 'TLabel') = 4, Format('TLabel across two identical forms = %d', [FtCountOf(Merged, 'TLabel')]));
  Check('formtypes.merge.empty', Length(MergeFormTypes([])) = 0);
end; // procedure

procedure TestSkipList;
const
  SRC =
    '# ConvRulesEditor -- classes marked "do not convert".'#13#10 +
    '# Written by the editor; safe to hand-edit or diff.'#13#10 +
    'skip TLabel'#13#10 +
    'skip TPanel'#13#10 +
    'filter DevExpress = ^Tdx'#13#10 +
    'filter DevExpress = ^Tcx'#13#10 +
    'filter Standard = +std'#13#10 +
    '# a hand-written note'#13#10 +
    'somethingelse entirely'#13#10;
var
  L  : TSkipList;
  L2 : TSkipList;
  L3 : TSkipList;
  Txt: string   ;
begin
  L:= ParseSkipList(SRC);

  Check('skiplist.parse.classes', Length(L.Classes) = 2, Format('%d', [Length(L.Classes)]));
  Check('skiplist.parse.class.first', SameText(L.Classes[0], 'TLabel'), L.Classes[0]);
  Check('skiplist.parse.filters', Length(L.Filters) = 2, Format('%d', [Length(L.Filters)]));
  Check('skiplist.parse.filter.accumulates', (Length(L.Filters[0].Patterns) = 2) and (L.Filters[0].Patterns[1] = '^Tcx'), 'two lines with one name make one filter');
  Check('skiplist.parse.filter.std', L.Filters[1].IncludeStandard and (Length(L.Filters[1].Patterns) = 0), '+std is a flag, not a regex');

  // A hand edit must survive a rewrite. The generated header must NOT come back
  // as foreign, or it would double on every save.
  Check('skiplist.parse.foreign.kept', Length(L.Foreign) = 2, Format('%d', [Length(L.Foreign)]));
  Check('skiplist.parse.header.not.foreign', not ContainsText(string.Join('|', L.Foreign), 'ConvRulesEditor --'), 'the generated header is not user content');

  Txt:= EmitSkipList(L);
  Check('skiplist.emit.crlf', ContainsText(Txt, #13#10) and not ContainsText(Txt.Replace(#13#10, ''), #10), 'CRLF only');
  Check('skiplist.emit.header', StartsText('# ConvRulesEditor --', Txt));
  Check('skiplist.emit.keeps.foreign', ContainsText(Txt, 'somethingelse entirely'));

  L2:= ParseSkipList(Txt);
  Check('skiplist.roundtrip.classes', Length(L2.Classes) = Length(L.Classes));
  Check('skiplist.roundtrip.filters', Length(L2.Filters) = Length(L.Filters));
  Check('skiplist.roundtrip.foreign', Length(L2.Foreign) = Length(L.Foreign));
  Check('skiplist.roundtrip.stable', EmitSkipList(L2) = Txt, 'a second emit must be byte-identical');

  Check('skiplist.isskipped.hit', IsSkipped(L, 'TLabel'));
  Check('skiplist.isskipped.ci', IsSkipped(L, 'tlabel'), 'class names are case-insensitive');
  Check('skiplist.isskipped.miss', not IsSkipped(L, 'TOvcTable'), 'positive control for the two above');

  L2:= SetSkipped(L, 'TOvcTable', True);
  Check('skiplist.set.on', IsSkipped(L2, 'TOvcTable'));
  Check('skiplist.set.on.nodup', Length(SetSkipped(L2, 'TOvcTable', True).Classes) = Length(L2.Classes), 'marking twice adds one row');
  L2:= SetSkipped(L2, 'TLabel', False);
  Check('skiplist.set.off', not IsSkipped(L2, 'TLabel'));
  Check('skiplist.set.off.spares.others', IsSkipped(L2, 'TPanel'), 'unmarking one must not clear the rest');

  Check('skiplist.path', SameText(ExtractFileName(SkipFilePath('C:\rules')), SKIP_FILE_NAME));
  Check('skiplist.path.empty', SkipFilePath('') = '', 'no folder yet -> no path, never a file at the CWD');

  Check('skiplist.parse.empty', Length(ParseSkipList('').Classes) = 0);
  Check('skiplist.emit.empty.header.only', StartsText('# ConvRulesEditor --', EmitSkipList(Default(TSkipList))));

  // Malformed-input coverage. Each shape below was chosen because a prior
  // revision of ParseSkipList silently DESTROYED one of them (a "filter Name ="
  // line with no value was accepted, created an empty filter record, and then
  // EmitSkipList rendered nothing for it -- the line vanished on the next
  // save). The doc-comment's contract is "never raises; an unparseable line
  // becomes a Foreign line" -- these checks hold the parser to that.
  L3:= ParseSkipList('filter DevExpress');
  Check('skiplist.malformed.filter.noequals', (Length(L3.Filters) = 0) and (Length(L3.Foreign) = 1), 'a filter line with no = must be foreign, not silently dropped');

  L3:= ParseSkipList('filter = ^Tdx');
  Check('skiplist.malformed.filter.noname', (Length(L3.Filters) = 0) and (Length(L3.Foreign) = 1), 'an empty filter name must be foreign');

  L3:= ParseSkipList('filter Name =');
  Check('skiplist.malformed.filter.novalue', (Length(L3.Filters) = 0) and (Length(L3.Foreign) = 1), 'an empty filter value must be foreign, not a silently dropped record -- this was the regression');
  Check('skiplist.malformed.filter.novalue.roundtrip', EmitSkipList(ParseSkipList(EmitSkipList(L3))) = EmitSkipList(L3), 'saving twice must not lose the line a second time either');

  L3:= ParseSkipList('skip');
  Check('skiplist.malformed.skip.bare', (Length(L3.Classes) = 0) and (Length(L3.Foreign) = 1), 'a bare "skip" with no class name must be foreign, not silently dropped');

  L3:= ParseSkipList('filter DevExpress = ^Tdx'#13#10 + 'filter devexpress = ^Tcx');
  Check('skiplist.filter.name.caseinsensitive.merge', (Length(L3.Filters) = 1) and (Length(L3.Filters[0].Patterns) = 2) and SameText(L3.Filters[0].Name, 'DevExpress'), 'two filter lines whose names differ only by case accumulate into one filter');

  // Finding 2 (2026-09-20 whole-branch review): a mark ticked before any rules
  // folder is known must survive the first LoadSkipList of that folder's skip
  // file -- MergePendingMarks is the pure merge LoadSkipList wires in instead
  // of the bare FSkipList:= ParseSkipList(...) reset that discarded them.
  var Pending: TSkipList:= Default(TSkipList);
  Pending.Classes:= ['TOvcTable'];             // ticked with no folder open yet
  Pending.Foreign:= ['ignored pending foreign line']; // must NOT leak into the merge
  var PendingFilter: TNamedFilter;
  PendingFilter.Name    := 'Extra';
  PendingFilter.Patterns:= ['^Tfoo'];
  var PendingDup: TNamedFilter;
  PendingDup.Name    := 'DevExpress'; // same name as a filter already on disk
  PendingDup.Patterns:= ['^Tzzz'];    // must NOT duplicate or replace the file's entry
  Pending.Filters:= [PendingFilter, PendingDup];

  var Merged: TSkipList:= MergePendingMarks(L, Pending);
  Check('skiplist.merge.pending.class.survives', IsSkipped(Merged, 'TOvcTable'), 'a mark made before the folder was known must not be discarded by the first load');
  Check('skiplist.merge.file.class.kept', IsSkipped(Merged, 'TLabel') and IsSkipped(Merged, 'TPanel'), 'marks already on disk must still be there after the merge');
  Check('skiplist.merge.classes.union', Length(Merged.Classes) = 3, Format('expected 3 (2 file + 1 pending), got %d', [Length(Merged.Classes)]));
  Check('skiplist.merge.filter.new.added', Length(Merged.Filters) = 3, Format('2 file filters + 1 new pending filter, got %d', [Length(Merged.Filters)]));
  Check('skiplist.merge.filter.dup.not.duplicated', SameText(Merged.Filters[0].Name, 'DevExpress') and (Length(Merged.Filters[0].Patterns) = 2) and not ContainsText(string.Join('|', Merged.Filters[0].Patterns), '^Tzzz'), 'a same-named pending filter must not replace or duplicate the file''s own entry');
  Check('skiplist.merge.foreign.file.only', Length(Merged.Foreign) = Length(L.Foreign), 'Foreign comes only from AFromFile; APending never contributes its own');
  Check('skiplist.merge.foreign.pending.excluded', not ContainsText(string.Join('|', Merged.Foreign), 'ignored pending foreign line'), 'a pending Foreign line must not leak into the merged result');
  Check('skiplist.merge.empty.pending.noop', Length(MergePendingMarks(L, Default(TSkipList)).Classes) = Length(L.Classes), 'nothing pending -> the file''s own list is unchanged');

  // A3 (2026-09-20 whole-branch review, Minor 10): ApplyNamedFilterClick used to
  // APPEND a new TNamedFilter on every Apply, so pressing it twice on the same
  // name wrote the pattern line twice; SetNamedFilter replaces by name instead.
  // It also drops blank memo lines, which used to survive into Patterns and get
  // emitted as a foreign "filter Name = " line preserved forever.
  var Base: TSkipList:= Default(TSkipList);
  var FilterOne: TNamedFilter;
  FilterOne.Name    := 'DevExpress';
  FilterOne.Patterns:= ['^Tdx', ''];  // trailing blank memo line
  var Once: TSkipList:= SetNamedFilter(Base, FilterOne);
  Check('namedfilter.set.once.count', Length(Once.Filters) = 1, Format('%d', [Length(Once.Filters)]));
  Check('namedfilter.set.blank.dropped', Length(Once.Filters[0].Patterns) = 1, 'the blank memo line must not become a Patterns entry');

  var FilterTwo: TNamedFilter;
  FilterTwo.Name    := 'DevExpress'; // same name, applied again
  FilterTwo.Patterns:= ['^Tdx', '^Tcx'];
  var Twice: TSkipList:= SetNamedFilter(Once, FilterTwo);
  Check('namedfilter.set.replace.not.duplicate', Length(Twice.Filters) = 1, 'apply twice on the same name -> one record, not two');
  Check('namedfilter.set.replace.content', Length(Twice.Filters[0].Patterns) = 2, 'the second Apply''s patterns replace the first''s');

  var FilterOther: TNamedFilter;
  FilterOther.Name    := 'Raize';
  FilterOther.Patterns:= ['^TRz'];
  var TwoNames: TSkipList:= SetNamedFilter(Twice, FilterOther);
  Check('namedfilter.set.new.name.appends', Length(TwoNames.Filters) = 2, 'a different name is appended, not merged');

  // Fix wave, Minor 9: the name match is case-insensitive (IndexOfFilter ->
  // SameText) but neither the doc nor a test pinned it -- 'devexpress' must
  // replace the existing 'DevExpress' record, not add a second one.
  var FilterCaseDiff: TNamedFilter;
  FilterCaseDiff.Name    := 'devexpress';
  FilterCaseDiff.Patterns:= ['^Tcx'];
  var CaseDiff: TSkipList:= SetNamedFilter(TwoNames, FilterCaseDiff);
  Check('namedfilter.set.case.insensitive.one.record', Length(CaseDiff.Filters) = 2, 'still 2 names total (DevExpress/Raize) -- ''devexpress'' must replace, not add a third');
  // IndexOfFilter stays implementation-private (SetNamedFilter's own doc, above,
  // is what pins case-insensitivity); DevExpress was the FIRST filter set, so a
  // correct replace-by-name keeps it at Filters[0].
  Check('namedfilter.set.case.insensitive.replaced', (Length(CaseDiff.Filters[0].Patterns) = 1) and (CaseDiff.Filters[0].Patterns[0] = '^Tcx'), 'the lowercase Apply must have replaced the DevExpress record''s content, in place');
end; // procedure

procedure TestFormTypesFilter;
var
  Err: string;
begin
  // --- the standard-controls test is deliberately LITERAL: Vcl./FMX. only.
  Check('formtypes.std.vcl', IsStandardVclOrFmxUnit('Vcl.StdCtrls'));
  Check('formtypes.std.fmx', IsStandardVclOrFmxUnit('FMX.Forms'   ));
  Check('formtypes.std.ci', IsStandardVclOrFmxUnit('vcl.graphics'), 'case-insensitive');
  Check('formtypes.std.empty' , not IsStandardVclOrFmxUnit(''              ), 'unresolved unit'                                            );
  Check('formtypes.std.system', not IsStandardVclOrFmxUnit('System.Classes'), 'RTL is not a "standard Delphi CONTROL"'                     );
  Check('formtypes.std.data'  , not IsStandardVclOrFmxUnit('Data.DB'       ), 'TIntegerField must not vanish behind a box labelled VCL/FMX');
  Check('formtypes.std.thirdparty', not IsStandardVclOrFmxUnit('ovcTable'));
  Check('formtypes.std.prefixonly', not IsStandardVclOrFmxUnit('VclSomething'), 'the namespace DOT is what makes it standard, not the letters');

  // --- exclusion is OR across patterns, case-insensitive, unanchored.
  Check('formtypes.excl.none', not TypeIsExcluded('TOvcTable', 'ovcTable', [], False, Err));
  Check('formtypes.excl.match', TypeIsExcluded('TOvcTable', 'ovcTable', ['^TOvc'], False, Err));
  Check('formtypes.excl.unanchored', TypeIsExcluded('TOvcTable', 'ovcTable', ['Ovc'  ], False, Err), 'a bare substring pattern matches');
  Check('formtypes.excl.ci'        , TypeIsExcluded('TOvcTable', 'ovcTable', ['^tovc'], False, Err), 'patterns are case-insensitive'   );
  Check('formtypes.excl.or', TypeIsExcluded('TLabel', 'Vcl.StdCtrls', ['^TOvc', '^TLabel'], False, Err), 'ANY pattern matching excludes');
  Check('formtypes.excl.or.none', not TypeIsExcluded('TPanel', 'Vcl.ExtCtrls', ['^TOvc', '^TLabel'], False, Err));
  Check('formtypes.excl.blank.skipped', not TypeIsExcluded('TPanel', 'Vcl.ExtCtrls', ['', '   '], False, Err), 'a blank condition row must not exclude everything');

  // --- the standard checkbox is independent of the patterns.
  Check('formtypes.excl.std.on', TypeIsExcluded('TLabel', 'Vcl.StdCtrls', [], True, Err));
  Check('formtypes.excl.std.off', not TypeIsExcluded('TLabel', 'Vcl.StdCtrls', [], False, Err));
  Check('formtypes.excl.std.spares.thirdparty', not TypeIsExcluded('TOvcTable', 'ovcTable', [], True, Err), 'a third-party control survives the standard-controls box');
  Check('formtypes.excl.std.unresolved', not TypeIsExcluded('TMystery', '', [], True, Err), 'an unresolved unit must not be assumed standard');

  // --- a malformed pattern reports and excludes NOTHING. It must never raise,
  //     and AError must be set -- a silent fail-open would hide a dead condition.
  Err:= '';
  Check('formtypes.excl.bad.nomatch', not TypeIsExcluded('TOvcTable', 'ovcTable', ['(unclosed'], False, Err));
  Check('formtypes.excl.bad.reports', Err <> '', 'a malformed regex must surface an error, not fail silently');
  Err:= '';
  Check('formtypes.excl.bad.other.still.runs', TypeIsExcluded('TOvcTable', 'ovcTable', ['(unclosed', '^TOvc'], False, Err), 'one bad condition must not disable the good ones');
  Check('formtypes.excl.good.no.error', not TypeIsExcluded('TPanel', 'Vcl.ExtCtrls', ['^TOvc'], False, Err) and (Err = ''));
end; // procedure

{ StampSkipMarks / SkipListFromRows / ApplyNamedFilterToRows: the pure decision
  logic behind ApplySkipMarks, SaveSkipList and ApplyNamedFilterClick
  (ConvRules.MainForm.pas, outside this test project's compile closure), per the
  2026-09-20 controller ruling that logic left in MainForm is permanently
  uncovered. }
procedure TestApplySkipMarks;
var
  Rows  : TFormTypeRows;
  Stamp : TFormTypeRows;
  List  : TSkipList    ;
  Hits  : Integer      ;
  Err   : string       ;
  Marked: TFormTypeRows;
begin
  SetLength(Rows, 3);
  Rows[0]:= Default(TFormTypeRow); Rows[0].TypeName:= 'TLabel';
  Rows[1]:= Default(TFormTypeRow); Rows[1].TypeName:= 'TPanel'; Rows[1].Skipped:= True;
  Rows[2]:= Default(TFormTypeRow); Rows[2].TypeName:= 'TOvcTable';

  // --- StampSkipMarks: file is truth, including UN-marking a row the caller
  //     had previously marked.
  List:= SetSkipped(Default(TSkipList), 'TLabel', True);
  Stamp:= StampSkipMarks(Rows, List);
  Check('stamp.marks.hit', Stamp[0].Skipped, 'TLabel is in the list');
  Check('stamp.marks.unmarks', not Stamp[1].Skipped, 'TPanel is NOT in the list, so a prior Skipped=True must be cleared');
  Check('stamp.marks.miss', not Stamp[2].Skipped);
  Check('stamp.marks.source.untouched', Length(Rows) = 3, 'ARows is not mutated in place');

  // --- SkipListFromRows: every row is written, marked AND unmarked; a class
  //     absent from ARows is left untouched (not evicted).
  List:= SetSkipped(Default(TSkipList), 'TStrayClass', True); // not in Rows at all
  List:= SkipListFromRows(List, Stamp);
  Check('skiplistfromrows.marked.kept', IsSkipped(List, 'TLabel'));
  Check('skiplistfromrows.unmarked.written', not IsSkipped(List, 'TPanel'), 'un-marking must persist, not just skip the write');
  Check('skiplistfromrows.absent.untouched', IsSkipped(List, 'TStrayClass'), 'a class not present in the current rows must not be evicted');

  // --- ApplyNamedFilterToRows: bulk-marks by pattern/standard-unit, counts only
  //     NEWLY marked rows, and surfaces the first bad pattern without stopping.
  Marked:= ApplyNamedFilterToRows(Rows, ['^TOvc'], ['', '', 'ovcTable'], False, Hits, Err);
  Check('namedfilter.marks.match', Marked[2].Skipped, 'TOvcTable matches ^TOvc');
  Check('namedfilter.marks.leaves.others', not Marked[0].Skipped);
  Check('namedfilter.hits.count', Hits = 1, Format('%d', [Hits]));
  Check('namedfilter.error.clean', Err = '');

  Marked:= ApplyNamedFilterToRows(Rows, [], ['', 'Vcl.ExtCtrls', ''], True, Hits, Err);
  Check('namedfilter.std.match', Marked[1].Skipped, 'TPanel/Vcl.ExtCtrls matches the standard-controls flag');
  Check('namedfilter.std.hits.already.marked', Hits = 0, 'TPanel was already Skipped=True in the fixture, so this is not a NEW hit');

  Marked:= ApplyNamedFilterToRows(Rows, ['(unclosed'], ['', '', ''], False, Hits, Err);
  Check('namedfilter.badpattern.reports', Err <> '', 'a malformed pattern must surface, not fail silently');
  Check('namedfilter.badpattern.excludes.nothing', Hits = 0, 'a bad pattern must be fail-open, matching TypeIsExcluded');

  Marked:= ApplyNamedFilterToRows(Rows, ['^TL'], nil, False, Hits, Err);
  Check('namedfilter.declaringunits.short', Marked[0].Skipped, 'fewer declaring units than rows must not raise -- missing entries are treated as blank');
end; // procedure

procedure TestClassRowModel;
var
  Dfm : TFormTypeRows;
  Rows: TFormTypeRows;
  Row : TFormTypeRow ;
  Cnt : TRowCounts   ;
  Vis : TArray<Integer>;
begin
  Dfm:= ScanDfmTypes(
    'object Form1: TVarInspForm'#13#10 +
    '  object Btn1: TabcToggleBtn'#13#10 +
    '  end'#13#10 +
    '  object Btn2: TabcToggleBtn'#13#10 +
    '  end'#13#10 +
    'end'#13#10);

  // --- union, origin-marked, .dfm first
  Rows:= MergeClassRows(Dfm, ['TVarInspForm', 'TVarRow', 'TsgDXFImageAccess']);
  Check('classrows.merge.total', Length(Rows) = 4, Format('%d', [Length(Rows)]));
  Check('classrows.merge.dfm.first', Rows[0].Origin in [roDfm, roBoth], 'dfm rows sort ahead of pas-only rows');
  Check('classrows.merge.count.kept', (Rows[0].TypeName = 'TabcToggleBtn') and (Rows[0].Count = 2), 'the dfm instance count survives the merge');

  Check('classrows.merge.both', MergeClassRows(Dfm, ['TVarInspForm'])[1].Origin = roBoth, 'a class on the form AND declared in the unit is one row, both origins');
  Check('classrows.merge.pasonly', Rows[High(Rows)].Origin = roPas);
  Check('classrows.merge.nodup', Length(MergeClassRows(Dfm, ['TabcToggleBtn'])) = 2, 'a name in both sources makes ONE row');
  Check('classrows.merge.ci', Length(MergeClassRows(Dfm, ['tabctogglebtn'])) = 2, 'case-insensitive');
  Check('classrows.merge.nopas', Length(MergeClassRows(Dfm, [])) = 2, 'a non-form unit still lists its dfm rows');
  Check('classrows.merge.nodfm', Length(MergeClassRows(nil, ['TOnlyDeclared'])) = 1, 'a unit with no .dfm still lists its declared classes');
  Check('classrows.merge.blank.ignored', Length(MergeClassRows(nil, ['', '   '])) = 0);

  // --- three states, and which one wins
  Row:= Default(TFormTypeRow);
  Check('rowstate.todo', RowState(Row) = rsToDo);
  Row.Ruled:= True;
  Check('rowstate.ruled', RowState(Row) = rsRuled);
  Row.Skipped:= True;
  Check('rowstate.skipped.beats.ruled', RowState(Row) = rsSkipped, 'an explicit user decision beats a derived fact');
  Row:= Default(TFormTypeRow); Row.Skipped:= True;
  Check('rowstate.skipped', RowState(Row) = rsSkipped);

  // --- the counts are the progress line; they must partition the rows
  SetLength(Rows, 4);
  Rows[0]:= Default(TFormTypeRow); Rows[0].TypeName:= 'TA';
  Rows[1]:= Default(TFormTypeRow); Rows[1].TypeName:= 'TB'; Rows[1].Ruled  := True;
  Rows[2]:= Default(TFormTypeRow); Rows[2].TypeName:= 'TC'; Rows[2].Skipped:= True;
  Rows[3]:= Default(TFormTypeRow); Rows[3].TypeName:= 'TD'; Rows[3].Ruled:= True; Rows[3].Skipped:= True;
  Cnt:= CountRows(Rows);
  Check('counts.total'  , Cnt.Total   = 4, Format('%d', [Cnt.Total  ]));
  Check('counts.ruled'  , Cnt.Ruled   = 1, Format('%d', [Cnt.Ruled  ]));
  Check('counts.skipped', Cnt.Skipped = 2, Format('%d', [Cnt.Skipped]));
  Check('counts.todo'   , Cnt.ToDo    = 1, Format('%d', [Cnt.ToDo   ]));
  Check('counts.partition', Cnt.Ruled + Cnt.Skipped + Cnt.ToDo = Cnt.Total, 'every row is counted exactly once');

  // --- the search filters VISIBILITY only
  Vis:= VisibleRowIndexes(Rows, '');
  Check('visible.all', Length(Vis) = 4, 'a blank search shows everything');
  Vis:= VisibleRowIndexes(Rows, 'tb');
  Check('visible.substring.ci', (Length(Vis) = 1) and (Vis[0] = 1), 'case-insensitive substring');
  Vis:= VisibleRowIndexes(Rows, 'zzz');
  Check('visible.none', Length(Vis) = 0);
  Check('visible.counts.unmoved', CountRows(Rows).Total = 4, 'a search must never change the score');
  Vis:= VisibleRowIndexes(Rows, '  ');
  Check('visible.blank.search', Length(Vis) = 4, 'whitespace is not a filter');
end; // procedure

{ ResolveSelectedRow / ListIndexForRow: the listbox-position <-> row-index map
  that SelectedRowIndex, FormTypeDrawItem and ToggleFormTypeSkip
  (ConvRules.MainForm.pas, outside this test project's compile closure) all
  route through, so a filtered list can never address the wrong class. }
procedure TestSelectedRowMapping;
var
  Vis: TArray<Integer>;
begin
  Vis:= [2, 5, 7]; // list slot 0/1/2 -> row 2/5/7; row count 8 (rows 0..7)

  // --- forward: list index -> row index
  Check('resolve.first', ResolveSelectedRow(Vis, 0, 8) = 2);
  Check('resolve.last', ResolveSelectedRow(Vis, 2, 8) = 7);
  Check('resolve.negative', ResolveSelectedRow(Vis, -1, 8) = -1, 'no selection');
  Check('resolve.past.end', ResolveSelectedRow(Vis, 3, 8) = -1, 'no such list slot');
  Check('resolve.empty.map', ResolveSelectedRow(nil, 0, 8) = -1, 'nothing visible, nothing selectable');
  Check('resolve.stale.row', ResolveSelectedRow(Vis, 2, 5) = -1, 'the mapped row index is outside the current row array');

  // --- reverse: row index -> list index, for re-selecting after a refresh
  Check('listidx.found.first', ListIndexForRow(Vis, 2) = 0);
  Check('listidx.found.middle', ListIndexForRow(Vis, 5) = 1);
  Check('listidx.found.last', ListIndexForRow(Vis, 7) = 2);
  Check('listidx.missing', ListIndexForRow(Vis, 3) = -1, 'row 3 is filtered out of the current view');
  Check('listidx.empty.map', ListIndexForRow(nil, 2) = -1);
end; // procedure

{ DescribeFormTypeRow / FormTypesProgressCaption: the checkbox list's three
  renderings and the progress line, extracted from FormTypeDrawItem and
  RefreshFormTypes (ConvRules.MainForm.pas, which ConvRulesModelTests.dpr does
  not compile) so they are reachable by an automated test. }
procedure TestFormTypeRendering;
var
  Row: TFormTypeRow;
  Cnt: TRowCounts;
begin
  // --- origin and visual mark
  Row:= Default(TFormTypeRow);
  Row.TypeName:= 'TFoo';
  Row.Origin  := roPas;
  Row.Visual  := tvkVisual;
  Check('rowtext.pas.visual', DescribeFormTypeRow(Row) = 'pas [V] TFoo', DescribeFormTypeRow(Row));

  Row.Origin:= roDfm;
  Row.Visual:= tvkNonVisual;
  Check('rowtext.dfm.nonvisual', DescribeFormTypeRow(Row) = 'dfm [N] TFoo', DescribeFormTypeRow(Row));

  Row.Origin:= roBoth;
  Check('rowtext.both.is.dfm', DescribeFormTypeRow(Row) = 'dfm [N] TFoo', 'only roPas renders as pas; roBoth reads as dfm, same as roDfm');

  Row.Visual:= tvkUnknown;
  Check('rowtext.unknown.mark', DescribeFormTypeRow(Row) = 'dfm [?] TFoo');

  // --- instance count, zero is omitted
  Row:= Default(TFormTypeRow); Row.TypeName:= 'TFoo'; Row.Origin:= roDfm;
  Check('rowtext.count.zero.omitted', DescribeFormTypeRow(Row) = 'dfm [?] TFoo');
  Row.Count:= 5;
  Check('rowtext.count.shown', DescribeFormTypeRow(Row) = 'dfm [?] TFoo  (5)');

  // --- ruled-by suffix, and the +N more guard (RuleCount is 0 until Task 11
  // fills it in; exercised here directly with a synthetic value)
  Row.Ruled:= True; Row.RuledBy:= 'bde.rules';
  Check('rowtext.ruledby', DescribeFormTypeRow(Row) = 'dfm [?] TFoo  (5)  -- bde.rules');
  Row.RuleCount:= 1;
  Check('rowtext.rulecount.one.no.suffix', DescribeFormTypeRow(Row) = 'dfm [?] TFoo  (5)  -- bde.rules', 'RuleCount = 1 means only the named rule; no +N more');
  Row.RuleCount:= 3;
  Check('rowtext.rulecount.more', DescribeFormTypeRow(Row) = 'dfm [?] TFoo  (5)  -- bde.rules  +2 more');

  // --- progress line: filter error wins over everything, even good counts
  Cnt:= Default(TRowCounts);
  Cnt.Total:= 5; Cnt.Ruled:= 2; Cnt.Skipped:= 1; Cnt.ToDo:= 2;
  Check('progress.filtererror', FormTypesProgressCaption(Cnt, 3, 'bad regex') = 'FILTER ERROR -- bad regex', FormTypesProgressCaption(Cnt, 3, 'bad regex'));

  // --- a search hiding rows: "N of M shown"
  Check('progress.filtered', FormTypesProgressCaption(Cnt, 3, '') = '3 of 5 shown -- 2 ruled, 1 skipped, 2 to do', FormTypesProgressCaption(Cnt, 3, ''));

  // --- nothing hidden: the plain form
  Check('progress.full', FormTypesProgressCaption(Cnt, 5, '') = '5 classes -- 2 ruled, 1 skipped, 2 to do', FormTypesProgressCaption(Cnt, 5, ''));

  // --- zero rows is the plain form too, not "0 of 0 shown"
  Cnt:= Default(TRowCounts);
  Check('progress.empty', FormTypesProgressCaption(Cnt, 0, '') = '0 classes -- 0 ruled, 0 skipped, 0 to do');
end; // procedure

{ DescribeOutlineOutcome: the status-line branching HarvestUnitClasses
  (ConvRules.MainForm.pas, outside this test project's compile closure) folds
  into its Result. Extracted so it has automated coverage at all. }
procedure TestDescribeOutlineOutcome;
begin
  // --- served from an already-covered or already-warm index: nothing to say
  Check('outline.describe.warm', DescribeOutlineOutcome(True, False, 'Foo.pas', '') = '', 'a normal successful answer needs no status note');

  // --- had to build a scratch index this call: say so, once
  Check('outline.describe.indexed',
    DescribeOutlineOutcome(True, True, 'Foo.pas', '') = ' (Foo.pas was not in any index; a local scratch index was built for it -- once only)');

  // --- the engine failed: fall back, and name the error
  Check('outline.describe.failed',
    DescribeOutlineOutcome(False, False, 'Foo.pas', 'db locked') = ' NOTE: the indexer could not list classes (db locked) -- fell back to a text scan, which cannot see conditionals or comments.');

  // --- a failed call ignores AIndexedNow -- there is nothing to report about indexing
  // when the call itself did not succeed.
  Check('outline.describe.failed.ignores.indexed',
    DescribeOutlineOutcome(False, True, 'Foo.pas', 'db locked') = ' NOTE: the indexer could not list classes (db locked) -- fell back to a text scan, which cannot see conditionals or comments.',
    'failure wins over AIndexedNow');
end; // procedure

{ ConvRules.RuleCatalog -- the folder-wide index of what is already converted.
  RC_BOOK mirrors the real convrules\BDE-to-FireDAC.rules shapes: qualified types,
  and a header carrying extra uses-units after the target. }
const
  RC_BOOK = '// a header comment'#13#10 + '#convert Bde.DBTables.TTable -> FireDAC.Comp.Client.TFDTable, FireDAC.Stan.Intf, FireDAC.DApt'#13#10 +
  '#link Active <- Active'#13#10 + '#convert Vcl.Graphics.TFont -> Vcl.Graphics.TFont'#13#10 + '#link Color <- Color'#13#10;

procedure TestRuleCatalogParse;
var
  Cat : TRuleCatalog     ;
  E   : TRuleCatalogEntry;
begin
  Check('catalog.bare.qualified', BareTypeName('Bde.DBTables.TTable') = 'TTable', BareTypeName('Bde.DBTables.TTable'));
  Check('catalog.bare.plain', BareTypeName('TTable') = 'TTable');
  Check('catalog.bare.empty', BareTypeName(''      ) = ''      );

  Cat:= CatalogFromText(RC_BOOK, 'C:\rules\bde.rules');
  Check('catalog.parse.count', Length(Cat) = 2, Format('expected 2 #convert, got %d', [Length(Cat)]));

  if Length(Cat) = 2 then
  begin
    Check('catalog.parse.from', Cat[0].FromType = 'Bde.DBTables.TTable', Cat[0].FromType);

    // The header carries THREE comma-separated items after '->'; only the first is
    // the target type, the rest are units to add. If they leak into ToType the
    // panel will report a nonsense target and a later save would write it back.
    Check('catalog.parse.to.strips.units', Cat[0].ToType = 'FireDAC.Comp.Client.TFDTable', Cat[0].ToType);

    Check('catalog.parse.path', Cat[0].FilePath = 'C:\rules\bde.rules', Cat[0].FilePath);

    // Line 1 is the comment, so the first #convert is on line 2.
    Check('catalog.parse.lineno'       , Cat[0].LineNo = 2, Format('first #convert LineNo = %d, expected 2' , [Cat[0].LineNo]));
    Check('catalog.parse.lineno.second', Cat[1].LineNo = 4, Format('second #convert LineNo = %d, expected 4', [Cat[1].LineNo]));
    Check('catalog.parse.order', Cat[1].FromType = 'Vcl.Graphics.TFont', Cat[1].FromType);
  end; // if

  Check('catalog.parse.none' , Length(CatalogFromText('// nothing here'#13#10, 'x')) = 0);
  Check('catalog.parse.empty', Length(CatalogFromText(''                     , 'x')) = 0);

  // --- lookup is BARE-name based: the .dfm side is always bare.
  Check('catalog.find.bare', FindRuleForType(Cat, 'TTable', E) and (E.FromType = 'Bde.DBTables.TTable'), 'a bare DFM name must find a qualified rule');
  Check('catalog.find.file', FindRuleForType(Cat, 'TTable', E) and (E.FilePath = 'C:\rules\bde.rules'), 'the owning book is reported');
  Check('catalog.find.ci'       , FindRuleForType(Cat, 'ttable'             , E), 'case-insensitive'           );
  Check('catalog.find.qualified', FindRuleForType(Cat, 'Bde.DBTables.TTable', E), 'a qualified query works too');
  Check('catalog.find.miss', not FindRuleForType(Cat, 'TOvcTable', E), 'an unconverted type must NOT be reported as ruled');
  Check('catalog.find.empty', not FindRuleForType(nil, 'TTable', E));

  Check('catalog.merge', Length(MergeCatalogs([Cat, Cat])) = 4);
  Check('catalog.merge.none', Length(MergeCatalogs([])) = 0);
end; // procedure

{ RulesForType feeds the rule chooser (ConvRules.RuleChooser): one From class may
  legitimately be converted by more than one rule, in different books, for
  different campaigns -- unlike FindRuleForType, which deliberately answers only
  the first. }
procedure TestRulesForType;
var
  Cat: TRuleCatalog;
  Got: TArray<TRuleCatalogEntry>;
begin
  Cat:= CatalogFromText(
    '#convert TabcToggleBtn -> TcxButton'#13#10 +
    '#convert TOvcTable -> TcxGrid'#13#10, 'A.rules');
  Cat:= MergeCatalogs([Cat, CatalogFromText('#convert TabcToggleBtn -> TdxBarButton'#13#10, 'B.rules')]);

  Got:= RulesForType(Cat, 'TabcToggleBtn');
  Check('rulesfor.many', Length(Got) = 2, Format('%d', [Length(Got)]));
  Check('rulesfor.many.tos', (Got[0].ToType <> Got[1].ToType), 'two different To classes for one From is legal');
  Check('rulesfor.one', Length(RulesForType(Cat, 'TOvcTable')) = 1);
  Check('rulesfor.none', Length(RulesForType(Cat, 'TNotThere')) = 0, 'positive control for the two above');
  Check('rulesfor.ci', Length(RulesForType(Cat, 'tabctogglebtn')) = 2, 'type names are case-insensitive');
  Check('rulesfor.bare', Length(RulesForType(Cat, 'UnitA.TabcToggleBtn')) = 2, 'a qualified name matches the bare From, as FindRuleForType does');
end; // procedure

{ A #mapping NAME must also live in exactly one file. Same invariant as one-rule-
  per-type, different key -- and it matters sooner: atomizing spreads #apply across
  files, so the health check has to be able to see a name declared twice BEFORE the
  first split happens.

  THE TRAP THIS PINS. A #mapping is not one line. The declaration
  (`#mapping N from T to C`) is followed by sibling #when/#else clause lines that
  repeat the NAME and are not re-declarations. The model marks the declaration with
  MapFromType <> ''; keying on the name alone would count BdeBatchMode six times in
  one file and report the corpus as duplicated when it is clean. }
procedure TestMappingCatalog;
var
  Cat  : TMappingCatalog   ;
  Dups : TMappingDuplicates;
  A    : TMappingCatalog   ;
  B    : TMappingCatalog   ;
  Real_: TMappingCatalog   ;
  Dir  : string            ;
const
  DECL_PLUS_CLAUSES = '#mapping BdeBatchMode from Bde.DBTables.TBatchMode to FireDAC.Comp.BatchMove.TFDBatchMove'#13#10 +
  '#mapping BdeBatchMode #when Mode = batAppend -> Mode = dmAppend'#13#10 + '#mapping BdeBatchMode #else -> Mode = dmAlwaysInsert'#13#10;
begin
  // --- only the DECLARATION is an entry; the two clauses are not.
  Cat:= MappingCatalogFromText(DECL_PLUS_CLAUSES, 'C:\rules\bde.rules');
  Check('catalog.mapping.decl.only', Length(Cat) = 1, Format('a declaration plus 2 clauses is ONE entry, got %d', [Length(Cat)]));
  if Length(Cat) = 1 then
  begin
    Check('catalog.mapping.name', SameText(Cat[0].Name    , 'BdeBatchMode'      ), Cat[0].Name    );
    Check('catalog.mapping.path', SameText(Cat[0].FilePath, 'C:\rules\bde.rules'), Cat[0].FilePath);
    Check('catalog.mapping.lineno', Cat[0].LineNo = 1, IntToStr(Cat[0].LineNo));
  end;

  Check('catalog.mapping.empty', Length(MappingCatalogFromText('', 'x')) = 0);
  Check('catalog.mapping.dup.empty', Length(FindDuplicateMappings(nil)) = 0);

  // --- two DIFFERENT names across two files is the intended state.
  A:= MappingCatalogFromText('#mapping One from A.T to B.C'#13#10, 'C:\rules\a.rules');
  B:= MappingCatalogFromText('#mapping Two from A.T to B.C'#13#10, 'C:\rules\b.rules');
  Check('catalog.mapping.dup.none', Length(FindDuplicateMappings(A + B)) = 0, 'distinct names in distinct files must report nothing');

  // --- THE case this exists for: one name, two files.
  B:= MappingCatalogFromText('#mapping One from X.T to Y.C'#13#10, 'C:\rules\legacy.rules');
  Dups:= FindDuplicateMappings(A + B);
  Check('catalog.mapping.dup.two.files', Length(Dups) = 1, Format('expected 1 duplicated mapping name, got %d', [Length(Dups)]));
  if Length(Dups) = 1 then
  begin
    Check('catalog.mapping.dup.names.it', SameText(Dups[0].Name, 'One'), Dups[0].Name);
    Check('catalog.mapping.dup.holds.both', Length(Dups[0].Entries) = 2, Format('both sites or it is not actionable, got %d', [Length(Dups[0].Entries)]));
    Check(
      'catalog.mapping.dup.scan.order',
      (Length(Dups[0].Entries) = 2) and SameText(ExtractFileName(Dups[0].Entries[0].FilePath), 'a.rules') and SameText(ExtractFileName(Dups[0].Entries[1].FilePath), 'legacy.rules')
    );
  end;

  // --- case-insensitively, as Pascal is.
  B:= MappingCatalogFromText('#mapping ONE from X.T to Y.C'#13#10, 'C:\rules\ci.rules');
  Check('catalog.mapping.dup.ci', Length(FindDuplicateMappings(A + B)) = 1);

  // --- twice in the SAME file is still one name in two places.
  Check(
    'catalog.mapping.dup.same.file',
    Length(FindDuplicateMappings( MappingCatalogFromText('#mapping One from A.T to B.C'#13#10 + '#mapping One from C.T to D.C'#13#10, 'C:\rules\same.rules'))) = 1);

  // --- REAL CORPUS. BDE-to-FireDAC.rules carries 10 #mapping LINES and exactly 2
  //     DECLARATIONS. Counting lines would give 10 and report 2 false duplicates.
  // ConvRulesCorpusPath is declared further down this file; inline the same rule.
  Dir:= TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\..\..\convrules\BDE-to-FireDAC.rules'));
  if not TFile.Exists(Dir) then
    Skip('catalog.mapping.real', 'BDE-to-FireDAC.rules absent')
  else
  begin
    Real_:= MappingCatalogFromText(TFile.ReadAllText(Dir), Dir);
    Check('catalog.mapping.real.count', Length(Real_) = 2, Format('expected 2 declarations among 10 #mapping lines, got %d', [Length(Real_)]));
    Check('catalog.mapping.real.clean', Length(FindDuplicateMappings(Real_)) = 0, 'the shipped book declares each mapping once');
  end;
end; // procedure

{ "Open owning rule" needs to turn a catalog entry back into a BLOCK in the book it
  came from. HeaderIndexFor is that lookup, and it is pure so the risky half (loading
  a file, discarding edits) stays in the form.

  WHY IT IS NOT JUST LineNo - 1. The catalog is an INDEX and the book on disk moves
  underneath it: add a comment at the top and every recorded line is off by one. A
  lookup that trusted LineNo would then select the WRONG BLOCK -- silently, because a
  neighbouring #convert is still a plausible-looking rule. So LineNo is a HINT,
  verified against the From type, and the type wins when they disagree.

  Out-of-range must return -1 rather than raise: the index can name a line past the
  end of a book that has since been trimmed, and that is a stale index, not a crash. }
procedure TestHeaderIndexFor;
var
  Book : TRuleBook        ;
  E    : TRuleCatalogEntry;
const
  SRC = '// header comment'#13#10 + '#convert Bde.DBTables.TQuery -> FireDAC.Comp.Client.TFDQuery'#13#10 + '#link SQL <- SQL'#13#10 +
  '#convert Bde.DBTables.TTable -> FireDAC.Comp.Client.TFDTable'#13#10;
begin
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(SRC);

    // --- exact hit: LineNo 2 is the TQuery header (1-based -> node index 1).
    E.FromType:= 'Bde.DBTables.TQuery'; E.ToType:= ''; E.FilePath:= 'x'; E.LineNo:= 2;
    Check('catalog.header.by.lineno', HeaderIndexFor(Book, E) = 1, IntToStr(HeaderIndexFor(Book, E)));

    // --- the second block, to prove it is not just finding the first #convert.
    E.FromType:= 'Bde.DBTables.TTable'; E.LineNo:= 4;
    Check('catalog.header.second.block', HeaderIndexFor(Book, E) = 3, IntToStr(HeaderIndexFor(Book, E)));

    // --- STALE LineNo: points at the #link, not a header. Must fall back to the
    //     From type and still land on the TQuery header.
    E.FromType:= 'Bde.DBTables.TQuery'; E.LineNo:= 3;
    Check('catalog.header.stale.lineno.falls.back', HeaderIndexFor(Book, E) = 1, Format('stale LineNo must resolve by From, got %d', [HeaderIndexFor(Book, E)]));

    // --- a BARE From in the index against a QUALIFIED one in the book still matches.
    E.FromType:= 'TQuery'; E.LineNo:= 0;
    Check('catalog.header.bare.matches.qualified', HeaderIndexFor(Book, E) = 1, IntToStr(HeaderIndexFor(Book, E)));

    // --- a type the book does not convert -> -1.
    E.FromType:= 'Vcl.StdCtrls.TButton'; E.LineNo:= 2;
    Check('catalog.header.missing.type', HeaderIndexFor(Book, E) = -1, IntToStr(HeaderIndexFor(Book, E)));

    // --- out of range must be -1, NOT an exception.
    E.FromType:= 'Bde.DBTables.TQuery'; E.LineNo:= 9999;
    Check('catalog.header.out.of.range', HeaderIndexFor(Book, E) = 1, 'an out-of-range hint still resolves by From');
    E.FromType:= 'Nope.TNothing'; E.LineNo:= 9999;
    Check('catalog.header.out.of.range.unknown', HeaderIndexFor(Book, E) = -1, 'out of range AND unknown must be -1, not a crash');

    E.FromType:= ''; E.LineNo:= 0;
    Check('catalog.header.empty.from', HeaderIndexFor(Book, E) = -1);
  finally
    Book.Free;
  end; // try
end; // procedure

{ Task 4 names a NEW atom file and guarantees the path is free.

  RuleFileNameFor must strip the uses-units that ride after a comma on a #convert
  header -- '-> FireDAC.Comp.Client.TFDQuery, FireDAC.Stan.Intf, ...' names ONE target
  and a list of units to add. Taking the whole tail would put half a uses clause in a
  file name. This is the same rule CatalogFromText applies to ToType.

  UniqueRulePath is a SAFETY function, not a convenience: DoSave writes wherever
  FFilePath points, and WriteBlocksTo APPENDS to an existing file. Returning a path
  that already exists would silently graft a new rule onto an unrelated atom. It must
  never return an existing path, and the test asserts that against real files.

  NOTE the file-NAME convention itself is owner ruling 1c and is not settled; it lives
  in one constant so a ruling costs one line. These checks pin the STRIPPING and the
  UNIQUENESS, which no ruling changes. }
procedure TestAtomFileNaming;
var
  Dir: string;
  P1 : string;
  P2 : string;
  P3 : string;
begin
  // --- units after the comma are NOT part of the target type.
  Check(
    'atom.name.strips.units', SameText(RuleFileNameFor('Bde.DBTables.TQuery', 'FireDAC.Comp.Client.TFDQuery, FireDAC.Stan.Intf, FireDAC.DApt'), 'TQuery-to-TFDQuery.rules'),
    RuleFileNameFor('Bde.DBTables.TQuery', 'FireDAC.Comp.Client.TFDQuery, FireDAC.Stan.Intf'));

  // --- already-bare names work unchanged.
  Check('atom.name.bare', SameText(RuleFileNameFor('TEdit', 'TMemo'), 'TEdit-to-TMemo.rules'), RuleFileNameFor('TEdit', 'TMemo'));

  // --- a name must never contain a path separator or other illegal character,
  //     whatever the book spells, or the "new file" would escape the folder.
  Check('atom.name.sanitised', Pos('\', RuleFileNameFor('A\B.TX', 'C/D.TY')) = 0, RuleFileNameFor('A\B.TX', 'C/D.TY'));
  Check('atom.name.sanitised.slash', Pos('/', RuleFileNameFor('A\B.TX', 'C/D.TY')) = 0);

  // --- empty input must not produce a dangling "-to-.rules".
  Check('atom.name.empty', RuleFileNameFor('', '') = '', RuleFileNameFor('', ''));

  // --- UniqueRulePath against REAL files.
  Dir:= TPath.Combine(TPath.GetTempPath, 'convrules_atom_' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(Dir);
  try
    P1:= UniqueRulePath(Dir, 'TQuery-to-TFDQuery.rules');
    Check('atom.path.free.is.plain', SameText(ExtractFileName(P1), 'TQuery-to-TFDQuery.rules'), ExtractFileName(P1));
    Check('atom.path.not.exists', not TFile.Exists(P1));

    TFile.WriteAllText(P1, '#convert A.T -> B.T'#13#10);
    P2:= UniqueRulePath(Dir, 'TQuery-to-TFDQuery.rules');
    Check('atom.path.avoids.existing', not SameText(P1, P2), 'must not hand back a path DoSave would append to');
    Check('atom.path.second.not.exists', not TFile.Exists(P2), P2);

    TFile.WriteAllText(P2, '#convert A.T -> B.T'#13#10);
    P3:= UniqueRulePath(Dir, 'TQuery-to-TFDQuery.rules');
    Check('atom.path.third', (not TFile.Exists(P3)) and (not SameText(P3, P1)) and (not SameText(P3, P2)), P3);

    Check('atom.path.in.folder', SameText(ExcludeTrailingPathDelimiter(ExtractFilePath(P3)), ExcludeTrailingPathDelimiter(Dir)), P3);
  finally
    TDirectory.Delete(Dir, True);
  end; // try
end; // procedure

{ One rule per type is the corpus invariant (owner, 2026-09-08): an atomic rule
  lives in exactly ONE file, because the same conversion in two places is how two
  versions of it diverge. FindDuplicates is what makes that invariant checkable. }
procedure TestRuleCatalogDuplicates;
var
  Cat : TRuleCatalog      ;
  Dups: TCatalogDuplicates;
  A   : TRuleCatalog      ;
  B   : TRuleCatalog      ;
begin
  // --- the intended state: one rule per type, across two files.
  A:= CatalogFromText('#convert Bde.DBTables.TQuery -> FireDAC.Comp.Client.TFDQuery'#13#10, 'C:\rules\bde.rules' );
  B:= CatalogFromText('#convert Vcl.Graphics.TFont -> Vcl.Graphics.TFont'#13#10           , 'C:\rules\font.rules');
  Dups:= FindDuplicates(MergeCatalogs([A, B]));
  Check('catalog.dup.none', Length(Dups) = 0, Format('a clean corpus must report nothing, got %d', [Length(Dups)]));

  Check('catalog.dup.empty', Length(FindDuplicates(nil)) = 0);

  // --- the same type in two files. THE case this exists for.
  B:= CatalogFromText('#convert Bde.DBTables.TQuery -> Other.TSomethingElse'#13#10, 'C:\rules\legacy.rules');
  Cat:= MergeCatalogs([A, B]);
  Dups:= FindDuplicates(Cat);
  Check('catalog.dup.found', Length(Dups) = 1, Format('expected 1 duplicated type, got %d', [Length(Dups)]));
  if Length(Dups) = 1 then
  begin
    Check('catalog.dup.names.the.type', SameText(BareTypeName(Dups[0].FromType), 'TQuery'), Dups[0].FromType);
    // BOTH sites, not just the loser -- the fix is to move or delete one, and you
    // cannot do that without being told where both are.
    Check('catalog.dup.holds.both', Length(Dups[0].Entries) = 2, Format('expected both sites, got %d', [Length(Dups[0].Entries)]));
    Check(
      'catalog.dup.scan.order',
      (Length(Dups[0].Entries) = 2)
        and SameText(ExtractFileName(Dups[0].Entries[0].FilePath), 'bde.rules')
        and SameText(ExtractFileName(Dups[0].Entries[1].FilePath), 'legacy.rules'),
      'sites come back in scan order -- the first is what FindRuleForType picks');
  end; // if

  // --- a QUALIFIED name in one book and a BARE one in another is still a
  //     duplicate. A qualified-string comparison would miss exactly this.
  B:= CatalogFromText('#convert TQuery -> Other.TSomethingElse'#13#10, 'C:\rules\bare.rules');
  Dups:= FindDuplicates(MergeCatalogs([A, B]));
  Check('catalog.dup.bare.vs.qualified', Length(Dups) = 1, 'Bde.DBTables.TQuery and a bare TQuery are the same rule twice');

  // --- case-insensitively, as Pascal is.
  B:= CatalogFromText('#convert bde.dbtables.tquery -> Other.T'#13#10, 'C:\rules\ci.rules');
  Check('catalog.dup.ci', Length(FindDuplicates(MergeCatalogs([A, B]))) = 1);

  // --- twice in the SAME file counts too: one rule, one place, and that place
  //     cannot be the same file twice either.
  Dups:= FindDuplicates(CatalogFromText( '#convert Bde.DBTables.TQuery -> A.TOne'#13#10 + '#convert Bde.DBTables.TQuery -> A.TTwo'#13#10, 'C:\rules\same.rules'));
  Check('catalog.dup.same.file', Length(Dups) = 1, 'a type declared twice in one file is still a duplicate');
  Check('catalog.dup.same.file.both', (Length(Dups) = 1) and (Length(Dups[0].Entries) = 2));

  // --- three sites report as ONE duplicated type carrying three entries, not as
  //     two or three separate findings.
  Dups:= FindDuplicates(CatalogFromText( '#convert TQuery -> A.T1'#13#10 + '#convert TQuery -> A.T2'#13#10 + '#convert TQuery -> A.T3'#13#10, 'C:\rules\three.rules'));
  Check('catalog.dup.three.is.one.finding', Length(Dups) = 1, Format('expected 1 finding, got %d', [Length(Dups)]));
  Check('catalog.dup.three.entries', (Length(Dups) = 1) and (Length(Dups[0].Entries) = 3));

  // --- the REAL corpus must be clean. If this ever fails, the corpus is wrong,
  //     not the test.
  begin
    var Dir: string:= TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\..\..\convrules'));
    if TDirectory.Exists(Dir) then
    begin
      var Errs: TArray<string>                                                     ;
      // Owner ruling 2026-09-20 (finding 4): several rules per class ACROSS books
      // is normal and legal -- only a SAME-book collision is a defect the real
      // corpus must stay clean of. Asserting bare FindDuplicates here would fail
      // the first time the owner legitimately adds a second campaign's rule for
      // a class already ruled in another book.
      var RealDups: TCatalogDuplicates:= SameBookDups(FindDuplicates(ScanRulesFolder(Dir, Errs)));
      var Msg: string:= ''                                                         ;
      if Length(RealDups) > 0 then
        Msg:= RealDups[0].FromType + ' in ' + ExtractFileName(RealDups[0].Entries[0].FilePath) + ' and ' + ExtractFileName(RealDups[0].Entries[1].FilePath);
      Check('catalog.dup.real.corpus.clean', Length(RealDups) = 0, Msg);
    end
    else
      Skip('catalog.dup.real.corpus.clean', 'no convrules\ folder');
  end; // begin
end; // procedure

{ Under the owner's ruling (2026-09-20), two rules for one From type in DIFFERENT
  books is normal -- convert-apply just needs a choice made, which the chooser
  gives it. Only when both sites are the SAME file does apply have no defined way
  to pick, so SameBookDups narrows FindDuplicates' full list down to that case. }
procedure TestSameBookDups;
var
  D: TCatalogDuplicates;
begin
  SetLength(D, 1);
  D[0].FromType:= 'TabcToggleBtn';
  SetLength(D[0].Entries, 2);
  D[0].Entries[0].FilePath:= 'A.rules';
  D[0].Entries[1].FilePath:= 'B.rules';
  Check('samebook.across.books.ok', Length(SameBookDups(D)) = 0, 'two books converting one class differently is legal');

  D[0].Entries[1].FilePath:= 'A.rules';
  Check('samebook.same.book.warns', Length(SameBookDups(D)) = 1, 'one book cannot convert one class two ways');

  // Windows paths are case-insensitive and can differ in separator style; a naive
  // '=' comparison would miss both and under-warn.
  D[0].Entries[0].FilePath:= 'C:\rules\A.rules';
  D[0].Entries[1].FilePath:= 'c:\rules\a.rules';
  Check('samebook.path.casing', Length(SameBookDups(D)) = 1, 'same file, different case, is still the same book');

  D[0].Entries[0].FilePath:= 'C:\rules\A.rules';
  D[0].Entries[1].FilePath:= 'C:/rules/A.rules';
  Check('samebook.path.separator', Length(SameBookDups(D)) = 1, 'same file, different separator style, is still the same book');
end; // procedure

procedure TestRuleCatalogIndex;
var
  Cat : TRuleCatalog     ;
  Back: TRuleCatalog     ;
  Txt : string           ;
  Dir : string           ;
  f   : string           ;
  Errs: TArray<string>   ;
  E   : TRuleCatalogEntry;
begin
  Cat:= CatalogFromText(RC_BOOK, 'C:\rules\bde.rules');
  Txt:= CatalogToIndexText(Cat);

  Check('catalog.index.header', StartsStr(CATALOG_INDEX_HEADER, Txt), 'the index must announce its version');

  Back:= CatalogFromIndexText(Txt);
  Check('catalog.index.roundtrip.count', Length(Back) = Length(Cat), Format('%d out, %d back', [Length(Cat), Length(Back)]));
  if (Length(Back) = 2) and (Length(Cat) = 2) then
  begin
    Check('catalog.index.roundtrip.from', Back[0].FromType = Cat[0].FromType);
    Check('catalog.index.roundtrip.to'  , Back[0].ToType   = Cat[0].ToType  );
    Check('catalog.index.roundtrip.path', Back[0].FilePath = Cat[0].FilePath);
    Check('catalog.index.roundtrip.line', Back[0].LineNo   = Cat[0].LineNo  );
  end;

  // A wrong/absent header refuses the WHOLE file. Half an index under-reports
  // coverage, which reads as "no rule yet" and invites a duplicate.
  Check(
    'catalog.index.bad.header', Length(CatalogFromIndexText('# something else'#13#10'A'#9'B'#9'C'#9'1'#13#10)) = 0, 'an unrecognised header must yield nothing, not a partial read'
  );
  Check('catalog.index.empty', Length(CatalogFromIndexText('')) = 0);
  Check('catalog.index.short.line', Length(CatalogFromIndexText(CATALOG_INDEX_HEADER + #13#10 + 'A'#9'B'#13#10)) = 0, 'a record without four fields is skipped');

  // --- folder scan, against a real temp folder.
  Dir:= TPath.Combine(TPath.GetTempPath, 'convrules_cat_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(Dir);
  try
    f:= TPath.Combine(Dir, 'a.rules');
    TFile.WriteAllText(f, RC_BOOK);
    TFile.WriteAllText(TPath.Combine(Dir, 'notes.txt'), 'ignored');

    Cat:= ScanRulesFolder(Dir, Errs);
    Check('catalog.scan.count', Length(Cat) = 2, Format('expected 2 from one book, got %d', [Length(Cat)]));
    Check('catalog.scan.noerrors', Length(Errs) = 0);
    Check('catalog.scan.path', (Length(Cat) > 0) and SameText(Cat[0].FilePath, f), 'entries carry the real file path');
    Check('catalog.scan.ignores.other.ext', not FindRuleForType(Cat, 'ignored', E));
  finally
    TDirectory.Delete(Dir, True);
  end; // try

  Check('catalog.scan.missing.folder', Length(ScanRulesFolder(TPath.Combine(TPath.GetTempPath, 'no_such_convrules_dir'), Errs)) = 0, 'a missing folder is empty, not an exception');
end; // procedure

{ The catalog against the REAL convrules\ folder this repo ships. A synthetic book
  cannot show that ToType stays clean on headers carrying eleven trailing units,
  which is exactly the shape BDE-to-FireDAC.rules is full of. Skips on a checkout
  that has no convrules\ folder rather than failing. }
procedure TestRuleCatalogRealFolder;
var
  Dir  : string           ;
  Cat  : TRuleCatalog     ;
  Errs : TArray<string>   ;
  E    : TRuleCatalogEntry;
  Bad  : string           ;
  i    : Integer          ;
begin
  // The runner lives at <root>\src\tools\convrules-editor\tests\ -- climb 4.
  Dir:= TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\..\..\convrules'));
  if not TDirectory.Exists(Dir) then
  begin
    Skip('catalog.real', 'no convrules\ folder at ' + Dir);
    Exit;
  end;

  Cat:= ScanRulesFolder(Dir, Errs);
  Check('catalog.real.nonempty', Length(Cat) > 0, Format('scanned %s, got %d entries', [Dir, Length(Cat)]));
  Check('catalog.real.noerrors', Length(Errs) = 0, string.Join('; ', Errs));

  // The units-leak guard, on real headers. '#convert Bde.DBTables.TTable ->
  // FireDAC.Comp.Client.TFDTable, FireDAC.Stan.Intf, ...' must yield a bare type.
  Bad:= '';
  for i:= 0 to High(Cat) do
    if (Pos(',', Cat[i].ToType) > 0) or (Pos(' ', Trim(Cat[i].ToType)) > 0) then
    begin
      Bad:= Format('%s (line %d of %s)', [Cat[i].ToType, Cat[i].LineNo, ExtractFileName(Cat[i].FilePath)]);
      Break;
    end;
  Check('catalog.real.to.is.a.type', Bad = '', 'a ToType still carries uses-units: ' + Bad);

  // Every entry must be attributable -- that is what makes a later save routable.
  Bad:= '';
  for i:= 0 to High(Cat) do
    if (Trim(Cat[i].FromType) = '') or (Cat[i].FilePath = '') or (Cat[i].LineNo <= 0) then
    begin
      Bad:= Format('entry %d is unattributable', [i]);
      Break;
    end;
  Check('catalog.real.attributable', Bad = '', Bad);

  // VARINSP.dfm carries TQuery and TTable, and the BDE book converts both -- this
  // is the exact lookup the form-types panel does to grey a row.
  Check('catalog.real.finds.TQuery', FindRuleForType(Cat, 'TQuery', E), 'the shipped BDE book converts Bde.DBTables.TQuery');
  Check('catalog.real.finds.TTable', FindRuleForType(Cat, 'TTable', E));
  Check('catalog.real.misses.TOvcTable', not FindRuleForType(Cat, 'TOvcTable', E), 'nothing converts TOvcTable yet -- it must NOT show as already ruled');
end; // procedure

{ Enum member auto-suggest. Shapes are the real ones: BDE TBatchMode -> FireDAC
  TFDBatchMoveMode (which convrules\BDE-to-FireDAC.rules:134-139 already maps by
  hand), and the Orpheus/VCL layout pair recorded in the Phase G design. }
procedure TestSuggestEnumPairs;
var
  Pairs  : TEnumPairs    ;
  Surplus: TArray<string>;
  SRC    : TArray<string>;
  Tgt    : TArray<string>;

  function TargetFor(const ASrc: string): string;
  var
    P: TEnumPair;
  begin
    Result:= '<none>';
    for P in Pairs do
      if SameText(P.FromMember, ASrc) then
        Exit(P.ToMember);
  end;

begin
  // --- the lowercase tag, which is what makes name matching work at all.
  Check('enum.tag.bde', LowercaseTagOf(['batAppend', 'batUpdate', 'batDelete']) = 'bat', LowercaseTagOf(['batAppend', 'batUpdate', 'batDelete']));
  Check('enum.tag.fd', LowercaseTagOf(['dmAppend', 'dmUpdate', 'dmAlwaysInsert']) = 'dm');
  Check('enum.tag.single', LowercaseTagOf(['ablGlyphLeft']) = 'abl', 'one member still yields its lowercase lead, not the whole name');
  Check('enum.tag.none', LowercaseTagOf(['Alpha', 'Beta']) = '', 'members with no lowercase lead have no tag');
  Check('enum.tag.empty', LowercaseTagOf([]) = '');
  Check('enum.tag.disjoint', LowercaseTagOf(['batAppend', 'dmAppend']) = '', 'no shared lead -> no tag');

  // THE TRAP: a raw common prefix of (abcOne, abcOnly) is 'abcOn', and stripping
  // that would compare 'e' with 'ly'. The tag must stop at the lowercase run.
  Check('enum.tag.stops.at.case.boundary', LowercaseTagOf(['abcOne', 'abcOnly']) = 'abc', LowercaseTagOf(['abcOne', 'abcOnly']));

  // --- the real BDE -> FireDAC pair.
  SRC:= ['batAppend', 'batUpdate', 'batAppendUpdate', 'batDelete', 'batCopy'       ];
  Tgt:= ['dmAppend' , 'dmUpdate' , 'dmAppendUpdate' , 'dmDelete' , 'dmAlwaysInsert'];
  Pairs:= SuggestEnumPairs(SRC, Tgt, Surplus);

  Check('enum.pairs.one.per.source', Length(Pairs) = 5, Format('expected 5 rows, got %d', [Length(Pairs)]));
  Check('enum.pairs.append', TargetFor('batAppend') = 'dmAppend');
  Check('enum.pairs.update', TargetFor('batUpdate') = 'dmUpdate');
  Check('enum.pairs.appendupdate', TargetFor('batAppendUpdate') = 'dmAppendUpdate', 'the longer name must not be stolen by the shorter one');
  Check('enum.pairs.delete', TargetFor('batDelete') = 'dmDelete');

  // batCopy has no dmCopy. That is the interesting answer, not a failure -- the
  // hand-written book maps it to dmAlwaysInsert, which no name rule could know.
  Check('enum.pairs.unmatched.is.blank', TargetFor('batCopy') = '', 'a source member with no name match must come back blank, not guessed');
  Check('enum.pairs.surplus.reported', (Length(Surplus) = 1) and SameText(Surplus[0], 'dmAlwaysInsert'), Format('surplus=%d: %s', [Length(Surplus), string.Join(',', Surplus)]));

  Check(
    'enum.pairs.order.preserved', (Length(Pairs) = 5) and (Pairs[0].FromMember = 'batAppend') and (Pairs[4].FromMember = 'batCopy'), 'rows come back in source declaration order');

  // --- the Orpheus/VCL layout pair from the Phase G design: 6 vs 4, 4 match.
  SRC:= ['ablGlyphLeft', 'ablGlyphRight', 'ablGlyphTop', 'ablGlyphBottom', 'ablGlyphOverlay', 'ablGlyphNone'];
  Tgt:= ['blGlyphLeft', 'blGlyphRight', 'blGlyphTop', 'blGlyphBottom'];
  Pairs:= SuggestEnumPairs(SRC, Tgt, Surplus);
  Check('enum.pairs.abc.count', Length(Pairs) = 6);
  Check('enum.pairs.abc.matched', (TargetFor('ablGlyphLeft') = 'blGlyphLeft') and (TargetFor('ablGlyphBottom') = 'blGlyphBottom'));
  Check('enum.pairs.abc.surplus.source', (TargetFor('ablGlyphOverlay') = '') and (TargetFor('ablGlyphNone') = ''), 'the two extra source members stay unmapped');
  Check('enum.pairs.abc.no.target.surplus', Length(Surplus) = 0, 'every target was used');

  // --- case-insensitivity and degenerate inputs.
  // Case-insensitivity applies to the NAME half. The tag is a LOWERCASE run by
  // definition, so an ALL-CAPS member ('DMAPPEND') correctly has no tag at all
  // and its bare name stays the whole identifier -- vary case after the tag.
  Pairs:= SuggestEnumPairs(['batAppend'], ['dmAPPEND'], Surplus);
  Check('enum.pairs.ci', (Length(Pairs) = 1) and (Pairs[0].ToMember = 'dmAPPEND'), 'matching is case-insensitive but returns the target VERBATIM');
  Pairs:= SuggestEnumPairs(['batAppend'], ['DMAPPEND'], Surplus);
  Check('enum.pairs.no.tag.no.match', Pairs[0].ToMember = '', 'an all-caps target has no lowercase tag, so its bare name is the whole name');

  Pairs:= SuggestEnumPairs([], ['dmAppend'], Surplus);
  Check('enum.pairs.no.source'            , Length(Pairs  ) = 0);
  Check('enum.pairs.no.source.all.surplus', Length(Surplus) = 1);

  Pairs:= SuggestEnumPairs(['batAppend'], [], Surplus);
  Check('enum.pairs.no.target', (Length(Pairs) = 1) and (Pairs[0].ToMember = ''));
  Check('enum.pairs.no.target.no.surplus', Length(Surplus) = 0);

  // A target may only be consumed ONCE -- two source members must not both claim
  // the same target, or the generated book would write a duplicate arm.
  // Reached only via DUPLICATE input: within one enum, members are unique and
  // share a tag, so their bare names are unique too and two of them can never
  // claim the same target. Duplicates CAN arrive from a caller, so the guard is
  // real -- and this is the input that actually exercises it.
  Pairs:= SuggestEnumPairs(['batAppend', 'batAppend'], ['dmAppend'], Surplus);
  Check(
    'enum.pairs.target.used.once', (Length(Pairs) = 2) and (Pairs[0].ToMember = 'dmAppend') and (Pairs[1].ToMember = ''),
    'a duplicated source member must not claim the same target twice');
  Check('enum.pairs.used.once.no.surplus', Length(Surplus) = 0, 'the target was consumed, so it is not surplus');
end; // begin

procedure TestOutlineClassNames;
const
  JSON =
    '[' +
    ' {"kind":"unit","name":"VARINSP","qname":"VARINSP","line":9},' +
    ' {"kind":"enum","name":"TFinalColor","qname":"VARINSP.TFinalColor","line":160},' +
    ' {"kind":"class","name":"TVarInspForm","qname":"VARINSP.TVarInspForm","line":190},' +
    ' {"kind":"class","name":"TsgDXFImageAccess","qname":"VARINSP.TsgDXFImageAccess","line":178},' +
    ' {"kind":"class","name":"tvarinspform","qname":"VARINSP.tvarinspform","line":9999},' +
    ' {"kind":"record","name":"TRectangleAround","qname":"VARINSP.TRectangleAround","line":172}' +
    ']';
var
  N : TArray<string>;
  N2: TArray<string>;
begin
  N:= ParseOutlineClassNames(JSON);
  Check('outline.classes.count', Length(N) = 2, Format('%d', [Length(N)]));
  Check('outline.classes.first', N[0] = 'TVarInspForm', N[0]);
  Check('outline.classes.order', N[1] = 'TsgDXFImageAccess', 'document order, not sorted');

  // A fresh, separate call (not the same N above) -- proves the case-insensitive
  // dedupe reliably keeps the FIRST-SEEN casing ('TVarInspForm') rather than
  // letting the later lowercase stub ('tvarinspform') win or overwrite it.
  N2:= ParseOutlineClassNames(JSON);
  Check(
    'outline.classes.dedupe.ci', (Length(N2) = 2) and (N2[0] = 'TVarInspForm'),
    'a forward stub repeats the name -- one row only, and first-seen casing must survive de-duplication');

  // The CLI prints a '(loaded defaults from ...)' preamble on some runs and not
  // others. Slicing first-'[' .. last-']' is what the IDE plugin does; without
  // it the parse fails on exactly the runs that print it.
  Check('outline.classes.preamble', Length(ParseOutlineClassNames('(loaded defaults from C:\x.json)'#13#10 + JSON)) = 2, 'CLI preamble must be tolerated');
  Check('outline.classes.trailing', Length(ParseOutlineClassNames(JSON + #13#10'note: 1 of 2 files changed')) = 2, 'trailing note must be tolerated');

  Check('outline.classes.empty.array', Length(ParseOutlineClassNames('[]')) = 0);
  Check('outline.classes.garbage', Length(ParseOutlineClassNames('not json at all')) = 0, 'never raises');
  Check('outline.classes.blank', Length(ParseOutlineClassNames('')) = 0);
  Check('outline.classes.no.classes', Length(ParseOutlineClassNames('[{"kind":"unit","name":"U"}]')) = 0, 'positive control: the parser can return empty for a real payload');

  // Well-formed brackets around MALFORMED JSON -- the hardest case for "never
  // raises": Pos('[')/LastDelimiter(']') both succeed, so ParseJSONValue is
  // actually reached and must throw into the except handler, not before it.
  Check('outline.classes.malformed.inside.brackets', Length(ParseOutlineClassNames('[{"kind": "class", "name":]')) = 0, 'invalid JSON between real brackets must be caught, not raised');
end; // procedure

{ The persistent per-unit scratch index path: stable per unit, distinct across
  units sharing a stem, and rooted under %LOCALAPPDATA%\DragLint\ConvRulesEditor. }
procedure TestScratchDbPath;
var
  A: string;
  B: string;
begin
  A:= ScratchDbPath('C:\Projects\M2022\VARINSP.PAS');
  B:= ScratchDbPath('C:\Projects\DB\ORM3\CLIENT\VARINSP.PAS');
  Check('scratchdb.stem', ContainsText(ExtractFileName(A), 'VARINSP'), A);
  Check('scratchdb.ext', SameText(ExtractFileExt(A), '.sqlite'), A);
  Check('scratchdb.stable', A = ScratchDbPath('C:\Projects\M2022\VARINSP.PAS'), 'same unit -> same DB, or the cold cost is paid every time');
  Check('scratchdb.ci', A = ScratchDbPath('c:\projects\m2022\varinsp.pas'), 'Windows paths are case-insensitive');
  Check('scratchdb.distinct', A <> B, 'two units with the SAME stem must not collide');
  Check('scratchdb.under.localappdata', ContainsText(A, 'ConvRulesEditor'), A);
  Check('scratchdb.blank', ScratchDbPath('') = '', 'no file -> no path');
end; // procedure

{ Live: OutlineClasses index-on-demand. Self-contained on purpose -- an orphan
  unit in no corpus and no manifest is exactly the shape this feature exists
  for (VARINSP is one), and it keeps the test from depending on which big
  indexes happen to exist on the machine. Proves: (1) an uncovered unit gets
  indexed on demand and answers correctly, (2) the scratch DB persists so the
  SECOND call does not pay the index cost again, (3) a unit a CONFIGURED db
  already covers is answered directly and never indexed. }
procedure TestOutlineClassesLive;
var
  Exe      : string        ;
  Eng      : TEngineAdapter;
  Covered  : TEngineAdapter;
  Classes  : TArray<string>;
  Indexed  : Boolean       ;
  Err      : string        ;
  Orphan   : string        ;
  ScratchDb: string        ;
  CopyDb   : string        ;
begin
  Exe:= ResolveExe;
  if Exe = '' then
  begin
    Skip('outline.classes.live', 'drag-lint.exe not found');
    Exit;
  end;

  Orphan:= TPath.Combine(TPath.GetTempPath, 'ConvRulesOrphanProbe.pas');
  TFile.WriteAllText(Orphan,
    'unit ConvRulesOrphanProbe;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TOrphanProbe = class(TObject)'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.'#13#10);
  ScratchDb:= ScratchDbPath(Orphan);
  CopyDb   := ScratchDb + '.covered-copy.sqlite';
  if TFile.Exists(ScratchDb) then
    TFile.Delete(ScratchDb); // start cold, or the first assertion lies
  if TFile.Exists(CopyDb) then
    TFile.Delete(CopyDb);

  Eng:= TEngineAdapter.Create(Exe, []);
  try
    Check('outline.live.orphan.ok', Eng.OutlineClasses(Orphan, Classes, Indexed, Err), Err);
    Check('outline.live.orphan.indexed', Indexed, 'an uncovered unit must be indexed on demand');
    Check('outline.live.orphan.class', (Length(Classes) = 1) and (Classes[0] = 'TOrphanProbe'), Format('%d classes', [Length(Classes)]));

    // R1.4: the scratch DB persists, so the SECOND call must not index again.
    // This is the assertion that proves the 27 s cold cost is paid once.
    Check('outline.live.orphan.warm', Eng.OutlineClasses(Orphan, Classes, Indexed, Err) and not Indexed, 'the second call must reuse the scratch DB');

    // R1.3 / A10 (2026-09-20 whole-branch review, Minor 12): this used to configure
    // Covered with the SAME scratch DB the warm call just proved above it can answer
    // from -- so a broken "resolve-dbs --in / outline against the configured DB"
    // path could never fail outline.live.covered.notindexed; it would just fall
    // through to the still-present warm scratch DB and read as covered either way.
    // Copying the scratch DB to a SECOND path and deleting the original removes that
    // fallback: if the configured-DB path were broken, OutlineClasses would have
    // nothing to fall through to at ScratchDb and would have to re-index (Indexed =
    // True) or fail (Result = False), either of which this assertion would catch.
    // Fix wave, Minor 10: TFile.Copy raises if ScratchDb is not there -- which
    // would mean outline.live.orphan.warm's own call above failed to create it,
    // an EARLIER assertion's job to catch. Guard so that surfaces as a Check
    // failure here too rather than an exception escaping this procedure and
    // aborting whatever runs after it.
    if TFile.Exists(ScratchDb) then
    begin
      TFile.Copy(ScratchDb, CopyDb);
      TFile.Delete(ScratchDb);
      Covered:= TEngineAdapter.Create(Exe, [CopyDb]);
      try
        Check('outline.live.covered.ok', Covered.OutlineClasses(Orphan, Classes, Indexed, Err), Err);
        Check('outline.live.covered.notindexed', not Indexed, 'a covered unit must never pay the index cost');
      finally
        Covered.Free;
      end;
    end
    else
      Check('outline.live.covered.setup', False, 'ScratchDb missing before the covered/warm split copy -- outline.live.orphan.warm must not have created it');
  finally
    Eng.Free;
    if TFile.Exists(Orphan) then
      TFile.Delete(Orphan);
    // A9 (2026-09-20 whole-branch review, Minor 17): the probe .pas is deleted
    // above, but its scratch DB(s) under %LOCALAPPDATA% otherwise survive this
    // test run forever.
    if TFile.Exists(ScratchDb) then
      TFile.Delete(ScratchDb);
    if TFile.Exists(CopyDb) then
      TFile.Delete(CopyDb);
  end; // try
end; // procedure

procedure TestMappingGridHooks;
var
  Book   : TArray<TRuleNode>       ;
  Blk    : TArray<TRuleNode>       ;
  Names  : TArray<string>          ;
  Conds  : TArray<TConditionalFrom>;
  Targets: TArray<string>          ;
begin
  Book:= ParseAll([
      '#mapping M from X.TStyle to cxButtons.TcxButton', '#mapping M #when Style = stOK -> Default = True, ModalResult = mrOk',
      '#mapping M #when Style = stCancel -> Cancel = True', '#mapping M #else -> ModalResult = mrNone', '#convert X.TBtn -> cxButtons.TcxButton', '#apply M']);
  Blk:= ParseAll(['#apply M']);

  Names:= AppliedMappingNames(Blk);
  Check('applied.names', (Length(Names) = 1) and (Names[0] = 'M'), 'the block applies M');

  Conds:= ConditionalFromPaths(Book, Names);
  Check('cond.one.path', Length(Conds) = 1, 'every clause reads the same From property, so there is ONE conditional leaf, got ' + IntToStr(Length(Conds)));
  Check(
    'cond.case.count', ConditionalCasesOf(Conds, 'Style') = 3,
    'two #when plus the #else are three branches of the same decision, got ' + IntToStr(ConditionalCasesOf(Conds, 'Style')));
  Check('cond.case.count.casing', ConditionalCasesOf(Conds, 'STYLE'  ) = 3, 'path matching is case-insensitive'                    );
  Check('cond.unrelated.leaf'   , ConditionalCasesOf(Conds, 'Caption') = 0, 'a leaf no mapping decides must stay freely assignable');
  Check('cond.needs.apply', Length(ConditionalFromPaths(Book, nil)) = 0, 'a mapping the block does not #apply must not claim that block''s From leaves');

  Targets:= MappedTargetPaths(Book, Names);
  Check('targets.count', Length(Targets) = 3, string.Join(',', Targets));
  Check('targets.deduped', CountOf(Targets, 'ModalResult') = 1, 'ModalResult is set by two clauses, and must be withheld from the pool once');
  Check('targets.needs.apply', Length(MappedTargetPaths(Book, nil)) = 0, 'an unapplied mapping must not take leaves out of the pool');
end; // procedure

{ Absolute path of a rule book in the repo's top-level convrules\ directory.
  The test exe lives in src\tools\convrules-editor\tests, so four levels up is the
  repo root. }
function ConvRulesCorpusPath(const AFileName: string): string;
begin
  Result:= TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\..\..\convrules\' + AFileName));
end;

{ Conformance harness for one imported reFind rule book.

  These files are Embarcadero's OWN reFind migration instructions, committed under
  convrules\vendor\ verbatim (see docs\converter\refind-corpus.md and
  convrules\vendor\README.md). They moved out of convrules\ on 2026-09-09 because
  they carry no #convert and so contribute nothing to the rule catalog, while a
  future atomization of their #migrate lines would collide with BDE-to-FireDAC.rules
  in the duplicate report. They remain a product deliverable a user can open in the
  editor, NOT an optional fixture -- so an absent file is a FAILURE, never a Skip.

  Three assertions, and none of them may be relaxed to get green:
    * a non-trivial count of RECOGNISED (non-blank, non-comment) lines, which stops a
      parser from "passing" by classifying the whole file as blank;
    * ZERO rnkUnknown lines -- the claim under test is that our DSL is a reFind
      superset, and every unknown line is a hole in that claim;
    * byte-exact round-trip: SaveToString must reproduce the file's exact text. }
procedure CheckReFindCorpus(const AId, AFileName: string; AMinRecognised: Integer);
var
  P           : string   ;
  Txt         : string   ;
  Round       : string   ;
  FirstUnknown: string   ;
  Book        : TRuleBook;
  n           : TRuleNode;
  Unknown     : Integer  ;
  Recognised  : Integer  ;
begin
  P:= ConvRulesCorpusPath(AFileName);
  if not TFile.Exists(P) then
  begin
    Check(AId + '.present', False, 'committed corpus file is missing: ' + P);
    Exit;
  end;
  Check(AId + '.present', True);

  Txt:= TFile.ReadAllText(P, TEncoding.ASCII);
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(Txt);

    Unknown     := 0;
    Recognised  := 0;
    FirstUnknown:= '';
    for n in Book.Nodes do
      if n.Kind = rnkUnknown then
      begin
        Inc(Unknown);
        if FirstUnknown = '' then
          FirstUnknown:= n.Raw;
      end
    else if not (n.Kind in [rnkBlank, rnkComment]) then
      Inc(Recognised);

    Check(AId + '.recognised.nontrivial', Recognised >= AMinRecognised, Format('%d recognised lines, want >= %d', [Recognised, AMinRecognised]));
    Check(AId + '.no.unknown', Unknown = 0, Format('%d unknown line(s); first: "%s"', [Unknown, FirstUnknown]));

    Round:= Book.SaveToString;
    Check(AId + '.roundtrip', Round = Txt, Format('round-trip altered the corpus (got %d chars, want %d)', [Length(Round), Length(Txt)]));
  finally
    Book.Free;
  end; // try
end; // procedure

{ Task 9: our DSL claims to be a reFind SUPERSET. This measures that claim against
  Embarcadero's two shipped reFind instruction files rather than invented input.

  READ THE LIMITS before trusting the green:
  * '.roundtrip' proves line-split / line-ending fidelity ONLY. TRuleNode.Emit returns
    Raw verbatim whenever Dirty is False, and LoadFromString never sets Dirty, so the
    round-trip cannot exercise ANY field reconstruction -- for #migrate exactly as much
    as for rnkPcre. TestReFindCorpusReconstructs is the test that does.
  * '.recognised.nontrivial' is met by line SHAPE, not by comprehension: for the rename
    corpus every non-blank line contains ' -> ', so the threshold is satisfied by the
    file format alone.
  * '.no.unknown' is the only assertion with real grammar content, and its strength
    differs per file -- keyword dispatch for the BDE corpus, an unanchored catch-all
    for the rename corpus. See docs\converter\refind-corpus.md. }
procedure TestReFindCorpusLoads;
begin
  // 69 directives (#unuse / #remove / #remove DFM: / #migrate) across 77 lines.
  CheckReFindCorpus('refind.bde', 'vendor\FireDAC_Migrate_BDE.rules', 20);
  // 197 bare 'old -> new' unit renames -- reFind's plain find/replace form.
  CheckReFindCorpus('refind.units', 'vendor\FireDAC_Rename_Units.rules', 20);
end;

{ The kinds TRuleNode.Emit rebuilds FROM ITS TYPED FIELDS when Dirty. Everything else
  (rnkMigrate, rnkPcre, rnkComment, rnkBlank, rnkUnknown) falls to Emit's else branch
  and returns Raw whatever Dirty says. }
const
  RECONSTRUCTING_KINDS = [rnkConvert, rnkLink, rnkDefault, rnkIgnore, rnkRemove, rnkUnuse, rnkUse, rnkUseSwap, rnkNote, rnkMapping, rnkApply];

  { Task 9 follow-up: make the BDE corpus prove something the plain round-trip cannot.

  Marking a node Dirty forces Emit to REBUILD the line out of the fields the parser
  decomposed it into, instead of echoing Raw. Doing that to the real corpus and getting
  the original bytes back is genuine evidence that parse and emit are inverses for those
  directive forms -- which is what "superset of reFind" has to mean in practice.

  Deliberately scoped to the kinds that HAVE a reconstruction path: dirtying a
  raw-only kind would prove nothing while making the check look broader than it is.
  The third assertion pins the known gap so it cannot close silently. }
procedure TestReFindCorpusReconstructs;
var
  P          : string   ;
  Txt        : string   ;
  Rebuilt    : string   ;
  Book       : TRuleBook;
  n          : TRuleNode;
  FirstUnuse : TRuleNode;
  Rebuildable: Integer  ;
  Migrates   : Integer  ;
  Bare       : Integer  ;
begin
  P:= ConvRulesCorpusPath('vendor\FireDAC_Migrate_BDE.rules');
  if not TFile.Exists(P) then
  begin
    Check('refind.bde.reconstruct.present', False, 'committed corpus file is missing: ' + P);
    Exit;
  end;

  Txt:= TFile.ReadAllText(P, TEncoding.ASCII);
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(Txt);

    Rebuildable:= 0;
    Migrates   := 0;
    Bare       := 0;
    FirstUnuse:= nil;
    for n in Book.Nodes do
    begin
      if n.Kind in RECONSTRUCTING_KINDS then
      begin
        Inc(Rebuildable);
        n.Dirty:= True; // force Emit down the field-reconstruction path
        if (n.Kind = rnkUnuse) and (FirstUnuse = nil) then
          FirstUnuse:= n;
      end;
      if n.Kind = rnkMigrate then
      begin
        Inc(Migrates);
        // A decomposed #migrate would have filled these; none of them does.
        if (n.FromType = '') and (n.ToType = '') and (n.Units = '') then
          Inc(Bare);
      end;
    end; // for

    { 6 x #unuse + 2 x #remove + 1 x #remove DFM: = 9 lines with a real parse->emit
      inverse to check. Small, but it is the honest number. }
    Check('refind.bde.reconstruct.count', Rebuildable >= 9, Format('%d reconstructable nodes, want >= 9', [Rebuildable]));

    Rebuilt:= Book.SaveToString;
    Check(
      'refind.bde.reconstruct.exact', Rebuilt = Txt,
      Format('re-emitting %d nodes from their parsed fields did not reproduce the corpus ' + '(got %d chars, want %d)', [Rebuildable, Length(Rebuilt), Length(Txt)]));

    { GAP, pinned: #migrate is recognised but NOT decomposed -- ParseLine sets only Kind
      and Raw, so Emit passes it straight through and all 60 of the corpus's #migrate
      lines round-trip vacuously. If someone teaches the parser to split #migrate, this
      check fails on purpose: update it AND docs\converter\refind-corpus.md together. }
    Check('refind.bde.migrate.notdecomposed', (Migrates >= 60) and (Bare = Migrates), Format('%d of %d #migrate nodes carry no parsed fields', [Bare, Migrates]));

    { Sensitivity guard: '.reconstruct.exact' would also pass if Dirty were ignored and
      every node echoed Raw. Perturb one parsed FIELD -- not Raw -- and the output must
      change. If it does not, the reconstruction path is dead and the check above is
      vacuous. }
    if FirstUnuse = nil then
      Check('refind.bde.reconstruct.live', False, 'no rnkUnuse node to perturb')
    else
    begin
      FirstUnuse.UnuseUnit:= 'ZZZ.Sentinel';
      Rebuilt:= Book.SaveToString;
      Check(
        'refind.bde.reconstruct.live', (Rebuilt <> Txt) and (Pos('#unuse ZZZ.Sentinel', Rebuilt) > 0),
        'editing a parsed field did not change the emitted text -- Emit ignored Dirty');
    end;
  finally
    Book.Free;
  end; // try
end; // procedure

{ convrules\BDE-to-FireDAC.rules is the assembled conversion LIBRARY: the BDE corpus
  re-expressed as #convert blocks with their property links filled in, machine-written
  by replaying the editor's own Auto-Match rule against drag-lint property trees.

  It is a product deliverable a user opens and edits, so -- exactly like the two
  imported reFind books -- an absent file is a FAILURE, never a Skip. What is pinned
  here are the invariants that must survive ANY edit the user makes, NOT the current
  block/link counts (those are expected to move as they work through it):

    * it loads with ZERO rnkUnknown lines;
    * SaveToString reproduces it byte for byte;
    * every #convert block "maps something", i.e. carries at least one
      #link / #apply / #ignore. This is the one that earns its keep: a block that
      maps nothing is SILENTLY DROPPED on save (TRuleBook.BlockMapsSomething, and
      docs\converter\convrules-dsl.md "Known limits" #3), so a library whose blocks
      were all #note would look fine and evaporate the first time it was saved. }
procedure TestConversionLibraryLoads;
var
  P   : string         ;
  Txt : string         ;
  Book: TRuleBook      ;
  Hdrs: TArray<Integer>;
  H   : Integer        ;
  Bad : Integer        ;
begin
  { The recognised-line floor is deliberately far below what the file carries today
    (~300 directives): this is a working document meant to be cut down, and a tight
    threshold would fail on legitimate editing rather than on a parser regression. }
  CheckReFindCorpus('convlib.bde2fd', 'BDE-to-FireDAC.rules', 50);

  P:= ConvRulesCorpusPath('BDE-to-FireDAC.rules');
  if not TFile.Exists(P) then Exit; // already reported by CheckReFindCorpus
  Txt:= TFile.ReadAllText(P, TEncoding.ASCII);
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(Txt);
    Hdrs:= Book.ConvertHeaders;
    Check('convlib.bde2fd.blocks', Length(Hdrs) > 0, 'no #convert block parsed');
    Bad:= 0;
    for H in Hdrs do
      if not TRuleBook.BlockMapsSomething(Book.NodesInBlock(H)) then
        Inc(Bad);
    Check('convlib.bde2fd.blocks.survive.save', Bad = 0, Format('%d of %d #convert block(s) map nothing and would be dropped on save', [Bad, Length(Hdrs)]));
  finally
    Book.Free;
  end; // try
end; // procedure

{ The library is almost entirely made of kinds that DO reconstruct (#convert, #link,
  #note, #mapping, #apply, #unuse, #remove), which makes it a far stronger parse/emit
  inverse witness than the reFind corpus -- there the honest number was 9 lines, here
  it is the whole file. Same shape as TestReFindCorpusReconstructs, including its
  sensitivity guard, because '.exact' alone would also pass if Dirty were ignored. }
procedure TestConversionLibraryReconstructs;
var
  P          : string   ;
  Txt        : string   ;
  Rebuilt    : string   ;
  Book       : TRuleBook;
  n          : TRuleNode;
  FirstLink  : TRuleNode;
  Rebuildable: Integer  ;
begin
  P:= ConvRulesCorpusPath('BDE-to-FireDAC.rules');
  if not TFile.Exists(P) then
  begin
    Check('convlib.bde2fd.reconstruct.present', False, 'library file is missing: ' + P);
    Exit;
  end;

  Txt:= TFile.ReadAllText(P, TEncoding.ASCII);
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(Txt);
    Rebuildable:= 0;
    FirstLink:= nil;
    for n in Book.Nodes do
      if n.Kind in RECONSTRUCTING_KINDS then
      begin
        Inc(Rebuildable);
        n.Dirty:= True;
        if (n.Kind = rnkLink) and (FirstLink = nil) then
          FirstLink:= n;
      end;

    Check('convlib.bde2fd.reconstruct.count', Rebuildable >= 50, Format('%d reconstructable nodes, want >= 50', [Rebuildable]));
    Rebuilt:= Book.SaveToString;
    Check(
      'convlib.bde2fd.reconstruct.exact', Rebuilt = Txt,
      Format('re-emitting %d nodes from their parsed fields did not reproduce the ' + 'library (got %d chars, want %d) -- the file is no longer canonical DSL', [Rebuildable, Length(Rebuilt), Length(Txt)])
    );

    if FirstLink = nil then
      Check('convlib.bde2fd.reconstruct.live', False, 'no rnkLink node to perturb')
    else
    begin
      FirstLink.LinkTo:= 'ZZZ.Sentinel';
      Rebuilt:= Book.SaveToString;
      Check(
        'convlib.bde2fd.reconstruct.live', (Rebuilt <> Txt) and (Pos('#link ZZZ.Sentinel <- ', Rebuilt) > 0),
        'editing a parsed field did not change the emitted text -- Emit ignored Dirty');
    end;
  finally
    Book.Free;
  end; // try
end; // procedure

{ The silent-damage guard for the conversion library.

  '#remove <P>' is FILE-SCOPED and takes a BARE property name -- unlike #migrate it has
  no '<Class>:' qualifier -- so it strips P from EVERY component in the converted file.
  Emitting one for a property that some OTHER #convert block legitimately reads would
  destroy that block's mapping, and nothing in the DSL would complain. This asserts the
  invariant the library is built to: no plain #remove names a property that any #link
  anywhere takes as its SOURCE (directly, or as the root of a dotted source path, since
  removing Params also removes Params.Items.Name).

  '#remove DFM: <P>' is deliberately EXCLUDED from the check, because it is a different
  statement: it drops only the value persisted in the .dfm and KEEPS the property in
  code. The corpus's '#remove DFM: Origin' coexists with '#link Origin <- Origin' on
  purpose -- Origin is the one inherited Data.DB.TField.Origin, carried by both
  Data.DB.TAutoIncField and FireDAC.Comp.DataSet.TFDAutoIncField (verified against
  library-Win64), so the link is real while the DFM remove only discards a stale
  BDE-format value. Promoting that line to a plain '#remove Origin' WOULD break the
  link -- and this test fails if anyone does, which is the point. }
procedure TestConversionLibraryRemovesAreSafe;
var
  P   : string   ;
  Txt : string   ;
  Bad : string   ;
  Book: TRuleBook;
  n   : TRuleNode;
  L2  : TRuleNode;
  SRC : string   ;
  Prop: string   ;
  Dot : Integer  ;
  NBad: Integer  ;
begin
  P:= ConvRulesCorpusPath('BDE-to-FireDAC.rules');
  if not TFile.Exists(P) then
  begin
    Check('convlib.bde2fd.removes.present', False, 'library file is missing: ' + P);
    Exit;
  end;

  Txt:= TFile.ReadAllText(P, TEncoding.ASCII);
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(Txt);
    NBad:= 0;
    Bad := '';
    for n in Book.Nodes do
    begin
      if (n.Kind <> rnkRemove) or n.RemoveDfmOnly then
        Continue;
      Prop:= Trim(n.RemoveProp);
      if Prop = '' then
        Continue;
      for L2 in Book.Nodes do
      begin
        if L2.Kind <> rnkLink then
          Continue;
        SRC:= Trim(L2.LinkFrom);
        Dot:= Pos('.', SRC);
        if Dot > 0 then
          SRC:= Copy(SRC, 1, Dot - 1);
        if SameText(SRC, Prop) then
        begin
          Inc(NBad);
          if Bad = '' then
            Bad:= Format('#remove %s vs #link %s <- %s', [Prop, L2.LinkTo, L2.LinkFrom]);
        end;
      end; // for
    end; // for
    Check('convlib.bde2fd.removes.dont.strip.links', NBad = 0, Format('%d file-scope #remove/#link collision(s); first: %s', [NBad, Bad]));
  finally
    Book.Free;
  end; // try
end; // procedure

function HarvestNames(const AUnits: TArray<THarvestedUnit>): string;
var
  Names: TArray<string>;
  i    : Integer;
begin
  SetLength(Names, Length(AUnits));
  for i:= 0 to High(AUnits) do
    Names[i]:= AUnits[i].UnitName;
  Result:= string.Join(',', Names);
end;

procedure TestUsesHarvestText;
var
  R: TArray<THarvestedUnit>;
begin
  R:= HarvestText('uses Forms, DB {comment, Fake}, Foo in ''Foo.pas'';');
  Check('harvest.text.uses.names', HarvestNames(R) = 'Forms,DB,Foo', HarvestNames(R));
  Check('harvest.text.uses.usedby', (Length(R) = 3) and (R[0].UsedBy = PASTED_SOURCE), HarvestNames(R));
  Check('harvest.text.uses.nosection', (Length(R) = 3) and (R[0].Section = ''), HarvestNames(R));

  R:= HarvestText('Forms, Vcl.Dialogs; DB' + #13#10 + 'Data.DB');
  Check('harvest.text.list.names', HarvestNames(R) = 'Forms,Vcl.Dialogs,DB,Data.DB', HarvestNames(R));

  // Prose: '3' (number), 'units:' (colon) and '12x.' (trailing dot) are not identifiers.
  R:= HarvestText('Replace these 3 units: Forms and 12x.');
  Check('harvest.text.list.drops.nonidents', HarvestNames(R) = 'Replace,these,Forms,and', HarvestNames(R));

  R:= HarvestText('Forms forms FORMS');
  Check('harvest.text.dedup.nocase', HarvestNames(R) = 'Forms', HarvestNames(R));

  R:= HarvestText('');
  Check('harvest.text.empty', Length(R) = 0, IntToStr(Length(R)));

  // A .dpr uses-clause selection WITHOUT the keyword (ruling R14): the `in` word,
  // the quoted path and both comment styles must not become units.
  R:= HarvestText('U1 in ''U1.pas'' {Form1},' + #13#10 + '  Sub.U2 in ''..\Sub\U2.pas'', // old DM' + #13#10 + '  Vcl.Forms');
  Check('harvest.text.dpr.fragment', HarvestNames(R) = 'U1,Sub.U2,Vcl.Forms', HarvestNames(R));
  R:= HarvestText('A IN ''a.pas'' (* Old, Junk *), B');
  Check('harvest.text.list.strips.paren.comment.and.IN', HarvestNames(R) = 'A,B', HarvestNames(R));
end;

procedure TestDprMembers;
const
  DPR =
    'program App;' + #13#10 +
    'uses' + #13#10 +
    '  Vcl.Forms,' + #13#10 +
    '  U1 in ''U1.pas'' {Form1},' + #13#10 +
    '  Sub.U2 in ''..\Sub\U2.pas'' {dm: TDataModule};' + #13#10 +
    'begin' + #13#10 +
    'end.';
var
  M: TArray<TDprMember>;
begin
  M:= ReadDprMembers(DPR, 'C:\P\App');
  Check('dpr.members.count', Length(M) = 3, IntToStr(Length(M)));
  if Length(M) <> 3 then
    Exit;
  Check('dpr.members.plain.name', M[0].UnitName = 'Vcl.Forms', M[0].UnitName);
  Check('dpr.members.plain.nopath', M[0].FilePath = '', M[0].FilePath);
  Check('dpr.members.in.path', SameText(M[1].FilePath, 'C:\P\App\U1.pas'), M[1].FilePath);
  Check('dpr.members.dotted.relative', (M[2].UnitName = 'Sub.U2') and SameText(M[2].FilePath, 'C:\P\Sub\U2.pas'), M[2].UnitName + ' ' + M[2].FilePath);
end;

procedure TestHarvestMergeAndFlag;
var
  A: TArray<THarvestedUnit>;
  B: TArray<THarvestedUnit>;
  R: TArray<THarvestedUnit>;
  H: THarvestedUnit;
begin
  H.UnitName:= 'Forms';
  H.Section := 'interface';
  H.UsedBy  := 'U1';
  A:= [H];
  H.UnitName:= 'forms';
  H.UsedBy  := 'U2';
  B:= [H];
  H.UnitName:= 'DB';
  H.Section := '';
  H.UsedBy  := PASTED_SOURCE;
  B:= B + [H];
  R:= MergeHarvest(A, B);
  Check('harvest.merge.nocase', HarvestNames(R) = 'Forms,DB', HarvestNames(R));
  Check('harvest.merge.first.kept', (Length(R) = 2) and (R[0].UsedBy = 'U1'), HarvestNames(R));
  Check('harvest.indexof.nocase', IndexOfUnit(R, 'db') = 1, IntToStr(IndexOfUnit(R, 'db')));
  Check('harvest.without', HarvestNames(WithoutUnit(R, 'FORMS')) = 'DB', HarvestNames(WithoutUnit(R, 'FORMS')));
  if Length(R) <> 2 then
    Exit;
  Check('harvest.flag.section', HarvestFlagText(R[0]) = 'interface, U1', HarvestFlagText(R[0]));
  Check('harvest.flag.nosection', HarvestFlagText(R[1]) = PASTED_SOURCE, HarvestFlagText(R[1]));
end;

procedure TestProjectSettings;
const
  DPROJ =
    '<Project>' + #13#10 +
    '<PropertyGroup><MainSource>App.dpr</MainSource></PropertyGroup>' + #13#10 +
    '<PropertyGroup Condition="''$(Config)''==''Base'' or ''$(Base)''!=''''">' + #13#10 +
    '  <Base>true</Base>' + #13#10 +
    '</PropertyGroup>' + #13#10 +
    '<PropertyGroup Condition="''$(Base)''!=''''">' + #13#10 +
    '  <DCC_Namespace>System;Data;Vcl;$(DCC_Namespace)</DCC_Namespace>' + #13#10 +
    '  <DCC_UnitSearchPath>..\Common;.\;$(BDS)\lib;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + #13#10 +
    '</PropertyGroup>' + #13#10 +
    '<PropertyGroup Condition="''$(Base_Win32)''!=''''">' + #13#10 +
    '  <DCC_Namespace>Winapi;Bde;$(DCC_Namespace)</DCC_Namespace>' + #13#10 +
    '</PropertyGroup>' + #13#10 +
    '<PropertyGroup Condition="''$(Base_Win64)''!=''''">' + #13#10 +
    '  <DCC_Namespace>Winapi;$(DCC_Namespace)</DCC_Namespace>' + #13#10 +
    '</PropertyGroup>' + #13#10 +
    '<PropertyGroup Condition="''$(Cfg_1)''!=''''">' + #13#10 +
    '  <DCC_UnitSearchPath>C:\CfgOnly;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + #13#10 +
    '</PropertyGroup>' + #13#10 +
    '</Project>';
var
  S: TProjectSettings;
begin
  S:= ReadProjectSettings(DPROJ, 'C:\P\App', cpWin64);
  Check('dproj.mainsource', SameText(S.MainSource, 'C:\P\App\App.dpr'), S.MainSource);
  Check('dproj.projectdir', SameText(S.ProjectDir, 'C:\P\App'), S.ProjectDir);
  Check('dproj.win64.scopes.inherit', string.Join(';', S.Scopes) = 'Winapi;System;Data;Vcl', string.Join(';', S.Scopes));
  Check('dproj.searchpath.relative', SameText(string.Join(';', S.SearchPath), 'C:\P\Common;C:\P\App'), string.Join(';', S.SearchPath));
  Check('dproj.searchpath.macro.skipped', string.Join(';', S.Skipped) = '$(BDS)\lib', string.Join(';', S.Skipped));
  Check('dproj.cfg.groups.ignored', Pos('CFGONLY', UpperCase(string.Join(';', S.SearchPath))) = 0, string.Join(';', S.SearchPath));
  S:= ReadProjectSettings(DPROJ, 'C:\P\App', cpWin32);
  Check('dproj.win32.scopes.bde', string.Join(';', S.Scopes) = 'Winapi;Bde;System;Data;Vcl', string.Join(';', S.Scopes));
  S:= ReadProjectSettings(DPROJ, 'C:\P\App', cpBoth);
  Check('dproj.both.is.win64', string.Join(';', S.Scopes) = 'Winapi;System;Data;Vcl', string.Join(';', S.Scopes));
  S:= ReadProjectSettings('<Project></Project>', 'C:\P\App', cpWin64);
  Check('dproj.no.mainsource', S.MainSource = '', S.MainSource);
end;

procedure TestProjectFileForDb;
begin
  Check('dbproject.drag.folder', SameText(ProjectFileForDb('C:\P\App\_D-RAG\App.sqlite'), 'C:\P\App\App.dproj'), ProjectFileForDb('C:\P\App\_D-RAG\App.sqlite'));
  Check('dbproject.other.folder', ProjectFileForDb('C:\P\App\App.sqlite') = '', ProjectFileForDb('C:\P\App\App.sqlite'));
  Check('dbproject.empty', ProjectFileForDb('') = '', '');
end;

procedure TestHarvestFiles;
var
  Dir : string;
  R   : TArray<THarvestedUnit>;
  Errs: TArray<string>;
  i   : Integer;
begin
  Dir:= TPath.Combine(TPath.GetTempPath, 'convrules-harvest-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'App.dproj'), '<Project><PropertyGroup><MainSource>App.dpr</MainSource></PropertyGroup></Project>', TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(Dir, 'App.dpr'),
      'program App;' + #13#10 + 'uses' + #13#10 + '  Vcl.Forms,' + #13#10 + '  U1 in ''U1.pas'',' + #13#10 + '  Gone in ''Gone.pas'';' + #13#10 + 'begin end.', TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(Dir, 'U1.pas'),
      'unit U1;' + #13#10 + 'interface' + #13#10 + 'uses DB, Forms;' + #13#10 + 'implementation' + #13#10 + 'uses DBTables;' + #13#10 + 'end.', TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(Dir, 'notes.txt'), 'x', TEncoding.ASCII);

    R:= HarvestFiles([TPath.Combine(Dir, 'App.dproj'), TPath.Combine(Dir, 'notes.txt')], Errs);
    Check('harvest.files.dproj.names', HarvestNames(R) = 'Vcl.Forms,U1,Gone,DB,Forms,DBTables', HarvestNames(R));
    Check('harvest.files.dpr.usedby', (Length(R) > 0) and (R[0].UsedBy = 'App') and (R[0].Section = ''), HarvestNames(R));
    i:= IndexOfUnit(R, 'DBTables');
    Check('harvest.files.member.section', (i >= 0) and (R[i].Section = 'implementation') and (R[i].UsedBy = 'U1'), IntToStr(i));
    Check('harvest.files.member.gone.reported', (Length(Errs) = 2) and (Pos('Gone', Errs[0]) > 0), string.Join(' | ', Errs));
    Check('harvest.files.other.ext.reported', (Length(Errs) = 2) and (Pos('notes.txt', Errs[1]) > 0), string.Join(' | ', Errs));

    R:= HarvestFiles([TPath.Combine(Dir, 'U1.pas')], Errs);
    Check('harvest.files.pas', (HarvestNames(R) = 'DB,Forms,DBTables') and (Length(Errs) = 0), HarvestNames(R));

    R:= HarvestFiles([TPath.Combine(Dir, 'NoSuch.pas')], Errs);
    Check('harvest.files.unreadable.reported', (Length(R) = 0) and (Length(Errs) = 1), string.Join(' | ', Errs));
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

function FixtureSettings(APlatform: TConvPlatform): TProjectSettings;
begin
  Result.ProjectDir:= 'C:\P\App';
  Result.MainSource:= 'C:\P\App\App.dpr';
  Result.SearchPath:= ['C:\P\Common'];
  if APlatform = cpWin32 then
    Result.Scopes:= ['Winapi', 'Bde', 'System', 'Data', 'Vcl']
  else
    Result.Scopes:= ['Winapi', 'System', 'Data', 'Vcl'];
  Result.Skipped:= nil;
end;

procedure TestUnitResolver;
var
  Files  : TArray<string>;
  Probe  : TFileProbe;
  Members: TArray<TDprMember>;
  M      : TDprMember;
  Plain  : TDprMember;
  Lib    : TArray<string>;
  R      : TDestinationResolver;
  S      : TUnitStatus;
begin
  Files:= ['C:\P\App\Local.pas', 'C:\P\Common\Shared.dcu'];
  Probe:= function(const APath: string): Boolean
    begin
      Result:= IndexText(APath, Files) >= 0;
    end;
  M.UnitName:= 'DMain';
  M.FilePath:= 'C:\P\App\DMain.pas';
  Members:= [M];
  Lib:= ['Vcl.Forms', 'Data.DB', 'System.SysUtils', 'Bde.DBTables', 'Local', 'Winapi.Foo', 'System.Foo'];

  R:= TDestinationResolver.Create(FixtureSettings(cpWin64), Members, Lib, Probe);
  try
    S:= R.Classify('DMain');
    Check('resolver.member', (S.Kind = uskProject) and SameText(S.Resolved, 'C:\P\App\DMain.pas'), StatusText(S) + ' ' + S.Resolved);
    S:= R.Classify('Local');
    Check('resolver.project.before.library', (S.Kind = uskProject) and SameText(S.Resolved, 'C:\P\App\Local.pas'), StatusText(S));
    S:= R.Classify('Shared');
    Check('resolver.searchpath.dcu', S.Kind = uskProject, StatusText(S));
    S:= R.Classify('Vcl.Forms');
    Check('resolver.library', S.Kind = uskLibrary, StatusText(S));
    S:= R.Classify('Forms');
    Check('resolver.viascope', (S.Kind = uskViaScope) and (S.Resolved = 'Vcl.Forms'), StatusText(S));
    Check('resolver.viascope.text', StatusText(S) = 'via scope -> Vcl.Forms', StatusText(S));
    S:= R.Classify('forms');
    Check('resolver.nocase', (S.Kind = uskViaScope) and SameText(S.Resolved, 'Vcl.Forms'), StatusText(S));
    S:= R.Classify('Foo');
    Check('resolver.scope.order', S.Resolved = 'Winapi.Foo', S.Resolved);
    S:= R.Classify('DBTables');
    Check('resolver.win64.dbtables.missing', S.Kind = uskMissing, StatusText(S));
    Check('resolver.missing.text', StatusText(S) = STATUS_MISSING_TEXT, StatusText(S));
  finally
    R.Free;
  end;

  R:= TDestinationResolver.Create(FixtureSettings(cpWin32), Members, Lib, Probe);
  try
    S:= R.Classify('DBTables');
    Check('resolver.win32.dbtables.viascope', (S.Kind = uskViaScope) and (S.Resolved = 'Bde.DBTables'), StatusText(S));
  finally
    R.Free;
  end;

  R:= TDestinationResolver.Create(FixtureSettings(cpWin64), nil, nil, Probe);
  try
    S:= R.Classify('Vcl.Forms');
    Check('resolver.empty.library.missing', S.Kind = uskMissing, StatusText(S));
  finally
    R.Free;
  end;

  Plain.UnitName:= 'Vcl.Forms';
  Plain.FilePath:= '';
  R:= TDestinationResolver.Create(FixtureSettings(cpWin64), [M, Plain], Lib, Probe);
  try
    S:= R.Classify('Vcl.Forms');
    Check('resolver.plain.dpr.entry.not.member', S.Kind = uskLibrary, StatusText(S));
  finally
    R.Free;
  end;

  Check('status.unknown.text', StatusText(UnknownStatus) = 'no destination', StatusText(UnknownStatus));
  S.Kind:= uskLibrary;
  Check('shouldadd.findmissing.library', not ShouldAdd(S, True, True), '');
  Check('shouldadd.all.library', ShouldAdd(S, False, True), '');
  S.Kind:= uskViaScope;
  Check('shouldadd.unqualified.on', ShouldAdd(S, True, True), '');
  Check('shouldadd.unqualified.off', not ShouldAdd(S, True, False), '');
  S.Kind:= uskMissing;
  Check('shouldadd.missing', ShouldAdd(S, True, False), '');
  Check('shouldadd.unknown', ShouldAdd(UnknownStatus, True, False), '');
end;

procedure TestUnitResolverDisk;
var
  Dir: string;
  St : TProjectSettings;
  R  : TDestinationResolver;
begin
  Dir:= TPath.Combine(TPath.GetTempPath, 'convrules-resolver-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'OnDisk.pas'), 'unit OnDisk; end.', TEncoding.ASCII);
    St.ProjectDir:= Dir;
    St.MainSource:= '';
    St.SearchPath:= [TPath.Combine(Dir, 'NoSuchFolder')];
    St.Scopes    := nil;
    St.Skipped   := nil;
    R:= TDestinationResolver.Create(St, nil, nil, nil);
    try
      Check('resolver.disk.found', R.Classify('ondisk').Kind = uskProject, StatusText(R.Classify('ondisk')));
      Check('resolver.disk.missing', R.Classify('NotThere').Kind = uskMissing, StatusText(R.Classify('NotThere')));
    finally
      R.Free;
    end;
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

{ ConvRules.UnitMask: session-only masks over harvested rows, and the display order. }
function MaskRow(const AName: string; AKind: TUnitStatusKind; const AResolved: string): TUnitRow;
begin
  Result.Harvest.UnitName:= AName;
  Result.Harvest.Section := '';
  Result.Harvest.UsedBy  := 'U1';
  Result.Status.Kind     := AKind;
  Result.Status.Resolved := AResolved;
end;

function RowNames(const ARows: TArray<TUnitRow>): string;
var
  Names: TArray<string>;
  i    : Integer;
begin
  SetLength(Names, Length(ARows));
  for i:= 0 to High(ARows) do
    Names[i]:= ARows[i].Harvest.UnitName;
  Result:= string.Join(',', Names);
end;

procedure TestUnitMask;
var
  Rows  : TArray<TUnitRow>;
  M     : TUnitMask;
  Hidden: Integer;
  Shown : TArray<TUnitRow>;
begin
  Rows:= [MaskRow('Vcl.Forms', uskLibrary, ''), MaskRow('Local', uskProject, 'C:\P\Common\Local.pas'),
    MaskRow('Forms', uskViaScope, 'Vcl.Forms'), MaskRow('DBTables', uskMissing, ''), MaskRow('cxGrid', uskMissing, '')];
  M:= Default(TUnitMask);
  Shown:= ApplyMask(Rows, M, Hidden);
  Check('mask.none', (Hidden = 0) and (Length(Shown) = 5), IntToStr(Hidden));
  M.HideLibrary:= True;
  Check('mask.library', RowNames(ApplyMask(Rows, M, Hidden)) = 'Local,Forms,DBTables,cxGrid', RowNames(ApplyMask(Rows, M, Hidden)));
  M:= Default(TUnitMask);
  M.HideProject:= True;
  Check('mask.project', RowNames(ApplyMask(Rows, M, Hidden)) = 'Vcl.Forms,Forms,DBTables,cxGrid', RowNames(ApplyMask(Rows, M, Hidden)));
  M:= Default(TUnitMask);
  M.HideQualified:= True;
  Check('mask.qualified', RowNames(ApplyMask(Rows, M, Hidden)) = 'Local,Forms,DBTables,cxGrid', RowNames(ApplyMask(Rows, M, Hidden)));
  M:= Default(TUnitMask);
  M.Folder:= 'C:\P\Common';
  Shown:= ApplyMask(Rows, M, Hidden);
  Check('mask.folder', (RowNames(Shown) = 'Vcl.Forms,Forms,DBTables,cxGrid') and (Hidden = 1), RowNames(Shown));
  M.Folder:= 'C:\P\Com';
  Check('mask.folder.prefix.trap', Length(ApplyMask(Rows, M, Hidden)) = 5, IntToStr(Hidden));
  M:= Default(TUnitMask);
  M.NameMask:= 'cx*';
  M.NameMode:= usmWildcard;
  Check('mask.name.wildcard', RowNames(ApplyMask(Rows, M, Hidden)) = 'Vcl.Forms,Local,Forms,DBTables', RowNames(ApplyMask(Rows, M, Hidden)));
  M.NameMask:= '^db';
  M.NameMode:= usmRegex;
  Check('mask.name.regex', RowNames(ApplyMask(Rows, M, Hidden)) = 'Vcl.Forms,Local,Forms,cxGrid', RowNames(ApplyMask(Rows, M, Hidden)));
  M.NameMask:= '[';
  Check('mask.name.invalid.hides.nothing', Length(ApplyMask(Rows, M, Hidden)) = 5, IntToStr(Hidden));
  Check('sort.missing.first', RowNames(SortForDisplay(Rows)) = 'DBTables,cxGrid,Forms,Local,Vcl.Forms', RowNames(SortForDisplay(Rows)));
end;

{ ConvRules.UnitMask.FilterHarvestRows: the check boxes, the rules and the masks
  together, and the three buckets every harvested row lands in exactly once. }
procedure TestFilterHarvestRows;
const
  TOTAL = 7;
var
  Rows   : TArray<TUnitRow>;
  M      : TUnitMask;
  V      : THarvestView;
  HasRule: THasRuleFunc;
begin
  Rows:= [MaskRow('NoDest', uskUnknown, ''), MaskRow('Local', uskProject, 'C:\P\Local.pas'),
    MaskRow('Vcl.Forms', uskLibrary, ''), MaskRow('Forms', uskViaScope, 'Vcl.Forms'),
    MaskRow('DBTables', uskMissing, ''), MaskRow('Ruled', uskMissing, ''), MaskRow('cxGrid', uskMissing, '')];
  HasRule:= function(const AUnit: string): Boolean
    begin
      Result:= SameText(AUnit, 'ruled');
    end;
  M:= Default(TUnitMask);
  M.NameMask:= 'cx*';
  M.NameMode:= usmWildcard;

  V:= FilterHarvestRows(Rows, True, True, HasRule, M);
  Check('view.missing.shown', RowNames(V.Shown) = 'DBTables,Forms,NoDest', RowNames(V.Shown));
  Check('view.missing.counts', (V.Masked = 1) and (V.Filtered = 3), Format('masked=%d filtered=%d', [V.Masked, V.Filtered]));
  Check('view.missing.buckets.sum', Length(V.Shown) + V.Masked + V.Filtered = TOTAL, IntToStr(Length(V.Shown) + V.Masked + V.Filtered));

  V:= FilterHarvestRows(Rows, False, True, HasRule, M);
  Check('view.all.shown', RowNames(V.Shown) = 'DBTables,Forms,NoDest,Local,Vcl.Forms', RowNames(V.Shown));
  Check('view.all.counts', (V.Masked = 1) and (V.Filtered = 1), Format('masked=%d filtered=%d', [V.Masked, V.Filtered]));
  Check('view.all.buckets.sum', Length(V.Shown) + V.Masked + V.Filtered = TOTAL, IntToStr(Length(V.Shown) + V.Masked + V.Filtered));

  V:= FilterHarvestRows(Rows, True, False, nil, Default(TUnitMask));
  Check('view.noscope.norule.shown', RowNames(V.Shown) = 'DBTables,Ruled,cxGrid,NoDest', RowNames(V.Shown));
  Check('view.noscope.norule.counts', (V.Masked = 0) and (V.Filtered = 3), Format('masked=%d filtered=%d', [V.Masked, V.Filtered]));
  Check('view.noscope.buckets.sum', Length(V.Shown) + V.Masked + V.Filtered = TOTAL, IntToStr(Length(V.Shown) + V.Masked + V.Filtered));

  Check('view.empty', (Length(FilterHarvestRows(nil, True, True, HasRule, M).Shown) = 0), '');

  // Ruling R16: a candidate yields to a harvested twin only when that twin is LISTED.
  Check('indexofrow.nocase', IndexOfRow(Rows, 'forms') = 3, IntToStr(IndexOfRow(Rows, 'forms')));
  Check('indexofrow.absent', IndexOfRow(Rows, 'Nope') = -1, IntToStr(IndexOfRow(Rows, 'Nope')));
end;

{ ConvRules.UsesHarvest.DestPlatformLabel: the Destination row's platform label (ruling R17). }
procedure TestDestPlatformLabel;
begin
  Check('destplatform.win32', DestPlatformLabel(cpWin32) = 'Platform: Win32', DestPlatformLabel(cpWin32));
  Check('destplatform.win64', DestPlatformLabel(cpWin64) = 'Platform: Win64', DestPlatformLabel(cpWin64));
  Check('destplatform.both', DestPlatformLabel(cpBoth) = 'Platform: Both -> Win64', DestPlatformLabel(cpBoth));
end;

{ Occurrences of ASub in S (non-overlapping). }
function Occurrences(const ASub, S: string): Integer;
var
  P: Integer;
begin
  Result:= 0;
  P:= Pos(ASub, S);
  while P > 0 do
  begin
    Inc(Result);
    P:= PosEx(ASub, S, P + Length(ASub));
  end;
end;

procedure TestBookDepth;
const
  CRLF          = #13#10;
  BOOK_NO_DEPTH = '// header' + CRLF + '#unuse OldU' + CRLF + '#convert TA -> TB' + CRLF + '#link Caption <- Caption' + CRLF;
  DEPTH_LOW     = 2;
  DEPTH_MID     = 3;
  DEPTH_FOUR    = 4;
  DEPTH_HIGH    = 7;
  DEPTH_OVER    = 11;
var
  B     : TRuleBook;
  N     : TRuleNode;
  S     : string;
  Hdr   : TRuleNode;
  Raised: Boolean;
begin
  B:= TRuleBook.Create;
  try
    N:= B.ParseLine('#depth 3');
    try
      Check('depth.parse.valid', (N.Kind = rnkDepth) and N.DepthValid and (N.DepthValue = DEPTH_MID));
    finally
      N.Free;
    end;
    // Directive names are case-insensitive (ParseLine lower-cases Dir). A TRAILING
    // comment is NOT stripped by ParseLine (StripComment only detects whole-line
    // comments), so '#depth 3 // x' is invalid -- deliberately not tested as valid.
    N:= B.ParseLine('#DEPTH 3');
    try
      Check('depth.parse.case', (N.Kind = rnkDepth) and N.DepthValid and (N.DepthValue = DEPTH_MID));
    finally
      N.Free;
    end;
    N:= B.ParseLine('#depth x');
    try
      Check('depth.parse.nonint', (N.Kind = rnkDepth) and not N.DepthValid);
    finally
      N.Free;
    end;
    N:= B.ParseLine('#depth 11');
    try
      Check('depth.parse.range.high', (N.Kind = rnkDepth) and not N.DepthValid);
    finally
      N.Free;
    end;
    N:= B.ParseLine('#depth 0');
    try
      Check('depth.parse.range.low', (N.Kind = rnkDepth) and not N.DepthValid);
    finally
      N.Free;
    end;
    // The engine accepts DECIMAL DIGITS only (IsDecimalDigits): a sign, a '$' hex
    // or a '0x' prefix is an engine error even where TryStrToInt would accept it.
    var LDigitsOnly: Boolean:= True;
    for var LBody: string in ['#depth +3', '#depth $A', '#depth 0x0A'] do
    begin
      N:= B.ParseLine(LBody);
      try
        LDigitsOnly:= LDigitsOnly and (N.Kind = rnkDepth) and not N.DepthValid;
      finally
        N.Free;
      end;
    end;
    Check('depth.parse.digits.only', LDigitsOnly);
    N:= B.ParseLine('#depth 03');
    try
      Check('depth.parse.digits.leading.zero', N.DepthValid and (N.DepthValue = DEPTH_MID));
    finally
      N.Free;
    end;

    B.LoadFromString(BOOK_NO_DEPTH);
    Check('depth.absent.default', (B.Depth = BOOK_DEPTH_DEFAULT) and (B.DepthState = bdsAbsent));
    Check('depth.absent.roundtrip', B.Snapshot = BOOK_NO_DEPTH, B.Snapshot);
    // Owner decision 1 (2026-10-04): an explicit pick of the DEFAULT on a book with
    // no #depth is recorded; only a book that already says exactly that skips it.
    Check('depth.pick.default.on.absent.writes', B.DepthPickWrites(BOOK_DEPTH_DEFAULT));

    Hdr:= B.Nodes[B.ConvertHeaders[0]];
    B.SetDepth(DEPTH_MID);
    S:= B.Snapshot;
    Check('depth.set.inserts', (B.Depth = DEPTH_MID) and (B.DepthState = bdsValid) and (Pos('#depth 3', S) > 0) and (Pos('#depth 3', S) < Pos('#convert', S)), S);
    Check('depth.set.header.found.by.node', B.Nodes.IndexOf(Hdr) = B.ConvertHeaders[0]);

    B.SetDepth(DEPTH_HIGH);
    S:= B.Snapshot;
    Check('depth.set.updates', (B.Depth = DEPTH_HIGH) and (Occurrences('#depth', S) = 1) and (Pos('#depth 7', S) > 0), S);

    B.LoadFromString('#depth 4' + CRLF + BOOK_NO_DEPTH);
    Check('depth.load.valid', (B.Depth = DEPTH_FOUR) and (B.DepthState = bdsValid));
    Check('depth.pick.same.on.valid.no.write', (not B.DepthPickWrites(DEPTH_FOUR)) and B.DepthPickWrites(DEPTH_HIGH));
    Check('depth.roundtrip.verbatim', B.Snapshot = '#depth 4' + CRLF + BOOK_NO_DEPTH, B.Snapshot);

    B.LoadFromString('#depth deep' + CRLF + BOOK_NO_DEPTH);
    Check('depth.invalid.default', (B.Depth = BOOK_DEPTH_DEFAULT) and (B.DepthState = bdsInvalid));
    Check('depth.pick.default.on.invalid.writes', B.DepthPickWrites(BOOK_DEPTH_DEFAULT));
    Check('depth.invalid.verbatim', Pos('#depth deep', B.Snapshot) = 1, B.Snapshot);

    B.LoadFromString('#depth 2' + CRLF + '#depth 9' + CRLF + BOOK_NO_DEPTH);
    Check('depth.duplicate.first.wins', (B.Depth = DEPTH_LOW) and (B.DepthState = bdsDuplicate));
    Check('depth.pick.same.on.duplicate.writes', B.DepthPickWrites(DEPTH_LOW));
    // An explicit depth change REPAIRS a duplicate (ruling R11): the engine rejects a
    // book with two #depth lines, so the first is set and every other one deleted.
    Hdr:= B.Nodes[B.ConvertHeaders[0]];
    B.SetDepth(DEPTH_HIGH);
    S:= B.Snapshot;
    Check('depth.set.duplicate.repairs', (B.Depth = DEPTH_HIGH) and (B.DepthState = bdsValid) and (Pos('#depth 7', S) = 1) and (Occurrences('#depth', S) = 1), S);
    Check('depth.set.duplicate.header.found.by.node', B.Nodes.IndexOf(Hdr) = B.ConvertHeaders[0]);

    // First line invalid, second valid: the engine still rejects the book, so the
    // state is bdsDuplicate (it wins over bdsInvalid) and no book value is claimed.
    B.LoadFromString('#depth x' + CRLF + '#depth 4' + CRLF + BOOK_NO_DEPTH);
    Check('depth.duplicate.first.invalid', (B.DepthState = bdsDuplicate) and (B.Depth = BOOK_DEPTH_DEFAULT));

    Raised:= False;
    try
      B.SetDepth(DEPTH_OVER);
    except  // dl:ok try-except-swallowed@af95 -- REVIEWED 2026-09-30 not swallowed: the catch sets Raised and the next Check fails when it is not set
      on EArgumentOutOfRangeException do
        Raised:= True;
    end;
    Check('depth.set.range.raises', Raised);

    B.LoadFromString('#unuse OldU' + CRLF);
    B.SetDepth(DEPTH_LOW);
    Check('depth.set.no.convert', Pos('#depth 2', B.Snapshot) > 0, B.Snapshot);
  finally
    B.Free;
  end;
end;

{ A From-only #convert (a From class, no To yet) must survive load, save + reload
  and a dirty re-emit, so a conversion can be authored in two sittings. The block
  carries an #ignore so Snapshot (which drops a block that maps nothing) keeps it. }
procedure TestConvertFromOnly;
const
  CRLF      = #13#10;
  FROM_TYPE = 'TNoSuchClassXyz';
  UNIT_NAME = 'NoSuchUnitXyz';

  function HeaderText(const ABook: TRuleBook): string;
  var
    LHdr: TRuleNode;
  begin
    if Length(ABook.ConvertHeaders) = 0 then
      Exit('<no #convert header>');
    LHdr:= ABook.Nodes[ABook.ConvertHeaders[0]];
    Result:= Format('from=[%s] to=[%s] units=[%s]', [LHdr.FromType, LHdr.ToType, LHdr.Units]);
  end;

  function RoundTrips(const AHeaderLine, AUnits: string; out ADetail: string): Boolean;
  var
    LBook : TRuleBook;
    LOther: TRuleBook;
    LWant : string;
  begin
    LWant:= Format('from=[%s] to=[] units=[%s]', [FROM_TYPE, AUnits]);
    LBook := TRuleBook.Create;
    LOther:= TRuleBook.Create;
    try
      LBook.LoadFromString(AHeaderLine + CRLF + '#ignore Tag' + CRLF);
      ADetail:= 'load ' + HeaderText(LBook);
      Result:= HeaderText(LBook) = LWant;

      LOther.LoadFromString(LBook.Snapshot);
      ADetail:= ADetail + '; reload ' + HeaderText(LOther);
      Result:= Result and (HeaderText(LOther) = LWant);

      // A dirty node re-emits through TRuleNode.Emit, not Raw.
      LBook.Nodes[LBook.ConvertHeaders[0]].Dirty:= True;
      LOther.LoadFromString(LBook.Snapshot);
      ADetail:= ADetail + '; dirty reload ' + HeaderText(LOther);
      Result:= Result and (HeaderText(LOther) = LWant);
    finally
      LOther.Free;
      LBook.Free;
    end; // try
  end;

var
  Detail: string;
begin
  Check('model.convert.from.only.roundtrip', RoundTrips('#convert ' + FROM_TYPE + ' -> ', '', Detail), Detail);
  Check('model.convert.from.only.with.unit.roundtrip', RoundTrips('#convert ' + FROM_TYPE + ' -> , ' + UNIT_NAME, UNIT_NAME, Detail), Detail);
end;

procedure TestEngineProgress;
const
  // The engine's real shape: elapsed_s is FormatFloat('0.0'), the rest are integers.
  LINE_A   = '{"progress":{"elapsed_s":15.0,"verb":"proptree","class":"FireDAC.Comp.Client.TFDQuery","depth":3,"max_depth":5,"classes_done":41,"classes_queued":28,"nodes":9120}}';
  ELAPSED  = 15;
  ELAPSED_TRUNC = 12;
  DEPTH    = 3;
  MAXDEPTH = 5;
  DONE     = 41;
  QUEUED   = 28;
  NODES    = 9120;
  TWO      = 2;
  COULD_NOT_START = -1; // RunCaptureStreaming: the process was never started
  MANY_LINES = 10000;
  LINE_WRONG_TYPES = '{"progress":{"depth":"x","verb":7,"elapsed_s":null,"class":[]}}';
var
  Sp      : TLineSplitter;
  Lines   : string;
  P       : TEngineProgress;
  Tok     : TCancelToken;
  Sink    : TProc<string>;
  Parsed  : Boolean;
  Names   : Boolean;
  Counts  : Boolean;
  Defaults: Boolean;
  Raised  : string;
  LCount  : Integer;
  LFirst  : string;
  LLast   : string;
  LChunk  : TStringBuilder;
begin
  Lines:= '';
  Sink:= procedure(ALine: string)
    begin
      Lines:= Lines + '[' + ALine + ']';
    end;
  Sp:= TLineSplitter.Create;
  try
    Sp.Feed('ab', Sink);
    Check('split.partial.held', Lines = '', Lines);
    Sp.Feed('c'#13#10'de', Sink);
    Check('split.crlf', Lines = '[abc]', Lines);
    Sp.Feed(#10#10'f', Sink);
    Check('split.lf.and.empty', Lines = '[abc][de][]', Lines);
    Sp.Flush(Sink);
    Check('split.flush.tail', Lines = '[abc][de][][f]', Lines);
    Sp.Flush(Sink);
    Check('split.flush.twice.noop', Lines = '[abc][de][][f]', Lines);
  finally
    Sp.Free;
  end;

  Lines:= '';
  Sp:= TLineSplitter.Create;
  try
    Sp.Feed('abc'#13, Sink);
    Sp.Feed(#10, Sink);
    Sp.Flush(Sink);
    Check('split.crlf.across.feeds', Lines = '[abc]', Lines);
  finally
    Sp.Free;
  end;

  // One chunk holding many lines: every line comes back, in order.
  LCount:= 0;
  LChunk:= TStringBuilder.Create;
  try
    for var LIdx: Integer:= 0 to MANY_LINES - 1 do
      LChunk.Append('line').Append(LIdx).Append(#13#10);
    Lines:= LChunk.ToString;
  finally
    LChunk.Free;
  end;
  Sp:= TLineSplitter.Create;
  try
    Sp.Feed(Lines,
      procedure(ALine: string)
      begin
        if LCount = 0 then
          LFirst:= ALine;
        LLast:= ALine;
        Inc(LCount);
      end);
    Check('split.many.lines.one.chunk', (LCount = MANY_LINES) and (LFirst = 'line0') and (LLast = 'line' + IntToStr(MANY_LINES - 1)),
      Format('count=%d first=[%s] last=[%s]', [LCount, LFirst, LLast]));
  finally
    Sp.Free;
  end;

  Parsed:= TryParseProgressLine(LINE_A, P);
  Names:= (P.ElapsedS = ELAPSED) and (P.Verb = 'proptree') and (P.QName = 'FireDAC.Comp.Client.TFDQuery');
  Counts:= (P.Depth = DEPTH) and (P.MaxDepth = MAXDEPTH) and (P.ClassesDone = DONE)
    and (P.ClassesQueued = QUEUED) and (P.Nodes = NODES);
  Check('progress.parse.accept', Parsed and Names and Counts);
  Check('progress.parse.padded', TryParseProgressLine('  ' + LINE_A + '  ', P));
  TryParseProgressLine('{"progress":{"elapsed_s":12.3,"depth":1}}', P);
  Check('progress.elapsed.decimal', P.ElapsedS = ELAPSED_TRUNC, IntToStr(P.ElapsedS));
  TryParseProgressLine('{"progress":{"elapsed_s":0.0,"depth":1}}', P);
  Check('progress.elapsed.zero', (P.ElapsedS = 0) and (P.Depth = 1), IntToStr(P.ElapsedS));
  Check('progress.reject.text', not TryParseProgressLine('(loaded defaults from C:\x.json)', P));
  Check('progress.reject.fatal', not TryParseProgressLine('FATAL: Exception: Unknown argument: --depth', P));
  Check('progress.reject.other.json', not TryParseProgressLine('{"schema":"apply/1","ok":true}', P));
  Check('progress.reject.extra.key', not TryParseProgressLine('{"progress":{"depth":1},"x":1}', P));
  Check('progress.reject.empty', not TryParseProgressLine('', P));
  Check('progress.reject.broken.json', not TryParseProgressLine('{"progress":{"depth":', P));

  Raised:= '';
  Parsed:= False;
  try
    Parsed:= TryParseProgressLine(LINE_WRONG_TYPES, P);
  except  // dl:ok try-except-swallowed@aa6b -- REVIEWED 2026-09-30 not swallowed: the text lands in Raised and the progress.wrong.type.no.raise Check fails on it
    on E: Exception do
      Raised:= E.ClassName + ': ' + E.Message;
  end;
  Defaults:= (P.Depth = 0) and (P.Verb = '') and (P.ElapsedS = 0) and (P.QName = '');
  Check('progress.wrong.type.no.raise', (Raised = '') and Parsed and Defaults,
    Format('raised=[%s] parsed=%s depth=%d verb=[%s] elapsed=%d class=[%s]',
      [Raised, BoolToStr(Parsed, True), P.Depth, P.Verb, P.ElapsedS, P.QName]));

  TryParseProgressLine(LINE_A, P);
  Check('progress.text', ProgressText(P) = 'TFDQuery -- depth 3 of 5 -- 41 done, 28 queued -- 15 s', ProgressText(P));
  P.QName:= '';
  Check('progress.text.no.class', ProgressText(P) = 'proptree -- depth 3 of 5 -- 41 done, 28 queued -- 15 s', ProgressText(P));

  Tok:= TCancelToken.Create;
  try
    Check('cancel.initially.clear', not Tok.IsCancelled);
    Tok.Cancel;
    Tok.Cancel;
    Check('cancel.set.idempotent', Tok.IsCancelled);
  finally
    Tok.Free;
  end;
  // Editor-side outcomes are NEGATIVE: never the engine's exit codes 0..3 (3 = FATAL)
  // and never -1 (could not start).
  Check('exit.codes.distinct', (ENGINE_OUTCOME_TIMEOUT < COULD_NOT_START) and (ENGINE_OUTCOME_CANCELLED < COULD_NOT_START)
    and (ENGINE_OUTCOME_TIMEOUT <> ENGINE_OUTCOME_CANCELLED) and (PROGRESS_INTERVAL_S = TWO));
end;

procedure TestEngineArgsAndCaps;
const
  INFO = '(loaded defaults from C:\x.json)' + #13#10
    + '{"version":"1.20.6-alpha","capabilities":{"apply_unit_rules":true,"book_depth":true,"progress_lines":false,"lazy_validate":"true"}}' + #13#10;
  DEPTH_THREE = 3;
var
  Caps: TArray<string>;
begin
  Check('args.none', DepthArgs(0, False) = '');
  Check('args.depth', DepthArgs(DEPTH_THREE, False) = ' --depth 3', DepthArgs(DEPTH_THREE, False));
  Check('args.progress', DepthArgs(0, True) = ' --progress-interval 2', DepthArgs(0, True));
  Check('args.both', DepthArgs(DEPTH_THREE, True) = ' --depth 3 --progress-interval 2', DepthArgs(DEPTH_THREE, True));
  Caps:= ParseCapabilityNames(INFO);
  Check('caps.true.only', (Length(Caps) = 2) and MatchText('apply_unit_rules', Caps) and MatchText('book_depth', Caps), string.Join(',', Caps));
  Check('caps.string.true.is.not.true', not MatchText('lazy_validate', Caps));
  Check('caps.garbage', Length(ParseCapabilityNames('FATAL: no')) = 0);
  Check('caps.no.block', Length(ParseCapabilityNames('{"version":"1"}')) = 0);
  Check('caps.consts', (CAPABILITY_BOOK_DEPTH = 'book_depth') and (CAPABILITY_PROGRESS_LINES = 'progress_lines')
    and (CAPABILITY_INHERITED_INSTANCES = 'inherited_instances'));
end;

{ CapabilityNames is bounded by its own InfoTimeoutMs, not ENGINE_TIMEOUT_MS: a
  stand-in engine (a .cmd that sleeps) must give [] within the bound. A second
  stand-in that answers proves the .cmd mechanism reaches CapabilityNames at all --
  without it, a stand-in that never started would pass the timeout check. }
procedure TestCapabilityProbeTimeout;
const
  BOUND_MS  = 1500;
  MARGIN_MS = 2500;  // the bound plus process start-up; the stand-in sleeps ~6 s
  SLEEP_CMD = '@ping -n 7 127.0.0.1 >nul' + #13#10;
  ANSWER_CMD = '@echo {"capabilities":{"book_depth":true}}' + #13#10;
var
  Dir    : string;
  Eng    : TEngineAdapter;
  Caps   : TArray<string>;
  TStart : UInt64;
  Elapsed: UInt64;
begin
  Dir:= TPath.Combine(TPath.GetTempPath, 'caps-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'answer.cmd'), ANSWER_CMD, TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(Dir, 'sleep.cmd'), SLEEP_CMD, TEncoding.ASCII);

    Eng:= TEngineAdapter.Create(TPath.Combine(Dir, 'answer.cmd'), []);
    try
      Check('caps.info.timeout.default', Eng.InfoTimeoutMs = INFO_TIMEOUT_MS, IntToStr(Eng.InfoTimeoutMs));
      Caps:= Eng.CapabilityNames;
      Check('caps.standin.answers', MatchText(CAPABILITY_BOOK_DEPTH, Caps), string.Join(',', Caps));
    finally
      Eng.Free;
    end;

    Eng:= TEngineAdapter.Create(TPath.Combine(Dir, 'sleep.cmd'), []);
    try
      Eng.InfoTimeoutMs:= BOUND_MS;
      TStart := GetTickCount64;
      Caps   := Eng.CapabilityNames;
      Elapsed:= GetTickCount64 - TStart;
      Check('caps.timeout.is.none', (Length(Caps) = 0) and (Elapsed < BOUND_MS + MARGIN_MS),
        Format('%d caps in %d ms', [Length(Caps), Elapsed]));
    finally
      Eng.Free;
    end;
  finally
    TDirectory.Delete(Dir, True);
  end; // try
end;

{ RunCaptureStreaming against a pwsh stand-in for the engine. SKIPs when pwsh.exe
  is not on PATH (it is on the dev box: PowerShell 7). }
procedure TestRunCaptureStreaming;
const
  SCRIPT =
      '[Console]::Error.WriteLine(''{"progress":{"elapsed_s":1,"verb":"proptree","class":"A.TX","depth":1,"max_depth":5,"classes_done":1,"classes_queued":2,"nodes":10}}'')' + #13#10
    + '[Console]::Error.WriteLine(''(loaded defaults from test)'')' + #13#10
    + '[Console]::Out.WriteLine(''{"qname":"A.TX"}'')' + #13#10
    + '[Console]::Error.WriteLine(''{"progress":{"elapsed_s":2,"verb":"proptree","class":"A.TX","depth":2,"max_depth":5,"classes_done":3,"classes_queued":0,"nodes":20}}'')' + #13#10
    + 'if ($args[0] -eq ''sleep'') { Start-Sleep -Seconds 4; Set-Content -LiteralPath $args[1] -Value survived }' + #13#10
    + 'if ($args[0] -eq ''fatal'') { [Console]::Error.WriteLine(''FATAL: cannot open the index''); exit 3 }' + #13#10
    + 'exit 0' + #13#10;
  LONG_MS       = 60000;
  SHORT_MS      = 1500;
  CANCEL_MAX_MS = 1500;
  SURVIVE_WAIT  = 6000;
  TWO           = 2;
  ENGINE_FATAL  = 3; // the engine's own FATAL exit code (unknown flag, DB cannot be opened)
var
  Pwsh, Dir, Ps1, Marker, Output: string;
  Eng  : TEngineAdapter;
  Seen : Integer;
  Last : TEngineProgress;
  Tok  : TCancelToken;
  Code : Integer;
  TCancel, TBack: UInt64;
begin
  Pwsh:= FileSearch('pwsh.exe', GetEnvironmentVariable('PATH'));
  if Pwsh = '' then
  begin
    Skip('stream.*', 'pwsh.exe not on PATH');
    Exit;
  end;
  Dir:= TPath.Combine(TPath.GetTempPath, 'stream-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  Eng:= TEngineAdapter.Create(Pwsh, []);
  try
    Ps1:= TPath.Combine(Dir, 'fake.ps1');
    TFile.WriteAllText(Ps1, SCRIPT, TEncoding.ASCII);
    Marker:= TPath.Combine(Dir, 'survived.txt');

    Seen:= 0;
    Code:= Eng.RunCaptureStreaming(Format('-NoProfile -NonInteractive -File "%s"', [Ps1]), LONG_MS,
      procedure(const AProgress: TEngineProgress)
      begin
        Inc(Seen);
        Last:= AProgress;
      end, nil, Output);
    Check('stream.exit0', Code = 0, IntToStr(Code) + ' ' + Output);
    Check('stream.stdout.kept', Pos('{"qname":"A.TX"}', Output) > 0, Output);
    Check('stream.stderr.kept', Pos('(loaded defaults from test)', Output) > 0, Output);
    Check('stream.progress.not.in.output', Pos('"progress"', Output) = 0, Output);
    Check('stream.progress.seen', (Seen = TWO) and (Last.Depth = TWO) and (Last.QName = 'A.TX'), IntToStr(Seen));

    // The engine's real exit 3 (FATAL) must come back AS 3, with its stderr text --
    // never confused with the editor's own timeout outcome.
    Code:= Eng.RunCaptureStreaming(Format('-NoProfile -NonInteractive -File "%s" fatal', [Ps1]), LONG_MS, nil, nil, Output);
    Check('stream.exit3.not.timeout', (Code = ENGINE_FATAL) and (Code <> ENGINE_OUTCOME_TIMEOUT) and (Pos('[timeout', Output) = 0), IntToStr(Code) + ' ' + Output);
    Check('stream.exit3.fatal.kept', Pos('FATAL: cannot open the index', Output) > 0, Output);

    Tok:= TCancelToken.Create;
    try
      TCancel:= 0;
      Code:= Eng.RunCaptureStreaming(Format('-NoProfile -NonInteractive -File "%s" sleep "%s"', [Ps1, Marker]), LONG_MS,
        procedure(const AProgress: TEngineProgress)
        begin
          if not Tok.IsCancelled then
          begin
            TCancel:= GetTickCount64;
            Tok.Cancel;
          end;
        end, Tok, Output);
      TBack:= GetTickCount64;
      Check('stream.cancel.code', Code = ENGINE_OUTCOME_CANCELLED, IntToStr(Code));
      Check('stream.cancel.fast', (TCancel > 0) and (TBack - TCancel < CANCEL_MAX_MS), Format('%d ms', [TBack - TCancel]));
      Sleep(SURVIVE_WAIT);  // dl:ok sleep-in-vcl@d144 -- REVIEWED 2026-09-30 console test runner, no VCL message loop: waits past the killed stand-in's would-be write
      Check('stream.cancel.killed', not TFile.Exists(Marker), 'the sleeping stand-in finished after Cancel');
    finally
      Tok.Free;
    end;

    Code:= Eng.RunCaptureStreaming(Format('-NoProfile -NonInteractive -File "%s" sleep "%s"', [Ps1, Marker]), SHORT_MS, nil, nil, Output);
    Check('stream.timeout.code', Code = ENGINE_OUTCOME_TIMEOUT, IntToStr(Code));

    // A progress sink that raises must not orphan the engine: the child is killed
    // on the way out, so the sleeping stand-in never writes its marker.
    var Raised: Boolean:= False;
    try
      Eng.RunCaptureStreaming(Format('-NoProfile -NonInteractive -File "%s" sleep "%s"', [Ps1, Marker]), LONG_MS,
        procedure(const AProgress: TEngineProgress)
        begin
          raise EAbort.Create('sink failed');
        end, nil, Output);
    except  // dl:ok try-except-swallowed@ab61 -- REVIEWED 2026-09-30 not swallowed: Raised is asserted by stream.raise.kills just below
      on EAbort do
        Raised:= True;
    end;
    Sleep(SURVIVE_WAIT);  // dl:ok sleep-in-vcl@d144 -- REVIEWED 2026-09-30 console test runner, no VCL message loop: waits past the killed stand-in's would-be write
    Check('stream.raise.kills', Raised and not TFile.Exists(Marker), Format('raised=%s marker=%s', [BoolToStr(Raised, True), BoolToStr(TFile.Exists(Marker), True)]));
  finally
    Eng.Free;
    TDirectory.Delete(Dir, True);
  end; // try
end;

{ GetProptree's LastCancelled describes the LAST call only, and a runner that
  raises comes back as an error, not an exception. The engine exe is a path that
  does not exist: a QUALIFIED name skips resolution, so the fake runner's answer
  is what that call sees; a BARE name then fails at resolution (the query process
  cannot start) inside the runner's work, before any proptree call. }
procedure TestProptreeCancelState;
const
  ENGINE_FATAL = 3; // the engine's own FATAL exit code
  DEPTH_THREE  = 3;
var
  Eng   : TEngineAdapter;
  Tree  : TProptree;
  Err   : string;
  Note  : string;
  Ok    : Boolean;
  Raised: Boolean;
begin
  Eng:= TEngineAdapter.Create(TPath.Combine(TPath.GetTempPath, 'no-such-engine-' + TPath.GetGUIDFileName + '.exe'), []);
  try
    Eng.LongCallRunner:=
      function(const ATitle: string; const AWork: TStreamingWork): Integer
      begin
        Result:= ENGINE_OUTCOME_CANCELLED;
      end;
    Ok:= Eng.GetProptree('U.TFoo', Tree, Err, Note);
    Check('engine.lastcancelled.set', (not Ok) and Eng.LastCancelled, Err);
    // The resolve runs INSIDE the runner's work since job C6, so this runner must
    // actually run it for the bare name's resolution failure to happen at all.
    Eng.LongCallRunner:=
      function(const ATitle: string; const AWork: TStreamingWork): Integer
      begin
        Result:= AWork(nil, nil);
      end;
    Ok:= Eng.GetProptree('TFoo', Tree, Err, Note);
    Check('engine.lastcancelled.reset.on.resolve.error', (not Ok) and (not Eng.LastCancelled) and (Pos('cannot resolve', Err) > 0), Err);

    // The engine's FATAL exit 3 is a FAILURE with the exit code named, not a timeout.
    Eng.LongCallRunner:=
      function(const ATitle: string; const AWork: TStreamingWork): Integer
      begin
        Result:= ENGINE_FATAL;
      end;
    Ok:= Eng.GetProptree('U.TFoo', Tree, Err, Note);
    Check('engine.proptree.exit3.is.failure', (not Ok) and (Pos('TIMED OUT', Err) = 0) and (Pos('exit 3', Err) > 0), Err);

    // The timeout advice names the Depth box only when it is usable (TreeDepth > 0
    // means the engine reports book_depth; an older engine's box is disabled).
    Eng.LongCallRunner:=
      function(const ATitle: string; const AWork: TStreamingWork): Integer
      begin
        Result:= ENGINE_OUTCOME_TIMEOUT;
      end;
    Eng.TreeDepth:= 0;
    Eng.GetProptree('U.TFoo', Tree, Err, Note);
    Check('engine.timeout.text.no.depth.box', (Pos('TIMED OUT', Err) > 0) and (Pos('Depth box', Err) = 0), Err);
    Eng.TreeDepth:= DEPTH_THREE;
    Eng.GetProptree('U.TFoo', Tree, Err, Note);
    Check('engine.timeout.text.depth.box', (Pos('TIMED OUT', Err) > 0) and (Pos('Depth box', Err) > 0), Err);

    Eng.LongCallRunner:=
      function(const ATitle: string; const AWork: TStreamingWork): Integer
      begin
        raise EInOutError.Create('worker failed');
      end;
    Raised:= False;
    Ok    := True;
    try
      Ok:= Eng.GetProptree('U.TFoo', Tree, Err, Note);
    except  // dl:ok try-except-swallowed@ee67 -- not swallowed: Raised is asserted by engine.proptree.runner.raise.is.error just below
      on Exception do
        Raised:= True;
    end;
    Check('engine.proptree.runner.raise.is.error', (not Raised) and (not Ok) and (Pos('worker failed', Err) > 0), Err);
  finally
    Eng.Free;
  end; // try
end;

{ ---------------------------------------------------------------------------
  Scoped validation (fix/validate-edited-blocks, 2026-10-05). The fixtures under
  fixtures\validate\ are REAL pinned-engine output (1.20.6-alpha-20261005-032338,
  --db library-Win64.sqlite) over the BDE book copied beside them:
    validate-bde-syntax.txt  convert-validate, no pair            exit 0, 0.6 s
    validate-bde-tquery.txt  --from Bde.DBTables.TQuery --to ...  exit 1, 145 errors
    validate-bde-ttable.txt  --from Bde.DBTables.TTable --to ...  exit 1, 14.8 s
    validate-bad-syntax.txt  bad-syntax.rules, no pair            exit 1 }

const
  { Facts about fixtures\validate\BDE-to-FireDAC.rules and its pinned-engine captures. }
  BDE_LINES               = 707; // lines in the book
  BDE_BLOCKS              = 10;  // #convert blocks, all with a To type
  BDE_TDATABASE_HDR       = 166; // #convert Bde.DBTables.TDatabase (#apply BdeTransIsolation)
  BDE_TTABLE_HDR          = 205; // #convert Bde.DBTables.TTable
  BDE_TTABLE_LAST         = 319; // its last line (blank, before the TQuery header)
  BDE_TQUERY_HDR          = 320; // #convert Bde.DBTables.TQuery
  BDE_TRANSISO_FIRST      = 130; // #mapping BdeTransIsolation: declaration ...
  BDE_TRANSISO_CLAUSE     = 131; // ... its first #when clause ...
  BDE_TRANSISO_LAST       = 133; // ... and its last line
  BDE_TRANSISO_LINES      = 4;
  BDE_BATCHMODE_CLAUSE    = 137; // a #mapping BdeBatchMode #when line, applied by TBatchMove only
  BDE_UNREACHABLE_LINK    = 274; // #link FieldOptions.AutoCreateMode -- FieldOptions is protected
  BLOCK_UNREACHABLE       = 4;   // FieldOptions.* links per dataset block (274-277 in TTable)
  TTABLE_CAPTURE_WARNINGS = 14;  // validate-bde-ttable.txt: every block vs the TTable pair
  TTABLE_CAPTURE_ERRORS   = 146;
  STUB_HDR_OFFSET         = 3;   // the appended From-only header: after the new block's 2 lines
function ValidateFixture(const AName: string): string;
var
  P: string;
begin
  P:= TPath.Combine(ExtractFilePath(ParamStr(0)), 'fixtures\validate\' + AName);
  if not TFile.Exists(P) then
    P:= 'fixtures\validate\' + AName;
  if TFile.Exists(P) then
    Result:= TFile.ReadAllText(P)
  else
    Result:= '';
end;

function CountDiags(const ADiags: TArray<TValidateDiag>; AWarnings: Boolean): Integer;
var
  D: TValidateDiag;
begin
  Result:= 0;
  for D in ADiags do
    if D.IsWarning = AWarnings then
      Inc(Result);
end;

function JobFrom(const AJobs: TArray<TValidateJob>; const AFrom: string): Integer;
var
  i: Integer;
begin
  for i:= 0 to High(AJobs) do
    if SameText(AJobs[i].FromType, AFrom) then
      Exit(i);
  Result:= -1;
end;

procedure TestValidateParse;
var
  D: TArray<TValidateDiag>;
  X: TValidateDiag;
  Noise: Boolean;
begin
  Check('validate.fixture.present', ValidateFixture('validate-bde-ttable.txt') <> '', 'fixtures\validate missing');
  D:= ParseValidateOutput(ValidateFixture('validate-bde-syntax.txt'));
  Check('validate.parse.syntax.ok.is.empty', Length(D) = 0, IntToStr(Length(D)));

  D:= ParseValidateOutput(ValidateFixture('validate-bad-syntax.txt'));
  Check('validate.parse.bad.two.errors', (Length(D) = 2) and (CountDiags(D, False) = 2), IntToStr(Length(D)));
  if Length(D) = 2 then
  begin
    Check('validate.parse.bad.depth.line1', (D[0].Line = 1) and (Pos('#depth', D[0].Text) > 0), D[0].Text);
    Check('validate.parse.bad.fromonly.line2', (D[1].Line = 2) and (Pos('has no To type', D[1].Text) > 0), D[1].Text);
  end;

  D:= ParseValidateOutput(ValidateFixture('validate-bde-ttable.txt'));
  Check('validate.parse.ttable.warnings', CountDiags(D, True) = TTABLE_CAPTURE_WARNINGS, IntToStr(CountDiags(D, True)));
  Check('validate.parse.ttable.errors', CountDiags(D, False) = TTABLE_CAPTURE_ERRORS, IntToStr(CountDiags(D, False)));
  Noise:= False;
  for X in D do
    if (Pos('loaded defaults', X.Text) > 0) or (Pos('resolver:', X.Text) > 0) or (X.Line = 0) then
      Noise:= True;
  Check('validate.parse.ttable.no.noise', not Noise);

  D:= ParseValidateOutput('OK'#13#10'FATAL: cannot open --db x.sqlite'#13#10'warning: something odd'#13#10 + '  resolver: edges were derived by r=1'#13#10'(loaded defaults from C:\x.json)'#13#10);
  Check('validate.parse.fatal.is.error.line0', (Length(D) = 2) and (D[0].Line = 0) and not D[0].IsWarning, IntToStr(Length(D)));
  if Length(D) = 2 then
    Check('validate.parse.bare.warning.line0', (D[1].Line = 0) and D[1].IsWarning, D[1].Text);
  Check('validate.noise.ok', IsValidateNoise('OK') and IsValidateNoise('  ') and IsValidateNoise('(loaded defaults from C:\Projects\.drag-lint.json)'));
  Check('validate.noise.not.diag', not IsValidateNoise('line 3: link ToPath not found'));
end;

procedure TestValidateScopeBlocks;
var
  Book   : TRuleBook;
  Src    : string   ;
  Txt    : string   ;
  Txt2   : string   ;
  Dropped: Integer  ;
  Map    : TArray<TRuleNode>;
  Jobs   : TArray<TValidateJob>;
  K      : Integer  ;
  D      : TArray<TValidateDiag>;
  Job    : TValidateJob;
begin
  Src:= ValidateFixture('BDE-to-FireDAC.rules');
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(Src);
    Txt:= Book.SaveCompleteWithMap(Dropped, Map);
    Check('validate.map.text.equals.savecomplete', Txt = Book.SaveCompleteToString(Dropped));
    // The captures were taken on the FILE; their line numbers hold only if Save
    // re-emits it unchanged.
    Check('validate.map.bde.canonical', Txt = Src, Format('%d vs %d bytes', [Length(Txt), Length(Src)]));
    Check('validate.map.one.node.per.line', Length(Map) = Length(Txt.Split([#13#10])) - 1, IntToStr(Length(Map)));
    Check('validate.map.header.line205', (Length(Map) >= BDE_TTABLE_HDR) and (Map[BDE_TTABLE_HDR - 1].Kind = rnkConvert) and (Map[BDE_TTABLE_HDR - 1].FromType = 'Bde.DBTables.TTable'));

    Jobs:= BlockJobs(Txt);
    Check('validate.blocks.count', Length(Jobs) = BDE_BLOCKS, IntToStr(Length(Jobs)));
    K:= JobFrom(Jobs, 'Bde.DBTables.TTable');
    // Not IfThen: it evaluates BOTH arguments, and Jobs[-1] is an access violation.
    var Span: string:= 'no job';
    if K >= 0 then
      Span:= Format('%d..%d', [Jobs[K].FirstLine, Jobs[K].LastLine]);
    Check('validate.blocks.ttable.span', (K >= 0) and (Jobs[K].FirstLine = BDE_TTABLE_HDR) and (Jobs[K].LastLine = BDE_TTABLE_LAST) and (Jobs[K].ToType = 'FireDAC.Comp.Client.TFDTable'), Span);
    K:= JobFrom(Jobs, 'Bde.DBTables.TDatabase');
    Check('validate.blocks.tdatabase.mapping.lines', (K >= 0) and (Length(Jobs[K].MappingLines) = BDE_TRANSISO_LINES) and (Jobs[K].MappingLines[0] = BDE_TRANSISO_FIRST) and (Jobs[K].MappingLines[High(Jobs[K].MappingLines)] = BDE_TRANSISO_LAST));

    Check('validate.changed.none', Length(ChangedBlockJobs(Txt, Txt)) = 0);
    Check('validate.changed.new.book.all', Length(ChangedBlockJobs('', Txt)) = BDE_BLOCKS);

    // One link edited in the TTable block: that block only.
    Book.Nodes[BDE_UNREACHABLE_LINK - 1].Raw:= Book.Nodes[BDE_UNREACHABLE_LINK - 1].Raw + ' ';
    Txt2:= Book.SaveCompleteToString(Dropped);
    Jobs:= ChangedBlockJobs(Txt, Txt2);
    Check('validate.changed.one.link', (Length(Jobs) = 1) and (Jobs[0].FromType = 'Bde.DBTables.TTable'), IntToStr(Length(Jobs)));
    Book.LoadFromString(Src);

    // A file-scope #mapping clause edited: the block that #applies it (TBatchMove).
    Book.Nodes[BDE_BATCHMODE_CLAUSE - 1].Raw:= Book.Nodes[BDE_BATCHMODE_CLAUSE - 1].Raw + ' ';
    Txt2:= Book.SaveCompleteToString(Dropped);
    Jobs:= ChangedBlockJobs(Txt, Txt2);
    Check('validate.changed.mapping', (Length(Jobs) = 1) and (Jobs[0].FromType = 'Bde.DBTables.TBatchMove'), IntToStr(Length(Jobs)));
    Book.LoadFromString(Src);

    // A new block, and a From-only block (skipped -- the syntax pass reports it).
    Txt2:= Txt + '#convert A.TNew -> B.TNew'#13#10'#link X <- X'#13#10'#convert A.TStub -> '#13#10'#link Y <- Y'#13#10;
    Jobs:= ChangedBlockJobs(Txt, Txt2);
    Check('validate.changed.new.header', (Length(Jobs) = 1) and (Jobs[0].FromType = 'A.TNew') and (Jobs[0].FirstLine = BDE_LINES + 1) and (Jobs[0].LastLine = BDE_LINES + 2), IntToStr(Length(Jobs)));
    Check('validate.jobatline.fromonly.false', not JobAtLine(Txt2, BDE_LINES + STUB_HDR_OFFSET, Job));
    Check('validate.jobatline.ttable', JobAtLine(Txt, BDE_TTABLE_HDR, Job) and (Job.LastLine = BDE_TTABLE_LAST));
    Check('validate.jobatline.not.header', not JobAtLine(Txt, BDE_TTABLE_HDR + 1, Job));

    // The 145-error TQuery capture filtered to the TQuery block: 4 warnings, 0 errors.
    Check('validate.jobatline.tquery', JobAtLine(Txt, BDE_TQUERY_HDR, Job));
    D:= DiagsForJob(ParseValidateOutput(ValidateFixture('validate-bde-tquery.txt')), Job);
    Check('validate.filter.tquery.own.block', (CountDiags(D, False) = 0) and (CountDiags(D, True) = BLOCK_UNREACHABLE), Format('%d err %d warn', [CountDiags(D, False), CountDiags(D, True)]));
    // TDatabase's pair pass keeps the BdeTransIsolation mapping lines it applies.
    Check('validate.jobatline.tdatabase', JobAtLine(Txt, BDE_TDATABASE_HDR, Job));
    D:= DiagsForJob([Default(TValidateDiag)], Job); // line 0 is always kept
    Check('validate.filter.line0.kept', Length(D) = 1);
    var M: TValidateDiag:= Default(TValidateDiag);
    M.Line:= BDE_TRANSISO_CLAUSE;
    var N: TValidateDiag:= Default(TValidateDiag);
    N.Line:= BDE_BATCHMODE_CLAUSE; // BdeBatchMode: not applied by TDatabase
    D:= DiagsForJob([M, N], Job);
    Check('validate.filter.applied.mapping.only', (Length(D) = 1) and (D[0].Line = BDE_TRANSISO_CLAUSE), IntToStr(Length(D)));
  finally
    Book.Free;
  end;
end;

{ Cancel (the progress window's button) mid-way through a Save's passes: the TTable
  pass completes, the TQuery pass is cancelled. The book is already on disk, so the
  cancelled block must stay OWED: NextPending keeps its key and ChangedBlockJobs
  returns it on the next save although it no longer differs from the snapshot. }
procedure TestValidateScopeCancel;
var
  Book   : TRuleBook;
  Src    : string   ;
  Old    : string   ;
  Txt    : string   ;
  Dropped: Integer  ;
  Map    : TArray<TRuleNode>;
  Jobs   : TArray<TValidateJob>;
  R      : TScopedValidation;
  Pending: TArray<string>;
  Calls  : Integer  ;
  Stop   : Boolean  ;
  Fake   : TValidateFn;
  Cancel : TCancelledFn;
  QMark  : TRuleMark;
begin
  Src:= ValidateFixture('BDE-to-FireDAC.rules');
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(Src);
    Old:= Book.SaveCompleteToString(Dropped);
    // Edit one link in TTable and one in TQuery: two changed blocks.
    Book.Nodes[BDE_UNREACHABLE_LINK - 1].Raw:= Book.Nodes[BDE_UNREACHABLE_LINK - 1].Raw + ' ';
    Book.Nodes[BDE_TQUERY_HDR].Raw:= Book.Nodes[BDE_TQUERY_HDR].Raw + ' ';
    Txt:= Book.SaveCompleteWithMap(Dropped, Map);
    Jobs:= ChangedBlockJobs(Old, Txt);
    Check('validate.cancel.two.jobs', Length(Jobs) = 2, IntToStr(Length(Jobs)));
    // A mark from an earlier save on the TQuery block must survive the cancel.
    QMark:= Default(TRuleMark);
    QMark.Text:= 'line 321: earlier';
    Map[BDE_TQUERY_HDR].Marks:= [QMark];

    Calls:= 0;
    Stop := False;
    Fake:= function(const AText, AFrom, ATo: string): string
      begin
        Inc(Calls);
        if AFrom = 'Bde.DBTables.TQuery' then
          Stop:= True; // the user presses Cancel during this pass
        if AFrom = 'Bde.DBTables.TTable' then
          Result:= ValidateFixture('validate-bde-ttable.txt')
        else
          Result:= ValidateFixture('validate-bde-syntax.txt');
      end;
    Cancel:= function: Boolean
      begin
        Result:= Stop;
      end;
    R:= RunScopedValidation(Txt, Jobs, Fake, Cancel);
    Check('validate.cancel.flag', R.Cancelled and R.SyntaxDone);
    Check('validate.cancel.done.flags', (Length(R.JobDone) = 2) and R.JobDone[0] and not R.JobDone[1]);
    Check('validate.cancel.kept.done.only', (R.Warnings = BLOCK_UNREACHABLE) and (R.Errors = 0), Format('%d/%d', [R.Errors, R.Warnings]));
    Check('validate.cancel.verdict', Pos('cancelled -- 1 changed block(s) not checked: Bde.DBTables.TQuery', ValidateVerdict(R)) = 1, ValidateVerdict(R));
    ApplyValidateMarks(Book.Nodes.ToArray, Map, Jobs, R);
    Check('validate.cancel.marks.kept', (Length(Map[BDE_TQUERY_HDR].Marks) = 1) and (Map[BDE_TQUERY_HDR].Marks[0].Text = 'line 321: earlier'));
    Check('validate.cancel.done.block.marked', Length(Map[BDE_UNREACHABLE_LINK - 1].Marks) = 1);

    Pending:= NextPending(nil, Jobs, R);
    Check('validate.pending.has.cancelled', (Length(Pending) = 1) and (Pending[0] = Jobs[1].Key), IntToStr(Length(Pending)));
    // Next save: nothing changed against the NEW snapshot, but TQuery is owed.
    Jobs:= ChangedBlockJobs(Txt, Txt, Pending);
    Check('validate.pending.revalidated', (Length(Jobs) = 1) and (Jobs[0].FromType = 'Bde.DBTables.TQuery'), IntToStr(Length(Jobs)));
    Stop:= False;
    Cancel:= function: Boolean
      begin
        Result:= False;
      end;
    R:= RunScopedValidation(Txt, Jobs, Fake, Cancel);
    Pending:= NextPending(Pending, Jobs, R);
    Check('validate.pending.cleared', (Length(Pending) = 0) and not R.Cancelled, IntToStr(Length(Pending)));
    Check('validate.pending.none.unchanged', Length(ChangedBlockJobs(Txt, Txt, Pending)) = 0);

    // Cancelled before anything ran: no pass done, syntax marks untouched.
    Calls:= 0;
    Map[0].Marks:= nil;
    QMark.FromSyntax:= True;
    Map[0].Marks:= [QMark];
    R:= RunScopedValidation(Txt, Jobs, Fake,
      function: Boolean
      begin
        Result:= True;
      end);
    Check('validate.cancel.early.no.calls', (Calls = 0) and R.Cancelled and not R.SyntaxDone, IntToStr(Calls));
    ApplyValidateMarks(Book.Nodes.ToArray, Map, Jobs, R);
    Check('validate.cancel.early.syntax.marks.kept', Length(Map[0].Marks) = 1);
    Check('validate.cancel.early.verdict', Pos('syntax not checked', ValidateVerdict(R)) > 0, ValidateVerdict(R));
  finally
    Book.Free;
  end;
end;

{ ValidateText's Output feeds ParseValidateOutput, which reads it LINE by line. A
  merged stdout+stderr pipe interleaves the two by chunk, and on 2026-10-05 a driven
  Save showed "Validate: s, not a re-parse). (+3 more)": the tail of the engine's
  stderr "resolver: ... (minutes, not a re-parse)." advisory, split from its head by
  a stdout chunk, parsed as an ERROR. Stand-in: stdout, stderr, stdout. Separate
  pipes put every stdout line first and the stderr line after them, whole. }
procedure TestValidateTextStreams;
const
  STANDIN_CMD = '@echo off'#13#10'echo line 1: warning: first'#13#10'echo   resolver: edges were derived by r=1 (minutes, not a re-parse). 1>&2'#13#10 +
    'echo line 2: warning: second'#13#10'exit /b 0'#13#10;
var
  Dir: string         ;
  Eng: TEngineAdapter ;
  Res: TValidateResult;
begin
  Dir:= TPath.Combine(TPath.GetTempPath, 'validate-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'standin.cmd'), STANDIN_CMD, TEncoding.ASCII);
    Eng:= TEngineAdapter.Create(TPath.Combine(Dir, 'standin.cmd'), []);
    try
      Res:= Eng.ValidateText('#note x'#13#10, 'A.TFrom', 'B.TTo');
      var D: TArray<TValidateDiag>:= ParseValidateOutput(Res.Output);
      Check('validate.text.standin.ran', Pos('line 1: warning: first', Res.Output) > 0, Res.Output);
      Check('validate.text.stdout.before.stderr', (Pos('line 2: warning: second', Res.Output) > 0) and (Pos('line 2: warning: second', Res.Output) < Pos('resolver:', Res.Output)), Res.Output);
      Check('validate.text.two.warnings.no.error', (CountDiags(D, True) = 2) and (CountDiags(D, False) = 0), Res.Output);
    finally
      Eng.Free;
    end;
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TestValidateScopeRun;
var
  Book   : TRuleBook;
  Src    : string   ;
  Txt    : string   ;
  Dropped: Integer  ;
  Map    : TArray<TRuleNode>;
  Jobs   : TArray<TValidateJob>;
  Calls  : TArray<string>;
  R      : TScopedValidation;
  Fake   : TValidateFn;
  E, W   : Integer  ;
begin
  Src:= ValidateFixture('BDE-to-FireDAC.rules');
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(Src);
    Txt:= Book.SaveCompleteWithMap(Dropped, Map);
    Calls:= nil;
    Fake:= function(const AText, AFrom, ATo: string): string
      begin
        Calls:= Calls + [AFrom + '|' + ATo];
        if AFrom = '' then
          Result:= ValidateFixture('validate-bde-syntax.txt')
        else if AFrom = 'Bde.DBTables.TTable' then
          Result:= ValidateFixture('validate-bde-ttable.txt')
        else
          Result:= 'FATAL: unexpected pair ' + AFrom;
      end;

    // Unchanged save: the syntax pass only.
    R:= RunScopedValidation(Txt, ChangedBlockJobs(Txt, Txt), Fake);
    Check('validate.run.unchanged.one.call', (Length(Calls) = 1) and (Calls[0] = '|'), string.Join(';', Calls));
    Check('validate.run.unchanged.ok', (R.Errors = 0) and (R.Warnings = 0) and (ValidateVerdict(R) = 'OK'), ValidateVerdict(R));

    // The TTable block edited: syntax + its own pair; the 146 errors of the other
    // blocks are not kept, its 4 warnings are -- although the engine exited 1.
    Calls:= nil;
    Book.Nodes[BDE_UNREACHABLE_LINK - 1].Raw:= Book.Nodes[BDE_UNREACHABLE_LINK - 1].Raw + ' ';
    var Old: string:= Txt;
    Txt:= Book.SaveCompleteWithMap(Dropped, Map);
    Jobs:= ChangedBlockJobs(Old, Txt);
    R:= RunScopedValidation(Txt, Jobs, Fake);
    Check('validate.run.changed.two.calls', (Length(Calls) = 2) and (Calls[1] = 'Bde.DBTables.TTable|FireDAC.Comp.Client.TFDTable'), string.Join(';', Calls));
    Check('validate.run.changed.counts', (R.Errors = 0) and (R.Warnings = BLOCK_UNREACHABLE), Format('%d err %d warn', [R.Errors, R.Warnings]));
    Check('validate.run.verdict.warnings', ValidateVerdict(R) = 'OK, 4 warning(s) -- see marked rules', ValidateVerdict(R));

    // Marks: on the rule that emitted the line, never in the text.
    var Before: string:= Book.Snapshot;
    ApplyValidateMarks(Book.Nodes.ToArray, Map, Jobs, R);
    Check('validate.marks.on.link.274', (Length(Map[BDE_UNREACHABLE_LINK - 1].Marks) = 1) and Map[BDE_UNREACHABLE_LINK - 1].Marks[0].IsWarning and (Pos('FieldOptions.AutoCreateMode', Map[BDE_UNREACHABLE_LINK - 1].Marks[0].Text) > 0));
    Check('validate.marks.not.in.snapshot', Book.Snapshot = Before);
    MarksText(BlockMarkNodes(Book, BDE_TTABLE_HDR - 1), E, W);
    Check('validate.marks.block.ttable', (E = 0) and (W = BLOCK_UNREACHABLE), Format('%d/%d', [E, W]));
    MarksText(BlockMarkNodes(Book, BDE_TQUERY_HDR - 1), E, W);
    Check('validate.marks.block.tquery.none', (E = 0) and (W = 0), Format('%d/%d', [E, W]));
    Check('validate.marker.text', (MarkerText(0, BLOCK_UNREACHABLE) = '4 warn') and (MarkerText(1, 2) = '1 err, 2 warn') and (MarkerText(0, 0) = ''), MarkerText(1, 2));

    // A later save that did not change the block keeps its marks...
    ApplyValidateMarks(Book.Nodes.ToArray, Map, nil, RunScopedValidation(Txt, nil, Fake));
    Check('validate.marks.unchanged.kept', Length(Map[BDE_UNREACHABLE_LINK - 1].Marks) = 1);
    // ...and revalidating it replaces them.
    var Clean: TScopedValidation:= Default(TScopedValidation);
    SetLength(Clean.JobDiags, Length(Jobs));
    // Every pass completed and found nothing (a cancelled one would keep its marks).
    Clean.SyntaxDone:= True;
    SetLength(Clean.JobDone, Length(Jobs));
    for var k:= 0 to High(Jobs) do
      Clean.JobDone[k]:= True;
    ApplyValidateMarks(Book.Nodes.ToArray, Map, Jobs, Clean);
    Check('validate.marks.revalidated.cleared', Length(Map[BDE_UNREACHABLE_LINK - 1].Marks) = 0);

    // Syntax marks are replaced on every pass; a FATAL counts as an error.
    var Bad: TScopedValidation:= RunScopedValidation('x', nil,
      function(const AText, AFrom, ATo: string): string
      begin
        Result:= 'line 1: #depth must be an integer 1..10'#13#10'FATAL: db locked'#13#10;
      end);
    Check('validate.run.fatal.is.error', (Bad.Errors = 2) and (Pos('line 1: #depth', ValidateVerdict(Bad)) = 1) and (Pos('(+1 more)', ValidateVerdict(Bad)) > 0), ValidateVerdict(Bad));
    ApplyValidateMarks(Book.Nodes.ToArray, Map, nil, Bad);
    Check('validate.marks.syntax.added', (Length(Map[0].Marks) = 1) and Map[0].Marks[0].FromSyntax);
    ApplyValidateMarks(Book.Nodes.ToArray, Map, nil, Clean);
    Check('validate.marks.syntax.replaced', Length(Map[0].Marks) = 0);
  finally
    Book.Free;
  end;
end;

{ The live tests' engine is chosen EXPLICITLY: beside the runner, else the exe
  CONVRULES_TEST_ENGINE names. Never a silent fallback to third_party\dll-win64 --
  that folder is the live, rebuilt-without-warning engine (2026-10-05: an
  unreviewed 1.21.0 build sat there while this suite was being run). }
procedure TestChooseTestEngine;
var
  Dir : string;
  Exe : string;
  Why : string;
  Got : string;
begin
  Dir:= TPath.Combine(TPath.GetTempPath, 'engchoice-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    Got:= ChooseTestEngine(Dir, '', Why);
    Check('engine.choice.none.is.empty', Got = '', Got);
    Check('engine.choice.none.says.why', (Pos(TEST_ENGINE_ENV, Why) > 0) and (Pos('beside', Why) > 0), Why);
    Got:= ChooseTestEngine(Dir, TPath.Combine(Dir, 'missing.exe'), Why);
    Check('engine.choice.env.missing.refused', (Got = '') and (Pos('missing.exe', Why) > 0), Got + ' / ' + Why);
    Exe:= TPath.Combine(Dir, 'named.exe');
    TFile.WriteAllText(Exe, 'x');
    Got:= ChooseTestEngine(Dir, Exe, Why);
    Check('engine.choice.env.used', SameText(Got, Exe), Got);
    TFile.WriteAllText(TPath.Combine(Dir, 'drag-lint.exe'), 'x');
    Got:= ChooseTestEngine(Dir, Exe, Why);
    Check('engine.choice.beside.wins', SameText(Got, TPath.Combine(Dir, 'drag-lint.exe')), Got);
    Check('engine.choice.never.dll-win64', Pos('dll-win64', LowerCase(ResolveExe)) = 0, ResolveExe);
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

{ Every engine verb whose stdout is PARSED (JSON / sql / query) reads it over a
  pipe of its own. The stand-ins write the stdout line in two pieces with a stderr
  line between them; a merged pipe puts the noise INSIDE the JSON. }
procedure TestStdoutSeparateFromStderr;
const
  CAPS_CMD = '@echo off'#13#10'<nul set /p ={"capabilities":{"book_depth"'#13#10'echo noise-on-stderr 1>&2'#13#10'echo :true}}'#13#10;
  SQL_CMD  = '@echo off'#13#10'<nul set /p ={"rows":[["A.pas"'#13#10'echo noise-on-stderr 1>&2'#13#10'echo ]]}'#13#10;
var
  Dir  : string;
  Eng  : TEngineAdapter;
  Files: TArray<string>;
  Err  : string;
begin
  Dir:= TPath.Combine(TPath.GetTempPath, 'pipes-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'caps.cmd'), CAPS_CMD, TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(Dir, 'sql.cmd'), SQL_CMD, TEncoding.ASCII);
    Eng:= TEngineAdapter.Create(TPath.Combine(Dir, 'caps.cmd'), []);
    try
      Check('pipes.info.json.whole', MatchText(CAPABILITY_BOOK_DEPTH, Eng.CapabilityNames), string.Join(',', Eng.CapabilityNames));
    finally
      Eng.Free;
    end;
    Eng:= TEngineAdapter.Create(TPath.Combine(Dir, 'sql.cmd'), []);
    try
      var Ok: Boolean:= Eng.ListIndexedFiles(['x.sqlite'], Files, Err);
      Check('pipes.sql.json.whole', Ok and (Length(Files) = 1) and (Files[0] = 'A.pas'), Err);
    finally
      Eng.Free;
    end;
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

{ ResolveClassQName (a `query`, 0.5-1 s) runs INSIDE the long-call runner, on its
  worker: the progress window and its Cancel cover it, and FTreeLoads (counted by
  the editor's runner) holds depth commits back. The stand-in engine logs every
  call and answers exit 1 (no such class / no tree). }
{ Lines in the stand-in engine's call log (0 when it was never called). }
function LogLineCount(const APath: string): Integer;
begin
  if TFile.Exists(APath) then
    Result:= Length(TFile.ReadAllLines(APath))
  else
    Result:= 0;
end;

procedure TestProptreeResolveInRunner;
const
  LOG_CMD = '@echo %1>>"%~dp0calls.log"'#13#10'@exit /b 1'#13#10;
var
  Dir     : string;
  Log     : string;
  Eng     : TEngineAdapter;
  Tree    : TProptree;
  Err     : string;
  Note    : string;
  CallsIn : Integer;
  Ran     : Boolean;
begin

  Dir:= TPath.Combine(TPath.GetTempPath, 'resolve-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  Log:= TPath.Combine(Dir, 'calls.log');
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'engine.cmd'), LOG_CMD, TEncoding.ASCII);
    Eng:= TEngineAdapter.Create(TPath.Combine(Dir, 'engine.cmd'), []);
    try
      CallsIn:= -1;
      Ran    := False;
      Eng.LongCallRunner:=
        function(const ATitle: string; const AWork: TStreamingWork): Integer
        begin
          CallsIn:= LogLineCount(Log); // engine calls made BEFORE the runner was entered
          Ran:= True;
          Result:= AWork(nil, nil);
        end;
      Eng.GetProptree('TFoo', Tree, Err, Note);
      Check('resolve.inside.runner', Ran and (CallsIn = 0), Format('engine calls before the runner: %d', [CallsIn]));
      Check('resolve.then.proptree', LogLineCount(Log) = 2, IntToStr(LogLineCount(Log)));

      // Cancel pressed before the work starts: no engine call at all.
      TFile.Delete(Log);
      Eng.LongCallRunner:=
        function(const ATitle: string; const AWork: TStreamingWork): Integer
        var
          T: TCancelToken;
        begin
          T:= TCancelToken.Create;
          try
            T.Cancel;
            Result:= AWork(nil, T);
          finally
            T.Free;
          end;
        end;
      var Ok: Boolean:= Eng.GetProptree('TFoo', Tree, Err, Note);
      Check('resolve.cancel.no.engine.call', (not Ok) and Eng.LastCancelled and (LogLineCount(Log) = 0), Format('calls=%d err=%s', [LogLineCount(Log), Err]));
    finally
      Eng.Free;
    end;
  finally
    TDirectory.Delete(Dir, True);
  end;
end;
{ ResolveClassQName answers are cached for the session (job C6 follow-up): every
  rule click resolved its From and To classes again (0.5-1.2 s each), so even a
  trivial load flashed the progress window. Keyed on the name (case-insensitive,
  as Delphi is) AND the --db set; a NEGATIVE answer (exit 1: no such class) is an
  answer and is cached; a FAILED lookup is not. Cleared by SetDbs, by
  ClearResolveCache and by IndexProject. The stand-ins log every call. }
{ Calls of one verb in the stand-in engine's log (each line is the verb, %1). }
function VerbCount(const APath, AVerb: string): Integer;
var
  L: string;
begin
  Result:= 0;
  if TFile.Exists(APath) then
    for L in TFile.ReadAllLines(APath) do
      if SameText(Trim(L), AVerb) then
        Inc(Result);
end;

procedure TestResolveCache;
const
  MISS_CMD = '@echo %1>>"%~dp0calls.log"'#13#10'@exit /b 1'#13#10;  // query: no such class; proptree: no tree
  FAIL_CMD = '@echo %1>>"%~dp0calls.log"'#13#10'@exit /b 2'#13#10;  // the call itself failed
var
  Dir : string;
  Log : string;
  Eng : TEngineAdapter;
  Tree: TProptree;
  Err : string;
  Note: string;
  Out : string;
  Q   : Integer; // query calls logged before the step under test

  procedure Load(const AName: string);
  begin
    Eng.GetProptree(AName, Tree, Err, Note);
  end;

begin
  Dir:= TPath.Combine(TPath.GetTempPath, 'rcache-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  Log:= TPath.Combine(Dir, 'calls.log');
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'miss.cmd'), MISS_CMD, TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(Dir, 'fail.cmd'), FAIL_CMD, TEncoding.ASCII);
    Eng:= TEngineAdapter.Create(TPath.Combine(Dir, 'miss.cmd'), ['a.sqlite']);
    try
      Eng.LongCallRunner:=
        function(const ATitle: string; const AWork: TStreamingWork): Integer
        begin
          Result:= AWork(nil, nil);
        end;
      Load('TFoo');
      Check('rcache.negative.answer', (VerbCount(Log, 'query') = 1) and (Pos('cannot resolve', Err) = 0), Err);
      Load('TFoo');
      Check('rcache.negative.cached', VerbCount(Log, 'query') = 1, IntToStr(VerbCount(Log, 'query')));
      Check('rcache.proptree.still.runs', VerbCount(Log, 'proptree') = 2, IntToStr(VerbCount(Log, 'proptree')));
      Load('tfoo');
      Check('rcache.key.case.insensitive', VerbCount(Log, 'query') = 1, IntToStr(VerbCount(Log, 'query')));
      Load('TBar');
      Check('rcache.key.other.name.misses', VerbCount(Log, 'query') = 2, IntToStr(VerbCount(Log, 'query')));
      Q:= VerbCount(Log, 'query');
      Eng.SetDbs(['b.sqlite']);
      Load('TFoo');
      Check('rcache.cleared.by.setdbs', VerbCount(Log, 'query') = Q + 1, IntToStr(VerbCount(Log, 'query')));
      Q:= VerbCount(Log, 'query');
      Eng.ClearResolveCache;
      Load('TFoo');
      Check('rcache.cleared.explicitly', VerbCount(Log, 'query') = Q + 1, IntToStr(VerbCount(Log, 'query')));
      Q:= VerbCount(Log, 'query');
      Eng.IndexProject('x.dproj', 'b.sqlite', Out);
      Load('TFoo');
      Check('rcache.cleared.by.reindex', VerbCount(Log, 'query') = Q + 1, IntToStr(VerbCount(Log, 'query')));
      // Cancelled before the lookup: nothing resolved, so nothing may be cached.
      Eng.ClearResolveCache;
      Q:= VerbCount(Log, 'query');
      Eng.LongCallRunner:=
        function(const ATitle: string; const AWork: TStreamingWork): Integer
        var
          T: TCancelToken;
        begin
          T:= TCancelToken.Create;
          try
            T.Cancel;
            Result:= AWork(nil, T);
          finally
            T.Free;
          end;
        end;
      Load('TBaz');
      Eng.LongCallRunner:=
        function(const ATitle: string; const AWork: TStreamingWork): Integer
        begin
          Result:= AWork(nil, nil);
        end;
      Load('TBaz');
      Check('rcache.cancel.not.cached', VerbCount(Log, 'query') = Q + 1, IntToStr(VerbCount(Log, 'query')));
    finally
      Eng.Free;
    end;
    TFile.Delete(Log);
    Eng:= TEngineAdapter.Create(TPath.Combine(Dir, 'fail.cmd'), ['a.sqlite']);
    try
      Eng.LongCallRunner:=
        function(const ATitle: string; const AWork: TStreamingWork): Integer
        begin
          Result:= AWork(nil, nil);
        end;
      Load('TFoo');
      Check('rcache.failure.reported', Pos('cannot resolve', Err) > 0, Err);
      Load('TFoo');
      Check('rcache.failure.not.cached', VerbCount(Log, 'query') = 2, IntToStr(VerbCount(Log, 'query')));
    finally
      Eng.Free;
    end;
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

{ C8 E1: the .dfm scan lists every inherited / inline object, nested ones included,
  with name, class, line, enclosing frame class and enclosing block type. Lists ('<',
  '(', '{' values) are skipped whole, so a collection's item/end never closes a
  component; quoted text is never a header. }
procedure TestInheritanceScan;
const
  DESC_DFM =
    'inherited dmlCPData: TdmlCPData' + sLineBreak +
    '  Height = 480' + sLineBreak +
    '  inherited tblFtrs: TTable' + sLineBreak +
    '    inherited tblFtrsDimName: TStringField' + sLineBreak +
    '      DisplayLabel = ''Characteristic Name''' + sLineBreak +
    '    end' + sLineBreak +
    '  end' + sLineBreak +
    '  inherited qryScrap: TQuery [2]' + sLineBreak +
    '    SQL.Strings = (' + sLineBreak +
    '      ''select a, b'' +' + sLineBreak +
    '      ''from t)'')' + sLineBreak +
    '  end' + sLineBreak +
    '  object qryOwn: TQuery' + sLineBreak +
    '  end' + sLineBreak +
    'end' + sLineBreak;
  FRAME_DFM =
    'object Form2: TForm2' + sLineBreak +
    '  Caption = ''inherited fake: TTable''' + sLineBreak +
    '  inline Frame11: TFrame1' + sLineBreak +
    '    inherited Button1: TButton' + sLineBreak +
    '      Caption = ''Go''' + sLineBreak +
    '    end' + sLineBreak +
    '  end' + sLineBreak +
    '  object Grid: TDBGrid' + sLineBreak +
    '    Columns = <' + sLineBreak +
    '      item' + sLineBreak +
    '        Expanded = False' + sLineBreak +
    '      end' + sLineBreak +
    '      item' + sLineBreak +
    '        Title.Caption = ''a > b''' + sLineBreak +
    '      end>' + sLineBreak +
    '  end' + sLineBreak +
    '  object After: TLabel' + sLineBreak +
    '  end' + sLineBreak +
    'end' + sLineBreak;
  // Ruling R2: a string CONTINUATION line holding '=' and '(' is not a property
  // assignment, so it must not open a list skip that would swallow every header after it.
  CONT_DFM =
    'inherited Form3: TForm3' + sLineBreak +
    '  object Lbl: TLabel' + sLineBreak +
    '    Hint =' + sLineBreak +
    '      ''abc = (def'' +' + sLineBreak +
    '      ''ghi''' + sLineBreak +
    '  end' + sLineBreak +
    '  inherited qryLate: TQuery' + sLineBreak +
    '  end' + sLineBreak +
    'end' + sLineBreak;
  LINE_DIM   = 4;
  LINE_SCRAP = 8;
  LINE_LATE  = 7;
  INSTANCES_IN_DESC = 3;
var
  S     : TDfmInheritance;
  Opener: TDfmOpener;
  Typ   : string;
begin
  S:= ScanDfmInheritance(DESC_DFM);
  Check('inherit.scan.root', S.RootClass = 'TdmlCPData', S.RootClass);
  Check('inherit.scan.count', Length(S.Instances) = INSTANCES_IN_DESC, IntToStr(Length(S.Instances)));
  if Length(S.Instances) = INSTANCES_IN_DESC then
  begin
    Check('inherit.scan.plain', (S.Instances[0].Name = 'tblFtrs') and (S.Instances[0].TypeName = 'TTable') and (S.Instances[0].Opener = doInherited)
      and (S.Instances[0].FrameClass = '') and (S.Instances[0].ParentType = ''));
    Check('inherit.scan.nested', (S.Instances[1].Name = 'tblFtrsDimName') and (S.Instances[1].Line = LINE_DIM) and (S.Instances[1].ParentType = 'TTable'),
      Format('%s line %d parent %s', [S.Instances[1].Name, S.Instances[1].Line, S.Instances[1].ParentType]));
    Check('inherit.scan.index.suffix', (S.Instances[2].TypeName = 'TQuery') and (S.Instances[2].Line = LINE_SCRAP), S.Instances[2].TypeName);
  end;
  Check('inherit.scan.list.skipped', FindDfmObject(DESC_DFM, 'qryOwn', Opener, Typ) and (Opener = doObject) and (Typ = 'TQuery'), Typ);

  S:= ScanDfmInheritance(FRAME_DFM);
  Check('inherit.scan.quoted.not.header', Length(S.Instances) = 2, IntToStr(Length(S.Instances)));
  if Length(S.Instances) = 2 then
  begin
    Check('inherit.scan.inline', (S.Instances[0].Name = 'Frame11') and (S.Instances[0].Opener = doInline) and (S.Instances[0].FrameClass = ''));
    Check('inherit.scan.frame.child', (S.Instances[1].Name = 'Button1') and (S.Instances[1].Opener = doInherited)
      and (S.Instances[1].FrameClass = 'TFrame1') and (S.Instances[1].ParentType = 'TFrame1'), S.Instances[1].FrameClass);
  end;
  Check('inherit.find.after.collection', FindDfmObject(FRAME_DFM, 'after', Opener, Typ) and (Opener = doObject) and (Typ = 'TLabel'), Typ);
  Check('inherit.find.ignores.frame.children', not FindDfmObject(FRAME_DFM, 'Button1', Opener, Typ));
  Check('inherit.find.absent', not FindDfmObject(FRAME_DFM, 'NoSuch', Opener, Typ));

  S:= ScanDfmInheritance(CONT_DFM);
  Check('inherit.scan.continuation.not.list', (Length(S.Instances) = 1) and (S.Instances[0].Name = 'qryLate') and (S.Instances[0].Line = LINE_LATE),
    IntToStr(Length(S.Instances)));

  S:= ScanDfmInheritance('TPF0'#0#1'garbage');
  Check('inherit.scan.binary', S.IsBinary and (Length(S.Instances) = 0));
  S:= ScanDfmInheritance('');
  Check('inherit.scan.empty', (S.RootClass = '') and (Length(S.Instances) = 0) and not S.IsBinary);
end;

{ C8 E1 helpers: bare class names, a book's #convert pairs (From-only stubs kept), the
  From-type test, and the two ConvRules.Usage helpers the scan now shares. }
procedure TestInheritancePairs;
const
  BOOK =
    '#convert Vcl.StdCtrls.TLabel -> Vcl.StdCtrls.TStaticText, Vcl.StdCtrls' + sLineBreak +
    '#link Caption <- Caption' + sLineBreak +
    '#convert TTable -> TFDTable' + sLineBreak +
    '#convert TQuery -> ' + sLineBreak;
  PAIRS_IN_BOOK = 3;
var
  Pairs: TArray<TTypePair>;
begin
  Check('inherit.bare.type', (BareType('Vcl.StdCtrls.TLabel') = 'TLabel') and (BareType('TTable') = 'TTable') and (BareType('') = ''));
  Pairs:= TypePairsOfText(BOOK);
  Check('inherit.pairs.count', Length(Pairs) = PAIRS_IN_BOOK, IntToStr(Length(Pairs)));
  if Length(Pairs) = PAIRS_IN_BOOK then
  begin
    Check('inherit.pairs.bare', (Pairs[0].FromType = 'TLabel') and (Pairs[0].ToType = 'TStaticText') and (Pairs[1].FromType = 'TTable') and (Pairs[1].ToType = 'TFDTable'));
    Check('inherit.pairs.from.only', (Pairs[2].FromType = 'TQuery') and (Pairs[2].ToType = ''));
  end;
  Check('inherit.isfrom', IsFromType('ttable', Pairs) and IsFromType('DBTables.TTable', Pairs) and not IsFromType('TMemo', Pairs));
  Check('inherit.isfrom.none', not IsFromType('TTable', nil));
  Check('usage.stripquoted.public', Pos('>', StripQuoted('Title.Caption = ''a > b''')) = 0);
  Check('usage.ispropname.public', IsPropName('Title.Caption') and not IsPropName('''abc'));
end;

{ A fake project index for the C8 walk: each row 'Class|PasPath|Parent[|f1:T1,f2:T2]'
  (the 4th part: the From-typed fields the class itself declares); a row 'Class|!'
  answers Failed (the engine could not be asked), 'Class|!|why' with Error 'why'. A class with no row is not in the
  index. ACalls (may be nil) records every question asked. }
function FakeLookup(const ARows: TArray<string>; ACalls: TStringList): TClassLookup;
const
  PARENT_FIELD = 2;
  FIELDS_FIELD = 3;
  FIELD_NAME   = 0;
  FIELD_TYPE   = 1;
var
  LRows: TArray<string>;
begin
  LRows:= ARows;
  Result:= function(const AClassName: string): TClassInfo
    var
      LParts: TArray<string>;
      LPair : TArray<string>;
      LField: TFieldDecl;
    begin
      Result:= Default(TClassInfo);
      if ACalls <> nil then
        ACalls.Add(AClassName);
      for var LRow: string in LRows do
      begin
        LParts:= LRow.Split(['|']);
        if not SameText(LParts[0], AClassName) then
          Continue;
        if LParts[1] = '!' then
        begin
          Result.Failed:= True;
          Result.Error := if Length(LParts) > PARENT_FIELD then LParts[PARENT_FIELD] else '';
        end
        else
        begin
          Result.Found  := True;
          Result.PasPath:= LParts[1];
          if Length(LParts) > PARENT_FIELD then
            Result.ParentClass:= LParts[PARENT_FIELD];
          if Length(LParts) > FIELDS_FIELD then
            for var LText: string in LParts[FIELDS_FIELD].Split([',']) do
            begin
              LPair          := LText.Split([':']);
              LField.Name    := LPair[FIELD_NAME];
              LField.TypeName:= LPair[FIELD_TYPE];
              Result.Fields  := Result.Fields + [LField];
            end;
        end;
        Exit;
      end;
    end;
end;

const
  { FakeReader answers drUnreadable for a path whose text is this. }
  FAKE_UNREADABLE_DFM = '<unreadable>';

{ A fake file system for the C8 walk: APaths[i] holds ATexts[i] (FAKE_UNREADABLE_DFM =
  the file exists but cannot be read); anything else is absent. }
function FakeReader(const APaths, ATexts: TArray<string>): TDfmTextReader;
var
  LPaths, LTexts: TArray<string>;
begin
  LPaths:= APaths;
  LTexts:= ATexts;
  Result:= function(const APath: string; out AText: string): TDfmRead
    begin
      AText:= '';
      for var I: Integer:= 0 to High(LPaths) do
        if SameText(LPaths[I], APath) then
        begin
          if LTexts[I] = FAKE_UNREADABLE_DFM then
            Exit(drUnreadable);
          AText:= LTexts[I];
          Exit(drRead);
        end;
      Result:= drMissing;
    end;
end;

{ A fake `refs` answer for the C8 code-use scan: rows 'Name|Receiver|Line' for every
  unit; AFail = the engine could not answer (AError = FAKE_REFS_ERROR). }
function FakeCodeUses(const ARows: TArray<string>; AFail: Boolean): TCodeUseLookup;
const
  FAKE_REFS_ERROR = 'fake: refs unavailable';
  NAME_FIELD     = 0;
  RECEIVER_FIELD = 1;
  LINE_FIELD     = 2;
var
  LRows: TArray<string>;
begin
  LRows:= ARows;
  Result:= function(const AUnitPas, AClassName: string; out AUses: TArray<TCodeUse>; out AError: string): Boolean
    var
      LParts: TArray<string>;
      LUse  : TCodeUse;
    begin
      AUses := nil;
      AError:= '';
      if AFail then
      begin
        AError:= FAKE_REFS_ERROR;
        Exit(False);
      end;
      for var LRow: string in LRows do
      begin
        LParts   := LRow.Split(['|']);
        LUse.Name:= CodeUseName(LParts[NAME_FIELD], LParts[RECEIVER_FIELD]);
        LUse.Line:= StrToInt(LParts[LINE_FIELD]);
        AUses    := AUses + [LUse];
      end;
      Result:= True;
    end;
end;

{ C8 E2b: descendant CODE on an ancestor's From-typed field counts as an inherited
  use even with no .dfm block for it (spec: `tblFtrs.IndexName := ...` in a descendant
  whose .dfm never overrides tblFtrs). Same chain rule as E2a; no double count with a
  .dfm block; own fields, unknown names and converted fields are not uses; a walk
  that cannot decide makes the unit unknown, never outside. }
procedure TestInheritanceCodeUses;  // dl:ok cyclomatic-complexity@520f -- REVIEWED 2026-10-06 an assertion list plus a one-loop lookup helper (nested function V); the count is mostly the and-chains in Check conditions, and splitting the list would only scatter one fixture
const
  BASE_PAS = 'fx\Base.pas';
  MID_PAS  = 'fx\Mid.pas';
  LEAF_PAS = 'fx\Leaf.pas';
  BASE_DFM = 'object BaseDM: TBaseDM' + sLineBreak + '  object tblFtrs: TTable' + sLineBreak + '  end' + sLineBreak +
    '  object tblOps: TTable' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  MID_DFM  = 'inherited MidDM: TMidDM' + sLineBreak + '  inherited tblOps: TTable' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  BARE_LEAF_DFM = 'inherited LeafDM: TLeafDM' + sLineBreak + '  Height = 200' + sLineBreak + 'end' + sLineBreak;
  BLOCK_LEAF_DFM = 'inherited LeafDM: TLeafDM' + sLineBreak + '  inherited tblFtrs: TTable' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  NONFROM_LEAF_DFM = 'inherited LeafDM: TLeafDM' + sLineBreak + '  inherited tblFtrs: TFDTable' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  CONV_BASE_DFM = 'object BaseDM: TBaseDM' + sLineBreak + '  object tblFtrs: TFDTable' + sLineBreak + '  end' + sLineBreak +
    '  object tblOps: TTable' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  BINARY_DFM = BINARY_DFM_SIGNATURE + 'binary';
  LINE_FIRST = 40;
  DEPTH_BASE = 2;
  CHAIN_OPS  = 2;
  N_USES     = 2;
var
  Pairs : TArray<TTypePair>;
  Rows  : TArray<string>;
  Reader: TDfmTextReader;
  Inner : TDfmTextReader;
  Reads : Integer;
  U     : TUnitInheritance;
  P     : TTypePair;

  function V(const AName: string): TInstanceVerdict;
  begin
    Result:= Default(TInstanceVerdict);
    for var LV: TInstanceVerdict in U.Verdicts do
      if SameText(LV.Instance.Name, AName) then
        Exit(LV);
  end;

begin
  Check('code.use.name', (CodeUseName('IndexName', 'tblFtrs') = 'tblFtrs') and (CodeUseName('Post', 'Self.tblOps') = 'tblOps')
    and (CodeUseName('Open', 'tblA.Fields[0]') = 'tblA') and (CodeUseName('tblX', '') = 'tblX') and (CodeUseName('Go', 'Self') = 'Go'));
  P.FromType:= 'TTable';
  P.ToType  := 'TFDTable';
  Pairs:= [P];
  // Base also lists qryOwn, so only the own-class skip (not "no ancestor declares it") drops the leaf's qryOwn use.
  Rows := ['TLeafDM|' + LEAF_PAS + '|TMidDM|qryOwn:TTable', 'TMidDM|' + MID_PAS + '|TBaseDM', 'TBaseDM|' + BASE_PAS + '|TDataModule|tblFtrs:TTable,tblOps:TTable,qryOwn:TTable'];
  Reader:= FakeReader(['fx\Leaf.dfm', 'fx\Mid.dfm', 'fx\Base.dfm'], [BARE_LEAF_DFM, MID_DFM, BASE_DFM]);

  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(Rows, nil), Reader,
    FakeCodeUses(['IndexName|tblFtrs|41', 'tblFtrs||40', 'Post|Self.tblOps|50', 'Caption|lblNoSuch|60', 'Open|qryOwn|70'], False));
  Check('code.use.no.dfm.block', U.Known and (Length(U.Verdicts) = N_USES), Format('known=%s n=%d %s', [BoolToStr(U.Known, True), Length(U.Verdicts), U.Error]));
  Check('code.use.declared.two.up', V('tblFtrs').Instance.FromCode and (V('tblFtrs').State = asUnconverted) and (V('tblFtrs').DeclaringUnit = 'Base')
    and (V('tblFtrs').Instance.TypeName = 'TTable') and (V('tblFtrs').Instance.Line = LINE_FIRST));
  Check('code.use.chain.e2a', (Length(V('tblFtrs').Chain) = 1) and SameText(V('tblFtrs').Chain[0].PasPath, BASE_PAS) and (V('tblFtrs').Chain[0].Depth = DEPTH_BASE)
    and (Length(V('tblOps').Chain) = CHAIN_OPS) and SameText(V('tblOps').Chain[0].PasPath, MID_PAS));
  Check('code.use.unknown.dropped', V('lblNoSuch').Instance.Name = '');
  Check('code.use.own.field.dropped', V('qryOwn').Instance.Name = '');
  Check('code.use.note', InheritanceRowNote(U, True) = 'inherits 2 TTable instance(s) from Base -- convert it first (recommended)', InheritanceRowNote(U, True));
  Check('code.use.left.note', CodeUseLeftNote(U) = '2 inherited code use(s) left: ancestor Base not converted', CodeUseLeftNote(U));

  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(Rows, nil),
    FakeReader(['fx\Leaf.dfm', 'fx\Mid.dfm', 'fx\Base.dfm'], [BLOCK_LEAF_DFM, MID_DFM, BASE_DFM]),
    FakeCodeUses(['IndexName|tblFtrs|41'], False));
  Check('code.use.no.double.count', (Length(U.Verdicts) = 1) and not U.Verdicts[0].Instance.FromCode, Format('%d verdicts', [Length(U.Verdicts)]));
  Check('code.use.left.note.dfm.only', CodeUseLeftNote(U) = '');

  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(Rows, nil), Reader, FakeCodeUses([], True));
  Check('code.use.lookup.failed', not U.Known and (U.Error <> '') and (Length(U.Verdicts) = 0), U.Error);
  Check('code.use.lookup.failed.cause', ContainsText(U.Error, 'fake: refs unavailable'), U.Error);
  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(Rows, nil), Reader, nil);
  Check('code.use.not.asked', U.Known and (Length(U.Verdicts) = 0));

  // A walk that cannot decide (the index fails on TBaseDM) is unknown, never outside or dropped.
  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(['TLeafDM|' + LEAF_PAS + '|TMidDM', 'TMidDM|' + MID_PAS + '|TBaseDM', 'TBaseDM|!'], nil), Reader,
    FakeCodeUses(['IndexName|tblFtrs|41'], False));
  Check('code.use.walk.unknown', not U.Known and (Pos('TBaseDM', U.Error) > 0) and (Length(U.Verdicts) = 0), U.Error);
  // A converted ancestor's field no longer has the From type: not a use (E11).
  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(['TLeafDM|' + LEAF_PAS + '|TMidDM', 'TMidDM|' + MID_PAS + '|TBaseDM',
    'TBaseDM|' + BASE_PAS + '|TDataModule|tblFtrs:TFDTable'], nil), Reader, FakeCodeUses(['IndexName|tblFtrs|41'], False));
  Check('code.use.converted.dropped', U.Known and (Length(U.Verdicts) = 0), Format('n=%d %s', [Length(U.Verdicts), U.Error]));
  // The PRODUCT shape of a converted ancestor: the filtered Fields omit tblFtrs (now a
  // TFDTable) while Base.dfm still opens it with the To type -- no inherited use left.
  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(['TLeafDM|' + LEAF_PAS + '|TMidDM', 'TMidDM|' + MID_PAS + '|TBaseDM',
    'TBaseDM|' + BASE_PAS + '|TDataModule|tblOps:TTable'], nil),
    FakeReader(['fx\Leaf.dfm', 'fx\Mid.dfm', 'fx\Base.dfm'], [BARE_LEAF_DFM, MID_DFM, CONV_BASE_DFM]), FakeCodeUses(['IndexName|tblFtrs|41'], False));
  Check('code.use.converted.product.shape', U.Known and (Length(U.Verdicts) = 0), Format('n=%d %s', [Length(U.Verdicts), U.Error]));

  // An unusable (binary) ancestor .dfm: a name no ancestor declares is still decided from
  // Fields alone (Known); a declared name needs that .dfm for its chain (unknown).
  Reader:= FakeReader(['fx\Leaf.dfm', 'fx\Mid.dfm', 'fx\Base.dfm'], [BARE_LEAF_DFM, BINARY_DFM, BASE_DFM]);
  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(Rows, nil), Reader, FakeCodeUses(['Caption|lblNoSuch|60', 'ShowMessage||61'], False));
  Check('code.use.binary.dfm.nonfield.known', U.Known and (Length(U.Verdicts) = 0), Format('known=%s n=%d %s', [BoolToStr(U.Known, True), Length(U.Verdicts), U.Error]));
  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(Rows, nil), Reader, FakeCodeUses(['IndexName|tblFtrs|41'], False));
  Check('code.use.binary.dfm.field.unknown', not U.Known and (Pos('Mid.dfm', U.Error) > 0) and (Length(U.Verdicts) = 0), U.Error);

  // One AnalyzeUnit reads each ancestor .dfm once, however many names walk past it.
  Inner:= FakeReader(['fx\Leaf.dfm', 'fx\Mid.dfm', 'fx\Base.dfm'], [BARE_LEAF_DFM, MID_DFM, BASE_DFM]);
  Reads:= 0;
  Reader:= function(const APath: string; out AText: string): TDfmRead
    begin
      if SameText(APath, 'fx\Base.dfm') then
        Inc(Reads);
      Result:= Inner(APath, AText);
    end;
  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(Rows, nil), Reader, FakeCodeUses(['IndexName|tblFtrs|41', 'Post|tblOps|50'], False));
  Check('code.use.dfm.read.once', (Length(U.Verdicts) = N_USES) and (Reads = 1), Format('n=%d reads=%d', [Length(U.Verdicts), Reads]));

  // A leaf .dfm block with a NON-From type is no verdict; the code use then counts from
  // the ancestor's From-typed field.
  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(Rows, nil),
    FakeReader(['fx\Leaf.dfm', 'fx\Mid.dfm', 'fx\Base.dfm'], [NONFROM_LEAF_DFM, MID_DFM, BASE_DFM]), FakeCodeUses(['IndexName|tblFtrs|41'], False));
  Check('code.use.leaf.block.nonfrom', U.Known and (Length(U.Verdicts) = 1) and U.Verdicts[0].Instance.FromCode and (U.Verdicts[0].DeclaringUnit = 'Base'),
    Format('n=%d %s', [Length(U.Verdicts), U.Error]));

  // Names match case-insensitively, against Fields and between uses (first line kept).
  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(Rows, nil), Inner, FakeCodeUses(['IndexName|TBLFTRS|45', 'tblftrs||40'], False));
  Check('code.use.case.insensitive', (Length(U.Verdicts) = 1) and (U.Verdicts[0].DeclaringUnit = 'Base') and (U.Verdicts[0].Instance.Line = LINE_FIRST),
    Format('n=%d %s', [Length(U.Verdicts), U.Error]));
end;

{ C8: the class lookup reads `sql --json`'s POSITIONAL rows [path, parent] (measured
  on DMTEST 2026-10-05). One file = found (a forward declaration's second row in the
  same file is the same class); two files = ambiguous, never guessed. A name that is
  not a plain identifier never reaches the SQL. A truncated answer is a failure. }
procedure TestClassLookup;
const
  ONE = '{"schema":"sql/1","columns":[{"name":"path"},{"name":"c"}],"rows":[["C:\\DM\\dmCPData.pas","TdmlGlbReadings"]],"row_count":1}'
    + sLineBreak + '(loaded defaults from C:\Projects\.drag-lint.json)';
  NONE = '{"schema":"sql/1","rows":[],"row_count":0}';
  TWO  = '{"rows":[["C:\\a\\U.pas","TForm"],["C:\\b\\U.pas","TForm"]]}';
  FWD  = '{"rows":[["C:\\a\\U.pas",""],["C:\\a\\U.pas","TForm"]]}';
  CUT  = '{"rows":[["C:\\a\\U.pas","TForm"]],"row_count":1,"truncated":true}';
  OLD  = '{"rows":[["C:\\a\\U.pas","TForm"]],"row_count":1,"truncated":false,"stale":true,"stale_files":1}';
var
  P, A    : string;
  LAccepts: Boolean;
  LRejects: Boolean;
begin
  Check('lookup.rows.found', (ParseClassLookupRows(ONE, P, A) = cloFound) and (P = 'C:\DM\dmCPData.pas') and (A = 'TdmlGlbReadings'), P + ' ' + A);  // dl:ok hardcoded-absolute-path@4926 -- REVIEWED 2026-10-05 a path VALUE inside fixture JSON; nothing on disk is touched
  Check('lookup.rows.absent', (ParseClassLookupRows(NONE, P, A) = cloAbsent) and (P = ''));
  Check('lookup.rows.ambiguous', (ParseClassLookupRows(TWO, P, A) = cloAmbiguous) and (P = '') and (A = ''));
  Check('lookup.rows.forward.decl', (ParseClassLookupRows(FWD, P, A) = cloFound) and (A = 'TForm'), A);
  Check('lookup.rows.garbage', ParseClassLookupRows('FATAL: index locked', P, A) = cloFailed);
  Check('lookup.rows.truncated.failed', (ParseClassLookupRows(CUT, P, A) = cloFailed) and (P = ''));
  Check('lookup.rows.stale.failed', (ParseClassLookupRows(OLD, P, A) = cloFailed) and (P = ''));
  LAccepts:= IsPlainIdentifier('TdmlCPData') and IsPlainIdentifier('_T1');
  LRejects:= not (IsPlainIdentifier('') or IsPlainIdentifier('x'' OR 1=1') or IsPlainIdentifier('Unit.TFoo') or IsPlainIdentifier('1T'));
  Check('lookup.ident', LAccepts and LRejects);
end;

{ The C8 two-unit fixture: Anc.pas declares TAncForm (Label1: TLabel, object in
  Anc.dfm); ADescPas declares ADescClass = class(TAncForm) with ADescBody as its
  class body and ADescImpl after implementation; ADescDfm is its .dfm. }
procedure WriteC8Fixture(const ADir, ADescPas, ADescClass, ADescBody, ADescImpl, ADescDfm: string);
var
  LDescUnit, LDescForm: string;
begin
  LDescUnit:= TPath.GetFileNameWithoutExtension(ADescPas);
  LDescForm:= Copy(ADescClass, 2, MaxInt);
  TFile.WriteAllText(TPath.Combine(ADir, 'Fix.dpr'), 'program Fix;' + sLineBreak + 'uses' + sLineBreak + '  Vcl.Forms,' + sLineBreak +
    '  Anc in ''Anc.pas'' {AncForm},' + sLineBreak + '  ' + LDescUnit + ' in ''' + LDescUnit + '.pas'' {' + LDescForm + '};' + sLineBreak +
    'begin' + sLineBreak + 'end.' + sLineBreak, TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(ADir, 'Anc.pas'), 'unit Anc;' + sLineBreak + 'interface' + sLineBreak + 'uses' + sLineBreak +
    '  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, System.Classes;' + sLineBreak + 'type' + sLineBreak + '  TAncForm = class(TForm)' + sLineBreak +
    '    Label1: TLabel;' + sLineBreak + '  end;' + sLineBreak + 'implementation' + sLineBreak + '{$R *.dfm}' + sLineBreak + 'end.' + sLineBreak, TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(ADir, 'Anc.dfm'), 'object AncForm: TAncForm' + sLineBreak + '  Caption = ''Anc''' + sLineBreak +
    '  object Label1: TLabel' + sLineBreak + '    Caption = ''Hello''' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak, TEncoding.ASCII);
  TFile.WriteAllText(ADescPas, 'unit ' + LDescUnit + ';' + sLineBreak + 'interface' + sLineBreak + 'uses' + sLineBreak + '  System.Classes, Anc;' + sLineBreak +
    'type' + sLineBreak + '  ' + ADescClass + ' = class(TAncForm)' + sLineBreak + ADescBody + '  end;' + sLineBreak + 'implementation' + sLineBreak +
    '{$R *.dfm}' + sLineBreak + ADescImpl + 'end.' + sLineBreak, TEncoding.ASCII);
  TFile.WriteAllText(ChangeFileExt(ADescPas, '.dfm'), ADescDfm, TEncoding.ASCII);
end;

{ C8 live: a 2-unit fixture indexed by the test engine; LookupClass answers from the
  real type_ancestors / files tables and AnalyzeUnit (through the editor's own
  EngineClassLookup binder) + DiskTextReader find the declaring ancestor on disk. A
  missing --db is a FAILED lookup: the pinned 1.21.1 engine exits 2 ("--db #1 of 1
  does not exist ... Nothing was answered") and creates no file (measured 2026-10-05). }
procedure TestClassLookupLive;
var
  Exe, Dir, Db, DescPas, Output, P, A, E: string;
  Eng: TEngineAdapter;
  U  : TUnitInheritance;
  Pr : TTypePair;
begin
  Exe:= ResolveExe;
  if Exe = '' then
  begin
    Skip('lookup.live', 'no test engine: ' + GEngineWhy);
    Exit;
  end;
  Dir:= TPath.Combine(TPath.GetTempPath, 'c8lookup-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    DescPas:= TPath.Combine(Dir, 'Desc.pas');
    Db     := TPath.Combine(Dir, 'Fix.sqlite');
    WriteC8Fixture(Dir, DescPas, 'TDescForm', '', '',
      'inherited DescForm: TDescForm' + sLineBreak + '  inherited Label1: TLabel' + sLineBreak + '    Caption = ''Desc''' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak);
    Eng:= TEngineAdapter.Create(Exe, [Db]);
    try
      Check('lookup.live.index', Eng.IndexProject(TPath.Combine(Dir, 'Fix.dpr'), Db, Output) = 0, Output);
      Check('lookup.live.found', (Eng.LookupClass(Db, 'TDescForm', P, A, E) = cloFound) and SameText(P, DescPas) and (A = 'TAncForm'), P + ' ' + A + ' ' + E);
      Check('lookup.live.nocase', (Eng.LookupClass(Db, 'tancform', P, A, E) = cloFound) and SameText(P, TPath.Combine(Dir, 'Anc.pas')) and (A = 'TForm'),
        P + ' ' + A + ' ' + E);
      Check('lookup.live.library.absent', Eng.LookupClass(Db, 'TForm', P, A, E) = cloAbsent, E);
      Check('lookup.live.injection.absent', Eng.LookupClass(Db, 'x'' OR ''1''=''1', P, A, E) = cloAbsent);
      Check('lookup.live.bad.db.failed', (Eng.LookupClass(TPath.Combine(Dir, 'none.sqlite'), 'TDescForm', P, A, E) = cloFailed) and (E <> '')
        and not TFile.Exists(TPath.Combine(Dir, 'none.sqlite')), E);
      Pr.FromType:= 'TLabel';
      Pr.ToType  := 'TStaticText';
      U:= AnalyzeUnit(DescPas, [Pr], EngineClassLookup(Eng, Db, [Pr]), DiskTextReader());
      Check('lookup.live.analysis', U.Known and (Length(U.Verdicts) = 1) and (U.Verdicts[0].State = asUnconverted) and (U.Verdicts[0].DeclaringUnit = 'Anc'),
        Format('known=%s n=%d %s', [BoolToStr(U.Known, True), Length(U.Verdicts), U.Error]));
      U:= AnalyzeUnit(DescPas, [Pr], EngineClassLookup(Eng, TPath.Combine(Dir, 'none.sqlite'), [Pr]), DiskTextReader());
      // The engine's own text ("--db #1 of 1 does not exist") reaches the unit's Error.
      Check('lookup.live.analysis.bad.db.unknown', not U.Known and ContainsText(U.Error, 'TDescForm') and ContainsText(U.Error, 'does not exist')
        and ContainsText(U.Error, 'none.sqlite'), U.Error);
    finally
      Eng.Free;
    end; // try
  finally
    TDirectory.Delete(Dir, True);
  end; // try
end;

{ C8 E10: convert-apply's apply/1 inherited[] (spec N1 key names) is read into
  TApplyRow.InheritedLeft; a converted row's note lists what was left ONLY when the
  engine reports inherited_instances; a refusal stays a refusal (today's handling).
  E11: ancestor then descendant, each unit reindexed before its first book. }
procedure TestInheritedApply;
const
  // The engine's own reason texts (DRagLint.Convert.Apply, 1.22.0).
  REASON_PTD = 'declared in PathToData, which still has TTable -- convert PathToData first (recommended)';
  REASON_LIB = 'declaring ancestor not found (no ancestor .dfm of TLeafDM declares qryLib) -- convert it from its own project';
  REASON_ANC = 'declared in Anc, which already has TStaticText -- retyping an inherited instance is not supported yet';
  INH_JSON ='{"schema":"apply/1","ok":true,"error":"","rule_errors":[],"edits_count":2,"converted":[],"todos":[],"reemit_notes":[],"warnings":[],'
    + '"inherited":[{"name":"tblFtrs","type":"TTable","line":4,"ancestor_unit":"PathToData","ancestor_state":"unconverted","reason":"' + REASON_PTD + '"},'
    + '{"name":"tblOps","type":"TTable","line":9,"ancestor_unit":"PathToData","ancestor_state":"unconverted","reason":"' + REASON_PTD + '"},'
    + '{"name":"qryLib","type":"TQuery","line":12,"ancestor_unit":"","ancestor_state":"outside","reason":"' + REASON_LIB + '"}]}';
  OLD_JSON = '{"schema":"apply/1","ok":true,"error":"","rule_errors":[],"edits_count":1,"converted":[],"todos":[],"reemit_notes":[],"warnings":[]}';
  // Engine 1.22.0's own output for a .dfm holding ONLY inherited instances (captured
  // 2026-10-06 on the E11 fixture after its ancestor was converted): ok, exit 0, no edit.
  SKIPPED_JSON = '{"schema":"apply/1","mode":"apply","ok":true,"error":"","refused":false,"reason":"","rule_errors":[],"edits_count":0,"converted":[],'
    + '"todos":[],"reemit_notes":[],"warnings":["line 2: warning: inherited instance Label1: TLabel skipped -- ' + REASON_ANC + '"],'
    + '"component_part":"skipped-no-instances","inherited":[{"name":"Label1","type":"TLabel","line":2,"ancestor_unit":"Anc",'
    + '"ancestor_state":"converted","reason":"' + REASON_ANC + '"}]}';
  // Fix round 1: the inherited warning is no longer counted in "remaining" (it is the
  // "left" note's), and without inherited_retype the note says the unit may break.
  NOTE_SKIPPED = '0 edit(s), 0 remaining for manual work; no component of its own to convert; '
    + '1 inherited instance(s) left: ancestor Anc converted -- this unit still has TLabel there and may not compile or load '
    + 'until the engine can retype inherited instances (N2)';
  NOTE_SKIPPED_RETYPE = '0 edit(s), 0 remaining for manual work; no component of its own to convert; '
    + '1 inherited instance(s) left: ancestor Anc converted -- retype pending (engine N2)';
  // One inherited warning and one other: only the other is manual remainder.
  MIXED_JSON = '{"schema":"apply/1","ok":true,"edits_count":1,"warnings":["line 2: warning: inherited instance Label1: TLabel skipped -- x",'
    + '"line 9: warning: something else"],"inherited":[{"name":"Label1","type":"TLabel","line":2,"ancestor_unit":"Anc","ancestor_state":"unconverted","reason":"x"}]}';
  // No inherited[] (not this contract): an inherited-shaped warning is still remainder.
  NO_LIST_JSON = '{"schema":"apply/1","ok":true,"edits_count":1,"warnings":["line 2: warning: inherited instance Label1: TLabel skipped -- x"]}';
  // A non-object entry is skipped; a wrongly-typed field reads as its default.
  BAD_ITEMS_JSON = '{"schema":"apply/1","ok":true,"edits_count":1,"inherited":[5,"x",null,{"name":"tblA","line":"four","type":7}]}';
  BAD_KEY_JSON   = '{"schema":"apply/1","ok":true,"edits_count":1,"inherited":{"name":"tblA"}}';
  REFUSED_JSON = '{"schema":"apply/1","ok":false,"refused":true,"reason":"inherited instances of TTable are not converted yet -- unit not changed","rule_errors":[],"edits_count":0}';
  ORIG = 'unit U;' + sLineBreak + 'interface' + sLineBreak + 'implementation' + sLineBreak + 'end.' + sLineBreak;
  LINE_TBL = 4;
  ITEMS    = 3;
  NOTE_LEFT = '2 inherited instance(s) left: ancestor PathToData not converted; 1 inherited instance(s) left: ancestor not determinable -- ' + REASON_LIB;
var
  Row : TApplyRow;
  Bad : TApplyRow;
  Dir, Anc, Desc: string;
  Rows: TArray<TConvertRow>;
  Log : TStringList;
  Index: TIndexFn;

  function ApplyWith(const AJson: string): TApplyFn;
  var
    LJson: string;
  begin
    LJson:= AJson;
    Result:= function(const AUnitPas, ARulesFile: string; out AJson2: string): Integer
      begin
        AJson2:= LJson;
        Result:= 0;
      end;
  end;

begin
  Row:= ParseApplyJson(INH_JSON);
  Check('apply.inherited.parsed', Row.Ok and (Length(Row.InheritedLeft) = ITEMS), IntToStr(Length(Row.InheritedLeft)));
  if Length(Row.InheritedLeft) = ITEMS then
  begin
    Check('apply.inherited.fields', (Row.InheritedLeft[0].Name = 'tblFtrs') and (Row.InheritedLeft[0].TypeName = 'TTable') and (Row.InheritedLeft[0].Line = LINE_TBL));
    Check('apply.inherited.fields.ancestor', (Row.InheritedLeft[0].AncestorUnit = 'PathToData') and (Row.InheritedLeft[0].AncestorState = 'unconverted')
      and (Row.InheritedLeft[2].AncestorState = 'outside'));
  end;
  Check('apply.inherited.absent.key', Length(ParseApplyJson(OLD_JSON).InheritedLeft) = 0);
  Bad:= ParseApplyJson(BAD_ITEMS_JSON);
  Check('apply.inherited.malformed.items', Bad.Ok and (Length(Bad.InheritedLeft) = 1) and (Bad.InheritedLeft[0].Name = 'tblA') and (Bad.InheritedLeft[0].Line = 0)
    and (Bad.InheritedLeft[0].TypeName = ''), Format('ok=%s n=%d %s', [BoolToStr(Bad.Ok, True), Length(Bad.InheritedLeft), Bad.Error]));
  Bad:= ParseApplyJson(BAD_KEY_JSON);
  Check('apply.inherited.malformed.key', Bad.Ok and (Length(Bad.InheritedLeft) = 0), Bad.Error);
  Check('apply.inherited.note', InheritedLeftNote(Row.InheritedLeft, True) = NOTE_LEFT, InheritedLeftNote(Row.InheritedLeft, True));
  Check('apply.inherited.note.empty', InheritedLeftNote(nil, True) = '');
  if Length(Row.InheritedLeft) = ITEMS then
  begin
    Check('apply.inherited.report', InheritedReportNote(Row.InheritedLeft[0], True) = 'tblFtrs: TTable line 4 -- ancestor PathToData not converted (' + REASON_PTD + ')',
      InheritedReportNote(Row.InheritedLeft[0], True));
    // outside: the reason is already in the words, so it is not repeated in parentheses.
    Check('apply.inherited.report.outside', InheritedReportNote(Row.InheritedLeft[2], True) = 'qryLib: TQuery line 12 -- ancestor not determinable -- ' + REASON_LIB,
      InheritedReportNote(Row.InheritedLeft[2], True));
  end;
  Bad:= ParseApplyJson(SKIPPED_JSON);
  Check('apply.component.part', Bad.Ok and (Bad.ComponentPart = 'skipped-no-instances') and (ParseApplyJson(OLD_JSON).ComponentPart = ''), Bad.ComponentPart);
  Check('apply.note.skipped', ConvertedRowNote(Bad, True, False) = NOTE_SKIPPED, ConvertedRowNote(Bad, True, False));
  Check('apply.note.skipped.retype', ConvertedRowNote(Bad, True, True) = NOTE_SKIPPED_RETYPE, ConvertedRowNote(Bad, True, True));
  Check('apply.note.plain', ConvertedRowNote(ParseApplyJson(OLD_JSON), True, False) = '1 edit(s), 0 remaining for manual work', ConvertedRowNote(ParseApplyJson(OLD_JSON), True, False));
  Check('apply.note.skipped.gated', ConvertedRowNote(Bad, False, False) = '0 edit(s), 0 remaining for manual work; no component of its own to convert', ConvertedRowNote(Bad, False, False));
  Check('apply.remainder.excludes.inherited', (Length(Bad.Remainder) = 0) and (Length(ParseApplyJson(MIXED_JSON).Remainder) = 1)
    and (ParseApplyJson(MIXED_JSON).Remainder[0] = 'line 9: warning: something else'), string.Join(' | ', ParseApplyJson(MIXED_JSON).Remainder));
  Check('apply.remainder.no.list.keeps', Length(ParseApplyJson(NO_LIST_JSON).Remainder) = 1);

  Dir:= TPath.Combine(TPath.GetTempPath, 'c8apply-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  Log:= TStringList.Create;
  try
    Anc := TPath.Combine(Dir, 'Anc.pas');
    Desc:= TPath.Combine(Dir, 'Desc.pas');
    TFile.WriteAllText(Anc, ORIG, TEncoding.ASCII);
    TFile.WriteAllText(Desc, ORIG, TEncoding.ASCII);
    Index:= function(out AOutput: string): Integer
      begin
        AOutput:= '';
        Log.Add('index');
        Result:= 0;
      end;

    Rows:= RunConversionUnits([Desc], ['A.rules'], ApplyWith(INH_JSON), Index, nil, nil, True);
    Check('runner.inherited.converted', (Length(Rows) = 1) and (Rows[0].Status = csConverted) and Rows[0].Note.EndsWith('; ' + NOTE_LEFT),
      if Length(Rows) = 1 then Rows[0].Note else IntToStr(Length(Rows)));
    Rows:= RunConversionUnits([Desc], ['A.rules'], ApplyWith(INH_JSON), Index, nil, nil, False);
    Check('runner.inherited.gated', (Length(Rows) = 1) and (Rows[0].Status = csConverted) and (Pos('inherited', Rows[0].Note) = 0),
      if Length(Rows) = 1 then Rows[0].Note else IntToStr(Length(Rows)));
    Rows:= RunConversionUnits([Desc], ['A.rules'], ApplyWith(REFUSED_JSON), Index, nil, nil, True);
    Check('runner.inherited.refusal.kept', (Length(Rows) = 1) and (Rows[0].Status = csRefused));
    // Engine 1.22.0: a .dfm with ONLY inherited instances is ok + exit 0 -- a converted row, never a failure.
    Rows:= RunConversionUnits([Desc], ['A.rules'], ApplyWith(SKIPPED_JSON), Index, nil, nil, True);
    Check('runner.inherited.skipped.no.instances', (Length(Rows) = 1) and (Rows[0].Status = csConverted) and (Rows[0].Note = NOTE_SKIPPED),
      if Length(Rows) = 1 then Rows[0].Note else IntToStr(Length(Rows)));
    Rows:= RunConversionUnits([Desc], ['A.rules'], ApplyWith(SKIPPED_JSON), Index, nil, nil, True, True);
    Check('runner.inherited.retype.passed', (Length(Rows) = 1) and (Rows[0].Note = NOTE_SKIPPED_RETYPE),
      if Length(Rows) = 1 then Rows[0].Note else IntToStr(Length(Rows)));

    Log.Clear;
    Rows:= RunConversionUnits([Anc, Desc], ['A.rules'],
      function(const AUnitPas, ARulesFile: string; out AJson: string): Integer
      begin
        Log.Add('apply ' + ExtractFileName(AUnitPas));
        AJson := OLD_JSON;
        Result:= 0;
      end, Index, nil, nil, True);
    Check('runner.e11.two.rows', Length(Rows) = 2, IntToStr(Length(Rows)));
    Check('runner.e11.ancestor.then.reindexed.descendant', Log.CommaText = 'index,"apply Anc.pas",index,index,"apply Desc.pas",index', Log.CommaText);
  finally
    Log.Free;
    TDirectory.Delete(Dir, True);
  end; // try
end;

{ C8 E11 live, ONLY against an engine that reports inherited_instances (1.22.0 on):
  Anc then Desc in one run; Anc's Label1 is retyped, Desc's inherited Label1 is left
  as it is (N1 skips it; retype is N2) and reported as left with state converted. }
procedure TestInheritedRunLive;
var
  Exe, Dir, Db, Dpr, AncPas, DescPas, Book, Output: string;
  DescDfm: string;
  Eng : TEngineAdapter;
  Job : TConvertJob;
  Rows: TArray<TConvertRow>;
  LShape: Boolean;
begin
  Exe:= ResolveExe;
  if (Exe = '') or not TFile.Exists(LibWin64) then
  begin
    Skip('inherited.live', 'exe or library-Win64 absent: ' + GEngineWhy);
    Exit;
  end;
  Eng:= TEngineAdapter.Create(Exe, []);
  try
    if not Eng.HasCapability(CAPABILITY_INHERITED_INSTANCES) then
    begin
      Skip('inherited.live', 'engine lacks ' + CAPABILITY_INHERITED_INSTANCES);
      Exit;
    end;
  finally
    Eng.Free;
  end; // try
  Dir:= TPath.Combine(TPath.GetTempPath, 'c8run-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    Dpr    := TPath.Combine(Dir, 'Fix.dpr');
    AncPas := TPath.Combine(Dir, 'Anc.pas');
    DescPas:= TPath.Combine(Dir, 'Desc.pas');
    Db     := TPath.Combine(Dir, 'Fix.sqlite');
    Book   := TPath.Combine(Dir, 'Fix.rules');
    TFile.WriteAllText(Dpr, 'program Fix;' + sLineBreak + 'uses' + sLineBreak + '  Vcl.Forms,' + sLineBreak + '  Anc in ''Anc.pas'' {AncForm},' + sLineBreak +
      '  Desc in ''Desc.pas'' {DescForm};' + sLineBreak + 'begin' + sLineBreak + 'end.' + sLineBreak, TEncoding.ASCII);
    TFile.WriteAllText(AncPas, 'unit Anc;' + sLineBreak + 'interface' + sLineBreak + 'uses' + sLineBreak + '  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, System.Classes;' + sLineBreak +
      'type' + sLineBreak + '  TAncForm = class(TForm)' + sLineBreak + '    Label1: TLabel;' + sLineBreak + '  end;' + sLineBreak + 'implementation' + sLineBreak +
      '{$R *.dfm}' + sLineBreak + 'end.' + sLineBreak, TEncoding.ASCII);
    TFile.WriteAllText(ChangeFileExt(AncPas, '.dfm'), 'object AncForm: TAncForm' + sLineBreak + '  object Label1: TLabel' + sLineBreak +
      '    Caption = ''Hello''' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak, TEncoding.ASCII);
    TFile.WriteAllText(DescPas, 'unit Desc;' + sLineBreak + 'interface' + sLineBreak + 'uses' + sLineBreak + '  Anc;' + sLineBreak + 'type' + sLineBreak +
      '  TDescForm = class(TAncForm)' + sLineBreak + '  end;' + sLineBreak + 'implementation' + sLineBreak + '{$R *.dfm}' + sLineBreak + 'end.' + sLineBreak, TEncoding.ASCII);
    DescDfm:= 'inherited DescForm: TDescForm' + sLineBreak + '  inherited Label1: TLabel' + sLineBreak + '    Caption = ''Desc''' + sLineBreak + '  end' + sLineBreak +
      'end' + sLineBreak;
    TFile.WriteAllText(ChangeFileExt(DescPas, '.dfm'), DescDfm, TEncoding.ASCII);
    TFile.WriteAllText(Book, '#convert Vcl.StdCtrls.TLabel -> Vcl.StdCtrls.TStaticText, Vcl.StdCtrls' + sLineBreak + '#link Caption <- Caption' + sLineBreak, TEncoding.ASCII);
    Eng:= TEngineAdapter.Create(Exe, [Db, LibWin64]);
    try
      Check('inherited.live.index', Eng.IndexProject(Dpr, Db, Output) = 0, Output);
      Job:= Default(TConvertJob);
      Job.Units             := [AncPas, DescPas];
      Job.Books             := [Book];
      Job.Dbs               := [Db, LibWin64];
      Job.ProjectDb         := Db;
      Job.ProjectFile       := Dpr;
      Job.InheritedSupported:= True;
      Job.RetypeSupported   := Eng.HasCapability(CAPABILITY_INHERITED_RETYPE);
      Rows:= RunConversion(Job, Eng, nil, nil);
      Check('inherited.live.both.converted', (Length(Rows) = 2) and (Rows[0].Status = csConverted) and (Rows[1].Status = csConverted), Format('%d rows', [Length(Rows)]));
      Check('inherited.live.ancestor.retyped', Pos('object Label1: TStaticText', TFile.ReadAllText(ChangeFileExt(AncPas, '.dfm'))) > 0,
        TFile.ReadAllText(ChangeFileExt(AncPas, '.dfm')));
      // Engine N1 (1.22.0): the descendant's inherited instance is SKIPPED even though its
      // ancestor now has the To type -- retyping it is N2. The .dfm stays byte-unchanged.
      // (Corrected 2026-10-06 from a real run: the Task 6 guess expected it retyped.)
      // THIS CHECK PINS N1 BEHAVIOUR ON PURPOSE: when the engine ships N2 (retype) it goes
      // RED -- that is the signal to re-adopt (retyped descendant, the retype texts), not a
      // regression.
      Check('inherited.live.descendant.unchanged', TFile.ReadAllText(ChangeFileExt(DescPas, '.dfm')) = DescDfm, TFile.ReadAllText(ChangeFileExt(DescPas, '.dfm')));
      LShape:= (Length(Rows) = 2) and (Length(Rows[1].Apply.InheritedLeft) = 1);
      Check('inherited.live.descendant.left', LShape and (Rows[1].Apply.InheritedLeft[0].Name = 'Label1') and (Rows[1].Apply.InheritedLeft[0].AncestorUnit = 'Anc')
        and (Rows[1].Apply.InheritedLeft[0].AncestorState = 'converted') and (Rows[1].Apply.ComponentPart = 'skipped-no-instances'),
        if Length(Rows) = 2 then Format('%d left, part=%s', [Length(Rows[1].Apply.InheritedLeft), Rows[1].Apply.ComponentPart]) else '');
      Check('inherited.live.descendant.note', (Length(Rows) = 2) and not Job.RetypeSupported and Rows[1].Note.EndsWith('; no component of its own to convert; '
        + '1 inherited instance(s) left: ancestor Anc converted -- this unit still has TLabel there and may not compile or load until the engine can '
        + 'retype inherited instances (N2)'), if Length(Rows) = 2 then Rows[1].Note else '');
    finally
      Eng.Free;
    end; // try
  finally
    TDirectory.Delete(Dir, True);
  end; // try
end;

{ C8 E2b engine reads: positional rows [name, type] and [name, receiver, line]. }
procedure TestCodeRefs;
const
  FIELDS_JSON = '{"rows":[["tblFtrs","TTable"],["qryX","TQuery"]]}' + sLineBreak + '(loaded defaults from C:\x.json)';
  REFS_JSON   = '{"rows":[["Post","tblFtrs",3371],["tblOps",null,3380],["Open","Self.qryX",3390]]}';
  LINE_FIRST = 3371;
  REF_ROWS   = 3;
var
  Fields : TArray<TEngineField>;
  Refs   : TArray<TEngineCodeRef>;
  LParsed: Boolean;
begin
  Check('fields.rows', ParseFieldRows(FIELDS_JSON, Fields) and (Length(Fields) = 2) and (Fields[0].Name = 'tblFtrs') and (Fields[1].TypeName = 'TQuery'));
  Check('fields.rows.garbage', not ParseFieldRows('FATAL', Fields) and (Length(Fields) = 0));
  LParsed:= ParseCodeRefRows(REFS_JSON, Refs) and (Length(Refs) = REF_ROWS);
  Check('refs.rows', LParsed and (Refs[0].Receiver = 'tblFtrs') and (Refs[0].Line = LINE_FIRST) and (Refs[1].Name = 'tblOps') and (Refs[1].Receiver = ''));
  Check('refs.rows.garbage', not ParseCodeRefRows('', Refs));
  Check('refs.rows.stale', not ParseCodeRefRows('{"rows":[["Post","tblFtrs",1]],"stale":true,"stale_files":2}', Refs) and (Length(Refs) = 0));
  Check('sql.quote', SqlQuoted('C:\a''b\U.pas') = '''C:\a''''b\U.pas''');  // dl:ok hardcoded-absolute-path@336f -- REVIEWED 2026-10-05 quoting test text; nothing on disk is touched
end;

{ The identifiers a ListCodeRefs answer stands for (CodeUseName per row). }
function CodeNames(const ARefs: TArray<TEngineCodeRef>): TArray<string>;
begin
  Result:= nil;
  for var LRef: TEngineCodeRef in ARefs do
    Result:= Result + [CodeUseName(LRef.Name, LRef.Receiver)];
end;

{ C8 E2b live: a descendant whose .dfm has NO block for Label1 but whose FormCreate
  writes Label1.Caption, and has a LOCAL Label2. The index must answer the field (on
  TAncForm) and the use (in TDesc2Form's method), never the local, and AnalyzeUnit
  must report the use as an inherited code use. }
procedure TestCodeRefsLive;
var
  Exe, Dir, Db, DescPas, AncPas, Output, Err: string;
  Eng   : TEngineAdapter;
  Fields: TArray<TEngineField>;
  Refs  : TArray<TEngineCodeRef>;  // dl:ok duplicate-code@e1ac -- REVIEWED 2026-10-05 the live-test skeleton (engine skip, private temp dir, fixture, adapter, try/finally) is repeated on purpose so each live test reads on its own; the shared fixture text is already WriteC8Fixture
  U     : TUnitInheritance;
  Pr    : TTypePair;
  LUsed : Boolean;
begin
  Exe:= ResolveExe;
  if Exe = '' then
  begin
    Skip('coderefs.live', 'no test engine: ' + GEngineWhy);
    Exit;
  end;
  Dir:= TPath.Combine(TPath.GetTempPath, 'c8code-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    DescPas:= TPath.Combine(Dir, 'Desc2.pas');
    Db     := TPath.Combine(Dir, 'Fix.sqlite');
    WriteC8Fixture(Dir, DescPas, 'TDesc2Form', '    procedure FormCreate(Sender: TObject);' + sLineBreak,
      'procedure TDesc2Form.FormCreate(Sender: TObject);' + sLineBreak + 'var' + sLineBreak + '  Label2: Integer;' + sLineBreak +
      'begin' + sLineBreak + '  Label1.Caption:= ''Two'';' + sLineBreak + '  Label2:= 0;' + sLineBreak + '  Tag:= Label2;' + sLineBreak + 'end;' + sLineBreak,
      'inherited Desc2Form: TDesc2Form' + sLineBreak + '  OnCreate = FormCreate' + sLineBreak + 'end' + sLineBreak);
    Eng:= TEngineAdapter.Create(Exe, [Db]);
    try
      Check('coderefs.live.index', Eng.IndexProject(TPath.Combine(Dir, 'Fix.dpr'), Db, Output) = 0, Output);
      AncPas:= TPath.Combine(Dir, 'Anc.pas');
      Check('coderefs.live.fields', Eng.ListClassFields(Db, 'TAncForm', AncPas, ['TLabel'], Fields, Err) and (Length(Fields) = 1) and (Fields[0].Name = 'Label1'), Err);
      Check('coderefs.live.fields.filtered', Eng.ListClassFields(Db, 'TAncForm', AncPas, ['TTable'], Fields, Err) and (Length(Fields) = 0), Err);
      Check('coderefs.live.fields.other.file', Eng.ListClassFields(Db, 'TAncForm', DescPas, ['TLabel'], Fields, Err) and (Length(Fields) = 0), Err);
      LUsed:= False;
      if Eng.ListCodeRefs(Db, DescPas, 'TDesc2Form', Refs, Err) then
        for var LRef: TEngineCodeRef in Refs do
          if SameText(CodeUseName(LRef.Name, LRef.Receiver), 'Label1') then
            LUsed:= True;
      Check('coderefs.live.use.found', LUsed, Format('%d refs %s', [Length(Refs), Err]));
      Check('coderefs.live.local.ignored', (Length(Refs) > 0) and not MatchText('Label2', CodeNames(Refs)), string.Join(',', CodeNames(Refs)));
      Check('coderefs.live.bad.db.failed', not Eng.ListCodeRefs(TPath.Combine(Dir, 'none.sqlite'), DescPas, 'TDesc2Form', Refs, Err) and (Err <> ''), Err);
      Check('coderefs.live.unit.not.indexed.failed', not Eng.ListCodeRefs(Db, TPath.Combine(Dir, 'Nope.pas'), 'TDesc2Form', Refs, Err)
        and ContainsText(Err, 'not in the index'), Err);
      Pr.FromType:= 'TLabel';
      Pr.ToType  := 'TStaticText';
      U:= AnalyzeUnit(DescPas, [Pr], EngineClassLookup(Eng, Db, [Pr]), DiskTextReader(), EngineCodeUses(Eng, Db));
      Check('coderefs.live.analysis', U.Known and (Length(U.Verdicts) = 1) and U.Verdicts[0].Instance.FromCode and (U.Verdicts[0].DeclaringUnit = 'Anc'),
        Format('known=%s n=%d %s', [BoolToStr(U.Known, True), Length(U.Verdicts), U.Error]));
      // A unit edited after it was indexed: the engine answers "stale": true, and a C8
      // read refuses it (a stale DB is not authoritative) -- measured on 1.21.1.
      TFile.AppendAllText(DescPas, '// edited after indexing' + sLineBreak, TEncoding.ASCII);
      TFile.SetLastWriteTime(DescPas, Now + 1 / MinsPerDay);
      Check('coderefs.live.stale.failed', not Eng.ListCodeRefs(Db, DescPas, 'TDesc2Form', Refs, Err) and ContainsText(Err, 'stale'), Err);
    finally
      Eng.Free;
    end; // try
  finally
    TDirectory.Delete(Dir, True);
  end; // try
end;

{ An analysis the index could not decide (Known = False, AError). }
function UnknownUnit(const APas, AError: string): TUnitInheritance;
begin
  Result:= Default(TUnitInheritance);
  Result.UnitPas:= APas;
  Result.Error  := AError;
end;

{ A decided analysis with no verdicts. }
function FreshUnit(const APas: string): TUnitInheritance;
begin
  Result:= Default(TUnitInheritance);
  Result.UnitPas:= APas;
  Result.Known  := True;
end;

{ C8 Task 6, analysis pass: one .dfm read per PASS (not per unit), a cancel makes the
  unit unknown with "cancelled" without asking the index, and the status text for the
  units the analysis could not decide. ConvertTab.pas is outside this closure. }
procedure TestInheritanceTabAnalysis;
const
  LEAF_DFM  = 'inherited LeafDM: TLeafDM' + sLineBreak + '  inherited tblFtrs: TTable' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  LEAF2_DFM = 'inherited Leaf2DM: TLeaf2DM' + sLineBreak + '  inherited tblFtrs: TTable' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  BASE_DFM  = 'object BaseDM: TBaseDM' + sLineBreak + '  object tblFtrs: TTable' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  N_UNITS   = 2;
var
  P       : TTypePair;
  Rows    : TArray<string>;
  Inner   : TDfmTextReader;
  BaseRead: Integer;
  Calls   : TStringList;
  Units   : TArray<TUnitInheritance>;
  U       : TUnitInheritance;
  Uses1   : TArray<TCodeUse>;
  Err     : string;
  LOrder  : Boolean;
  LKnown  : Boolean;
begin
  P.FromType:= 'TTable';
  P.ToType  := 'TFDTable';
  Rows:= ['TLeafDM|fx\Leaf.pas|TBaseDM', 'TLeaf2DM|fx\Leaf2.pas|TBaseDM', 'TBaseDM|fx\Base.pas|TDataModule'];
  Inner:= FakeReader(['fx\Leaf.dfm', 'fx\Leaf2.dfm', 'fx\Base.dfm'], [LEAF_DFM, LEAF2_DFM, BASE_DFM]);
  BaseRead:= 0;
  Units:= AnalyzeUnits(['fx\Leaf.pas', 'fx\Leaf2.pas'], [P], FakeLookup(Rows, nil),
    function(const APath: string; out AText: string): TDfmRead
    begin
      if SameText(APath, 'fx\Base.dfm') then
        Inc(BaseRead);
      Result:= Inner(APath, AText);
    end);
  LOrder:= (Length(Units) = N_UNITS) and (Units[0].UnitPas = 'fx\Leaf.pas') and (Units[1].UnitPas = 'fx\Leaf2.pas');
  LKnown:= LOrder and Units[0].Known and Units[1].Known and (Length(Units[0].Verdicts) = 1) and (Length(Units[1].Verdicts) = 1);
  Check('tab.analyze.units.order', LKnown, IntToStr(Length(Units)));
  Check('tab.analyze.units.one.read.per.pass', BaseRead = 1, IntToStr(BaseRead));

  Calls:= TStringList.Create;
  try
    U:= AnalyzeUnit('fx\Leaf.pas', [P], CancellableLookup(FakeLookup(Rows, Calls), function: Boolean begin Result:= True; end), Inner);
    Check('tab.cancel.unknown', not U.Known and ContainsText(U.Error, ANALYSIS_CANCELLED) and (Length(U.Verdicts) = 0), U.Error);
    Check('tab.cancel.index.not.asked', Calls.Count = 0, Calls.CommaText);
    U:= AnalyzeUnit('fx\Leaf.pas', [P], CancellableLookup(FakeLookup(Rows, Calls), function: Boolean begin Result:= False; end), Inner);
    Check('tab.cancel.not.passes.through', U.Known and (Length(U.Verdicts) = 1) and (Calls.Count > 0), U.Error);
  finally
    Calls.Free;
  end; // try
  Check('tab.cancel.code.uses', not CancellableCodeUses(FakeCodeUses(['tblFtrs||40'], False), function: Boolean begin Result:= True; end)('fx\Leaf.pas', 'TLeafDM', Uses1, Err)
    and (Err = ANALYSIS_CANCELLED) and (Length(Uses1) = 0), Err);
  Check('tab.cancel.code.uses.not', CancellableCodeUses(FakeCodeUses(['tblFtrs||40'], False), function: Boolean begin Result:= False; end)('fx\Leaf.pas', 'TLeafDM', Uses1, Err)
    and (Length(Uses1) = 1), Err);

  Check('tab.unknown.text.none', UnknownUnitsText([FreshUnit('a\A.pas'), UnknownUnit('a\B.pas', '')]) = '');
  Check('tab.unknown.text.first.plus.more', UnknownUnitsText([FreshUnit('a\A.pas'), UnknownUnit('a\B.pas', 'boom'), UnknownUnit('a\C.pas', 'bang'), UnknownUnit('a\D.pas', 'pow')])
    = 'B.pas: boom (+2 more)', UnknownUnitsText([UnknownUnit('a\B.pas', 'boom'), UnknownUnit('a\C.pas', 'bang'), UnknownUnit('a\D.pas', 'pow')]));
end;

{ C8 Task 6 fix round 1: Convert's gate after its inherited-instance check (cancelled
  = stop; any unit unchecked = ask once; else run), one code-use note per unit (not
  per book), and the report's 8-column `inherited left` lines. }
procedure TestInheritanceTabGate;
const
  REPORT_COLS = 8;
  NOTE_COL    = REPORT_COLS - 1; // the Note column is the last
  INH_JSON = '{"schema":"apply/1","ok":true,"error":"","rule_errors":[],"edits_count":2,"converted":[],"todos":[],"reemit_notes":[],"warnings":[],'
    + '"inherited":[{"name":"tblFtrs","type":"TTable","line":4,"ancestor_unit":"PathToData","ancestor_state":"unconverted","reason":"ancestor not converted"},'
    + '{"name":"qryLib","type":"TQuery","line":12,"ancestor_unit":"LibForms","ancestor_state":"outside","reason":"ancestor not in any --db"}]}';
var
  Q      : string;
  Row    : TConvertRow;
  Earlier: TConvertRow;
  Lines  : TArray<string>;
  Cols   : TArray<string>;
  LShape : Boolean;
begin
  Check('tab.gate.cancelled', (InheritanceGate(True, [UnknownUnit('a\A.pas', 'boom')], 'boom', Q) = igCancelled) and (Q = ''), Q);
  Check('tab.gate.cancelled.text', GATE_CANCELLED_TEXT = 'Convert cancelled: the inherited-instance check was cancelled.');
  Check('tab.gate.proceed', (InheritanceGate(False, [FreshUnit('a\A.pas'), UnknownUnit('a\B.pas', '')], '', Q) = igProceed) and (Q = ''), Q);
  Check('tab.gate.ask.units', (InheritanceGate(False, [FreshUnit('a\A.pas'), UnknownUnit('a\B.pas', 'x'), UnknownUnit('a\C.pas', 'y')], 'x', Q) = igAsk)
    and (Q = 'Could not check inherited instances for B.pas, C.pas -- convert anyway?'), Q);
  Check('tab.gate.ask.error.only', (InheritanceGate(False, [FreshUnit('a\A.pas')], 'Fix.rules: locked', Q) = igAsk)
    and (Q = 'Could not check inherited instances for the listed units -- convert anyway?'), Q);
  Check('tab.gate.stop.text', InheritanceGateStopText('boom') = 'Convert cancelled: inherited instances could not be checked -- boom', InheritanceGateStopText('boom'));
  // M2: a drop under a run, the analysis or one of its prompts is refused (OLE delivers
  // drops inside a MessageDlg's modal loop); a run outranks a check.
  Check('tab.add.refused.running', SourcesAddRefusal(True, False) = 'A conversion is running -- sources cannot be added until it finishes.', SourcesAddRefusal(True, False));
  Check('tab.add.refused.running.wins', SourcesAddRefusal(True, True) = SourcesAddRefusal(True, False), SourcesAddRefusal(True, True));
  Check('tab.add.refused.checking', SourcesAddRefusal(False, True) = 'Inherited instances are being checked -- add the sources again when it finishes.', SourcesAddRefusal(False, True));
  Check('tab.add.allowed', SourcesAddRefusal(False, False) = '', SourcesAddRefusal(False, False));

  Row:= Default(TConvertRow);
  Row.UnitPas:= 'x\Desc.pas';
  Row.Book   := 'B2.rules';
  Row.Status := csConverted;
  Earlier:= Row;
  Earlier.Book:= 'B1.rules';
  Check('tab.note.due.first', CodeUseNoteDue(Row, []));
  Check('tab.note.due.once.per.unit', not CodeUseNoteDue(Row, [Earlier]));
  Earlier.UnitPas:= 'x\Other.pas';
  Check('tab.note.due.other.unit', CodeUseNoteDue(Row, [Earlier]));
  Row.Status:= csRefused;
  Check('tab.note.due.not.converted', not CodeUseNoteDue(Row, []));

  Row:= Default(TConvertRow);
  Row.UnitPas:= 'x\Desc.pas';
  Row.Book   := 'B.rules';
  Row.Status := csConverted;
  Row.Apply  := ParseApplyJson(INH_JSON);
  Lines:= InheritedReportLines(Row, True, True);
  Cols := if Length(Lines) > 0 then Lines[0].Split([#9]) else nil;
  LShape:= (Length(Lines) = Length(Row.Apply.InheritedLeft)) and (Length(Cols) = REPORT_COLS);
  Check('tab.report.lines.shape', LShape, Format('%d lines, %d cols', [Length(Lines), Length(Cols)]));
  if LShape then
    Check('tab.report.lines.text', (Cols[0] = 'B.rules') and (Cols[1] = 'x\Desc.pas') and (Cols[2] = REPORT_STATUS_INHERITED_LEFT) and (Cols[2] = 'inherited left')
      and (Cols[NOTE_COL] = InheritedReportNote(Row.Apply.InheritedLeft[0], True)), Lines[0]);
  // Controller ruling M4: the engine's inherited[] is authoritative (reported after the
  // runner's reindex), so nothing filters it -- not even an ancestor converted earlier
  // in the run (that case is tab.r4.runner.engine.unfiltered).
  Check('tab.report.lines.engine.unfiltered', (Length(Lines) = Length(Row.Apply.InheritedLeft)) and (Length(Lines) > 0)
    and (Pos('PathToData', Lines[0]) > 0), string.Join(' | ', Lines));
  Check('tab.report.lines.gated', Length(InheritedReportLines(Row, False, True)) = 0);
  Row.Status:= csRolledBack;
  Check('tab.report.lines.converted.only', Length(InheritedReportLines(Row, True, True)) = 0);
end;

{ C8 Task 6, ruling R4: an ancestor converted EARLIER IN THE SAME RUN converted its
  descendants' code uses too, so the editor's code-use note omits it. The engine's own
  inherited[] is NOT filtered (controller ruling M4: it is reported after the runner's
  reindex and is authoritative) -- neither in the note nor in the runner's row. }
procedure TestInheritanceTabR4;
const
  REASON_LIB = 'declaring ancestor not found (no ancestor .dfm of TLeafDM declares qryLib) -- convert it from its own project';
  INH_JSON  = '{"schema":"apply/1","ok":true,"error":"","rule_errors":[],"edits_count":2,"converted":[],"todos":[],"reemit_notes":[],"warnings":[],'
    + '"inherited":[{"name":"tblFtrs","type":"TTable","line":4,"ancestor_unit":"PathToData","ancestor_state":"unconverted","reason":"ancestor not converted"},'
    + '{"name":"qryLib","type":"TQuery","line":12,"ancestor_unit":"","ancestor_state":"outside","reason":"' + REASON_LIB + '"}]}';
  OLD_JSON  = '{"schema":"apply/1","ok":true,"error":"","rule_errors":[],"edits_count":1,"converted":[],"todos":[],"reemit_notes":[],"warnings":[]}';
  ORIG      = 'unit U;' + sLineBreak + 'interface' + sLineBreak + 'implementation' + sLineBreak + 'end.' + sLineBreak;
  NOTE_LIB  = '1 inherited instance(s) left: ancestor not determinable -- ' + REASON_LIB;
  N_ROWS    = 2;
var
  U     : TUnitInheritance;
  V     : TInstanceVerdict;
  Items : TArray<TInheritedLeft>;
  Item  : TInheritedLeft;
  CRows : TArray<TConvertRow>;
  CRow  : TConvertRow;
  Dir   : string;
  Index : TIndexFn;
  LShape: Boolean;
begin
  U:= FreshUnit('fx\Leaf.pas');
  V:= Default(TInstanceVerdict);
  V.Instance.Name    := 'tblFtrs';
  V.Instance.TypeName:= 'TTable';
  V.Instance.FromCode:= True;
  V.State            := asUnconverted;
  V.DeclaringUnit    := 'Base';
  U.Verdicts:= [V];
  V.Instance.Name    := 'qryOps';
  V.DeclaringUnit    := 'Mid';
  U.Verdicts:= U.Verdicts + [V];
  Check('tab.r4.code.left.all', CodeUseLeftNote(U) = '1 inherited code use(s) left: ancestor Base not converted; 1 inherited code use(s) left: ancestor Mid not converted', CodeUseLeftNote(U));
  Check('tab.r4.code.left.omits.converted', CodeUseLeftNote(U, ['base']) = '1 inherited code use(s) left: ancestor Mid not converted', CodeUseLeftNote(U, ['base']));
  Check('tab.r4.code.left.all.converted', CodeUseLeftNote(U, ['Base', 'Mid']) = '');

  Item:= Default(TInheritedLeft);
  Item.AncestorUnit := 'PathToData';
  Item.AncestorState:= 'unconverted';
  Items:= [Item];
  Item.AncestorUnit := '';
  Item.AncestorState:= 'outside';
  Item.Reason       := REASON_LIB;
  Items:= Items + [Item];
  Check('tab.r4.left.engine.all', InheritedLeftNote(Items, True) = '1 inherited instance(s) left: ancestor PathToData not converted; ' + NOTE_LIB, InheritedLeftNote(Items, True));

  CRows:= nil;
  CRow:= Default(TConvertRow);
  CRow.UnitPas:= 'x\PathToData.pas';
  CRow.Status := csConverted;
  CRows:= CRows + [CRow, CRow];
  CRow.UnitPas:= 'x\Rolled.pas';
  CRow.Status := csRolledBack;
  CRows:= CRows + [CRow];
  CRow.UnitPas:= 'x\My.Dotted.pas';
  CRow.Status := csConverted;
  CRows:= CRows + [CRow];
  Check('tab.r4.units.converted.in', string.Join(',', UnitsConvertedIn(CRows)) = 'PathToData,My.Dotted', string.Join(',', UnitsConvertedIn(CRows)));

  Dir:= TPath.Combine(TPath.GetTempPath, 'c8tab-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'PathToData.pas'), ORIG, TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(Dir, 'Desc.pas'), ORIG, TEncoding.ASCII);
    Index:= function(out AOutput: string): Integer
      begin
        AOutput:= '';
        Result := 0;
      end;
    CRows:= RunConversionUnits([TPath.Combine(Dir, 'PathToData.pas'), TPath.Combine(Dir, 'Desc.pas')], ['A.rules'],
      function(const AUnitPas, ARulesFile: string; out AJson: string): Integer
      begin
        AJson := if SameText(ExtractFileName(AUnitPas), 'Desc.pas') then INH_JSON else OLD_JSON;
        Result:= 0;
      end, Index, nil, nil, True);
    LShape:= (Length(CRows) = N_ROWS) and (CRows[1].Status = csConverted);
    Check('tab.r4.runner.engine.unfiltered', LShape and CRows[1].Note.EndsWith('; ' + NOTE_LIB) and (Pos('ancestor PathToData not converted', CRows[1].Note) > 0),
      if Length(CRows) = N_ROWS then CRows[1].Note else IntToStr(Length(CRows)));
    CRows:= RunConversionUnits([TPath.Combine(Dir, 'Desc.pas')], ['A.rules'],
      function(const AUnitPas, ARulesFile: string; out AJson: string): Integer
      begin
        AJson := INH_JSON;
        Result:= 0;
      end, Index, nil, nil, True);
    Check('tab.r4.runner.keeps.unconverted.ancestor', (Length(CRows) = 1) and (Pos('ancestor PathToData not converted', CRows[0].Note) > 0),
      if Length(CRows) = 1 then CRows[0].Note else IntToStr(Length(CRows)));
  finally
    TDirectory.Delete(Dir, True);
  end; // try
end;

{ C8 Task 8 (engine 1.22.0, N1+N5): the row note and the report note for every
  ancestor_state the engine sends -- unconverted, converted (retype is N2), mismatched
  (the type read from the engine's reason; a reason of another shape falls back to it
  verbatim), outside (ancestor_unit is '', grouped by reason) and any other state. }
procedure TestInheritedStateTexts;
const
  REASON_MIS   = 'declared in Base as TADOTable, neither TTable nor TFDTable -- not converted';
  REASON_MIS_2 = 'declared in Base as TClientDataSet, neither TTable nor TFDTable -- not converted';
  REASON_ODD   = 'the declaring object has some other type';
  REASON_OUT_A = 'declaring ancestor not found (Mid.dfm is binary (TPF0)) -- convert it from its own project';
  REASON_OUT_B = 'declaring ancestor not found (no ancestor .dfm of TLeafDM declares qryLib) -- convert it from its own project';
  NOTE_MIS     = '2 inherited instance(s) left: ancestor Base has TADOTable (neither TTable nor TFDTable)';
  ITEM_LINE    = 3; // the 'line 3' of the report notes below
  NOTE_CONV_N1 = '1 inherited instance(s) left: ancestor Anc converted -- this unit still has TTable there and may not compile or load until the engine '
    + 'can retype inherited instances (N2)';
var
  Items: TArray<TInheritedLeft>;

  function Item(const AName, AUnit, AState, AReason: string): TInheritedLeft;
  begin
    Result:= Default(TInheritedLeft);
    Result.Name         := AName;
    Result.TypeName     := 'TTable';
    Result.Line         := ITEM_LINE;
    Result.AncestorUnit := AUnit;
    Result.AncestorState:= AState;
    Result.Reason       := AReason;
  end;

begin
  Check('state.converted', InheritedLeftNote([Item('tblA', 'Anc', 'converted', 'x')], True) = '1 inherited instance(s) left: ancestor Anc converted -- retype pending (engine N2)',
    InheritedLeftNote([Item('tblA', 'Anc', 'converted', 'x')], True));
  Items:= [Item('tblA', 'Base', 'mismatched', REASON_MIS), Item('tblB', 'Base', 'mismatched', REASON_MIS)];
  Check('state.mismatched', InheritedLeftNote(Items, True) = NOTE_MIS, InheritedLeftNote(Items, True));
  Items:= Items + [Item('tblC', 'Base', 'mismatched', REASON_MIS_2)];
  Check('state.mismatched.by.found.type', InheritedLeftNote(Items, True) = NOTE_MIS + '; 1 inherited instance(s) left: ancestor Base has TClientDataSet (neither TTable nor TFDTable)',
    InheritedLeftNote(Items, True));
  Check('state.mismatched.fallback', InheritedLeftNote([Item('tblA', 'Base', 'mismatched', REASON_ODD)], True) = '1 inherited instance(s) left: ancestor Base has another type -- ' + REASON_ODD,
    InheritedLeftNote([Item('tblA', 'Base', 'mismatched', REASON_ODD)], True));
  Check('state.mismatched.fallback.other.unit', Pos('has another type', InheritedLeftNote([Item('tblA', 'Mid', 'mismatched', REASON_MIS)], True)) > 0,
    InheritedLeftNote([Item('tblA', 'Mid', 'mismatched', REASON_MIS)], True));
  Items:= [Item('tblA', '', 'outside', REASON_OUT_A), Item('tblB', '', 'outside', REASON_OUT_B), Item('tblC', '', 'outside', REASON_OUT_A)];
  Check('state.outside.by.reason', InheritedLeftNote(Items, True) = '2 inherited instance(s) left: ancestor not determinable -- ' + REASON_OUT_A
    + '; 1 inherited instance(s) left: ancestor not determinable -- ' + REASON_OUT_B, InheritedLeftNote(Items, True));
  Check('state.other', InheritedLeftNote([Item('tblA', 'Anc', 'frobbed', 'x')], True) = '1 inherited instance(s) left: ancestor Anc: frobbed',
    InheritedLeftNote([Item('tblA', 'Anc', 'frobbed', 'x')], True));
  Check('state.report.mismatched', InheritedReportNote(Item('tblA', 'Base', 'mismatched', REASON_MIS), True)
    = 'tblA: TTable line 3 -- ancestor Base has TADOTable (neither TTable nor TFDTable) (' + REASON_MIS + ')', InheritedReportNote(Item('tblA', 'Base', 'mismatched', REASON_MIS), True));
  Check('state.report.fallback.once', InheritedReportNote(Item('tblA', 'Base', 'mismatched', REASON_ODD), True) = 'tblA: TTable line 3 -- ancestor Base has another type -- ' + REASON_ODD,
    InheritedReportNote(Item('tblA', 'Base', 'mismatched', REASON_ODD), True));
  Check('state.report.converted', InheritedReportNote(Item('tblA', 'Anc', 'converted', 'why'), True)
    = 'tblA: TTable line 3 -- ancestor Anc converted -- retype pending (engine N2) (why)', InheritedReportNote(Item('tblA', 'Anc', 'converted', 'why'), True));
  Check('state.report.no.reason', InheritedReportNote(Item('tblA', 'Anc', 'unconverted', ''), True) = 'tblA: TTable line 3 -- ancestor Anc not converted',
    InheritedReportNote(Item('tblA', 'Anc', 'unconverted', ''), True));

  // Fix round 1 (controller ruling): until the engine retypes (N2) a converted ancestor
  // leaves this unit with the From type there -- say it may not compile or load.
  Check('state.converted.no.retype', InheritedLeftNote([Item('tblA', 'Anc', 'converted', 'x')], False) = NOTE_CONV_N1,
    InheritedLeftNote([Item('tblA', 'Anc', 'converted', 'x')], False));
  Items:= [Item('tblA', 'Anc', 'converted', 'x'), Item('tblB', 'Anc', 'converted', 'y')];
  Items[1].TypeName:= 'TQuery';
  Check('state.converted.no.retype.by.type', InheritedLeftNote(Items, False) = NOTE_CONV_N1 + '; 1 inherited instance(s) left: ancestor Anc converted -- this unit still has '
    + 'TQuery there and may not compile or load until the engine can retype inherited instances (N2)', InheritedLeftNote(Items, False));
  Check('state.unconverted.same.both', InheritedLeftNote([Item('tblA', 'Anc', 'unconverted', 'x')], False) = InheritedLeftNote([Item('tblA', 'Anc', 'unconverted', 'x')], True));
  Check('state.report.converted.no.retype', InheritedReportNote(Item('tblA', 'Anc', 'converted', 'why'), False)
    = 'tblA: TTable line 3 -- ancestor Anc converted -- this unit still has TTable there and may not compile or load until the engine can retype inherited '
    + 'instances (N2) (why)', InheritedReportNote(Item('tblA', 'Anc', 'converted', 'why'), False));
end;

{ C8 Task 6: the real disk reader (missing, BOM stripped as TFile.ReadAllText does,
  binary passed through for the scanner to recognise, locked = unreadable) and ONE
  reindex-and-retry on a STALE index (never more; other failures are not retried). }
procedure TestInheritanceTabDiskAndStale;
const
  STALE_ERR = 'cannot ask the index about TLeafDM (class lookup failed for x.sqlite: the index is stale (2 file(s) changed since it was indexed) -- reindex the project first)';
  BIN_TAIL: array[0..1] of Byte = (0, $FF);
  N_ASKED   = 2;
var
  Units  : TArray<TUnitInheritance>;
  Dir    : string;
  Txt    : string;
  Lock   : TFileStream;
  Reindex: Integer;
  Asked  : TArray<string>;
  Ok     : TIndexRefresh;
  LAll   : Boolean;
begin
  Dir:= TPath.Combine(TPath.GetTempPath, 'c8disk-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    Check('tab.disk.missing', DiskTextReader()(TPath.Combine(Dir, 'None.dfm'), Txt) = drMissing);
    TFile.WriteAllText(TPath.Combine(Dir, 'Bom.dfm'), 'object A: TA' + sLineBreak + 'end' + sLineBreak, TEncoding.UTF8);
    Check('tab.disk.bom.stripped', (DiskTextReader()(TPath.Combine(Dir, 'Bom.dfm'), Txt) = drRead) and Txt.StartsWith('object A: TA')
      and (ScanDfmInheritance(Txt).RootClass = 'TA'), Txt);
    TFile.WriteAllBytes(TPath.Combine(Dir, 'Bin.dfm'), TEncoding.ASCII.GetBytes(BINARY_DFM_SIGNATURE) + [BIN_TAIL[0], BIN_TAIL[1]]);
    Check('tab.disk.binary', (DiskTextReader()(TPath.Combine(Dir, 'Bin.dfm'), Txt) = drRead) and ScanDfmInheritance(Txt).IsBinary, Copy(Txt, 1, Length(BINARY_DFM_SIGNATURE)));
    TFile.WriteAllText(TPath.Combine(Dir, 'Locked.dfm'), 'object A: TA' + sLineBreak + 'end' + sLineBreak, TEncoding.ASCII);
    Lock:= TFileStream.Create(TPath.Combine(Dir, 'Locked.dfm'), fmOpenReadWrite or fmShareExclusive);
    try
      Check('tab.disk.unreadable', DiskTextReader()(TPath.Combine(Dir, 'Locked.dfm'), Txt) = drUnreadable);
    finally
      Lock.Free;
    end; // try
  finally
    TDirectory.Delete(Dir, True);
  end; // try

  Check('tab.stale.match', IsStaleIndexError(STALE_ERR) and not IsStaleIndexError('cannot ask the index about TX (DB does not exist)'));
  Ok:= function(out AError: string): Boolean
    begin
      Inc(Reindex);
      AError:= '';
      Result:= True;
    end;
  Reindex:= 0;
  Asked  := nil;
  Units:= AnalyzeRetryingStale(['a\A.pas', 'a\B.pas'],
    function(const APaths: TArray<string>): TArray<TUnitInheritance>
    begin
      Asked := Asked + [string.Join('+', APaths)];
      Result:= [FreshUnit('a\A.pas'), UnknownUnit('a\B.pas', 'DB does not exist')];
    end, Ok);
  Check('tab.stale.not.stale.no.reindex', (Reindex = 0) and (Length(Asked) = 1) and not Units[1].Known, IntToStr(Reindex));
  Reindex:= 0;
  Asked  := nil;
  Units:= AnalyzeRetryingStale(['a\A.pas', 'a\B.pas', 'a\C.pas'],
    function(const APaths: TArray<string>): TArray<TUnitInheritance>
    begin
      Asked:= Asked + [string.Join('+', APaths)];
      if Length(Asked) = 1 then
        Result:= [UnknownUnit('a\A.pas', STALE_ERR), FreshUnit('a\B.pas'), UnknownUnit('a\C.pas', STALE_ERR)]
      else
        Result:= [FreshUnit('a\A.pas'), FreshUnit('a\C.pas')];
    end, Ok);
  LAll:= Units[0].Known and Units[1].Known and Units[2].Known and (Units[2].UnitPas = 'a\C.pas');
  Check('tab.stale.reindex.once.retry.stale.only', (Reindex = 1) and (string.Join(' | ', Asked) = 'a\A.pas+a\B.pas+a\C.pas | a\A.pas+a\C.pas') and LAll,
    string.Join(' | ', Asked));
  Reindex:= 0;
  Asked  := nil;
  Units:= AnalyzeRetryingStale(['a\A.pas'],
    function(const APaths: TArray<string>): TArray<TUnitInheritance>
    begin
      Asked := Asked + [string.Join('+', APaths)];
      Result:= [UnknownUnit('a\A.pas', STALE_ERR + ' #' + IntToStr(Length(Asked)))];
    end, Ok);
  Check('tab.stale.twice.stays.unknown', (Reindex = 1) and (Length(Asked) = N_ASKED) and not Units[0].Known and Units[0].Error.EndsWith('#2'), Units[0].Error);
  Reindex:= 0;
  Asked  := nil;
  Units:= AnalyzeRetryingStale(['a\A.pas'],
    function(const APaths: TArray<string>): TArray<TUnitInheritance>
    begin
      Asked := Asked + [string.Join('+', APaths)];
      Result:= [UnknownUnit('a\A.pas', STALE_ERR)];
    end,
    function(out AError: string): Boolean
    begin
      Inc(Reindex);
      AError:= 'boom';
      Result:= False;
    end);
  Check('tab.stale.reindex.failed', (Reindex = 1) and (Length(Asked) = 1) and not Units[0].Known and Units[0].Error.EndsWith('; reindex failed: boom'), Units[0].Error);
end;

{ C8 E5-E9 decisions, on hand-built verdicts (the walk itself is TestInheritanceWalk):
  the row note's exact text, the topmost-first chain, the offer, the insertion
  (dedupe, directly before the descendant), the ordering warning (never a block) and
  the notes for an engine without inherited_instances. }
procedure TestInheritanceDecisions;
const
  BASE_PAS = 'fx\Base.pas';
  MID_PAS  = 'fx\Mid.pas';
  LEAF_PAS = 'fx\Leaf.pas';
  X_PAS    = 'fx\X.pas';
  Y_PAS    = 'fx\Y.pas';
  LOW_PAS  = 'fx\Low.pas';
  DEPTH_MID   = 1;
  DEPTH_BASE  = 2;
  DEPTH_FRAME = 3;
  N_WARN     = 2;
  N_NOTES    = 2;
var
  Leaf, Done, Unknown, CodeOnly, NoAnc, Framed, MidU: TUnitInheritance;
  Warn : TArray<string>;
  Notes: TArray<string>;

  function Link(const APas: string; ADepth: Integer): TChainUnit;
  begin
    Result.PasPath:= APas;
    Result.Depth  := ADepth;
  end;

  function Verdict(const AName, AType: string; AState: TAncestorState; const AUnit: string; const AChain: TArray<TChainUnit>): TInstanceVerdict;
  begin
    Result:= Default(TInstanceVerdict);
    Result.Instance.Name    := AName;
    Result.Instance.TypeName:= AType;
    Result.State            := AState;
    Result.DeclaringUnit    := AUnit;
    Result.DeclaringPas     := if AState = asOutside then '' else 'fx\' + AUnit + '.pas';
    Result.Chain            := AChain;
  end;

begin
  Leaf:= Default(TUnitInheritance);
  Leaf.UnitPas := LEAF_PAS;
  Leaf.Known   := True;
  // Bottom-up first-seen (Mid before Base): only the Depth sort puts Base first.
  Leaf.Verdicts:= [Verdict('tblOps', 'TTable', asUnconverted, 'Base', [Link(MID_PAS, DEPTH_MID), Link(BASE_PAS, DEPTH_BASE)]),
    Verdict('tblFtrs', 'TTable', asUnconverted, 'Base', [Link(BASE_PAS, DEPTH_BASE)]),
    Verdict('qryX', 'TQuery', asUnconverted, 'Base', [Link(BASE_PAS, DEPTH_BASE)]),
    Verdict('qryLib', 'TQuery', asOutside, 'TDataModule', [])];
  Check('inherit.note.text', InheritanceRowNote(Leaf, True) = 'inherits 3 TTable, TQuery instance(s) from Base -- convert it first (recommended); '
    + 'inherits from TDataModule, which is not in this project''s index -- convert it from its own project', InheritanceRowNote(Leaf, True));
  NoAnc:= Leaf;
  NoAnc.Verdicts:= [Verdict('qryLib', 'TQuery', asOutside, OUTSIDE_NO_ANCESTOR, [])];
  Check('inherit.note.outside.no.ancestor', (InheritanceRowNote(NoAnc, True) = OutsideNote(NoAnc.Verdicts[0]))
    and not InheritanceRowNote(NoAnc, True).Contains(OUTSIDE_NO_ANCESTOR), InheritanceRowNote(NoAnc, True));
  Done:= Leaf;
  Done.Verdicts:= [Verdict('tblFtrs', 'TTable', asConverted, 'Base', [])];
  Check('inherit.note.converted.silent', InheritanceRowNote(Done, True) = '', InheritanceRowNote(Done, True));
  Unknown:= Leaf;
  Unknown.Known:= False;
  Check('inherit.note.unknown.silent', InheritanceRowNote(Unknown, True) = '');

  Check('inherit.chain.topmost.first', string.Join(',', AncestorChain(Leaf)) = BASE_PAS + ',' + MID_PAS, string.Join(',', AncestorChain(Leaf)));
  // Mid is first met at depth 1 (below Base), then at depth 3 as a frame above it: its largest Depth wins.
  Framed:= Leaf;
  Framed.Verdicts:= [Verdict('tblOps', 'TTable', asUnconverted, 'Base', [Link(MID_PAS, DEPTH_MID), Link(BASE_PAS, DEPTH_BASE)]),
    Verdict('qryFrm', 'TQuery', asUnconverted, 'Mid', [Link(MID_PAS, DEPTH_FRAME)])];
  Check('inherit.chain.max.depth', string.Join(',', AncestorChain(Framed)) = MID_PAS + ',' + BASE_PAS, string.Join(',', AncestorChain(Framed)));
  Check('inherit.chain.converted.empty', Length(AncestorChain(Done)) = 0);
  Check('inherit.offer.text', OfferText(MissingAncestors(AncestorChain(Leaf), [LEAF_PAS]), LEAF_PAS, UnconvertedTypes(Leaf), True) = 'Add Base.pas, Mid.pas ahead of Leaf.pas?',
    OfferText(MissingAncestors(AncestorChain(Leaf), [LEAF_PAS]), LEAF_PAS, UnconvertedTypes(Leaf), True));
  Check('inherit.offer.missing', string.Join(',', MissingAncestors([BASE_PAS, MID_PAS], ['FX\mid.pas', LEAF_PAS])) = BASE_PAS);
  Check('inherit.offer.none.when.listed', Length(MissingAncestors([BASE_PAS, MID_PAS], [MID_PAS, BASE_PAS, LEAF_PAS])) = 0);

  Check('inherit.insert.before', string.Join(',', InsertAncestors([X_PAS, LEAF_PAS, Y_PAS], LEAF_PAS, [BASE_PAS, MID_PAS])) = string.Join(',', [X_PAS, BASE_PAS, MID_PAS, LEAF_PAS, Y_PAS]),
    string.Join(',', InsertAncestors([X_PAS, LEAF_PAS, Y_PAS], LEAF_PAS, [BASE_PAS, MID_PAS])));
  Check('inherit.insert.skips.listed', string.Join(',', InsertAncestors([MID_PAS, LEAF_PAS], LEAF_PAS, [BASE_PAS, MID_PAS])) = string.Join(',', [BASE_PAS, MID_PAS, LEAF_PAS]),
    string.Join(',', InsertAncestors([MID_PAS, LEAF_PAS], LEAF_PAS, [BASE_PAS, MID_PAS])));
  Check('inherit.insert.around.listed.middle', string.Join(',', InsertAncestors([Y_PAS, MID_PAS, LEAF_PAS], LEAF_PAS, [BASE_PAS, MID_PAS, LOW_PAS]))
    = string.Join(',', [Y_PAS, BASE_PAS, MID_PAS, LOW_PAS, LEAF_PAS]), string.Join(',', InsertAncestors([Y_PAS, MID_PAS, LEAF_PAS], LEAF_PAS, [BASE_PAS, MID_PAS, LOW_PAS])));
  // Mid re-opens Base's tblOps, so a result with Base below Mid trips E7 on its own.
  MidU:= Default(TUnitInheritance);
  MidU.UnitPas := MID_PAS;
  MidU.Known   := True;
  MidU.Verdicts:= [Verdict('tblOps', 'TTable', asUnconverted, 'Base', [Link(BASE_PAS, DEPTH_MID)])];
  Check('inherit.insert.result.order.clean', Length(OrderWarnings(InsertAncestors([MID_PAS, LEAF_PAS], LEAF_PAS, AncestorChain(Leaf)), [Leaf, MidU], True)) = 0,
    string.Join(' | ', OrderWarnings(InsertAncestors([MID_PAS, LEAF_PAS], LEAF_PAS, AncestorChain(Leaf)), [Leaf, MidU], True)));
  Check('inherit.insert.unit.absent.appends', string.Join(',', InsertAncestors([X_PAS], LEAF_PAS, [BASE_PAS])) = string.Join(',', [X_PAS, BASE_PAS]));

  Warn:= OrderWarnings([LEAF_PAS, BASE_PAS, MID_PAS], [Leaf], True);
  Check('inherit.order.warns', (Length(Warn) = N_WARN) and (Warn[0] = 'Leaf.pas is listed above its ancestor Base.pas, which is not converted yet')
    and (Warn[1] = 'Leaf.pas is listed above its ancestor Mid.pas, which is not converted yet'), string.Join(' | ', Warn));
  Check('inherit.order.ok', Length(OrderWarnings([BASE_PAS, MID_PAS, LEAF_PAS], [Leaf], True)) = 0);
  Check('inherit.order.unlisted.ancestor', Length(OrderWarnings([LEAF_PAS], [Leaf], True)) = 0);
  Check('inherit.order.converted.silent', Length(OrderWarnings([LEAF_PAS, BASE_PAS], [Done], True)) = 0);
  Check('inherit.order.text', OrderWarningText(Warn, True).StartsWith('Some units are listed above an ancestor that is not converted yet')
    and OrderWarningText(Warn, True).Contains(Warn[0]) and OrderWarningText(Warn, True).EndsWith('Convert in this order anyway?'), OrderWarningText(Warn, True));

  Notes:= EngineRefusalNotes([Leaf, Done, Unknown], False);
  Check('inherit.refusal.notes', (Length(Notes) = N_NOTES)
    and (Notes[0] = 'Leaf.pas: 4 inherited instance(s) of a From type -- this engine refuses such a unit (no inherited_instances capability), so it will be left unchanged')
    and (Notes[1] = 'Leaf.pas: 1 inherited instance(s) of a From type -- this engine refuses such a unit (no inherited_instances capability), so it will be left unchanged'),
    string.Join(' | ', Notes));
  Check('inherit.refusal.notes.supported', Length(EngineRefusalNotes([Leaf], True)) = 0);
  CodeOnly:= Leaf;
  CodeOnly.Verdicts:= [Verdict('tblFtrs', 'TTable', asUnconverted, 'Base', [Link(BASE_PAS, DEPTH_BASE)])];
  CodeOnly.Verdicts[0].Instance.FromCode:= True;
  Check('inherit.refusal.notes.code.only.silent', Length(EngineRefusalNotes([CodeOnly], False)) = 0);
  Check('inherit.chain.code.use', string.Join(',', AncestorChain(CodeOnly)) = BASE_PAS);

  // Fix round 1 (controller ruling): until the engine retypes inherited instances (N2),
  // converting an ancestor first breaks the descendant, and the order does not change
  // this run's result. E5 stays verbatim and gains a suffix; E6 gains a sentence; E7 no
  // longer claims reordering helps. With retype, the texts above are unchanged.
  Check('inherit.types.unconverted', string.Join(',', UnconvertedTypes(Leaf)) = 'TTable,TQuery', string.Join(',', UnconvertedTypes(Leaf)));
  Check('inherit.note.text.no.retype', InheritanceRowNote(Leaf, False) = 'inherits 3 TTable, TQuery instance(s) from Base -- convert it first (recommended)'
    + ' -- with this engine, converting it now breaks this unit until N2; '
    + 'inherits from TDataModule, which is not in this project''s index -- convert it from its own project', InheritanceRowNote(Leaf, False));
  Check('inherit.offer.text.no.retype', OfferText(MissingAncestors(AncestorChain(Leaf), [LEAF_PAS]), LEAF_PAS, UnconvertedTypes(Leaf), False)
    = 'Add Base.pas, Mid.pas ahead of Leaf.pas? Converting Base.pas, Mid.pas leaves Leaf.pas''s inherited instance(s) as TTable, TQuery until engine N2 '
    + '-- Leaf.pas may not compile or load.', OfferText(MissingAncestors(AncestorChain(Leaf), [LEAF_PAS]), LEAF_PAS, UnconvertedTypes(Leaf), False));
  Warn:= OrderWarnings([LEAF_PAS, BASE_PAS], [Leaf], False);
  Check('inherit.order.warns.no.retype', (Length(Warn) = 1) and (Warn[0] = 'Leaf.pas is listed above its ancestor Base.pas.'), string.Join(' | ', Warn));
  Check('inherit.order.text.no.retype', OrderWarningText(Warn, False) = 'Leaf.pas is listed above its ancestor Base.pas.' + sLineBreak + sLineBreak
    + 'With this engine the order does not change this run''s result: inherited instances are skipped either way. Run anyway?', OrderWarningText(Warn, False));
  Check('inherit.order.cancel.text', (OrderCancelledText(True) = 'Convert cancelled: reorder the source units (ancestors first) and press Convert again.')
    and (OrderCancelledText(False) = 'Convert cancelled: nothing was run.'), OrderCancelledText(False));
end;

{ C8 E2 / E3 / E8: the ancestor walk over a fake index. The fixture mirrors the
  measured DMTEST shape: the leaf's tblFtrs is declared two levels up (Base), and
  the middle unit does not mention it; Mid re-opens tblOps; qryLib is declared by
  no project unit (the chain leaves the index at TDataModule -- outside). }
procedure TestInheritanceWalk;  // dl:ok cyclomatic-complexity@2712 -- REVIEWED 2026-10-06 an assertion list plus a one-loop lookup helper (nested function V); the count is mostly the and-chains in Check conditions (Task 8 added the mismatched checks), and splitting the list would only scatter one fixture
const
  BASE_PAS = 'fx\Base.pas';
  MID_PAS  = 'fx\Mid.pas';
  LEAF_PAS = 'fx\Leaf.pas';
  BASE_DFM = 'object BaseDM: TBaseDM' + sLineBreak + '  object tblFtrs: TTable' + sLineBreak + '  end' + sLineBreak +
    '  object tblOps: TTable' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  BASE_DONE_DFM = 'object BaseDM: TBaseDM' + sLineBreak + '  object tblFtrs: TFDTable' + sLineBreak + '  end' + sLineBreak +
    '  object tblOps: TFDTable' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  BASE_MIS_DFM = 'object BaseDM: TBaseDM' + sLineBreak + '  object tblFtrs: TADOTable' + sLineBreak + '  end' + sLineBreak +
    '  object tblOps: TFDTable' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  NOTE_MISMATCHED = 'inherits 1 TTable instance(s) from Base, where they are TADOTable -- not this book''s From or To type';
  MID_DFM  = 'inherited MidDM: TMidDM' + sLineBreak + '  inherited tblOps: TTable' + sLineBreak + '    ReadOnly = True' + sLineBreak +
    '  end' + sLineBreak + 'end' + sLineBreak;
  LEAF_DFM ='inherited LeafDM: TLeafDM' + sLineBreak + '  inherited tblFtrs: TTable' + sLineBreak + '  end' + sLineBreak +
    '  inherited tblOps: TTable' + sLineBreak + '  end' + sLineBreak + '  inherited qryLib: TQuery' + sLineBreak + '  end' + sLineBreak +
    '  inherited memNote: TMemo' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  FORM_DFM = 'object Form2: TForm2' + sLineBreak + '  inline Frame11: TFrame1' + sLineBreak + '    inherited Button1: TButton' + sLineBreak +
    '    end' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  FRAME_DFM = 'object Frame1: TFrame1' + sLineBreak + '  object Button1: TButton' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  ANCF_DFM = 'object AncF: TAncF' + sLineBreak + '  inline Frame11: TFrame1' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  DESCF_DFM = 'inherited DescF: TDescF' + sLineBreak + '  inherited Frame11: TFrame1' + sLineBreak + '    inherited Button1: TButton' + sLineBreak +
    '    end' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  LOOP_DFM = 'inherited LoopDM: TLoopA' + sLineBreak + '  inherited tblX: TTable' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  CHAIN_DEPTH_BASE = 2;
  LEAF_FROM_INSTANCES = 3;
  OPS_CHAIN_UNITS = 2;
  CACHE_CALLS_AFTER_BROKEN = 3;
  NOTE_OUTSIDE_LIB = 'inherits from TDataModule, which is not in this project''s index -- convert it from its own project';
  NOTE_NO_ANCESTOR = 'inherits qryLib from an ancestor that is not in this project''s index -- convert it from its own project';
var
  Pairs : TArray<TTypePair>;
  Rows  : TArray<string>;
  U     : TUnitInheritance;
  Calls : TStringList;
  Cache : TDictionary<string, TClassInfo>;
  Cached: TClassLookup;
  Info  : TClassInfo;

  function Pair(const AFrom, ATo: string): TTypePair;
  begin
    Result.FromType:= AFrom;
    Result.ToType  := ATo;
  end;

  function V(const AName: string): TInstanceVerdict;
  begin
    Result:= Default(TInstanceVerdict);
    for var LV: TInstanceVerdict in U.Verdicts do
      if SameText(LV.Instance.Name, AName) then
        Exit(LV);
  end;

begin
  Pairs:= [Pair('TTable', 'TFDTable'), Pair('TQuery', 'TFDQuery'), Pair('TButton', 'TcxButton')];
  Rows := ['TLeafDM|' + LEAF_PAS + '|TMidDM', 'TMidDM|' + MID_PAS + '|TBaseDM', 'TBaseDM|' + BASE_PAS + '|TDataModule'];
  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(Rows, nil),
    FakeReader(['fx\Leaf.dfm', 'fx\Mid.dfm', 'fx\Base.dfm'], [LEAF_DFM, MID_DFM, BASE_DFM]));
  Check('inherit.walk.known', U.Known and (U.Error = ''), U.Error);
  Check('inherit.walk.from.filter', Length(U.Verdicts) = LEAF_FROM_INSTANCES, IntToStr(Length(U.Verdicts)) + ' (memNote is a TMemo: not a From type)');
  Check('inherit.walk.two.levels', (V('tblFtrs').State = asUnconverted) and (V('tblFtrs').DeclaringUnit = 'Base') and SameText(V('tblFtrs').DeclaringPas, BASE_PAS));
  Check('inherit.walk.skips.silent.middle', (Length(V('tblFtrs').Chain) = 1) and SameText(V('tblFtrs').Chain[0].PasPath, BASE_PAS)
    and (V('tblFtrs').Chain[0].Depth = CHAIN_DEPTH_BASE));
  Check('inherit.walk.intermediate.in.chain', (Length(V('tblOps').Chain) = OPS_CHAIN_UNITS) and SameText(V('tblOps').Chain[0].PasPath, MID_PAS)
    and SameText(V('tblOps').Chain[1].PasPath, BASE_PAS));
  Check('inherit.walk.outside.library', (V('qryLib').State = asOutside) and (V('qryLib').DeclaringUnit = 'TDataModule') and (V('qryLib').DeclaringPas = '')
    and (Length(V('qryLib').Chain) = 0), V('qryLib').DeclaringUnit);
  Check('inherit.note.outside', OutsideNote(V('qryLib')) = NOTE_OUTSIDE_LIB, OutsideNote(V('qryLib')));
  Check('inherit.note.not.outside', OutsideNote(V('tblFtrs')) = '', OutsideNote(V('tblFtrs')));

  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(Rows, nil),
    FakeReader(['fx\Leaf.dfm', 'fx\Mid.dfm', 'fx\Base.dfm'], [LEAF_DFM, MID_DFM, BASE_DONE_DFM]));
  Check('inherit.walk.converted', (V('tblFtrs').State = asConverted) and (V('tblFtrs').DeclaringUnit = 'Base') and (Length(V('tblFtrs').Chain) = 0));
  Check('inherit.note.converted.silent.walk', InheritanceRowNote(U, True) = NOTE_OUTSIDE_LIB, InheritanceRowNote(U, True));

  // Task 8 (reverses preflight ruling C4): a declaring object of a THIRD type -- neither
  // the book's From (TTable) nor its To (TFDTable) -- is mismatched, as the engine says.
  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(Rows, nil),
    FakeReader(['fx\Leaf.dfm', 'fx\Mid.dfm', 'fx\Base.dfm'], [LEAF_DFM, MID_DFM, BASE_MIS_DFM]));
  Check('inherit.walk.mismatched', (V('tblFtrs').State = asMismatched) and (V('tblFtrs').DeclaringUnit = 'Base') and (V('tblFtrs').FoundType = 'TADOTable')
    and (Length(V('tblFtrs').Chain) = 0), Format('state=%d found=%s', [Ord(V('tblFtrs').State), V('tblFtrs').FoundType]));
  Check('inherit.walk.mismatched.to.is.converted', V('tblOps').State = asConverted, IntToStr(Ord(V('tblOps').State)));
  Check('inherit.note.mismatched', InheritanceRowNote(U, True) = NOTE_MISMATCHED + '; ' + NOTE_OUTSIDE_LIB, InheritanceRowNote(U, True));
  Check('inherit.chain.mismatched.not.offered', Length(AncestorChain(U)) = 0, string.Join(',', AncestorChain(U)));
  Check('inherit.order.mismatched.silent', Length(OrderWarnings([LEAF_PAS, BASE_PAS], [U], True)) = 0);
  Check('inherit.walk.mismatched.direct', ResolveInstance(V('tblFtrs').Instance, 'TMidDM', FakeLookup(Rows, nil),
    FakeReader(['fx\Mid.dfm', 'fx\Base.dfm'], [MID_DFM, BASE_MIS_DFM]), Pairs).State = asMismatched);

  U:= AnalyzeUnit('fx\Form2.pas', Pairs, FakeLookup(['TForm2|fx\Form2.pas|TForm', 'TFrame1|fx\Frame1.pas|TFrame'], nil),
    FakeReader(['fx\Form2.dfm', 'fx\Frame1.dfm'], [FORM_DFM, FRAME_DFM]));
  Check('inherit.walk.inline.frame', (Length(U.Verdicts) = 1) and (V('Button1').State = asUnconverted) and (V('Button1').DeclaringUnit = 'Frame1'),
    Format('%d verdicts', [Length(U.Verdicts)]));
  Check('inherit.walk.inline.not.listed', V('Frame11').Instance.Name = '');

  U:= AnalyzeUnit('fx\DescF.pas', Pairs,
    FakeLookup(['TDescF|fx\DescF.pas|TAncF', 'TAncF|fx\AncF.pas|TForm', 'TFrame1|fx\Frame1.pas|TFrame'], nil),
    FakeReader(['fx\DescF.dfm', 'fx\AncF.dfm', 'fx\Frame1.dfm'], [DESCF_DFM, ANCF_DFM, FRAME_DFM]));
  Check('inherit.walk.frame.in.ancestor', (V('Button1').State = asUnconverted) and (V('Button1').DeclaringUnit = 'Frame1'), V('Button1').DeclaringUnit);

  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(Rows, nil), FakeReader([], []));
  Check('inherit.walk.no.dfm', not U.Known and (Length(U.Verdicts) = 0));
  U:= AnalyzeUnit(LEAF_PAS, nil, FakeLookup(Rows, nil), FakeReader(['fx\Leaf.dfm'], [LEAF_DFM]));
  Check('inherit.walk.no.checked.book', not U.Known and (Length(U.Verdicts) = 0));
  U:= AnalyzeUnit(LEAF_PAS, [Pair('TMemoX', 'TcxMemo')], FakeLookup(Rows, nil), FakeReader(['fx\Leaf.dfm'], [LEAF_DFM]));
  Check('inherit.walk.no.from.match', U.Known and (Length(U.Verdicts) = 0));
  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(['TMidDM|' + MID_PAS + '|TBaseDM'], nil), FakeReader(['fx\Leaf.dfm'], [LEAF_DFM]));
  Check('inherit.walk.unit.not.indexed', not U.Known and (Length(U.Verdicts) = 0));
  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(['TLeafDM|' + LEAF_PAS + '|TMidDM', 'TMidDM|!'], nil),
    FakeReader(['fx\Leaf.dfm', 'fx\Mid.dfm'], [LEAF_DFM, MID_DFM]));
  Check('inherit.walk.lookup.failed', not U.Known and (Length(U.Verdicts) = 0) and (U.Error <> ''), U.Error);
  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(['TLeafDM|' + LEAF_PAS + '|TMidDM', 'TMidDM|!|index is locked'], nil),
    FakeReader(['fx\Leaf.dfm', 'fx\Mid.dfm'], [LEAF_DFM, MID_DFM]));
  Check('inherit.walk.lookup.failed.cause', not U.Known and ContainsText(U.Error, 'TMidDM') and ContainsText(U.Error, 'index is locked'), U.Error);
  U:= AnalyzeUnit('fx\Loop.pas', Pairs, FakeLookup(['TLoopA|fx\Loop.pas|TLoopB', 'TLoopB|fx\LoopB.pas|TLoopA'], nil),
    FakeReader(['fx\Loop.dfm'], [LOOP_DFM]));
  Check('inherit.walk.cycle.ends', not U.Known and (Length(U.Verdicts) = 0) and ContainsText(U.Error, 'loops back to TLoopB') and ContainsText(U.Error, 'tblX'),
    U.Error);

  // C3: the unit's own class records no ancestor at all -- outside, but there is no
  // class to name, so the note names the instance instead of a pseudo-class.
  U:= AnalyzeUnit(LEAF_PAS, Pairs, FakeLookup(['TLeafDM|' + LEAF_PAS + '|'], nil), FakeReader(['fx\Leaf.dfm'], [LEAF_DFM]));
  Check('inherit.walk.no.ancestor', U.Known and (V('qryLib').State = asOutside) and (V('qryLib').DeclaringUnit = OUTSIDE_NO_ANCESTOR),
    V('qryLib').DeclaringUnit);
  Check('inherit.note.no.ancestor', OutsideNote(V('qryLib')) = NOTE_NO_ANCESTOR, OutsideNote(V('qryLib')));
  Check('inherit.unit.name', UnitNameOf('fx\PathToData.pas') = 'PathToData');

  Calls:= TStringList.Create;
  Cache:= TDictionary<string, TClassInfo>.Create;
  try
    Cached:= CachingLookup(FakeLookup(Rows + ['TBroken|!'], Calls), Cache);
    Info:= Cached('TBaseDM');
    Check('inherit.cache.answers', Info.Found and SameText(Info.PasPath, BASE_PAS), Info.PasPath);
    Info:= Cached('tbasedm');
    Check('inherit.cache.one.question', Info.Found and (Calls.Count = 1), Calls.CommaText);
    Cached('TBroken');
    Cached('TBroken');
    Check('inherit.cache.failure.not.cached', Calls.Count = CACHE_CALLS_AFTER_BROKEN, Calls.CommaText);
  finally
    Cache.Free;
    Calls.Free;
  end; // try
end;

{ C8 E2 edges: the frame fallback at any nesting depth inside the frame (a panel
  between frame and button), a re-opening intermediate form kept in Chain below the
  frame, and the outcomes that are UNKNOWN (cycle, depth cap, binary or unreadable
  ancestor .dfm -- never reported as outside) or that end at an INDEXED class with no
  ancestor (the no-ancestor wording, never naming that class). }
procedure TestInheritanceWalkEdges;
const
  FRAMEP_DFM = 'object Frame1: TFrame1' + sLineBreak + '  object Panel1: TPanel' + sLineBreak + '    object Button1: TButton' + sLineBreak +
    '    end' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  ANCF_DFM = 'object AncF: TAncF' + sLineBreak + '  inline Frame11: TFrame1' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  DESCP_DFM = 'inherited DescF: TDescF' + sLineBreak + '  inherited Frame11: TFrame1' + sLineBreak + '    inherited Panel1: TPanel' + sLineBreak +
    '      inherited Button1: TButton' + sLineBreak + '      end' + sLineBreak + '    end' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  MIDF_DFM = 'inherited MidF: TMidF' + sLineBreak + '  inherited Frame11: TFrame1' + sLineBreak + '    inherited Panel1: TPanel' + sLineBreak +
    '      inherited Button1: TButton' + sLineBreak + '      end' + sLineBreak + '    end' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  LEAF_DFM = 'inherited LeafDM: TLeafDM' + sLineBreak + '  inherited tblFtrs: TTable' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  MID_DFM  = 'inherited MidDM: TMidDM' + sLineBreak + 'end' + sLineBreak;
  BASE_DFM = 'object BaseDM: TBaseDM' + sLineBreak + '  object tblFtrs: TTable' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  BINARY_DFM = BINARY_DFM_SIGNATURE + #1#2#3;
  CAP_DFM  = 'inherited C0: TC0' + sLineBreak + '  inherited tblX: TTable' + sLineBreak + '  end' + sLineBreak + 'end' + sLineBreak;
  CAP_EXTRA_CLASSES = 8;
  REOPEN_CHAIN_UNITS = 2;
  NOTE_NO_ANCESTOR = 'inherits tblFtrs from an ancestor that is not in this project''s index -- convert it from its own project';
var
  Pairs: TArray<TTypePair>;
  Rows : TArray<string>;
  U    : TUnitInheritance;
  S    : TDfmInheritance;
  R    : TInstanceVerdict;
  Btn  : TInstanceVerdict;

  function Pair(const AFrom, ATo: string): TTypePair;
  begin
    Result.FromType:= AFrom;
    Result.ToType  := ATo;
  end;

  function V(const AName: string): TInstanceVerdict;
  begin
    Result:= Default(TInstanceVerdict);
    for var LV: TInstanceVerdict in U.Verdicts do
      if SameText(LV.Instance.Name, AName) then
        Exit(LV);
  end;

begin
  Pairs:= [Pair('TTable', 'TFDTable'), Pair('TButton', 'TcxButton')];

  S:= ScanDfmInheritance(DESCP_DFM);
  Btn:= Default(TInstanceVerdict);
  for var LInst: TInheritedInstance in S.Instances do
    if LInst.Name = 'Button1' then
      Btn.Instance:= LInst;
  Check('inherit.scan.enclosing', (Length(Btn.Instance.Enclosing) = REOPEN_CHAIN_UNITS) and (Btn.Instance.Enclosing[0] = 'TPanel')
    and (Btn.Instance.Enclosing[1] = 'TFrame1'), string.Join(',', Btn.Instance.Enclosing));

  // A panel between the frame and the button: the fallback must reach TFrame1.
  U:= AnalyzeUnit('fx\DescF.pas', Pairs,
    FakeLookup(['TDescF|fx\DescF.pas|TAncF', 'TAncF|fx\AncF.pas|TForm', 'TFrame1|fx\Frame1.pas|TFrame'], nil),
    FakeReader(['fx\DescF.dfm', 'fx\AncF.dfm', 'fx\Frame1.dfm'], [DESCP_DFM, ANCF_DFM, FRAMEP_DFM]));
  Check('inherit.walk.frame.panel.between', U.Known and (V('Button1').State = asUnconverted) and (V('Button1').DeclaringUnit = 'Frame1'),
    V('Button1').DeclaringUnit + ' ' + U.Error);

  // An intermediate form re-opens Frame11 / Panel1 / Button1: it stays in Chain, and
  // the frame (converted first) sits above it.
  U:= AnalyzeUnit('fx\DescF.pas', Pairs,
    FakeLookup(['TDescF|fx\DescF.pas|TMidF', 'TMidF|fx\MidF.pas|TAncF', 'TAncF|fx\AncF.pas|TForm', 'TFrame1|fx\Frame1.pas|TFrame'], nil),
    FakeReader(['fx\DescF.dfm', 'fx\MidF.dfm', 'fx\AncF.dfm', 'fx\Frame1.dfm'], [DESCP_DFM, MIDF_DFM, ANCF_DFM, FRAMEP_DFM]));
  Btn:= V('Button1');
  Check('inherit.walk.frame.reopen.in.chain', (Btn.DeclaringUnit = 'Frame1') and (Length(Btn.Chain) = REOPEN_CHAIN_UNITS)
    and SameText(Btn.Chain[0].PasPath, 'fx\MidF.pas') and SameText(Btn.Chain[1].PasPath, 'fx\Frame1.pas'),
    Format('%s, %d chain units', [Btn.DeclaringUnit, Length(Btn.Chain)]));
  if Length(Btn.Chain) = REOPEN_CHAIN_UNITS then
    Check('inherit.walk.frame.depth.above.forms', Btn.Chain[1].Depth > Btn.Chain[0].Depth,
      Format('MidF %d, Frame1 %d', [Btn.Chain[0].Depth, Btn.Chain[1].Depth]));

  Rows:= ['TLeafDM|fx\Leaf.pas|TMidDM', 'TMidDM|fx\Mid.pas|TBaseDM', 'TBaseDM|fx\Base.pas|TDataModule'];
  U:= AnalyzeUnit('fx\Leaf.pas', Pairs, FakeLookup(Rows, nil), FakeReader(['fx\Leaf.dfm', 'fx\Base.dfm'], [LEAF_DFM, BASE_DFM]));
  Check('inherit.walk.missing.dfm.skipped', U.Known and (V('tblFtrs').State = asUnconverted) and (V('tblFtrs').DeclaringUnit = 'Base'), U.Error);
  U:= AnalyzeUnit('fx\Leaf.pas', Pairs, FakeLookup(Rows, nil),
    FakeReader(['fx\Leaf.dfm', 'fx\Mid.dfm', 'fx\Base.dfm'], [LEAF_DFM, BINARY_DFM, BASE_DFM]));
  Check('inherit.walk.binary.ancestor.unknown', not U.Known and (Length(U.Verdicts) = 0) and ContainsText(U.Error, 'TMidDM'), U.Error);
  U:= AnalyzeUnit('fx\Leaf.pas', Pairs, FakeLookup(Rows, nil),
    FakeReader(['fx\Leaf.dfm', 'fx\Mid.dfm', 'fx\Base.dfm'], [LEAF_DFM, FAKE_UNREADABLE_DFM, BASE_DFM]));
  Check('inherit.walk.unreadable.ancestor.unknown', not U.Known and (Length(U.Verdicts) = 0) and ContainsText(U.Error, 'TMidDM'), U.Error);

  // An INDEXED ancestor with no ancestor of its own ends the chain: no-ancestor wording.
  U:= AnalyzeUnit('fx\Leaf.pas', Pairs, FakeLookup(['TLeafDM|fx\Leaf.pas|TMidDM', 'TMidDM|fx\Mid.pas|'], nil),
    FakeReader(['fx\Leaf.dfm', 'fx\Mid.dfm'], [LEAF_DFM, MID_DFM]));
  Check('inherit.walk.indexed.no.ancestor', U.Known and (V('tblFtrs').State = asOutside) and (V('tblFtrs').DeclaringUnit = OUTSIDE_NO_ANCESTOR),
    V('tblFtrs').DeclaringUnit);
  Check('inherit.note.indexed.no.ancestor', (OutsideNote(V('tblFtrs')) = NOTE_NO_ANCESTOR) and not ContainsText(OutsideNote(V('tblFtrs')), 'TMidDM'),
    OutsideNote(V('tblFtrs')));

  // A chain longer than MAX_CHAIN_DEPTH is unknown, not outside.
  Rows:= nil;
  for var I: Integer:= 0 to MAX_CHAIN_DEPTH + CAP_EXTRA_CLASSES do
    Rows:= Rows + [Format('TC%d|fx\C%d.pas|TC%d', [I, I, I + 1])];
  U:= AnalyzeUnit('fx\C0.pas', Pairs, FakeLookup(Rows, nil), FakeReader(['fx\C0.dfm'], [CAP_DFM]));
  Check('inherit.walk.depth.cap.unknown', not U.Known and (Length(U.Verdicts) = 0) and ContainsText(U.Error, 'longer than ' + IntToStr(MAX_CHAIN_DEPTH)),
    U.Error);

  // The failure travels as a state, not as an empty string.
  R:= ResolveInstance(Btn.Instance, 'TBroken', FakeLookup(['TBroken|!'], nil), FakeReader([], []), []);
  Check('inherit.resolve.unknown.state', (R.State = asUnknown) and ContainsText(R.Reason, 'TBroken') and (OutsideNote(R) = ''), R.Reason);
end;

begin
  try
    if ResolveExe <> '' then
      Writeln('engine: ', ResolveExe)
    else
      Writeln('engine: (none) -- ', GEngineWhy);
    TestReFindCorpusLoads;
    TestReFindCorpusReconstructs;
    TestConversionLibraryLoads;
    TestConversionLibraryReconstructs;
    TestConversionLibraryRemovesAreSafe;
    TestBlockSplitRulesRoundTrip;
    TestBlockSplitTrailing;
    TestBlockOpsSelection;
    TestBlockOpsSelectionCorpus;
    TestApplyIntegrity;
    TestApplyIntegrityCorpus;
    TestWorkingSetSelection;
    TestWorkingSetSelectionCorpus;
    TestTagDirective;
    TestCatalogTags;
    TestBlockSplitCastLibRoundTrip;
    TestBlockLabel;
    TestBlockOpsSplit;
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
    TestScanPasReceiverAndComments;
    TestScanDfmInstanceNames;
    TestScanUsesClauses;
    TestScanUsesClausesLimits;
    TestScanUsesClausesSections;
    TestScanClassesDeclared;
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
    TestBookDepth;
    TestConvertFromOnly;
    TestPickerDatasource;
    TestFillFromUnit;
    TestProptreeBareClass;
    TestProptree2Live;
    TestThemeModel;
    TestPropCellText;
    TestPlatformDefaults;
    TestEngineTimeoutHeadroom;
    TestProptreeRefsAsLeavesLive;
    TestResolveHardFailureIsReported;
    TestControlTypesFromNonProjectUnit;
  TestConvCatalog;
    TestAcceptanceTcxButtonToPool;
    TestQueryLocationParse;
    TestQuerySymbolTieBreak;
    TestEnumMembersParse;
    TestGoToDefinitionLive;
    TestMappingRules;
    TestMappingRoundTrip;
    TestMappingWhenWithoutSets;
    TestMappingEmit;
    TestSaveCompleteKeepsApplyOnly;
    TestBlockMapsSomething;
    TestSaveCompleteKeepsIgnoreOnly;
    TestReplaceMapping;
    TestMappingValidation;
    TestMappingBadLiteral;
    TestMappingIssueSeverity;
    TestMappingFold;
    TestMappingDivergentWhenFrom;
    TestMappingGridHooks;
    TestFormTypesScan;
    TestSkipList;
    TestFormTypesFilter;
    TestApplySkipMarks;
    TestClassRowModel;
    TestSelectedRowMapping;
    TestFormTypeRendering;
    TestDescribeOutlineOutcome;
    TestRuleCatalogParse;
    TestRulesForType;
    TestRuleCatalogIndex;
    TestRuleCatalogDuplicates;
    TestSameBookDups;
    TestMappingCatalog;
    TestHeaderIndexFor;
    TestAtomFileNaming;
    TestRuleCatalogRealFolder;
    TestSuggestEnumPairs;
    TestOutlineClassNames;
    TestScratchDbPath;
    TestOutlineClassesLive;
    TestMissingUnitNodes;
    TestUnitPickFilter;
    TestUnitPickMulti;
    TestBookSnapshot;
    TestConvertRun;
    TestConvertSourceRow;
    TestConvertRunner;
    TestConvertRunnerFaults;
    TestConvertRunnerLive;
    TestInheritanceScan;
    TestInheritancePairs;
    TestInheritanceWalk;
    TestInheritanceDecisions;
    TestInheritanceWalkEdges;
    TestInheritanceCodeUses;
    TestClassLookup;
    TestClassLookupLive;
    TestInheritedApply;
    TestInheritedRunLive;
    TestCodeRefs;
    TestCodeRefsLive;
    TestInheritanceTabAnalysis;
    TestInheritanceTabR4;
    TestInheritedStateTexts;
    TestInheritanceTabDiskAndStale;
    TestInheritanceTabGate;
    TestUnitPickPlatform;
    TestListUnitsPerDb;
    TestUsesHarvestText;
    TestDprMembers;
    TestHarvestMergeAndFlag;
    TestProjectSettings;
    TestProjectFileForDb;
    TestHarvestFiles;
    TestUnitResolver;
    TestUnitResolverDisk;
    TestUnitMask;
    TestFilterHarvestRows;
    TestDestPlatformLabel;
    TestEngineProgress;
    TestEngineArgsAndCaps;
    TestCapabilityProbeTimeout;
    TestRunCaptureStreaming;
    TestProptreeCancelState;
    TestChooseTestEngine;
    TestStdoutSeparateFromStderr;
    TestProptreeResolveInRunner;
    TestResolveCache;
    TestValidateParse;
    TestValidateScopeBlocks;
    TestValidateScopeRun;
    TestValidateTextStreams;
    TestValidateScopeCancel;

    FreeAndNil(GParseBook);

    Writeln('');
    Writeln(Format('model-tests: %d pass / %d fail / %d skip / %d total', [GPass, GFail, GSkip, GPass + GFail + GSkip]));
    if GFail > 0 then
      Halt(1);
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message);
      Halt(2);
    end;
  end; // try
end. // begin
