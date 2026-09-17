unit DRagLint.Analysis.SurfaceAdapters;

{ The two sides of the fingerprint comparison, and the stamp that says they are
  comparable at all.

  SurfaceFingerprint is a pure function over TArray<TSymbol> / TArray<TUnitUse>.
  It has no opinion about where those arrays came from, and that is exactly the
  hazard this unit exists to contain: lint-tree feeds it from TWO different
  producers -- the PARSER, for an unsaved editor buffer, and the STORE, for what
  the index last saw -- and any skew between them reads as an interface change
  that never happened.

  WHY THE STAMP IS NOT OPTIONAL. `symbols.directives` and `symbols.vis_explicit`
  arrived in schema 22. On a pre-v22 row the read side maps NULL to '' and True
  (documented at Core.Model.pas:218-244). So a baseline captured from a v21 index
  and diffed against a v22 parse yields '' vs 'virtual' for EVERY routine -- a
  whole-surface false positive that looks exactly like a real edit and would fan
  out to every dependent of every unit. The fix is not to normalise the
  difference away, which would silently discard a real signal; it is to REFUSE
  the comparison and say why. TIndexerProfile carries the stamp and Matches is
  the refusal test.

  WHY BODIES NEED THE SOURCE TEXT. An `inline` routine is expanded into its
  CALLER and a generic method is instantiated there, so for those two kinds an
  implementation edit really does change what dependents compile. Detecting them
  is a symbol-level question (`Directives`, schema v22); hashing them is a TEXT
  question, and the text lives in the buffer on one side and on disk on the
  other. CollectInlineBodies takes the lines from whichever side is asking, so
  both produce the same hash for the same bytes. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Analysis.SurfaceFingerprint;

type
  /// <summary>
  /// The identity of the extraction that produced a set of symbols, parsed from
  /// the `indexer_fingerprint` schema_meta value
  /// (`v=1.15.0-alpha;schema=22;pp=1;plat=win64`).
  /// </summary>
  /// <remarks>
  /// Two surfaces are only comparable when their profiles match on extractor
  /// version and schema. Platform and preprocess are carried so the buffer can
  /// be parsed the way the index was, not merely checked.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Analysis.LintTree.pas), declaration (DRagLint.Analysis.SurfaceAdapters.pas), DRagLint.Analysis.LintTree.ReadBaselineFile (DRagLint.Analysis.LintTree.pas), DRagLint.Analysis.LintTree.RunLintTree (DRagLint.Analysis.LintTree.pas), DRagLint.Analysis.SurfaceAdapters.ParseIndexerFingerprint (DRagLint.Analysis.SurfaceAdapters.pas) (+1 more)</para>
  /// <para>Used in units: DRagLint.Analysis.LintTree, DRagLint.Analysis.SurfaceAdapters</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TIndexerProfile = record
    /// <summary>Extractor version, the `v=` field, e.g. `1.15.0-alpha`.</summary>
    ExtractorVersion: string;
    /// <summary>Schema version, the `schema=` field; 0 when absent.</summary>
    SchemaVersion   : Integer;
    /// <summary>True when the index was built with preprocessing on (`pp=1`).</summary>
    Preprocess      : Boolean;
    /// <summary>Target platform, the `plat=` field, e.g. `win64`.</summary>
    Platform        : string;
    /// <summary>The raw value, kept verbatim for diagnostics.</summary>
    Raw             : string;
    /// <summary>
    /// True when a surface stamped <paramref name="pOther"/> may be diffed
    /// against one stamped with Self.
    /// </summary>
    /// <param name="pOther">The other side's profile.</param>
    /// <returns>
    /// True only when extractor version AND schema version are identical.
    /// Platform and preprocess are NOT part of the test: they change which
    /// branches are parsed, which is a real interface difference that the
    /// fingerprint should report rather than refuse.
    /// </returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: SameText</para>
    /// <para>Returns: (ExtractorVersion &lt;&gt; '')</para>
    /// <para>Reads: ExtractorVersion, SchemaVersion</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Analysis.SurfaceAdapters.TIndexerProfile.Describe"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Matches(const pOther: TIndexerProfile): Boolean;
    /// <summary>Human-readable form for a refusal message.</summary>
    /// <returns>e.g. `v=1.15.0-alpha schema=22`.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Analysis.LintTree.RunLintTree (DRagLint.Analysis.LintTree.pas)</para>
    /// <para>Calls: Format</para>
    /// <para>Returns: Format('v=%s schema=%d', [VersionText, SchemaVersion])</para>
    /// <para>Reads: ExtractorVersion, SchemaVersion</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Analysis.SurfaceAdapters.TIndexerProfile.Matches"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Describe: string;
  end;

/// <summary>
/// Parses an `indexer_fingerprint` schema_meta value into its fields.
/// </summary>
/// <param name="pRaw">
/// The stored value, e.g. `v=1.15.0-alpha;schema=22;pp=1;plat=win64`. An empty
/// or unrecognised string yields a zeroed profile whose Matches always fails,
/// which is the safe direction: an unknown provenance is not comparable.
/// </param>
/// <returns>The parsed profile, with <c>Raw</c> set to the input.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Analysis.SurfaceAdapters.IndexProfileOf (DRagLint.Analysis.SurfaceAdapters.pas)</para>
/// <para>Calls: Copy, Default, LowerCase, Pos, StrToIntDef, Trim</para>
/// <para>Returns: Default(TIndexerProfile)</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseIndexerFingerprint(const pRaw: string): TIndexerProfile;

/// <summary>Reads the profile of the index behind <paramref name="pStore"/>.</summary>
/// <param name="pStore">An open store; must not be nil.</param>
/// <returns>
/// The parsed profile. A store whose `indexer_fingerprint` is missing yields a
/// zeroed profile rather than raising, so the caller reports a refusal with a
/// reason instead of a stack trace.
/// </returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Analysis.LintTree.BuildIndexSide (DRagLint.Analysis.LintTree.pas)</para>
/// <para>Calls: Default, DRagLint.Analysis.SurfaceAdapters.ParseIndexerFingerprint, DRagLint.Core.Interfaces.ISymbolStore.GetMetaValue</para>
/// <para>Returns: Default(TIndexerProfile); ParseIndexerFingerprint(pStore.GetMetaValue(META_INDEXER_FINGERPRINT))</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Analysis.SurfaceAdapters.ParseIndexerFingerprint"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetMetaValue"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IndexProfileOf(const pStore: ISymbolStore): TIndexerProfile;

/// <summary>
/// Selects the routines whose bodies are visible to dependents and hashes their
/// implementation spans.
/// </summary>
/// <param name="pSymbols">The unit's symbols, from either side.</param>
/// <param name="pSourceLines">
/// The unit's source, 0-based, from the SAME side as the symbols: the editor
/// buffer for the parser side, the file on disk for the index side. Spans that
/// fall outside these lines are skipped rather than clamped, because a clamped
/// body hashes differently on the two sides and would fan out forever.
/// </param>
/// <returns>One entry per expansion-visible routine; may be empty.</returns>
/// <remarks>
/// Expansion-visible means <c>Directives</c> contains `inline`, or the routine
/// belongs to a generic type. The generic test is a HEURISTIC -- a `&lt;` in the
/// qualified name -- and it is deliberately inclusive: a routine wrongly
/// included costs a spurious fan-out that the user sees and can dismiss, while
/// one wrongly excluded is a silent all-clear.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Analysis.LintTree.BuildIndexSide (DRagLint.Analysis.LintTree.pas), DRagLint.Analysis.LintTree.RunLintTree (DRagLint.Analysis.LintTree.pas), DRagLint.Analysis.SurfaceAdapters.FingerprintOfParse (DRagLint.Analysis.SurfaceAdapters.pas), DRagLint.Analysis.SurfaceAdapters.TryFingerprintOfIndex (DRagLint.Analysis.SurfaceAdapters.pas)</para>
/// <para>Calls: Default, DRagLint.Analysis.SurfaceAdapters.IsExpansionVisible, DRagLint.Analysis.SurfaceAdapters.SpanText, SameText</para>
/// <para>Returns: Acc.ToArray</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Analysis.SurfaceAdapters.IsExpansionVisible"/>
/// <seealso cref="DRagLint.Analysis.SurfaceAdapters.SpanText"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CollectInlineBodies(const pSymbols: TArray<TSymbol>;
                             const pSourceLines: TArray<string>):
                             TArray<TInlineBody>;

