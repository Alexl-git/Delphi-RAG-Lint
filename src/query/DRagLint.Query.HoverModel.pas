unit DRagLint.Query.HoverModel;

{ Assembles the STRUCTURED hover model -- the shape `hover --format json` emits
  and the IDE's colored popup consumes -- from an indexed symbol.

  WHY THIS UNIT EXISTS. The assembly (read the implementation span, mine the
  Result:=/Exit() returns with their source lines, resolve the unit file, build
  the model, then attach the Phase-2 doc facts) lived inline in
  DRagLint.CLI.DoHover, so the only way to obtain a model was to SPAWN
  drag-lint.exe. The IDE hover did exactly that, on the main thread, per hover,
  with the FULL database list -- which is what cold-opened the ~1.4 GB library
  index every time a tooltip appeared.

  Serving the popup over the already-warm LSP needed the same assembly in
  process. Copying it would have created a second definition of what a hover
  says about a symbol, and the two would have drifted the first time either was
  touched -- so it moved here, and BOTH surfaces now call it.

  THE FACTS ARE PART OF THE MODEL, NOT A GARNISH. TDocFactsBuilder.Build plus
  TDocRegions.FormatPhase2FactLines is the identical pair `document` uses to
  write the managed doc block. Routing every surface through it is the
  doc/hover consistency lock: the popup cannot claim something the committed
  documentation does not. }

interface

uses
  DRagLint.Core  .Model     ,
  DRagLint.Core  .Interfaces,
  DRagLint.Symbol.Describe  ,
  DRagLint.Hover .Renderer  ;

type
  /// <summary>Everything a hover surface needs about one symbol.</summary>
  /// <remarks>
  /// Returned as a record rather than a model plus out-params because
  /// the three parts are produced by one pass and are only correct together:
  /// ReturnRhs is what Model's return facts were built FROM, so a caller that
  /// rendered markdown from a separately mined list could contradict the JSON
  /// its own model produces.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HoverModel.pas) ?, DRagLint.CLI.Hover.DoHover (DRagLint.CLI.Hover.pas) ?, DRagLint.LSP.Server.HoverSetByLines (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleHoverBundle (DRagLint.LSP.Server.pas) ?, DRagLint.Query.HoverModel.AssembleHover (DRagLint.Query.HoverModel.pas) (+1 more)</para>
  /// <para>Used in units: DRagLint.CLI.Hover, DRagLint.LSP.Server, DRagLint.Query.HoverModel</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THoverAssembly = record
    Model    : THoverModel   ;
    /// <summary>Formatted Phase-2 fact lines; empty when the symbol has none.</summary>
    FactLines: TArray<string>;
    /// <summary>One line (Implemented by: TFoo.Bar, ...) naming the methods that answer an INTERFACE method; empty for every other symbol. Computed whatever AWithFacts is, so hover --format plain can print it; with AWithFacts it is also appended to FactLines (md, json, LSP hoverBundle).</summary>
    ImplLines: TArray<string>;
    /// <summary>The mined Result:=/Exit() expressions, in first-seen order --
    /// what RenderHoverMarkdown takes as its AReturnRhs.</summary>
    ReturnRhs: TArray<string>;
    /// <summary>The declared type, formatted by FormatDeclaredType ('string'
    /// or 'string (declared in Unit.TBase)'); '' when the symbol has none.
    /// What the md / plain renderers take as their ADeclaredType.</summary>
    DeclaredType: string;
    /// <summary>The 'Called from:' line (Doc.Facts.FormatHoverCalledFromLine) for the md card;
    /// '' without AWithFacts, without callers, or when the /// block already shows it. Kept OUT
    /// of FactLines: the json model feeds the RAD Studio popup, which lists resolvedCallers.</summary>
    CalledFromLine: string;
  end;

  /// <summary>An optional hover section the caller can leave out (v152: the fast first step of a
  /// deferred hover skips the slow ones).</summary>
  /// <remarks>
  /// hskImplementors = the 'Implemented by:' line (ImplementingMethodsOf; seconds on an
  /// interface method with many implementors -- ASYNC's measurement). hskSetBy = the check-init writer
  /// list (ruling HB2), which is computed only together with the facts anyway.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HoverModel.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THoverSkip = (hskImplementors, hskSetBy);
  /// <summary>The sections AssembleHover leaves out; [] (the default) computes all of them.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HoverModel.pas), DRagLint.Query.HoverModel.AssembleHover (DRagLint.Query.HoverModel.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THoverSkips = set of THoverSkip;

