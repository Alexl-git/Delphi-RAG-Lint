unit DRagLint.Analysis.LintTree;

{ `lint-tree` -- does an edit to this unit's INTERFACE reach anybody?

  THE PROBLEM IT EXISTS FOR. Since the SHADOW ghost-check ruling, an interface
  edit to unit B compiles B alone. A saved dependent A is then broken and
  nothing says so until the next real build -- and `lint-all` does not say so
  either. MEASURED 2026-09-10 on an A-uses-B fixture: removing three interface
  symbols from B while A still referenced all three produced 3 findings, all
  [info], none about the broken references, and the count went DOWN from 4 to 3
  because the deleted routine's own empty-body finding disappeared. Of 179
  catalog rules only two mention resolution at all. So the fan-out has to come
  from the index, and this verb is where it comes from.

  EXIT CODE IS NOT A FINDING COUNT. This verb exits 0 whether or not it found
  anything; 2 means it could not run. A fan-out that reddened the IDE's build
  status every time someone edited an interface would be turned off in a week.

  WHY THE OLD SIDE IS A FILE AND NOT THE INDEX. The plugin passes --baseline,
  captured ONCE at the start of an edit episode. Diffing against the live index
  instead would compare the buffer with an index that a background reindex may
  have just refreshed to match it -- the worklist would delete itself the moment
  a save landed, which is precisely when the user still needs it. The live index
  is the OLD side only for CLI/manual use with no --baseline, and a launch from
  the plugin without one is a defect.

  WHY A BASELINE CAN BE REFUSED. directives and vis_explicit arrived in schema
  22 and a pre-v22 row reads back '' / True, so a v21 baseline against a v22
  parse marks EVERY routine changed. That is indistinguishable from a real edit,
  so the baseline carries both stamps and a mismatch is refused with a reason
  rather than diffed. See DRagLint.Analysis.SurfaceAdapters. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Analysis.SurfaceFingerprint,
  DRagLint.Analysis.SurfaceAdapters;

const
  /// <summary>Output schema tag, bumped when the JSON shape changes.</summary>
  LINT_TREE_SCHEMA     = 'lint-tree/1';
  /// <summary>Baseline file schema tag.</summary>
  LINT_TREE_BASELINE_SCHEMA = 'lint-tree-baseline/1';

type
  /// <summary>Everything `lint-tree` needs, mapped from the CLI's TArgs.</summary>
  /// <remarks>
  /// A record rather than TArgs so the engine is testable without the CLI, and
  /// so this unit does not depend on DRagLint.CLI.
  /// </remarks>
  TLintTreeOptions = record
    /// <summary>Path of the unit whose interface may have changed. Required.</summary>
    UnitPath         : string;
    /// <summary>Path of a file holding the unsaved buffer; empty means read UnitPath.</summary>
    BufferPath       : string;
    /// <summary>The .dproj this unit belongs to; used to resolve the define profile.</summary>
    ProjectPath      : string;
    /// <summary>Index to read. Required.</summary>
    DbPath           : string;
    /// <summary>Edit-episode baseline to diff against; empty means use the index.</summary>
    BaselinePath     : string;
    /// <summary>When set, capture the index side to this file and do nothing else.</summary>
    WriteBaselinePath: string;
    /// <summary>win32 | win64; empty means take the index's own platform.</summary>
    Platform         : string;
    /// <summary>json | text. Empty means text.</summary>
    Format           : string;
    /// <summary>Also harvest ordinary lint findings for direct dependents (B3+).</summary>
    WithRules        : Boolean;
    /// <summary>Run the tier-3 shadow compile (B6).</summary>
    Compile          : Boolean;
  end;

  /// <summary>Opens the index for a given path; injected so tests need no DB.</summary>
  /// <param name="pDbPath">Path of the SQLite index.</param>
  /// <returns>An open read-only store, or nil when it cannot be opened.</returns>
  TStoreOpener = reference to function(const pDbPath: string): ISymbolStore;

  /// <summary>Builds a parser for a source extension; injected for the same reason.</summary>
  /// <param name="pExtension">File extension including the dot, e.g. `.pas`.</param>
  /// <returns>A parser, or nil when the extension has none.</returns>
  TParserFactory = reference to function(const pExtension: string): IParser;

  /// <summary>Preprocesses UTF-8 source the way the indexer did.</summary>
  /// <param name="pUtf8">UTF-8 source bytes.</param>
  /// <param name="pFile">Path, used to resolve the define profile.</param>
  /// <returns>Preprocessed bytes; byte length and line structure are preserved.</returns>
  TPreprocessor = reference to function(const pUtf8: TBytes;
                                        const pFile: string): TBytes;

  /// <summary>Compiles one unit with a shadow directory FIRST on the unit
  /// search path, so it binds the shadow copy of an edited unit.</summary>
  /// <param name="pUnitPath">The dependent to compile, at its real path.</param>
  /// <param name="pProjectPath">The .dproj supplying the compile context.</param>
  /// <param name="pPlatform">win32 | win64.</param>
  /// <param name="pShadowDir">Directory holding the staged buffer(s).</param>
  /// <returns>Compiler findings; errors and warnings alike, filtered by the caller.</returns>
  /// <remarks>Injected rather than called directly so this unit stays free of
  /// the CLI, and so a test can drive tier 3 without a compiler.</remarks>
  TUnitCompiler = reference to function(const pUnitPath, pProjectPath,
    pPlatform, pShadowDir: string): TArray<TCompilerFinding>;

/// <summary>Runs the verb and renders its report.</summary>
/// <param name="pOptions">Parsed command-line options.</param>
/// <param name="pOpenStore">Store opener; must not be nil.</param>
/// <param name="pParserFor">Parser factory; must not be nil.</param>
/// <param name="pPreprocess">
/// Preprocessor; may be nil, in which case the source is parsed verbatim and
/// the report says so, because a unit with `{$IFDEF}` in its interface would
/// otherwise be permanently reported as changed.
/// </param>
/// <param name="AOutput">Receives the rendered report (JSON or text).</param>
/// <returns>0 when the verb ran, 2 when it could not.</returns>
/// <remarks>
/// Exit code is deliberately NOT a finding count -- see the unit header.
/// </remarks>
function RunLintTree(const pOptions   : TLintTreeOptions;
                     const pOpenStore : TStoreOpener;
                     const pParserFor : TParserFactory;
                     const pPreprocess: TPreprocessor;
                     const pCompile   : TUnitCompiler;
                     out   AOutput    : string): Integer;

implementation

uses
  Winapi.Windows,
  System.DateUtils,
  System.Diagnostics,
  DRagLint.Core.Encoding;

const
  { How much of a 64-char hash is echoed to a human. Enough to tell two
    fingerprints apart at a glance, short enough to read; the full value is
    always in the JSON. }
  FINGERPRINT_ECHO_CHARS = 16;

  { How many same-prefix symbols the ambiguity gate inspects before deciding a
    bare name is safe to join on. The question is only "is there MORE THAN ONE
    declarer", and the first foreign hit answers it, so this bounds a scan that
    has already succeeded rather than the decision itself. }
  AMBIGUITY_SCAN_LIMIT   = 200;

type
  { The whole answer, in one place. It used to be eight positional parameters
    to the JSON renderer and seven to the text one, which is how the two
    drifted: the JSON branch carried the profile stamp and the text branch
    silently did not. }
  { One interface symbol as the BASELINE recorded it. Carries the index's
    symbol Id, which is what the routine rule joins refs on -- a parser-side
    symbol has no id, which is why the NEW side is never the baseline. }
  TBaselineSymbol = record
    Id       : Int64;
    Kind     : string;
    QName    : string;
    Signature: string;
  end;

  TLintTreeDelta = record
    Removed: TArray<TBaselineSymbol>;
    Changed: TArray<TBaselineSymbol>;
    Added  : TArray<string>;
  end;

  TLintTreeFinding = record
    FilePath : string;
    Line     : Integer;
    Col      : Integer;
    Rule     : string;
    Severity : string;
    Message  : string;
    { The refs.kind the hit came through, echoed so a reader can see that
      member-access rows are included -- the correction of 2026-09-10. }
    RefKind  : string;
    Unchecked: Boolean;
  end;

  { Everything a finding collector needs, so the two collectors take four
    parameters instead of eight. They share the same six values and had begun
    to drift apart in argument order. }
  TFindingCtx = record
    Store    : ISymbolStore;
    OwnFileId: Int64;
    Closure  : TArray<TDependentFile>;
    InClosure: TDictionary<Int64, string>;
    Unchecked: TDictionary<Int64, Boolean>;
    Acc      : TList<TLintTreeFinding>;
  end;

  TLintTreeReport = record
    Changed   : Boolean;
    ParseError: Boolean;
    Reason    : string;
    NewFp     : string;
    OldFp     : string;
    OldSource : string;
    Profile   : TIndexerProfile;
    Delta     : TLintTreeDelta;
    Findings  : TArray<TLintTreeFinding>;
    HasClosure: Boolean;
    DirectCnt : Integer;
    TotalCnt  : Integer;
    ClosureMs : Int64;
    { How many removed/changed TYPE or DATA symbols were skipped because a
      bare-name join would have been ambiguous. Reported so an empty findings
      list is never mistaken for 'nothing broke'. }
    Suppressed: Integer;
    Compiled  : Boolean;
    ShadowDir : string;
  end;

  TSurfaceSide = record
    Fingerprint: string;
    Symbols    : TArray<TSymbol>;
    UsesEntries: TArray<TUnitUse>;
    Profile    : TIndexerProfile;
    Present    : Boolean;
  end;

function InterfaceSymbolsOf(const pSymbols: TArray<TSymbol>): TArray<TSymbol>;
var
  Acc: TList<TSymbol>;
  Sym: TSymbol;
begin
  Acc:= TList<TSymbol>.Create;
  try
    for Sym in pSymbols do
      if SameText(Sym.Section, 'interface')
         and not (Sym.Kind in [skUnit, skParam, skLocalVar]) then
        Acc.Add(Sym);
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

function SymbolToJson(const pSymbol: TSymbol): TJSONObject;
begin
  Result:= TJSONObject.Create;
  { The symbol ID is carried because the diff's routine rule joins on
    refs.symbol_id, and only a baseline captured FROM THE INDEX has ids to
    join with. A parser-side symbol has none, which is why the NEW side is
    never the baseline. }
  Result.AddPair('id',        TJSONNumber.Create(pSymbol.Id));
  Result.AddPair('kind',      pSymbol.Kind.ToText);
  Result.AddPair('qname',     pSymbol.QualifiedName);
  Result.AddPair('signature', pSymbol.Signature);
  Result.AddPair('modifiers', pSymbol.Modifiers);
  Result.AddPair('heritage',  pSymbol.Heritage);
  Result.AddPair('prop_access', pSymbol.PropAccess);
  Result.AddPair('is_helper', TJSONBool.Create(pSymbol.IsHelper));
  Result.AddPair('directives', pSymbol.Directives);
end;

function InterfaceUsesOf(const pUses: TArray<TUnitUse>): TArray<string>;
var
  Acc: TList<string>;
  U  : TUnitUse;
begin
  Acc:= TList<string>.Create;
  try
    for U in pUses do
      if U.Section = uusInterface then
        Acc.Add(U.UnitName);
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

function ReadSourceLines(const pBytes: TBytes): TArray<string>;
begin
  { Split on LF only, and from the bytes the PARSER SAW. The preprocessor blanks
    dead branches in place, preserving byte length and LF positions, so symbol
    line numbers index into exactly this array. Splitting on CRLF here would
    shift every line and silently mis-slice every inline body. }
  Result:= TEncoding.UTF8.GetString(pBytes).Split([#10]);
end;

function BuildIndexSide(const pStore: ISymbolStore; const pUnitPath: string;
  const pSourceLines: TArray<string>; out ASide: TSurfaceSide): Boolean;
var
  FileId: Int64;
begin
  ASide  := Default(TSurfaceSide);
  Result := False;
  if pStore = nil then
    Exit;

  ASide.Profile:= IndexProfileOf(pStore);
  FileId:= pStore.FindFileIdByPath(pUnitPath);
  if FileId <= 0 then
    Exit;

  ASide.Symbols    := pStore.FindSymbolsByFile(pUnitPath);
  ASide.UsesEntries:= pStore.GetUnitUsesForFile(FileId);
  ASide.Fingerprint:= SurfaceFingerprint(ASide.Symbols, ASide.UsesEntries,
    CollectInlineBodies(ASide.Symbols, pSourceLines));
  ASide.Present:= True;
  Result:= True;
end;

function WriteBaselineFile(const pPath, pUnitPath: string;
  const pSide: TSurfaceSide): Boolean;
var
  Root   : TJSONObject;
  Symbols: TJSONArray;
  UsesArr: TJSONArray;
  Sym    : TSymbol;
  U      : string;
begin
  Root:= TJSONObject.Create;
  try
    Root.AddPair('schema', LINT_TREE_BASELINE_SCHEMA);
    Root.AddPair('unit', pUnitPath);
    Root.AddPair('fingerprint', pSide.Fingerprint);
    { Both stamps, because a baseline read back against a different extraction
      is not comparable and must be refused rather than diffed. }
    Root.AddPair('extractor_version', pSide.Profile.ExtractorVersion);
    Root.AddPair('schema_version',
      TJSONNumber.Create(pSide.Profile.SchemaVersion));
    Root.AddPair('platform', pSide.Profile.Platform);

    Symbols:= TJSONArray.Create;
    for Sym in InterfaceSymbolsOf(pSide.Symbols) do
      Symbols.AddElement(SymbolToJson(Sym));
    Root.AddPair('symbols', Symbols);

    UsesArr:= TJSONArray.Create;
    for U in InterfaceUsesOf(pSide.UsesEntries) do
      UsesArr.Add(U);
    Root.AddPair('uses', UsesArr);

    try
      { WriteAllText with TEncoding.UTF8 emits a BOM, and a Delphi reader strips
        it again -- so a Delphi-to-Delphi round trip hides the problem while every
        strict JSON parser (the plugin's, python's, jq's) fails on byte 0.
        MEASURED 2026-09-10: the first baseline written here was rejected by
        json.load. GetBytes adds no preamble. }
      TFile.WriteAllBytes(pPath, TEncoding.UTF8.GetBytes(Root.ToJSON));
      Result:= True;
    except
      on E: Exception do
      begin
        { The caller turns False into an exit-2 naming the path. Swallowing
          the class here is deliberate -- a read-only volume, a missing
          directory and a locked file are the same outcome to the caller --
          but it is caught as Exception rather than bare, so an
          EOutOfMemory still propagates. }
        Result:= False;
      end;
    end;
  finally
    Root.Free;
  end;
end;

{ ---- the diff, and the findings it drives ---------------------------------- }

function BaselineSymbolsOf(const pRoot: TJSONObject): TArray<TBaselineSymbol>;
var
  Arr: TJSONArray;
  I  : Integer;
  Obj: TJSONObject;
  Acc: TList<TBaselineSymbol>;
  B  : TBaselineSymbol;
begin
  Acc:= TList<TBaselineSymbol>.Create;
  try
    Arr:= pRoot.GetValue('symbols') as TJSONArray;
    if Arr <> nil then
      for I:= 0 to Arr.Count - 1 do
      begin
        Obj:= Arr.Items[I] as TJSONObject;
        if Obj = nil then
          Continue;
        B           := Default(TBaselineSymbol);
        B.Id        := Obj.GetValue<Int64>('id', 0);
        B.Kind      := Obj.GetValue<string>('kind', '');
        B.QName     := Obj.GetValue<string>('qname', '');
        B.Signature := Obj.GetValue<string>('signature', '');
        Acc.Add(B);
      end;
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

function IsRoutineKind(const pKind: string): Boolean;
begin
  { The kinds whose references the resolver binds to a symbol id. Everything
    else goes down the name-join path (B3 step 2) or is not reportable at all
    -- which the report states rather than implies. }
  Result:= SameText(pKind, 'procedure') or SameText(pKind, 'function')
        or SameText(pKind, 'method')    or SameText(pKind, 'constructor')
        or SameText(pKind, 'destructor');
end;

function SymbolKeyOf(const pQName, pSignature: string): string;
begin
  { (qualified_name, signature), not the name alone: overloads share a name, so
    dropping one overload of three is a REMOVED entry that keying on the name
    would hide behind its surviving siblings. }
  Result:= LowerCase(pQName) + '|' + pSignature;
end;

function ComputeDelta(const pOld: TArray<TBaselineSymbol>;
                      const pNew: TArray<TSymbol>): TLintTreeDelta;
var
  NewKeys : TDictionary<string, Boolean>;
  NewNames: TDictionary<string, Boolean>;
  OldNames: TDictionary<string, Boolean>;
  Removed : TList<TBaselineSymbol>;
  Changed : TList<TBaselineSymbol>;
  Added   : TList<string>;
  O       : TBaselineSymbol;
  S       : TSymbol;
begin
  Result  := Default(TLintTreeDelta);
  NewKeys := TDictionary<string, Boolean>.Create;
  NewNames:= TDictionary<string, Boolean>.Create;
  OldNames:= TDictionary<string, Boolean>.Create;
  Removed := TList<TBaselineSymbol>.Create;
  Changed := TList<TBaselineSymbol>.Create;
  Added   := TList<string>.Create;
  try
    for S in pNew do
    begin
      if not SameText(S.Section, 'interface') then
        Continue;
      if S.Kind in [skUnit, skParam, skLocalVar] then
        Continue;
      NewKeys .AddOrSetValue(SymbolKeyOf(S.QualifiedName, S.Signature), True);
      NewNames.AddOrSetValue(LowerCase(S.QualifiedName), True);
    end;

    for O in pOld do
    begin
      OldNames.AddOrSetValue(LowerCase(O.QName), True);
      if NewKeys.ContainsKey(SymbolKeyOf(O.QName, O.Signature)) then
        Continue;
      { The name survives but the exact (name, signature) pair does not: the
        declaration CHANGED. The name is gone entirely: REMOVED. Both break a
        dependent; they read differently to a human and the message says which. }
      if NewNames.ContainsKey(LowerCase(O.QName)) then
        Changed.Add(O)
      else
        Removed.Add(O);
    end;

    for S in pNew do
    begin
      if not SameText(S.Section, 'interface') then
        Continue;
      if S.Kind in [skUnit, skParam, skLocalVar] then
        Continue;
      if not OldNames.ContainsKey(LowerCase(S.QualifiedName)) then
        Added.Add(S.QualifiedName);
    end;

    Result.Removed:= Removed.ToArray;
    Result.Changed:= Changed.ToArray;
    Result.Added  := Added.ToArray;
  finally
    Added.Free;
    Changed.Free;
    Removed.Free;
    OldNames.Free;
    NewNames.Free;
    NewKeys.Free;
  end;
end;

{ One pass over one list. Called twice so the VERB is decided by which list the
  symbol came from rather than re-derived inside the loop -- the first draft
  computed it from the symbol itself and got it wrong for every entry. }
procedure CollectRoutineFindings(const pCtx : TFindingCtx;
                                 const pGone: TArray<TBaselineSymbol>;
                                 const pVerb: string);
var
  O   : TBaselineSymbol;
  Refs: TArray<TReference>;
  Ref : TReference;
  F   : TLintTreeFinding;
begin
  for O in pGone do
  begin
    if not IsRoutineKind(O.Kind) then
      Continue;
    { A baseline captured from the index always carries ids; a zero means the
      baseline was hand-written or came from the parser side, and joining on it
      would silently match nothing. Skipped rather than guessed. }
    if O.Id <= 0 then
      Continue;

    { KEYED ON symbol_id ALONE, WITH NO KIND FILTER. CORRECTED 2026-09-10.
      The design spec recorded "refs.symbol_id is populated for kind='call'
      edges ONLY" from a 5-row fixture, and the draft rule filtered on it.
      Re-measured on a fixture containing a PARENLESS function call
      (`I := W.Value;` where `function Value: Integer`), the resolved row came
      back as kind='member-access' pointing at uB.TWidget.Value.
      docs\INDEX-SCHEMA.md had said so all along: "Populated for `call` and
      `member-access` refs only". A kind='call' filter would therefore drop
      every parenless call -- property-style getters and parameterless
      functions, which are everywhere in Delphi -- SILENTLY, reading as an
      all-clear. A resolved symbol_id is unambiguous by construction, so
      dropping the kind filter is strictly safer, not looser. }
    Refs:= pCtx.Store.FindReferencesTo(O.Id);
    for Ref in Refs do
    begin
      if not pCtx.InClosure.ContainsKey(Ref.FileId) then
        Continue;
      F         := Default(TLintTreeFinding);
      F.FilePath:= pCtx.InClosure[Ref.FileId];
      F.Line    := Ref.StartLine;
      F.Col     := Ref.StartCol;
      F.Rule    := 'stale-interface-reference';
      F.Severity:= 'warning';
      F.RefKind := Ref.Kind;
      F.Unchecked:= pCtx.Unchecked.ContainsKey(Ref.FileId);
      F.Message := Format('the edited unit %s %s; this reference will not ' +
        'compile until it is updated', [pVerb, O.QName]);
      pCtx.Acc.Add(F);
    end;
  end;
end;

{ The kind strings are TSymbolKind.ToText's, taken from KindText in
  Core.Model.pas rather than guessed. The first draft of this file invented
  'type_alias', 'const_decl' and 'var_decl'; none of the three exists, so the
  whole name-join path matched nothing and reported a clean run -- silently,
  which is the failure mode this verb exists to prevent. The real values are
  class interface record enum type / var const. }
function IsTypeKind(const pKind: string): Boolean;
begin
  Result:= SameText(pKind, 'class')  or SameText(pKind, 'interface')
        or SameText(pKind, 'record') or SameText(pKind, 'enum')
        or SameText(pKind, 'type');
end;

function IsDataKind(const pKind: string): Boolean;
begin
  Result:= SameText(pKind, 'const') or SameText(pKind, 'var');
end;

function BareNameOf(const pQName: string): string;
var
  P: Integer;
begin
  P:= LastDelimiter('.', pQName);
  if P > 0 then
    Result:= Copy(pQName, P + 1, MaxInt)
  else
    Result:= pQName;
end;

{ Would a bare-name join for S be AMBIGUOUS?

  THE FLOOD THIS PREVENTS. refs.name_text stores the BARE member name, so
  `Create`, `Free`, `Execute` and `Count` match across the whole corpus. Removing
  a method named Create from B and joining on the name would light up every
  dependent that constructs anything at all.

  THE GATE, AND HOW IT DIFFERS FROM THE PLAN. The plan asks: "no OTHER unit
  VISIBLE TO D declares an interface-level S". Per-dependent visibility needs the
  machinery inside TProjectLintRules.Run, which is not yet a callable helper.
  This asks the strictly STRONGER question -- does any unit ANYWHERE in the index
  other than the edited one declare an interface-level S -- so it reports a
  strict SUBSET of what the plan's gate would: never a false positive the plan
  would have avoided, sometimes a silence where the plan would have spoken.

  That trade is only acceptable because the silence is COUNTED and reported
  (`suppressed_ambiguous`). An unreported suppression would be exactly the
  failure this whole verb exists to prevent -- an all-clear that is really an
  "I did not look". }
function NameIsAmbiguous(const pStore: ISymbolStore; const pBareName: string;
  const pOwnUnitFileId: Int64): Boolean;
var
  Candidates: TArray<TSymbol>;
  S         : TSymbol;
begin
  Result:= False;
  if pBareName = '' then
    Exit(True);

  { A generous cap: the question is only "is there more than one declarer", so
    the first foreign hit answers it and the limit never truncates a decision,
    only a scan that has already succeeded. }
  Candidates:= pStore.FindSymbolsByPrefix(pBareName, AMBIGUITY_SCAN_LIMIT);
  for S in Candidates do
  begin
    if not SameText(S.Name, pBareName) then
      Continue;
    if not SameText(S.Section, 'interface') then
      Continue;
    if S.FileId = pOwnUnitFileId then
      Continue;
    Exit(True);
  end;
end;

{ Types, consts and vars: joined by NAME, because the resolver does not bind
  their refs to a symbol id. MEASURED 2026-09-10 on the A-uses-B fixture:

    TWidget  type_use  symbol_id=NULL      BConst  read  symbol_id=NULL
    TWidget  read      symbol_id=NULL      BVar    read  symbol_id=NULL

  so the symbol_id path that carries every routine finding is empty here. The
  `read` kind for a const and a var was a PREDICTION in the plan and is now
  measured; type_use likewise. }
procedure CollectNameJoinFindings(const pCtx       : TFindingCtx;
                                  const pGone      : TArray<TBaselineSymbol>;
                                  const pVerb      : string;
                                  var   ASuppressed: Integer);
var
  O    : TBaselineSymbol;
  Bare : string;
  Dep  : TDependentFile;
  Refs : TArray<TReference>;
  Ref  : TReference;
  F    : TLintTreeFinding;
  Want : Boolean;
begin
  for O in pGone do
  begin
    if not (IsTypeKind(O.Kind) or IsDataKind(O.Kind)) then
      Continue;

    Bare:= BareNameOf(O.QName);
    if NameIsAmbiguous(pCtx.Store, Bare, pCtx.OwnFileId) then
    begin
      Inc(ASuppressed);
      Continue;
    end;

    for Dep in pCtx.Closure do
    begin
      Refs:= pCtx.Store.GetReferencesFromFile(Dep.FileId);
      for Ref in Refs do
      begin
        if not SameText(Ref.NameText, Bare) then
          Continue;
        { Kinds measured on the fixture. A type is referenced as `type_use` and
          also as `read` (TWidget.Create reads the class reference); a const or
          var is `read`, and a var may also be written. Anything else -- a
          member-access on a removed TYPE, say -- is left alone rather than
          guessed at. }
        if IsTypeKind(O.Kind) then
          Want:= SameText(Ref.Kind, 'type_use') or SameText(Ref.Kind, 'read')
        else
          Want:= SameText(Ref.Kind, 'read') or SameText(Ref.Kind, 'write');
        if not Want then
          Continue;

        F          := Default(TLintTreeFinding);
        F.FilePath := Dep.Path;
        F.Line     := Ref.StartLine;
        F.Col      := Ref.StartCol;
        F.Rule     := 'stale-interface-reference';
        F.Severity := 'warning';
        F.RefKind  := Ref.Kind;
        F.Unchecked:= pCtx.Unchecked.ContainsKey(Dep.FileId);
        F.Message  := Format('the edited unit %s %s; this reference will not ' +
          'compile until it is updated', [pVerb, O.QName]);
        pCtx.Acc.Add(F);
      end;
    end;
  end;
end;

function BuildFindings(const pStore     : ISymbolStore;
                       const pDelta     : TLintTreeDelta;
                       const pClosure   : TArray<TDependentFile>;
                       const pUnchecked : TDictionary<Int64, Boolean>;
                       const pOwnFileId : Int64;
                       out   ASuppressed: Integer): TArray<TLintTreeFinding>;
var
  InClosure: TDictionary<Int64, string>;
  Acc      : TList<TLintTreeFinding>;
  Dep      : TDependentFile;
  Ctx      : TFindingCtx;
begin
  ASuppressed:= 0;
  InClosure  := TDictionary<Int64, string>.Create;
  Acc        := TList<TLintTreeFinding>.Create;
  try
    for Dep in pClosure do
      InClosure.AddOrSetValue(Dep.FileId, Dep.Path);

    Ctx          := Default(TFindingCtx);
    Ctx.Store    := pStore;
    Ctx.OwnFileId:= pOwnFileId;
    Ctx.Closure  := pClosure;
    Ctx.InClosure:= InClosure;
    Ctx.Unchecked:= pUnchecked;
    Ctx.Acc      := Acc;

    { Routines first: they carry a resolved symbol_id, so their findings are
      exact. The name-join path below is the best available answer for kinds
      the resolver does not bind, and it is gated. }
    CollectRoutineFindings(Ctx, pDelta.Removed, 'no longer declares');
    CollectRoutineFindings(Ctx, pDelta.Changed,
      'has changed the declaration of');

    CollectNameJoinFindings(Ctx, pDelta.Removed, 'no longer declares',
      ASuppressed);
    CollectNameJoinFindings(Ctx, pDelta.Changed,
      'has changed the declaration of', ASuppressed);

    Result:= Acc.ToArray;
  finally
    Acc.Free;
    InClosure.Free;
  end;
end;

{ A dependent whose file on disk is NEWER than the row the index holds for it
  was edited after the index was built, so every ref position taken from that
  row may be stale. Such findings are still REPORTED -- suppressing them would
  hide real breakage -- but FLAGGED, because a line number from a stale row
  points at plausible code in the wrong place, which is worse than an obvious
  error. This repo has a scar for exactly that: find-callers once returned two
  of three callers at a consistent 62-line offset, and every hit rendered real,
  plausible Delphi from the wrong place. }
function CollectUnchecked(const pStore  : ISymbolStore;
                          const pClosure: TArray<TDependentFile>):
                          TDictionary<Int64, Boolean>;
var
  Dep      : TDependentFile;
  DiskTime : TDateTime;
  DiskUnix : Int64;
  IndexUnix: Int64;
begin
  Result:= TDictionary<Int64, Boolean>.Create;
  for Dep in pClosure do
  begin
    { FileAge rather than TFile.GetLastWriteTime: it reports failure by returning
      False instead of raising, so a deleted or locked dependent needs no
      exception handler whose only action would be to set the same flag. }
    if not FileAge(Dep.Path, DiskTime) then
    begin
      Result.AddOrSetValue(Dep.FileId, True);
      Continue;
    end;
    IndexUnix:= pStore.GetFileMTime(Dep.FileId);
    if IndexUnix <= 0 then
    begin
      { No recorded mtime at all -- treat as unverifiable rather than current.
        A MISSING stamp is STALE, not fresh. }
      Result.AddOrSetValue(Dep.FileId, True);
      Continue;
    end;
    DiskUnix:= DateTimeToUnix(TTimeZone.Local.ToUniversalTime(DiskTime));
    { One second of slack: FAT/network timestamps and the indexer's own read can
      differ by sub-second amounts, and flagging every dependent as unchecked
      would make the flag meaningless. }
    if DiskUnix > IndexUnix + 1 then
      Result.AddOrSetValue(Dep.FileId, True);
  end;
end;

function ReadBaselineFile(const pPath: string; out AFingerprint: string;
  out AProfile: TIndexerProfile; out ASymbols: TArray<TBaselineSymbol>;
  out AWhy: string): Boolean;
var
  Text: string;
  Root: TJSONObject;
  Num : TJSONNumber;
begin
  AFingerprint:= '';
  AProfile    := Default(TIndexerProfile);
  ASymbols    := [];
  AWhy        := '';
  Result      := False;

  if not TFile.Exists(pPath) then
  begin
    AWhy:= 'baseline file not found: ' + pPath;
    Exit;
  end;

  try
    Text:= TFile.ReadAllText(pPath, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      AWhy:= 'baseline unreadable: ' + E.Message;
      Exit;
    end;
  end;

  Root:= TJSONObject.ParseJSONValue(Text) as TJSONObject;
  if Root = nil then
  begin
    AWhy:= 'baseline is not valid JSON';
    Exit;
  end;
  try
    AFingerprint:= Root.GetValue<string>('fingerprint', '');
    AProfile.ExtractorVersion:= Root.GetValue<string>('extractor_version', '');
    Num:= Root.GetValue('schema_version') as TJSONNumber;
    if Num <> nil then
      AProfile.SchemaVersion:= Num.AsInt;
    AProfile.Platform:= Root.GetValue<string>('platform', '');
    if AFingerprint = '' then
    begin
      AWhy:= 'baseline carries no fingerprint';
      Exit;
    end;
    ASymbols:= BaselineSymbolsOf(Root);
    Result  := True;
  finally
    Root.Free;
  end;
end;

function UncheckedSuffix(const pUnchecked: Boolean): string;
begin
  { Said out loud rather than left to a JSON field the text reader never sees:
    this dependent changed on disk after the index was built, so the LINE is
    not to be trusted even though the finding is. }
  if pUnchecked then
    Result:= '   (UNCHECKED: this file changed since it was indexed)'
  else
    Result:= '';
end;

function QNameArray(const pSymbols: TArray<TBaselineSymbol>): TJSONArray;
var
  S: TBaselineSymbol;
  O: TJSONObject;
begin
  Result:= TJSONArray.Create;
  for S in pSymbols do
  begin
    O:= TJSONObject.Create;
    O.AddPair('qname', S.QName);
    O.AddPair('kind',  S.Kind);
    O.AddPair('signature', S.Signature);
    Result.AddElement(O);
  end;
end;

function StringArray(const pItems: TArray<string>): TJSONArray;
var
  S: string;
begin
  Result:= TJSONArray.Create;
  for S in pItems do
    Result.Add(S);
end;

function FindingArray(const pFindings: TArray<TLintTreeFinding>): TJSONArray;
var
  F: TLintTreeFinding;
  O: TJSONObject;
begin
  Result:= TJSONArray.Create;
  for F in pFindings do
  begin
    O:= TJSONObject.Create;
    O.AddPair('file',     F.FilePath);
    O.AddPair('line',     TJSONNumber.Create(F.Line));
    O.AddPair('col',      TJSONNumber.Create(F.Col));
    O.AddPair('rule',     F.Rule);
    O.AddPair('severity', F.Severity);
    O.AddPair('message',  F.Message);
    O.AddPair('ref_kind', F.RefKind);
    O.AddPair('unchecked', TJSONBool.Create(F.Unchecked));
    Result.AddElement(O);
  end;
end;

{ One report, one renderer. RenderJson took eight parameters and RenderText
  seven of the same ones, which is how the two drifted apart in the first draft:
  the JSON branch carried `profile` and the text branch silently did not. A
  record makes adding a field to the report a single edit instead of two
  parallel argument lists, which matters because B3 adds four more. }
function Render(const pOptions: TLintTreeOptions;
  const pReport: TLintTreeReport): string;
var
  Root: TJSONObject;
  Fp  : TJSONObject;
  Base: TJSONObject;
  Cl  : TJSONObject;
  NR  : TJSONArray;
  SB  : TStringBuilder;
  F   : TLintTreeFinding;
begin
  if not SameText(pOptions.Format, 'json') then
  begin
    SB:= TStringBuilder.Create;
    try
      SB.AppendLine('lint-tree: ' + pOptions.UnitPath);
      if pReport.ParseError then
      begin
        SB.AppendLine('  parse error: ' + pReport.Reason);
        SB.AppendLine('  no dependents were analysed.');
      end
      else if pReport.Reason <> '' then
        SB.AppendLine('  refused: ' + pReport.Reason)
      else
      begin
        if pReport.Changed then
          SB.AppendLine('  interface CHANGED against the ' + pReport.OldSource)
        else
          SB.AppendLine('  interface unchanged against the ' + pReport.OldSource
            + ' -- no dependent can be affected.');
        SB.AppendLine('  new ' + Copy(pReport.NewFp, 1, FINGERPRINT_ECHO_CHARS));
        SB.AppendLine('  old ' + Copy(pReport.OldFp, 1, FINGERPRINT_ECHO_CHARS));
        if pReport.HasClosure then
          SB.AppendLine(Format('  %d dependent(s), %d of them direct  [%d ms]',
            [pReport.TotalCnt, pReport.DirectCnt, pReport.ClosureMs]));
        for F in pReport.Findings do
          SB.AppendLine(Format('  %s:%d:%d  [%s] %s: %s%s',
            [F.FilePath, F.Line, F.Col, F.Severity, F.Rule, F.Message,
             UncheckedSuffix(F.Unchecked)]));
        if Length(pReport.Findings) = 0 then
          SB.AppendLine('  no reportable reference broke -- see not_reportable');
        if pReport.Suppressed > 0 then
          SB.AppendLine(Format('  %d name(s) NOT checked: another unit also ' +
            'declares them, so a name join would be ambiguous',
            [pReport.Suppressed]));
      end;
      Exit(SB.ToString);
    finally
      SB.Free;
    end;
  end;

  Root:= TJSONObject.Create;
  try
    Root.AddPair('schema', LINT_TREE_SCHEMA);
    Root.AddPair('unit', pOptions.UnitPath);
    Root.AddPair('changed', TJSONBool.Create(pReport.Changed));
    Root.AddPair('parse_error', TJSONBool.Create(pReport.ParseError));
    if pReport.Reason <> '' then
      Root.AddPair('reason', pReport.Reason);

    Fp:= TJSONObject.Create;
    Fp.AddPair('new', pReport.NewFp);
    Fp.AddPair('old', pReport.OldFp);
    Root.AddPair('fingerprint', Fp);

    Base:= TJSONObject.Create;
    Base.AddPair('source', pReport.OldSource);
    Base.AddPair('extractor_version', pReport.Profile.ExtractorVersion);
    Base.AddPair('schema_version',
      TJSONNumber.Create(pReport.Profile.SchemaVersion));
    Root.AddPair('baseline', Base);

    { NOT 'changed' for the delta array. The plan's schema names BOTH the
      boolean and the array `changed`, which emits a duplicate JSON key; a
      strict parser keeps the LAST, so the primary answer -- did anything
      change at all -- silently became an array. Caught 2026-09-10 by parsing
      the output instead of reading it. The boolean keeps the plain name
      because it is what every consumer branches on. }
    Root.AddPair('removed_symbols', QNameArray(pReport.Delta.Removed));
    Root.AddPair('changed_symbols', QNameArray(pReport.Delta.Changed));
    Root.AddPair('added_symbols',   StringArray(pReport.Delta.Added));

    if pReport.HasClosure then
    begin
      Cl:= TJSONObject.Create;
      Cl.AddPair('direct', TJSONNumber.Create(pReport.DirectCnt));
      Cl.AddPair('total',  TJSONNumber.Create(pReport.TotalCnt));
      Cl.AddPair('ms',     TJSONNumber.Create(pReport.ClosureMs));
      Root.AddPair('closure', Cl);
    end;

    Root.AddPair('buffer_set', TJSONArray.Create);
    Root.AddPair('findings', FindingArray(pReport.Findings));
    Root.AddPair('suppressed_ambiguous',
      TJSONNumber.Create(pReport.Suppressed));
    Root.AddPair('compiled', TJSONBool.Create(pReport.Compiled));

    { Stated rather than implied: an empty findings list means "no reportable
      row", not "nothing is broken". Property, field and member-access changes
      are not reported, and a caller must not read silence as coverage. }
    NR:= TJSONArray.Create;
    NR.Add('property');
    NR.Add('field');
    Root.AddPair('not_reportable', NR);

    Result:= Root.ToJSON;
  finally
    Root.Free;
  end;
end;

{ Argument and resource validation, collected here so RunLintTree below reads as
  the ALGORITHM rather than as a wall of guard clauses. Returns '' when the run
  may proceed; otherwise the message the caller prints to stderr before exiting
  2. Splitting it out is not cosmetic -- B3 adds the closure query and the diff
  to RunLintTree, and a routine that is half validation is where a new early
  return quietly acquires the wrong default. }
function ValidateAndResolve(const pOptions  : TLintTreeOptions;
                            const pOpenStore: TStoreOpener;
                            out   AStore    : ISymbolStore;
                            out   ADiskLines: TArray<string>;
                            out   AIndexSide: TSurfaceSide): string;
begin
  AStore    := nil;
  ADiskLines:= [];
  AIndexSide:= Default(TSurfaceSide);

  if pOptions.UnitPath = '' then
    Exit('ERROR: lint-tree needs --unit <file.pas>');
  if not TFile.Exists(pOptions.UnitPath) then
    Exit('ERROR: unit not found: ' + pOptions.UnitPath);
  if pOptions.DbPath = '' then
    Exit('ERROR: lint-tree needs --db <index.sqlite>');

  AStore:= pOpenStore(pOptions.DbPath);
  if AStore = nil then
    Exit('ERROR: could not open index: ' + pOptions.DbPath);

  { The index side is built from the file ON DISK, because that is the text the
    index parsed. The buffer may be ahead of it; that difference is the whole
    point of the comparison and must not be erased by feeding both sides the
    same lines. A unit that cannot be read still has an index side -- body
    hashes are simply omitted, symmetrically, by passing no lines. }
  try
    ADiskLines:= ReadSourceLines(
      EnsureUtf8Bytes(TFile.ReadAllBytes(pOptions.UnitPath)));
  except
    on E: Exception do
      { No disk text means no body hashes -- for BOTH sides, because the
        index side is the only one built from this array. Omitting them
        symmetrically is safe; computing one side's from different text
        would not be. }
      ADiskLines:= [];
  end;

  if not BuildIndexSide(AStore, pOptions.UnitPath, ADiskLines, AIndexSide) then
    Exit('ERROR: this index does not cover ' + pOptions.UnitPath);

  Result:= '';
end;

{ REVIEWED 2026-09-10, dl:ok too-many-exit-points. Ten exits, and they stay.
  The rule's own advice is "consolidate exits OR use guard clauses" -- these
  ARE guard clauses: every one is a distinct terminal outcome that names what
  went wrong, and each was already reduced from fourteen by moving argument
  and resource validation into ValidateAndResolve. Threading a status variable
  through the remaining ten to reach a single exit is the shape that produces
  a wrong DEFAULT when a later branch forgets to set it, which for this verb
  means reporting changed:false -- a silent all-clear -- instead of refusing.
  Re-examine when B3 adds the closure and diff steps. }
{ ---- tier 3: compile the dependents against the unsaved buffer -------------- }

{ WHY A SHADOW DIRECTORY AND NOT THE REAL FILES. The 2026-09-08 ruling: a ghost
  compile must never write the user's source. All dirty buffers go into ONE
  shadow dir, and dcc is invoked with that dir FIRST on the unit search path, so
  a dependent compiled from its real location still binds the SHADOW copy of the
  edited unit. That is also why this cannot be an msbuild project build: a .dproj
  binds its units by their own paths and a shadow cannot displace them.

  THE PRECEDENCE IS THE WHOLE MECHANISM, AND IT IS A PREDICTION UNTIL A GUARD
  PROVES IT. dcc will happily take a stale B.dcu over a shadow B.pas if the
  search order lets it, in which case this tier reports success on exactly the
  edit it was built to catch. The guard therefore has to build a stale .dcu
  FIRST and prove the shadow still wins; without that step it proves nothing. }
function CompileDependents(const pOptions   : TLintTreeOptions;
                           const pPlatform  : string;
                           const pCompile   : TUnitCompiler;
                           const pClosure   : TArray<TDependentFile>;
                           const pBufferBytes: TBytes;
                           const pUnchecked : TDictionary<Int64, Boolean>;
                           out   AShadowUsed: string): TArray<TLintTreeFinding>;
var
  ShadowDir : string;
  Acc       : TList<TLintTreeFinding>;
  Dep       : TDependentFile;
  Raw       : TArray<TCompilerFinding>;
  CF        : TCompilerFinding;
  F         : TLintTreeFinding;
  Ordered   : TList<TDependentFile>;
begin
  AShadowUsed:= '';
  Acc        := TList<TLintTreeFinding>.Create;
  Ordered    := TList<TDependentFile>.Create;
  try
    ShadowDir:= TPath.Combine(TPath.GetTempPath,
      Format('draglint_tree_%d_%d', [GetCurrentProcessId, GetTickCount64]));
    AShadowUsed:= ShadowDir;
    try
      TDirectory.CreateDirectory(ShadowDir);
      { The edited unit, under its OWN file name, is the only thing staged. Its
        dependents are compiled from their real locations -- staging them too
        would hide a dependent that is itself unsaved, and tier 2 already marks
        those UNCHECKED rather than pretending to have checked them. }
      TFile.WriteAllBytes(
        TPath.Combine(ShadowDir, ExtractFileName(pOptions.UnitPath)),
        pBufferBytes);

      { EVERY unit that will be compiled must be staged, not just the edited
        one. CompileUnitInContext compiles `<shadow>\<basename of AUnitPath>`
        (CLI.pas:18739), so naming a dependent whose file is NOT in the shadow
        asks dcc to compile a path that does not exist -- which produced no
        findings at all and read as a clean compile. MEASURED 2026-09-10: the
        compile-shadow guard went red on exactly that, and ghost-check, which
        stages every overlay entry, reported the E2003 the same fixture owed.
        Dependents are staged from DISK because they are unedited; the edited
        unit above is staged from the BUFFER. }
      { STAGING IS LOAD-BEARING -- REMOVING IT WAS TRIED AND THE GUARD CAUGHT IT.

        2026-09-11: staging every dependent into the shadow looked like pure cost
        (67 project units recompiled from source per invocation, with the
        project's 1,465 prebuilt DCUs shadowed out of reach). Removing it and
        compiling each dependent at its REAL path made
        run_lint_tree_compile_shadow.ps1 case 2 go RED: the shadow stopped beating
        a stale .dcu -- a silent all-clear, the worst failure this feature has.

        WHY: dcc searches the COMPILED FILE'S OWN DIRECTORY before -U. Compiling
        shadow\A.pas makes the shadow that directory, so shadow\B.pas wins.
        Compiling the real A.pas makes the real directory that directory, and a
        stale B.dcu sitting there wins instead. Being first on -U is not enough.

        So the cost is real but this is not where to take it out. The fix is T6:
        keep the staging, compile ONCE via a probe unit instead of 207 times. }
      for Dep in pClosure do
        if not SameText(Dep.Path, pOptions.UnitPath) then
          if TFile.Exists(Dep.Path) then
            TFile.Copy(Dep.Path,
              TPath.Combine(ShadowDir, ExtractFileName(Dep.Path)), True);

      { Direct users first, then the rest. A break usually surfaces in a direct
        user, and a developer reading a truncated list wants that one first. }
      for Dep in pClosure do
        if Dep.IsDirect then
          Ordered.Add(Dep);
      for Dep in pClosure do
        if not Dep.IsDirect then
          Ordered.Add(Dep);

      { T6: ONE dcc INVOCATION, NOT 207.

        Every dependent is already staged in the shadow (that staging is what
        creates shadow precedence -- see the note above). So a synthetic unit
        whose interface `uses` all of them makes dcc compile the edited buffer
        once, each dependent once, and everything else from DCU -- with the RTL,
        DevExpress and Spring symbol tables loaded ONCE instead of 207 times.
        That is what the IDE's own incremental build does.

        Measured before this change: ~67 project units recompiled from source on
        EVERY one of 207 invocations.

        dcc stops at the first unit with errors, so a broken dependent costs one
        re-run with that unit excluded. Invocations = 1 + independent breakage
        roots, capped at the old cost so this can never be slower. }
      var ProbeName: string:= 'draglint_probe';
      var ProbePath: string:= TPath.Combine(ShadowDir, ProbeName + '.pas');
      var Excluded : TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
      var Runs     : Integer:= 0;
      try
        while Runs <= Ordered.Count do
        begin
          var Names: TStringList:= TStringList.Create;
          try
            Names.Duplicates:= dupIgnore;
            Names.Sorted    := False;
            for Dep in Ordered do
            begin
              var UName: string:= ChangeFileExt(ExtractFileName(Dep.Path), '');
              if Excluded.ContainsKey(LowerCase(UName)) then Continue;
              if Names.IndexOf(UName) < 0 then Names.Add(UName);
            end;
            if Names.Count = 0 then Break;

            { 7-bit ASCII, CRLF, and NO directives of any kind in the generated
              text -- a brace-directive inside a brace comment has broken this
              build four times. }
            var SB: TStringBuilder:= TStringBuilder.Create;
            try
              SB.Append('unit ').Append(ProbeName).Append(';').Append(#13#10);
              SB.Append('interface').Append(#13#10);
              SB.Append('uses').Append(#13#10);
              for var I: Integer:= 0 to Names.Count - 1 do
              begin
                SB.Append('  ').Append(Names[I]);
                if I < Names.Count - 1 then SB.Append(',') else SB.Append(';');
                SB.Append(#13#10);
              end;
              SB.Append('implementation').Append(#13#10);
              SB.Append('end.').Append(#13#10);
              TFile.WriteAllText(ProbePath, SB.ToString, TEncoding.ASCII);
            finally
              SB.Free;
            end;
          finally
            Names.Free;
          end;

          Inc(Runs);
          Raw:= pCompile(ProbePath, pOptions.ProjectPath, pPlatform, ShadowDir);

          var NewlyBroken: string:= '';
          for CF in Raw do
          begin
            if not SameText(CF.Severity, 'Error') then Continue;

            var Base: string:= LowerCase(ChangeFileExt(ExtractFileName(CF.RawPath), ''));
            { The probe's own F2063 'could not compile used unit' echoes carry no
              information the named unit does not already carry. }
            if SameText(Base, ProbeName) then Continue;

            F         := Default(TLintTreeFinding);
            if SameText(ExtractFileName(CF.RawPath), ExtractFileName(pOptions.UnitPath)) then
              F.FilePath:= pOptions.UnitPath
            else
            begin
              { Map a shadow copy back to the dependent's REAL path so an IDE can
                place a marker -- the old loop only remapped the edited unit. }
              F.FilePath:= CF.RawPath;
              for Dep in Ordered do
                if SameText(ExtractFileName(Dep.Path), ExtractFileName(CF.RawPath)) then
                begin
                  F.FilePath:= Dep.Path;
                  Break;
                end;
            end;
            F.Line     := CF.LineNo;
            F.Col      := CF.ColNo;
            F.Rule     := 'stale-interface-reference';
            F.Severity := 'error';
            F.RefKind  := 'compile';
            F.Message  := Format('[compile] %s %s', [CF.Code, CF.Message]);
            Acc.Add(F);

            if (NewlyBroken = '') and not SameText(Base, ChangeFileExt(ExtractFileName(pOptions.UnitPath), '')) then
              NewlyBroken:= Base;
          end;

          { Nothing new broke -> the pass is clean and we are done. }
          if NewlyBroken = '' then Break;
          if Excluded.ContainsKey(NewlyBroken) then Break;
          Excluded.AddOrSetValue(NewlyBroken, True);
        end;
      finally
        Excluded.Free;
        try if TFile.Exists(ProbePath) then TFile.Delete(ProbePath); except end;
      end;
    finally
      { Best-effort. A leftover temp dir is harmless; failing to remove it must
        never turn a successful check into an error. }
      try
        if TDirectory.Exists(ShadowDir) then
          TDirectory.Delete(ShadowDir, True);
      except
        on E: Exception do
          AShadowUsed:= ShadowDir + ' (not removed: ' + E.Message + ')';
      end;
    end;
    Result:= Acc.ToArray;
  finally
    Ordered.Free;
    Acc.Free;
  end;
end;

function RunLintTree(const pOptions   : TLintTreeOptions;  // dl:ok too-many-exit-points@49da
                     const pOpenStore : TStoreOpener;
                     const pParserFor : TParserFactory;
                     const pPreprocess: TPreprocessor;
                     const pCompile   : TUnitCompiler;
                     out   AOutput    : string): Integer;
var
  Store      : ISymbolStore;
  Parser     : IParser;
  SourcePath : string;
  RawBytes   : TBytes;
  ParseBytes : TBytes;
  BufferLines: TArray<string>;
  DiskLines  : TArray<string>;
  ParseRes   : TParseResult;
  IndexSide  : TSurfaceSide;
  Report     : TLintTreeReport;
  BaseProfile: TIndexerProfile;
  BaseSymbols: TArray<TBaselineSymbol>;
  Closure    : TArray<TDependentFile>;
  Unchecked  : TDictionary<Int64, Boolean>;
  Dep        : TDependentFile;
  T0         : TStopwatch;
  ShadowUsed : string;
  EffPlatform: string;
  TargetId   : Int64;
  Why        : string;
begin
  AOutput:= ValidateAndResolve(pOptions, pOpenStore, Store, DiskLines, IndexSide);
  if AOutput <> '' then
    Exit(2);

  Report          := Default(TLintTreeReport);
  Report.Profile  := IndexSide.Profile;
  Report.OldSource:= 'index';
  Report.OldFp    := IndexSide.Fingerprint;

  { --write-baseline captures the index side and stops. It is the FIRST thing an
    edit episode does, before any diff, so the OLD side is pinned to what the
    index held when editing began. }
  if pOptions.WriteBaselinePath <> '' then
  begin
    if not WriteBaselineFile(pOptions.WriteBaselinePath, pOptions.UnitPath,
      IndexSide) then
    begin
      AOutput:= 'ERROR: could not write baseline: ' + pOptions.WriteBaselinePath;
      Exit(2);
    end;
    if SameText(pOptions.Format, 'json') then
      AOutput:= Format('{"schema":"%s","unit":"%s","baseline_written":"%s",' +
        '"fingerprint":"%s","extractor_version":"%s","schema_version":%d}',
        [LINT_TREE_SCHEMA,
         StringReplace(pOptions.UnitPath, '\', '/', [rfReplaceAll]),
         StringReplace(pOptions.WriteBaselinePath, '\', '/', [rfReplaceAll]),
         IndexSide.Fingerprint, IndexSide.Profile.ExtractorVersion,
         IndexSide.Profile.SchemaVersion])
    else
      AOutput:= 'lint-tree: baseline written to ' + pOptions.WriteBaselinePath +
        sLineBreak + '  ' + Copy(IndexSide.Fingerprint, 1, FINGERPRINT_ECHO_CHARS) +
        '  (' + IndexSide.Profile.Describe + ')';
    Exit(0);
  end;

  { ---- the NEW side: parse the buffer the way the index was parsed ---- }

  SourcePath:= pOptions.BufferPath;
  if SourcePath = '' then
    SourcePath:= pOptions.UnitPath;
  if not TFile.Exists(SourcePath) then
  begin
    AOutput:= 'ERROR: buffer not found: ' + SourcePath;
    Exit(2);
  end;

  Parser:= pParserFor(ExtractFileExt(pOptions.UnitPath));
  if Parser = nil then
  begin
    AOutput:= 'ERROR: no parser for ' + ExtractFileExt(pOptions.UnitPath);
    Exit(2);
  end;

  try
    RawBytes:= EnsureUtf8Bytes(TFile.ReadAllBytes(SourcePath));
  except
    on E: Exception do
    begin
      AOutput:= 'ERROR: buffer unreadable: ' + E.Message;
      Exit(2);
    end;
  end;

  ParseBytes:= RawBytes;
  if Assigned(pPreprocess) then
  begin
    try
      { The path passed is the REAL unit path, not the buffer's temp name: the
        define profile is resolved from the unit's project, and a temp file in
        %TEMP% belongs to no project. }
      ParseBytes:= pPreprocess(RawBytes, pOptions.UnitPath);
    except
      on E: Exception do
      begin
        Report.ParseError:= True;
        Report.Reason    := 'profile: ' + E.Message;
        AOutput:= Render(pOptions, Report);
        Exit(0);
      end;
    end;
  end;

  BufferLines:= ReadSourceLines(ParseBytes);
  ParseRes   := Parser.Parse(ParseBytes, pOptions.UnitPath);

  { The parse gate. A buffer mid-edit does not parse, and the honest answer is
    "I cannot tell", never "nothing changed" -- reporting changed:false here
    would be a silent all-clear at exactly the moment the user is typing. }
  if Length(ParseRes.Symbols) = 0 then
  begin
    Report.ParseError:= True;
    Report.Reason    := 'the buffer produced no symbols; it is probably mid-edit';
    AOutput:= Render(pOptions, Report);
    Exit(0);
  end;

  Report.NewFp:= SurfaceFingerprint(ParseRes.Symbols, ParseRes.UsesEntries,
    CollectInlineBodies(ParseRes.Symbols, BufferLines));

  { ---- the OLD side: a baseline file, or the index ---- }

  if pOptions.BaselinePath <> '' then
  begin
    if not ReadBaselineFile(pOptions.BaselinePath, Report.OldFp, BaseProfile,
      BaseSymbols, Why) then
    begin
      AOutput:= 'ERROR: ' + Why;
      Exit(2);
    end;
    Report.OldSource:= 'baseline';
    if not IndexSide.Profile.Matches(BaseProfile) then
    begin
      Report.Reason:= Format('baseline_version: baseline is %s but the index ' +
        'is %s; a diff across extractions would report every routine as changed',
        [BaseProfile.Describe, IndexSide.Profile.Describe]);
      AOutput:= Render(pOptions, Report);
      Exit(0);
    end;
  end;

  Report.Changed:= not SameText(Report.NewFp, Report.OldFp);

  { The closure is only computed when something actually changed. That is not
    an optimisation for its own sake: the overwhelmingly common case in an
    editor is a keystroke inside a method body, where the interface is
    identical and there is nothing to fan out to. Paying for a recursive CTE
    on every idle tick is how a background feature earns a reputation. }
  if Report.Changed and (Length(BaseSymbols) > 0) then
  begin
    Report.Delta:= ComputeDelta(BaseSymbols, ParseRes.Symbols);

    TargetId:= Store.FindFileIdByPath(pOptions.UnitPath);
    T0      := TStopwatch.StartNew;
    Closure := Store.GetDependentFiles(TargetId);
    Report.ClosureMs := T0.ElapsedMilliseconds;
    Report.HasClosure:= True;
    Report.TotalCnt  := Length(Closure);
    for Dep in Closure do
      if Dep.IsDirect then
        Inc(Report.DirectCnt);

    Unchecked:= CollectUnchecked(Store, Closure);
    try
      Report.Findings:= BuildFindings(Store, Report.Delta, Closure, Unchecked,
        TargetId, Report.Suppressed);

      { Tier 3 runs only when ASKED and only when tier 2 already found the
        interface changed. Compiling a dependent closure is seconds to minutes
        of dcc; doing it speculatively on an unchanged interface would burn a
        core for nothing. }
      if pOptions.Compile and Assigned(pCompile) then
      begin
        Report.Compiled := True;
        { --platform is OPTIONAL, and an empty one would hand dcc nothing. The
          index knows which platform it was built for (schema_meta `plat=`), and
          compiling a dependent for a DIFFERENT platform than the index was
          built for would compare two different define profiles. So the index's
          platform is the default, and an explicit --platform overrides it. }
        if pOptions.Platform <> '' then
          EffPlatform:= pOptions.Platform
        else
          EffPlatform:= IndexSide.Profile.Platform;
        Report.Findings := Report.Findings +
          CompileDependents(pOptions, EffPlatform, pCompile, Closure, RawBytes,
            Unchecked, ShadowUsed);
        Report.ShadowDir:= ShadowUsed;
      end;
    finally
      Unchecked.Free;
    end;
  end;

  AOutput:= Render(pOptions, Report);
  Result := 0;
end;

end.