/// <summary>Fingerprints an unsaved buffer that has already been parsed.</summary>
/// <param name="pParse">The parser's output for the buffer.</param>
/// <param name="pSourceLines">The buffer's lines, 0-based.</param>
/// <returns>The surface fingerprint of the buffer's interface.</returns>
/// <remarks>
/// The caller owns the parse, and must have preprocessed the buffer with the
/// profile the index was built with -- otherwise a unit with `{$IFDEF}` in its
/// interface is permanently `changed:true`.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: DRagLint.Analysis.SurfaceAdapters.CollectInlineBodies, DRagLint.Analysis.SurfaceFingerprint.SurfaceFingerprint</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Analysis.SurfaceAdapters.CollectInlineBodies"/>
/// <seealso cref="DRagLint.Analysis.SurfaceFingerprint.SurfaceFingerprint"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FingerprintOfParse(const pParse: TParseResult;
                            const pSourceLines: TArray<string>): string;

/// <summary>Fingerprints what the index currently holds for a file.</summary>
/// <param name="pStore">An open store; must not be nil.</param>
/// <param name="pPath">Absolute path of the unit, as the index stores it.</param>
/// <param name="pSourceLines">
/// The file's lines as the INDEX saw them. Pass an empty array when the file on
/// disk may have moved on; body hashes are then omitted from both sides by the
/// caller rather than computed from text the index never parsed.
/// </param>
/// <param name="AFingerprint">Receives the fingerprint on success.</param>
/// <returns>False when the file is not in this index; AFingerprint is then ''.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: DRagLint.Analysis.SurfaceAdapters.CollectInlineBodies, DRagLint.Analysis.SurfaceFingerprint.SurfaceFingerprint, DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile, DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile</para>
/// <para>Returns: False; True</para>
/// <para>Mutates: AFingerprint (out)</para>
/// <seealso cref="DRagLint.Analysis.SurfaceAdapters.CollectInlineBodies"/>
/// <seealso cref="DRagLint.Analysis.SurfaceFingerprint.SurfaceFingerprint"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function TryFingerprintOfIndex(const pStore: ISymbolStore;
                               const pPath: string;
                               const pSourceLines: TArray<string>;
                               out AFingerprint: string): Boolean;