const
  /// <summary>Default check-init budget (most CFGs built) for the hover's 'Set by:' section; a tenth
  /// of check-init's own default so a hover stays fast. Override: environment variable
  /// DRAGLINT_HOVER_SETBY_MAX_ROUTINES (a whole number &gt;= 1).</summary>
  HOVER_SETBY_MAX_ROUTINES = 200;

  /// <summary>Wall-clock cap in seconds (check-init --max-seconds) for the hover's 'Set by:' solve;
  /// a hover must not wait the verb's 60 s default. A capped solve shows state budget-exceeded.
  /// Override: environment variable DRAGLINT_HOVER_SETBY_MAX_SECONDS (a number &gt; 0).</summary>
  HOVER_SETBY_MAX_SECONDS = 5;

  /// <summary>v152 HOVERCACHE: seconds of the hover cap kept back for what follows the 'Set by:' solve
  /// (building its JSON and lines, rendering the card) and for the solve's own last step past its clock.</summary>
  HOVER_RENDER_HEADROOM_SECONDS = 0.15;

  /// <summary>v152 HOVERCACHE: the least wall clock the 'Set by:' solve gets when the facts build already
  /// used the cap; the writer list needs no solve, so it stays complete even then.</summary>
  HOVER_SETBY_MIN_SECONDS = 0.05;

  /// <summary>Writer rows the hover card shows before 'Set by: and N more' (plan D5).</summary>
  HOVER_SETBY_ROWS = 5;

/// <summary>Assembles the structured hover model for one indexed symbol,
/// together with the fact lines and mined returns that render with it.</summary>
/// <param name="AStore">The store that OWNS <paramref name="ASym"/>. Passing a
/// different store yields facts about a same-named symbol elsewhere, which is
/// the exact failure the hover framework-scope fix was about.</param>
/// <param name="ASym">The resolved symbol; its Id must be from AStore.</param>
/// <param name="AWithFacts">False leaves FactLines empty and SKIPS the Phase-2
/// facts build entirely. Only the surfaces that render facts should pay for it
/// -- `hover --format plain` never has, because the covered-by BFS inside it is
/// the expensive part of assembling a hover.</param>
/// <param name="AExtraStores">Wave 149 LX: other project DBs handed to TDocFactsBuilder.Build
/// as extra stores, so 'Used in:' / 'Used in (via property X):' carry a use that lives only in
/// another DB (as `document --db A --db B` writes it). nil = the owning store only (the old
/// answer). Never pass a platform library: the callers filter it out.</param>
/// <param name="ASkip">v152: sections to leave out. hskImplementors drops the 'Implemented by:'
/// line (ImplLines stays empty); hskSetBy drops the check-init writer list. [] = everything.</param>
/// <returns>A populated assembly; a zeroed one when AStore is nil.</returns>
/// <remarks>
/// Reads the symbol's implementation span through TLiveDocuments, so
/// an editor's UNSAVED buffer is mined when one is registered and the file on
/// disk otherwise. The disk path is byte-for-byte the read the CLI has always
/// done (ANSI), which is what lets the CLI keep emitting identical JSON.
/// v152 HBHOVER (ruling HB2): with AWithFacts, a unit variable / class var / field also gets the
/// check-init writer list (AttachHoverSetBy): Model.SetByJson plus 'Init:' / 'Set by:' fact lines.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Hover.DoHover (DRagLint.CLI.Hover.pas), DRagLint.LSP.Server.TLSPServer.HandleHoverBundle (DRagLint.LSP.Server.pas)</para>
/// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolDoc, DRagLint.Core.LiveDocs.TLiveDocuments.Readable, DRagLint.Core.LiveDocs.TLiveDocuments.ReadLines, DRagLint.Doc.Facts.FormatHoverCalledFromLine, DRagLint.Doc.Facts.TDocFactsBuilder.Build, DRagLint.Doc.Regions.TDocRegions.FormatPhase2FactLines, DRagLint.Doc.Regions.TDocRegions.FormatUsedInLines (+16 more)</para>
/// <para>Returns: Default(THoverAssembly)</para>
/// <para>Complexity: 32 (cyclomatic, outer body), 176 lines (full implementation)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolDoc"/>
/// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.Readable"/>
/// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.ReadLines"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function AssembleHover(const AStore: ISymbolStore; const ASym: TSymbol;
  AWithFacts: Boolean = True; const AExtraStores: TArray<ISymbolStore> = nil;
  ASkip: THoverSkips = []): THoverAssembly;

