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
                     out   AOutput    : string): Integer;

implementation

uses
  DRagLint.Core.Encoding;

const
  { How much of a 64-char hash is echoed to a human. Enough to tell two
    fingerprints apart at a glance, short enough to read; the full value is
    always in the JSON. }
  FINGERPRINT_ECHO_CHARS = 16;

type
  { The whole answer, in one place. It used to be eight positional parameters
    to the JSON renderer and seven to the text one, which is how the two
    drifted: the JSON branch carried the profile stamp and the text branch
    silently did not. }
  TLintTreeReport = record
    Changed   : Boolean;
    ParseError: Boolean;
    Reason    : string;
    NewFp     : string;
    OldFp     : string;
    OldSource : string;
    Profile   : TIndexerProfile;
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

function ReadBaselineFile(const pPath: string; out AFingerprint: string;
  out AProfile: TIndexerProfile; out AWhy: string): Boolean;
var
  Text: string;
  Root: TJSONObject;
  Num : TJSONNumber;
begin
  AFingerprint:= '';
  AProfile    := Default(TIndexerProfile);
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
    Result:= True;
  finally
    Root.Free;
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
  NR  : TJSONArray;
  SB  : TStringBuilder;
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

    Root.AddPair('buffer_set', TJSONArray.Create);
    Root.AddPair('findings', TJSONArray.Create);

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
function RunLintTree(const pOptions   : TLintTreeOptions;  // dl:ok too-many-exit-points@49da
                     const pOpenStore : TStoreOpener;
                     const pParserFor : TParserFactory;
                     const pPreprocess: TPreprocessor;
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
      Why) then
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
  AOutput:= Render(pOptions, Report);
  Result := 0;
end;

end.