implementation

const
  META_INDEXER_FINGERPRINT = 'indexer_fingerprint';

function TIndexerProfile.Matches(const pOther: TIndexerProfile): Boolean;
begin
  { An empty extractor version never matches, including against another empty
    one: two surfaces of unknown provenance are not known to be comparable. }
  Result:= (ExtractorVersion <> '')
       and SameText(ExtractorVersion, pOther.ExtractorVersion)
       and (SchemaVersion = pOther.SchemaVersion)
       and (SchemaVersion > 0);
end;

function TIndexerProfile.Describe: string;
var
  VersionText: string;
begin
  if ExtractorVersion = '' then
    VersionText:= '<unknown>'
  else
    VersionText:= ExtractorVersion;
  Result:= Format('v=%s schema=%d', [VersionText, SchemaVersion]);
end;

function ParseIndexerFingerprint(const pRaw: string): TIndexerProfile;
var
  Parts: TArray<string>;
  Part : string;
  Key  : string;
  Value: string;
  P    : Integer;
begin
  Result:= Default(TIndexerProfile);
  Result.Raw:= pRaw;
  if pRaw = '' then
    Exit;

  Parts:= pRaw.Split([';']);
  for Part in Parts do
  begin
    P:= Pos('=', Part);
    if P <= 1 then
      Continue;
    Key  := LowerCase(Trim(Copy(Part, 1, P - 1)));
    Value:= Trim(Copy(Part, P + 1, MaxInt));

    if Key = 'v' then
      Result.ExtractorVersion:= Value
    else if Key = 'schema' then
      Result.SchemaVersion:= StrToIntDef(Value, 0)
    else if Key = 'pp' then
      Result.Preprocess:= (Value = '1')
    else if Key = 'plat' then
      Result.Platform:= LowerCase(Value);
  end;