/// <summary>Adds the check-init writer list of ASym (ruling HB2: which routines / events set this
/// variable) to an assembly: Model.SetByJson and the 'Init:' / 'Set by:' lines appended to FactLines.</summary>
/// <param name="AStore">The SQLite store that owns ASym (its index file is what check-init reads).
/// Any other store (an editor's in-memory buffer) adds nothing.</param>
/// <param name="ASym">The hovered symbol. Only a variable or field is answered; check-init refuses
/// a local, a parameter, a record field ... and then nothing is added.</param>
/// <param name="AAsm">The assembly to extend; FactLines is appended to, never replaced.</param>
/// <param name="ASpentSeconds">v152 HOVERCACHE: seconds the hover already spent before this section (the
/// facts build); the solve gets the cap minus this and minus HOVER_RENDER_HEADROOM_SECONDS, never less than
/// HOVER_SETBY_MIN_SECONDS, so the WHOLE hover stays inside the cap. 0 (the LSP's deferred step) = the full cap.</param>
/// <remarks>
/// <para>The JSON `set_by` object: state (listed | never-set | budget-exceeded | error), verdict
/// (SET, NEVER-SET, MAY-BE-UNSET, UNKNOWN-CALLEE), proven, summary, writers (byte-equal to
/// `check-init --json` writers), shown (rows on the card), budget {routines, ms, exhausted, max}.</para>
/// <para>Budget: HOVER_SETBY_MAX_ROUTINES CFGs (env DRAGLINT_HOVER_SETBY_MAX_ROUTINES overrides) and
/// HOVER_SETBY_MAX_SECONDS wall clock (env DRAGLINT_HOVER_SETBY_MAX_SECONDS overrides).
/// Exhausted -&gt; state budget-exceeded: the writers are still complete (they are events, not the
/// solve); only the verdict is unproven.</para>
/// <para>Cached per index file + write time + QName + budget, so a re-hover is free and a reindex
/// recomputes. Thread-safe: one lock serialises CheckInit (whose parse cache is not thread-safe)
/// and the cache. LSP: call it in the deferred second step only (it can take a solve).</para>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.LSP.Server.HoverSetByLines (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleHoverBundle (DRagLint.LSP.Server.pas), DRagLint.Query.HoverModel.AssembleHover (DRagLint.Query.HoverModel.pas)</para>
/// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.DbPath, DRagLint.Core.Model.JsonEscape, DRagLint.Query.HappensBefore.CheckInit, DRagLint.Query.HoverModel.BuildSetBy, DRagLint.Query.HoverModel.SetByMaxRoutines, DRagLint.Query.HoverModel.SetByMaxSeconds, FloatToStr, Format, FormatDateTime, LowerCase</para>
/// <para>Catches: EHbUsage (swallowed); Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.DbPath"/>
/// <seealso cref="DRagLint.Core.Model.JsonEscape"/>
/// <seealso cref="DRagLint.Query.HappensBefore.CheckInit"/>
/// <seealso cref="DRagLint.Query.HoverModel.BuildSetBy"/>
/// <seealso cref="DRagLint.Query.HoverModel.SetByMaxRoutines"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure AttachHoverSetBy(const AStore: ISymbolStore; const ASym: TSymbol; var AAsm: THoverAssembly;
  ASpentSeconds: Double = 0);

implementation

uses
  System.SysUtils              ,
  System.RegularExpressions    ,
  System.Math                  ,
  System.StrUtils              ,
  System.JSON                  ,
  System.IOUtils               ,
  System.Generics.Collections  ,
  System.Diagnostics           ,
  DRagLint.Query.HappensBefore        ,
  DRagLint.Query.HappensBefore.Types  ,
  DRagLint.Query.HappensBefore.Render ,
  DRagLint.Core .LiveDocs ,
  DRagLint.Hover.Returns  ,
  DRagLint.Doc  .Facts    ,
  DRagLint.Doc  .Regions  ,
  DRagLint.Query.Implementors,
  DRagLint.Index.Manifest ;