end;

function IndexProfileOf(const pStore: ISymbolStore): TIndexerProfile;
begin
  if pStore = nil then
    Exit(Default(TIndexerProfile));
  Result:= ParseIndexerFingerprint(pStore.GetMetaValue(META_INDEXER_FINGERPRINT));
end;

function IsExpansionVisible(const pSymbol: TSymbol): Boolean;
var
  Words: TArray<string>;
  W    : string;
begin
  if not (pSymbol.Kind in [skProcedure, skFunction, skMethod,
                           skConstructor, skDestructor]) then
    Exit(False);

  { A whole-word test, not a substring one: a routine named `InlineHelper`
    carries no directive, and Pos() would call it expansion-visible and hash a
    body that no dependent can see. }
  Words:= LowerCase(pSymbol.Directives).Split([' ']);
  for W in Words do
    if W = 'inline' then
      Exit(True);

  { Generic methods are instantiated in the caller. HEURISTIC, and inclusive on
    purpose -- see the CollectInlineBodies remarks. }
  Result:= Pos('<', pSymbol.QualifiedName) > 0;
end;

function SpanText(const pSourceLines: TArray<string>;
  const pFromLine, pToLine: Integer): string;
var
  SB: TStringBuilder;
  I : Integer;
begin
  { 1-based inclusive line numbers over a 0-based array. A span that does not
    fit is REFUSED, not clamped: a clamped span hashes differently depending on
    which side clamped it, which would fan out on every keystroke forever. }
  if (pFromLine <= 0) or (pToLine < pFromLine)
     or (pToLine > Length(pSourceLines)) then
    Exit('');

  SB:= TStringBuilder.Create;
  try
    for I:= pFromLine - 1 to pToLine - 1 do
    begin
      SB.Append(pSourceLines[I]);
      SB.Append(#10);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function CollectInlineBodies(const pSymbols: TArray<TSymbol>;
                             const pSourceLines: TArray<string>):
                             TArray<TInlineBody>;
var
  Acc  : TList<TInlineBody>;
  Sym  : TSymbol;
  Body : TInlineBody;
  Text : string;
begin
  Acc:= TList<TInlineBody>.Create;
  try
    for Sym in pSymbols do
    begin
      if not SameText(Sym.Section, 'interface') then
        Continue;
      if not IsExpansionVisible(Sym) then
        Continue;

      Text:= SpanText(pSourceLines, Sym.ImplStartLine, Sym.ImplEndLine);
      if Text = '' then
        Continue;

      Body:= Default(TInlineBody);
      Body.QualifiedName:= Sym.QualifiedName;
      Body.BodyText     := Text;
      Acc.Add(Body);
    end;
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

function FingerprintOfParse(const pParse: TParseResult;
                            const pSourceLines: TArray<string>): string;
begin
  Result:= SurfaceFingerprint(
    pParse.Symbols,
    pParse.UsesEntries,
    CollectInlineBodies(pParse.Symbols, pSourceLines));
end;

function TryFingerprintOfIndex(const pStore: ISymbolStore;
                               const pPath: string;
                               const pSourceLines: TArray<string>;
                               out AFingerprint: string): Boolean;
var
  FileId : Int64;
  Symbols: TArray<TSymbol>;
  UnitUses: TArray<TUnitUse>;
begin
  AFingerprint:= '';
  Result:= False;
  if pStore = nil then
    Exit;

  FileId:= pStore.FindFileIdByPath(pPath);
  if FileId <= 0 then
    Exit;

  Symbols:= pStore.FindSymbolsByFile(pPath);
  UnitUses:= pStore.GetUnitUsesForFile(FileId);

  AFingerprint:= SurfaceFingerprint(Symbols, UnitUses,
    CollectInlineBodies(Symbols, pSourceLines));
  Result:= True;
end;

end.