const
  /// <summary>Answering methods named on the hover line before "(+N more)".</summary>
  IMPL_LINE_CAP = 6;

{ The `const` / `var` / `out` / `constref` in front of AParamName within a
  routine signature, or '' when the parameter is passed by value.

  It is read back out of the SIGNATURE TEXT because that is the only place it
  survives: EmitRoutineParams stores a parameter's declared type and nothing
  else, since the modifier tokens are siblings of the type field rather than
  part of it.

  Grouped parameters share one modifier and one type (`const A, B: string`), so
  a group is matched by scanning its comma-separated name list, not by assuming
  one name per group. }
function ModifierOf(const ASignature, AParamName: string): string;
const
  MODS: array[0..3] of string = ('const', 'var', 'out', 'constref');
var
  Inner, Grp, Names, First: string;
  P1, P2, C               : Integer;
begin
  Result:= '';
  if (ASignature = '') or (AParamName = '') then Exit;
  P1:= Pos('(', ASignature);
  if P1 <= 0 then Exit;
  { Last ')' -- a parameter's own type may carry parentheses. }
  P2:= LastDelimiter(')', ASignature);
  if P2 <= P1 then Exit;
  Inner:= Copy(ASignature, P1 + 1, P2 - P1 - 1);

  for Grp in Inner.Split([';']) do
  begin
    C:= Pos(':', Grp);
    if C > 0 then Names:= Copy(Grp, 1, C - 1) else Names:= Grp;  { untyped var/out }
    Names:= Trim(Names);
    if Names = '' then Continue;

    { A leading modifier applies to every name in the group. }
    First:= Trim(Copy(Names, 1, Pos(' ', Names + ' ') - 1));
    Result:= '';
    for var M: string in MODS do
      if SameText(First, M) then
      begin
        Result:= LowerCase(First);
        Names := Trim(Copy(Names, Length(First) + 1, MaxInt));
        Break;
      end;

    for var Nm: string in Names.Split([',']) do
      if SameText(Trim(Nm), AParamName) then Exit;   { Result already holds the group's modifier }
  end;
  Result:= '';
end;

{ v152 HBHOVER -- the 'Set by:' section (ruling HB2 second half). }

type
  /// <summary>One cached set-by answer: the JSON object and the card lines built from it.</summary>
  TSetByEntry = record
    Json : string;
    Lines: TArray<string>;
  end;

var
  { Guarded by GSetByLock: CheckInit's parse cache is not thread-safe, and the LSP may hover from
    more than one thread. Created in initialization, freed in finalization. }
  GSetByLock : TObject;
  GSetByCache: TDictionary<string, TSetByEntry>;

const
  /// <summary>Entries kept before the cache is emptied (a hover session touches far fewer).</summary>
  SETBY_CACHE_CAP = 512;

function SetByMaxRoutines: Integer;
begin
  Result:= StrToIntDef(GetEnvironmentVariable('DRAGLINT_HOVER_SETBY_MAX_ROUTINES'), 0);
  if Result < 1 then Result:= HOVER_SETBY_MAX_ROUTINES;
end;

function SetByMaxSeconds: Double;
begin
  if not TryStrToFloat(GetEnvironmentVariable('DRAGLINT_HOVER_SETBY_MAX_SECONDS'), Result,
    TFormatSettings.Invariant) or (Result <= 0) then Result:= HOVER_SETBY_MAX_SECONDS;
end;

{ One card row per writer: 'Set by: Unit.Routine (File.pas:12, assign; fired by Form.Btn.OnClick)'. }
function SetByRow(const pW: TJSONObject): string;
begin
  var Routine: string:= pW.GetValue<string>('routine', '');
  var FileName: string:= ExtractFileName(pW.GetValue<string>('file', ''));
  var Where: string:= Format('%s:%d', [FileName, pW.GetValue<Integer>('line', 0)]);
  var Detail: string:= Where + ', ' + pW.GetValue<string>('how', '');
  if not pW.GetValue<Boolean>('counts', True) then Detail:= Detail + ', not counted';
  var FiredBy: string:= pW.GetValue<string>('fired_by', '');
  var CallerCount: Integer:= pW.GetValue<Integer>('callers.count', 0);
  if FiredBy <> '' then Detail:= Detail + '; fired by ' + FiredBy
  else if CallerCount > 0 then
  begin
    var Top: TJSONArray:= pW.GetValue<TJSONArray>('callers.top', nil);
    var Names: string:= '';
    if Top <> nil then
      for var K:= 0 to Top.Count - 1 do Names:= Names + IfThen(K = 0, ': ', ', ') + Top.Items[K].Value;
    Detail:= Detail + Format('; called from %d%s', [CallerCount, Names]);
  end;
  Result:= 'Set by: ' + IfThen(Routine <> '', Routine, Where) + ' (' + Detail + ')';
end;

{ The set-by JSON object and card lines from one check-init answer (see AttachHoverSetBy). }
function BuildSetBy(const pAnswer: THbAnswer; pMax: Integer): TSetByEntry;
begin
  Result:= Default(TSetByEntry);
  var Ans: TJSONObject:= TJSONObject.ParseJSONValue(HbAnswerJson(pAnswer)) as TJSONObject;
  try
    var Writers: TJSONArray:= Ans.GetValue<TJSONArray>('writers');
    var State: string:=
      if pAnswer.Budget.Exhausted then 'budget-exceeded'
      else if Writers.Count = 0 then 'never-set'
      else 'listed';
    var Shown: Integer:= Min(Writers.Count, HOVER_SETBY_ROWS);
    var Obj: TJSONObject:= TJSONObject.Create;
    try
      Obj.AddPair('state', State);
      Obj.AddPair('verdict', VerdictCode(pAnswer.Verdict));
      Obj.AddPair('proven', TJSONBool.Create(pAnswer.Proven));
      Obj.AddPair('summary', pAnswer.Summary);
      Obj.AddPair('writers', Writers.Clone as TJSONArray);
      Obj.AddPair('shown', TJSONNumber.Create(Shown));
      var Bud: TJSONObject:= Ans.GetValue<TJSONObject>('budget').Clone as TJSONObject;
      Bud.AddPair('max', TJSONNumber.Create(pMax));
      Obj.AddPair('budget', Bud);
      Result.Json:= Obj.ToJSON;
    finally
      Obj.Free;
    end;

    var Head: string:= 'Init: ' + VerdictCode(pAnswer.Verdict);
    if pAnswer.Summary <> '' then
      Head:= Head + IfThen(pAnswer.Summary.StartsWith('('), ' ', ' -- ') + pAnswer.Summary;
    Result.Lines:= [Head];
    if Writers.Count = 0 then Result.Lines:= Result.Lines + ['Set by: never set (no writer in the index)'];
    for var K:= 0 to Shown - 1 do Result.Lines:= Result.Lines + [SetByRow(Writers.Items[K] as TJSONObject)];
    if Writers.Count > Shown then
      Result.Lines:= Result.Lines + [Format('Set by: and %d more (check-init %s lists all)',
        [Writers.Count - Shown, pAnswer.Target.QName])];
    if pAnswer.Budget.TimedOut then
      Result.Lines:= Result.Lines + [Format('Set by: budget exceeded after %s s -- the writers are complete, the verdict is not proven',
        [FloatToStr(pAnswer.Budget.MaxSeconds, TFormatSettings.Invariant)])]
    else if pAnswer.Budget.Exhausted then
      Result.Lines:= Result.Lines + [Format('Set by: budget exceeded after %d routines -- the writers are complete, the verdict is not proven',
        [pAnswer.Budget.Routines])];
  finally
    Ans.Free;
  end;
end;

procedure AttachHoverSetBy(const AStore: ISymbolStore; const ASym: TSymbol; var AAsm: THoverAssembly;
  ASpentSeconds: Double);
begin
  if (AStore = nil) or (ASym.Kind not in [skVarDecl, skField]) then Exit;
  var DbPath: string:= AStore.DbPath; { v152 BK-VSHOVER (B51): was an RTTI read of FConn }
  if (DbPath = '') or not TFile.Exists(DbPath) then Exit;
  var MaxR: Integer:= SetByMaxRoutines;
  var MaxS: Double:= SetByMaxSeconds;
  { the cache key carries the hover cap, not the remaining budget: a re-hover reuses the answer }
  var Key: string:= Format('%s|%s|%s|%d|%s', [LowerCase(DbPath),
    FormatDateTime('yyyymmddhhnnsszzz', TFile.GetLastWriteTime(DbPath)), ASym.QualifiedName, MaxR,
    FloatToStr(MaxS, TFormatSettings.Invariant)]);
  { v152 HOVERCACHE: the cap covers the whole hover, so the solve gets what the facts build left }
  var SolveS: Double:= Max(MaxS - ASpentSeconds - HOVER_RENDER_HEADROOM_SECONDS, HOVER_SETBY_MIN_SECONDS);
  var Entry: TSetByEntry;
  TMonitor.Enter(GSetByLock);
  try
    if not GSetByCache.TryGetValue(Key, Entry) then
    begin
      var Opt: THbOptions:= Default(THbOptions);
      Opt.MaxRoutines:= MaxR;
      Opt.MaxSeconds:= SolveS;
      try
        Entry:= BuildSetBy(CheckInit(DbPath, ASym.QualifiedName, '', Opt), MaxR);
      except
        { A local, a parameter, a record field, an ambiguous name: check-init has no answer, and
          the hover has no section (cached, so a re-hover does not ask again). }
        on EHbUsage do Entry:= Default(TSetByEntry);
        { Anything else is a defect in the solve; the hover must still appear, so it is shown as
          the section's state instead of breaking the popup. }
        on E: Exception do
        begin
          Entry.Json := Format('{"state":"error","summary":"%s","writers":[]}', [JsonEscape(E.Message)]);
          Entry.Lines:= ['Set by: not computed (' + E.Message + ')'];
        end;
      end;
      if GSetByCache.Count >= SETBY_CACHE_CAP then GSetByCache.Clear;
      GSetByCache.Add(Key, Entry);
    end;
  finally
    TMonitor.Exit(GSetByLock);
  end;
  if Entry.Json = '' then Exit;
  AAsm.Model.SetByJson:= Entry.Json;
  AAsm.FactLines:= AAsm.FactLines + Entry.Lines;
end;

function AssembleHover(const AStore: ISymbolStore; const ASym: TSymbol;
  AWithFacts: Boolean; const AExtraStores: TArray<ISymbolStore>;
  ASkip: THoverSkips): THoverAssembly;
var
  Doc     : TParsedDoc      ;
  Rhs     : TArray<string>  ;
  RhsLines: TArray<Integer> ;
  UnitFile: string          ;
  ParamMod: string          ;
  Doc2Sig : string          ;
begin
  Result:= Default(THoverAssembly);
  if AStore = nil then Exit;
  { v152 HOVERCACHE: the hover cap covers the whole assembly; AttachHoverSetBy gets what is left }
  var Watch: TStopwatch:= TStopwatch.StartNew;

  { No doc comment is not fatal: the renderer still shows the qualified name and
    an IDE-style Parameters block parsed from the signature. }
  Doc:= AStore.GetSymbolDoc(ASym.Id);

  { A PARAMETER MUST NOT BORROW ITS ROUTINE'S WORDS.

    Two defects, one cause -- an skParam symbol stores only its declared TYPE
    (EmitRoutineParams deliberately excludes the modifier tokens, which are
    siblings of the type field, not part of it) and resolves its doc to the
    OWNING ROUTINE's block. Measured on DataCopy 2026-09-01:

      // NOTE: braces are spelled out below -- a nested closing brace would end
      // this comment early, which is a trap this repo has paid for twice.
      hover TransferFile        -> params: modifier "const", name "AFile", ...
      hover TransferFile.AFile  -> kind "parameter", signature "string",
                                   summary = the ROUTINE's summary, verbatim

    So the modifier the engine already knows was dropped at hover time, and both
    AFile and AMess described the routine rather than themselves.

    Both are fixed by COMPOSITION from the parent, which is why this costs no
    extractor bump and no reindex: the facts are already indexed, they were just
    never assembled for this kind. }
  if (ASym.Kind = skParam) and (ASym.ParentId > 0) then
  begin
    var Owner: TSymbol:= AStore.GetSymbolById(ASym.ParentId);
    if Owner.Id > 0 then
    begin
      { The <param name="..."> entry, not the routine's <summary>. When the
        routine documents no such param the summary is left EMPTY rather than
        falling back -- an empty hover is honest, and the routine's prose about
        something else is not. }
      { ParamsJsonRaw, not Params: GetSymbolDoc fills the RAW json and leaves the
        parsed array empty (its own comment says "v0.16 renderers read these
        directly; v0.17 may parse"). Reading Params here returned nothing and
        looked like "the routine documents no parameters". Same regex the hover
        renderer already uses, so the two cannot disagree about the shape. }
      var OwnerDoc: TParsedDoc:= AStore.GetSymbolDoc(Owner.Id);
      Doc.Summary:= '';
      Doc.Remarks:= '';
      if OwnerDoc.ParamsJsonRaw <> '' then
        for var M: TMatch in TRegEx.Create('"name":"([^"]+)","desc":"([^"]*)"').Matches(OwnerDoc.ParamsJsonRaw) do
          if SameText(M.Groups[1].Value, ASym.Name) then
          begin
            Doc.Summary:= M.Groups[2].Value;
            Break;
          end;

      { `const AFile: string` rather than a bare `string`. The modifier is read
        back out of the owning routine's signature, which is the only place it
        survives. }
      ParamMod:= ModifierOf(Owner.Signature, ASym.Name);
      if ASym.Signature <> '' then
      begin
        if ParamMod <> '' then Doc2Sig:= ParamMod + ' ' + ASym.Name + ': ' + ASym.Signature
        else Doc2Sig:= ASym.Name + ': ' + ASym.Signature;
      end
      else if ParamMod <> '' then Doc2Sig:= ParamMod + ' ' + ASym.Name   { untyped var/out }
      else Doc2Sig:= '';
    end;
  end;

  SetLength(Rhs     , 0);
  SetLength(RhsLines, 0);
  if (ASym.ImplStartLine > 0) and (ASym.ImplEndLine >= ASym.ImplStartLine) then
  begin
    var Path: string:= AStore.GetFilePath(ASym.FileId);
    if (Path <> '') and TLiveDocuments.Readable(Path) then
    begin
      var AllLines: TArray<string>:= TLiveDocuments.ReadLines(Path);
      var Lo: Integer:= ASym.ImplStartLine - 1;   { 1-based -> 0-based }
      var Hi: Integer:= ASym.ImplEndLine   - 1;
      if Lo < 0 then Lo:= 0;
      if Hi > High(AllLines) then Hi:= High(AllLines);
      if Hi >= Lo then   { a stale or invalid span yields no returns, not a crash }
      begin
        var Body: TArray<string>;
        SetLength(Body, Hi - Lo + 1);
        for var k:= Lo to Hi do Body[k - Lo]:= AllLines[k];

        { Mine WITH first-seen line offsets so the popup can jump to each
          return's source line. Body[0] is source line ImplStartLine, so the
          absolute 1-based line is ImplStartLine + offset. }
        var Mined: TArray<TReturnMined>:= MineReturnExpressionsEx(Body, ASym.QualifiedName);
        SetLength(Rhs     , Length(Mined));
        SetLength(RhsLines, Length(Mined));
        for var mi:= 0 to High(Mined) do
        begin
          Rhs     [mi]:= Mined[mi].Expr;
          RhsLines[mi]:= ASym.ImplStartLine + Mined[mi].LineOffset;
        end;
      end;
    end;
  end;

  UnitFile        := ExtractFileName(AStore.GetFilePath(ASym.FileId));

  { A TYPE carries nothing in Signature -- the parser has no single line to
    put there -- so the hover showed a bare `enum FileLockInfo.TRmAppType`
    while Ctrl-Space on the same type listed its members. Reported from a
    live IDE 2026-08-24. DescribeTypeKind is the ONE describer the
    completion item builder also calls; see its header for why it does not
    live in either surface. Applied only when the symbol says nothing for
    itself, so a real signature is never overwritten. }
  var Described: TSymbol:= ASym;
  if Described.Signature = '' then Described.Signature:= DescribeTypeKind(Described, AStore);
  { A bare re-published property ('property Text;') stores NO type; the
    ancestor that declares it does. DescribeDeclaredType runs the converter's
    climb (memoized on a writable store, session-cached otherwise), and the
    resolved token also replaces a memoized ': string' so the signature reads
    the way an indexed one does. Only a RE-PUBLICATION (no accessor of its
    own) is rewritten: a property with accessors keeps its own signature. }
  var Declared: TDeclaredType:= DescribeDeclaredType(ASym, AStore);
  if (ASym.Kind = skProperty) and (Trim(ASym.PropAccess) = '') and (Declared.TypeName <> '') then
    Described.Signature:= Declared.TypeName;
  { Composed above for a parameter: `const AFile: string` instead of `string`. }
  if Doc2Sig <> '' then Described.Signature:= Doc2Sig;

  Result.Model    := BuildHoverModel(Described, Doc, UnitFile, Rhs, RhsLines);
  Result.ReturnRhs:= Rhs;
  Result.Model.TypeName  := Declared.TypeName  ;
  Result.Model.DeclaredIn:= Declared.DeclaredIn;
  Result.DeclaredType    := FormatDeclaredType(Declared);

  { TDocFactsBuilder.Build + TDocRegions.FormatPhase2FactLines is the identical
    pair `document` uses to write the managed doc block. Going through it is the
    doc/hover consistency lock: the popup cannot claim a fact the committed
    documentation does not. }
  if AWithFacts then
  begin
    var Facts: TDocFacts:= TDocFactsBuilder.Build(AStore, ASym, LoadDocHandlesOptions, False, False, '', AExtraStores); { gap 3: the SAME 'Catches:' knob document writes with; 149 LX: + extra stores }
    Result.FactLines:= TDocRegions.FormatPhase2FactLines(Facts, LoadDocComplexityMin);
    { E-USE-EDGES-PHASE2: the property/field 'Used in:' line, from the SAME
      formatter the doc block writes with (md, json, LSP hoverBundle). }
    Result.FactLines:= TDocRegions.FormatUsedInLines(Facts) + Result.FactLines;
    { Purity v2: the SAME verdict the fact line above was rendered from, handed
      to the JSON consumer structured. BuildHoverModel left these at -1/''/'';
      they are overwritten only here, inside the AWithFacts branch, because
      outside it no facts row was read and -1 is the honest answer. }
    Result.Model.EffectFree   := Facts.EffectFree;
    Result.Model.EffectSummary:= Facts.EffectSummary;
    Result.Model.EffectWitness:= Facts.EffectWitness;
    Result.CalledFromLine:= FormatHoverCalledFromLine(Facts, Doc.RawBlock + Doc.Remarks); { 150 LX2 }
  end;
  { C22: an interface METHOD names its answering methods (ImplementingMethodsOf, the
    LSP implementation / code-lens primitive). [] for any other symbol. }
  { v152 (ASYNC's measurement): the fast first step of a deferred hover passes hskImplementors --
    this lookup cost 1.6 / 7.4 s on two interface methods with many implementors. }
  var Answering: TArray<TSymbol>:= nil;
  if hskImplementors not in ASkip then Answering:= ImplementingMethodsOf(AStore, ASym);
  if Length(Answering) > 0 then
  begin
    var Line: string:= '';
    for var K:= 0 to Min(Length(Answering), IMPL_LINE_CAP) - 1 do
      Line:= Line + IfThen(K = 0, '', ', ') + Answering[K].QualifiedName;
    if Length(Answering) > IMPL_LINE_CAP then Line:= Line + Format(' (+%d more)', [Length(Answering) - IMPL_LINE_CAP]);
    Result.ImplLines:= TArray<string>.Create('Implemented by: ' + Line);
    if AWithFacts then Result.FactLines:= Result.FactLines + Result.ImplLines;
  end;
  { v152 HBHOVER (ruling HB2): which routines / events set this variable. Only with the facts: the
    plain format and the fast first step of a deferred hover never pay for a solve. }
  if AWithFacts and (hskSetBy not in ASkip) then
    AttachHoverSetBy(AStore, ASym, Result, Watch.Elapsed.TotalSeconds);
end; // function

initialization
  GSetByLock := TObject.Create;
  GSetByCache:= TDictionary<string, TSetByEntry>.Create;

finalization
  GSetByCache.Free;
  GSetByLock.Free;

end.
