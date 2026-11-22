unit DRagLint.Lint.ProjectChecks;

// v0.9: project-level lint rules. Operate on a .dproj + sibling .dpr/.dpk,
// not on per-file ASTs. The first rule (`unit-not-in-dpr`) is from a known
// real-world hazard: Delphi compiles a unit if either the .dproj DCCReference
// list OR the search path resolves it, so a unit can be "in the build" without
// being listed in both places - and that silently breaks future re-IDE-opens.
//
// v0.65: the pure parsing/normalization helpers (NormUnit, ExtractUsesNames,
// ReadDCCReferences, ...) live in DRagLint.Lint.ProjectChecks.Parse so they can
// be unit-tested without dragging in SQLite/FireDAC/Core.

interface

uses
  System.SysUtils
  , System.StrUtils
  , System.Classes
  , System.IOUtils
  , System  .Generics.Collections
  , DRagLint.Core    .Model
  , DRagLint.Core    .Interfaces
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoIndex (DRagLint.CLI.pas) ?, DRagLint.CLI.DoLint (DRagLint.CLI.pas) ?, DRagLint.CLI.DoLintAll (DRagLint.CLI.pas) ?, DRagLint.CLI.DoLintProject (DRagLint.CLI.pas) ?, DRagLint.V152.PROJ2.Support.FindUnlistedClosureOutsideRoots (DRagLint.V152.PROJ2.Support.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.V152.PROJ2.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TProjectChecks = class  // dl:ok high-response@3638 -- REVIEWED 2026-11-21 SLZ-S05: RFC 60; design-level finding, not a local equivalent edit; restructuring deferred (risk to the checker behaviour outweighs the gain)
    public
      // Compare .dproj <DCCReference Include="..."/> entries vs the matching
      // .dpr/.dpk's `uses` clause. Returns findings for every unit that is
      // present on one side but not the other.
      /// <summary><!-- drag-lint:auto sum -->Compare .dproj &lt;DCCReference
      /// Include="..."/&gt; entries vs the matching .dpr/.dpk's `uses` clause. Returns
      /// findings for every unit that is present on one side but not the other.</summary>
      /// <param name="ADprojPath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AClosureFiles">The project's compile-closure .pas files,
      /// already scoped to its own roots. Optional: when empty the third
      /// direction below is SKIPPED rather than half-answered.</param>
      /// <param name="AWithLinks">v151 EXCL: True (the default, the lint path) also appends
      /// CheckNonUsesLinks for the same closure; the index-time report passes False to stay cheap.</param>
      /// <param name="AExcludeRoots">1.52.2 Q5: library / third-party folders (registry library
      /// paths plus the manifest Library "include" folders). A closure file under one of them is
      /// dropped before the third direction and the link scan: the library, not the project,
      /// owns it. nil (the default) drops nothing.</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TLintFinding&gt; -- Observed:
      /// Findings.ToArray; ASet.TryGetValue(AStem, Orig) and (Pos('.',
      /// NormUnitQualified(Orig)) = 0).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.V152.PROJ2.Support.FindUnlistedClosureOutsideRoots (DRagLint.V152.PROJ2.Support.pas)</para>
      /// <para>Calls: Default, DRagLint.Lint.ProjectChecks.Parse.ExtractUsesNames, DRagLint.Lint.ProjectChecks.Parse.FindSiblingProgramFile, DRagLint.Lint.ProjectChecks.Parse.NormUnit, DRagLint.Lint.ProjectChecks.Parse.NormUnitQualified, DRagLint.Lint.ProjectChecks.Parse.ReadDCCReferences, DRagLint.Lint.ProjectChecks.RealCasedFileName, DRagLint.Lint.ProjectChecks.TProjectChecks.CheckNonUsesLinks, ExtractFileExt, ExtractFileName (+6 more)</para>
      /// <para>Complexity: 37 (cyclomatic, outer body), 201 lines (full implementation)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.ExtractUsesNames"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.FindSiblingProgramFile"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.NormUnit"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.NormUnitQualified"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.ReadDCCReferences"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckUnitsInDpr( const ADprojPath: string;
                                      const AClosureFiles: TArray<string> = nil;
                                      const AWithLinks: Boolean = True;
                                      const AExcludeRoots: TArray<string> = nil): TArray<TLintFinding>;
      /// <summary>1.52.2 Q5: the closure files that lie under none of the excluded roots.</summary>
      /// <param name="AFiles">Closure files, absolute or relative.</param>
      /// <param name="ARoots">Folders to drop; nil returns AFiles unchanged.</param>
      /// <returns>AFiles minus every path at or below one of ARoots (case-insensitive,
      /// '/' read as '\', a root matches whole path segments only).</returns>
      /// <remarks>Pure; touches no file system state beyond path expansion. Thread-safe.</remarks>
      class function WithoutRoots(const AFiles, ARoots: TArray<string>): TArray<string>; static;
      /// <summary>Reports project-local units that the compile closure does NOT reach through `uses`
      /// but that a closure unit still depends on by another link (owner ruling OQ13): such a unit
      /// belongs to the project, so it needs a `uses` entry and a project entry.</summary>
      /// <param name="ADprojPath">The project's .dproj; its folder is one of the candidate folders.</param>
      /// <param name="AClosureFiles">The project's compile-closure files (.pas; others are ignored).
      /// Empty -> no findings (nothing to compare against).</param>
      /// <returns>One `unit-not-in-dpr` warning per (anchor file, linked unit, link). Links found:
      /// (1) a closure unit's sibling .dfm streams a class (`object|inherited|inline Name: TClass`)
      /// that no closure unit declares and a candidate unit does; anchored on the .dfm line.
      /// (2) a closure source names the candidate unit qualified, `UnitName.Ident`, with Ident
      /// declared in that unit's interface (typically inside an inactive conditional branch, the
      /// only place such code still compiles); anchored on the source line.
      /// (3) a closure source looks a class up by name, `GetClass|FindClass('TName')`, and TName is
      /// declared only in a candidate unit; anchored on the source line.</returns>
      /// <remarks>
      /// Candidates are the .pas files directly in the folders of the closure units and
      /// of the .dproj (no recursion) that are not themselves closure members and do not share a
      /// closure unit's name. A unit with no link at all is NOT reported: by OQ13 it is not part
      /// of the project. Look-alike guarded: a qualified name whose first part is also declared
      /// as an identifier in the using file (`Cfg: TRec; Cfg.Value`) is that identifier, not the
      /// unit. Text scan with comments blanked (string literals too for link 2, kept for link 3); all
      /// conditional branches are read on purpose. Binary .dfm files are skipped. Touches the
      /// file system; no DB access; thread-safe.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUnitsInDpr (DRagLint.Lint.ProjectChecks.pas)</para>
      /// <para>Calls: AddAdvice, Copy, Default, DRagLint.Lint.ProjectChecks.AddMatches, DRagLint.Lint.ProjectChecks.Parse.FindSiblingProgramFile, DRagLint.Lint.ProjectChecks.Parse.StripPasCommentsKeepLayout, DRagLint.Lint.ProjectChecks.ReadTextOrEmpty, DRagLint.Lint.ProjectChecks.TProjectChecks.CheckNonUsesLinks.CollectCandidates, DRagLint.Lint.ProjectChecks.TProjectChecks.CheckNonUsesLinks.ScanDfm, DRagLint.Lint.ProjectChecks.TProjectChecks.CheckNonUsesLinks.ScanSource (+11 more)</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.AddMatches"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.FindSiblingProgramFile"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.StripPasCommentsKeepLayout"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.ReadTextOrEmpty"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.TProjectChecks.CheckNonUsesLinks.CollectCandidates"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckNonUsesLinks(const ADprojPath: string;
                                       const AClosureFiles: TArray<string>): TArray<TLintFinding>;
      /// <summary>Flags every `uses X` whose unit X resolves to no known unit
      /// (project member / platform library / standard alias / RTL namespace).
      /// Findings attach to the `uses` token line on the using file. No .dproj
      /// required. Uses with an explicit `in '&lt;path>'` locator are skipped.</summary>
      /// <param name="AStore">Open project symbol store (the project scope).</param>
      /// <param name="ALibDbPath">Platform library SQLite DB; '' skips the library source.</param>
      /// <param name="AProjectFile"><!-- drag-lint:auto type -->const string = ''</param>
      /// <returns>One warning per unresolvable used unit.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.DoLintProject (DRagLint.CLI.pas)</para>
      /// <para>Calls: ChangeFileExt, Copy, Default, DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile, DRagLint.Core.Model.TUnitUse.FromInclude, DRagLint.Core.Model.TUnitUse.HostCol, DRagLint.Core.Model.TUnitUse.HostLine, DRagLint.Core.Model.TUnitUse.IncludeSuffix (+9 more)</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Complexity: 12 (cyclomatic, outer body), 162 lines (full implementation)</para>
      /// <para>Catches: Exception (empty)</para>
      /// <para>SQL: reads FILES</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile"/>
      /// <seealso cref="DRagLint.Core.Model.TUnitUse.FromInclude"/>
      /// <seealso cref="DRagLint.Core.Model.TUnitUse.HostCol"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckUsedUnitResolvable(const AStore: ISymbolStore;
        const ALibDbPath: string; const AProjectFile: string = ''): TArray<TLintFinding>;
  end;

implementation

uses
  FireDAC.Comp.Client
  , DRagLint.Project.TargetStudio { ResolveTargetStudio: the project's Delphi, for the .dcu search (GH #13) }
  , DRagLint.Storage.FileMembership { ConnectReadOnly: the shared reader open }
  , System.RegularExpressions { v151 EXCL: CheckNonUsesLinks text scan }
  , DRagLint.Lint.ProjectChecks.Parse
  , DRagLint.Project.Resolver
  ;

{ The scoped closure list arrives LOWERCASED, so a unit reported from it read as
  "hidden.helper" rather than "Hidden.Helper" -- and the advice is "add this to
  your project files", where the name is copied by hand. FindFirst returns the
  name as the filesystem holds it, which is the only authority on its case. }
function RealCasedFileName(const APath: string): string;
var
  SR: TSearchRec;
begin
  Result:= ExtractFileName(APath);
  if FindFirst(APath, faAnyFile, SR) = 0 then
  try
    if SR.Name <> '' then Result:= SR.Name;
  finally
    FindClose(SR);
  end;
end;

class function TProjectChecks.WithoutRoots(const AFiles, ARoots: TArray<string>): TArray<string>;
var
  Keys: TArray<string>;
begin
  if Length(ARoots) = 0 then Exit(AFiles);
  Keys:= nil;
  for var R: string in ARoots do
    if Trim(R) <> '' then
      Keys:= Keys + [IncludeTrailingPathDelimiter(LowerCase(StringReplace(ExpandFileName(R), '/', '\', [rfReplaceAll])))];
  Result:= nil;
  for var F: string in AFiles do
  begin
    var Key: string:= LowerCase(StringReplace(ExpandFileName(F), '/', '\', [rfReplaceAll]));
    var Under: Boolean:= False;
    for var K: string in Keys do
      if StartsStr(K, Key) then
      begin
        Under:= True;
        Break;
      end;
    if not Under then Result:= Result + [F];
  end;
end;

class function TProjectChecks.CheckUnitsInDpr( const ADprojPath: string;  // dl:ok cyclomatic-complexity@0328 -- REVIEWED 2026-11-21 SLZ-S05: measured 37 (max 30); design-level finding, not a local equivalent edit; restructuring deferred (risk to the checker behaviour outweighs the gain)
                                               const AClosureFiles: TArray<string>;
                                               const AWithLinks: Boolean;
                                               const AExcludeRoots: TArray<string>): TArray<TLintFinding>;
var
  Closure    : TArray<string>             ;
  DCCRefs    : TArray<string>             ;
  ProgramUses: TArray<string>             ;
  ProgramPath: string                     ;
  DCCSet     : TDictionary<string, string>;
  UsesSet    : TDictionary<string, string>;
  StemSatisfies: TFunc<string, TDictionary<string, string>, Boolean>;
  DCCStemSet : TDictionary<string, string>;  { legacy unqualified fallback only }
  UsesStemSet: TDictionary<string, string>;
  Pair       : TPair<string, string>      ;
  Finding    : TLintFinding               ;
  Findings   : TList<TLintFinding>        ;
  UsesLine   : Integer                    ;
  RefPath    : string                     ;
  Name       : string                     ;
begin
  Findings:= TList<TLintFinding>.Create;
  DCCSet := TDictionary<string, string>.Create;
  UsesSet:= TDictionary<string, string>.Create;
  DCCStemSet := TDictionary<string, string>.Create;
  UsesStemSet:= TDictionary<string, string>.Create;
  try
    DCCRefs    := ReadDCCReferences     (ADprojPath);
    ProgramPath:= FindSiblingProgramFile(ADprojPath);
    if ProgramPath = '' then
    begin
      Finding:= Default(TLintFinding);
      Finding.RuleId  := 'unit-not-in-dpr';
      Finding.Severity:= 'warning';
      Finding.Message:= 'No sibling .dpr or .dpk found for ' + ExtractFileName(ADprojPath);
      Finding.FilePath := ADprojPath;
      Finding.StartLine:= 1;
      Finding.StartCol := 1;
      Findings.Add(Finding);
      Exit(Findings.ToArray);
    end;
    ProgramUses:= ExtractUsesNames(ProgramPath, UsesLine);

    { The stem fallback exists for ONE case: a LEGACY UNQUALIFIED name on one
      side matching a qualified file on the other -- a .dpr saying `Graphics`
      where the DCCReference is `Vcl.Graphics.pas`. It fires only when the
      COUNTERPART entry is itself unqualified.

      Testing the wrong side is the trap this replaced. Gating on the key being
      undotted looks equivalent and is not: in the FP-9 case the DOTTED name is
      the one being looked up (`vcl.graphics`) and the UNQUALIFIED one is what it
      must match, so that gate skips the fallback and reports a false positive.
      Gating on the counterpart also keeps `DRagLint.Doc.Drift` from being
      satisfied by `DRagLint.Index.Drift`, which is the whole point: both are
      qualified, so no fallback applies. }
    StemSatisfies := TFunc<string, TDictionary<string, string>, Boolean>(
      function(const AStem: string; const ASet: TDictionary<string, string>): Boolean
      var
        Orig: string;
      begin
        Result := ASet.TryGetValue(AStem, Orig) and (not NormUnitQualified(Orig).Contains('.'));
      end);

    { Normalize BOTH sides identically so dotted unit names like 'Foo.ViewModel'
      and 'Foo.ViewModel.pas' compare equal (FP-9 class of bug).

      KEYED ON THE QUALIFIED NAME, not the last dot-segment. NormUnit truncates
      to the final segment, which collapses DRagLint.Doc.Drift and
      DRagLint.Index.Drift onto the same key 'drift' -- so a unit present in the
      .dproj and MISSING from the .dpr was silently satisfied by an unrelated
      namesake and never reported. Measured on this repo: DRagLint.Doc.Drift is
      in the .dproj, absent from the .dpr, and the rule returned 0 findings.

      The stem sets are kept alongside for the LEGACY UNQUALIFIED case that
      truncation was added for -- a .dpr naming 'Graphics' where the reference is
      'Vcl.Graphics.pas'. The fallback is consulted ONLY for a name that carries
      no qualification of its own, so it can no longer let one namespace stand in
      for another. }
    for RefPath in DCCRefs do
    begin
      DCCSet    .AddOrSetValue(NormUnitQualified(RefPath), RefPath);
      DCCStemSet.AddOrSetValue(NormUnit         (RefPath), RefPath);
    end;
    for Name in ProgramUses do
    begin
      UsesSet    .AddOrSetValue(NormUnitQualified(Name), Name);
      UsesStemSet.AddOrSetValue(NormUnit         (Name), Name);
    end;

    // In .dproj but not in .dpr/.dpk uses -> most dangerous case.
    for Pair in DCCSet do
    begin
      if not (UsesSet.ContainsKey(Pair.Key)
              or StemSatisfies(NormUnit(Pair.Value), UsesStemSet)) then
      begin
        Finding:= Default(TLintFinding);
        Finding.RuleId  := 'unit-not-in-dpr';
        Finding.Severity:= 'warning';
        Finding.Message:= Format(
          'Unit "%s" is in the .dproj DCCReference list but missing from ' + 'the %s uses clause. Add it so re-IDE-opens keep it in the build.',
          [Pair.Value, ExtractFileName(ProgramPath)]);
        Finding.FilePath := ProgramPath;
        Finding.StartLine:= UsesLine;
        Finding.StartCol := 1;
        Findings.Add(Finding);
      end;
    end; // for

    // In .dpr/.dpk uses but not in .dproj DCCReference -> typically compiles
    // via search path, but IDE-managed dependency tracking misses it.
    for Pair in UsesSet do
    begin
      if not (DCCSet.ContainsKey(Pair.Key)
              or StemSatisfies(NormUnit(Pair.Value), DCCStemSet)) then
      begin
        // Skip RTL/VCL/FMX/standard-library names - they live in BDS Lib paths
        // and are never expected in DCCReference.
        if StartsText('System.', Pair.Value) or StartsText('Vcl.', Pair.Value) or StartsText('Fmx.', Pair.Value) or StartsText('Data.', Pair.Value) or  // dl:ok boolean-expression-complexity@b2bc -- REVIEWED 2026-11-21 SLZ-S05: 18 and/or/xor operators; design-level finding, not a local equivalent edit; restructuring deferred (risk to the checker behaviour outweighs the gain)
        StartsText('Winapi.', Pair.Value) or StartsText('FireDAC.', Pair.Value) or StartsText('IdContext', Pair.Value) or StartsText('REST.', Pair.Value) or
        SameText(Pair.Value, 'Forms') or SameText(Pair.Value, 'SysUtils') or SameText(Pair.Value, 'Classes') or SameText(Pair.Value, 'Windows') or
        SameText(Pair.Value, 'Messages') or SameText(Pair.Value, 'Variants') or SameText(Pair.Value, 'Graphics') or SameText(Pair.Value, 'Controls') or
        SameText(Pair.Value, 'Dialogs') or SameText(Pair.Value, 'Menus') or SameText(Pair.Value, 'StdCtrls') then Continue;
        { Only a unit that EXISTS as a source file beside the .dproj can meaningfully
          be added to its DCCReference list. Everything else in a .dpr uses clause
          resolves from the library search path -- EurekaLog's injected block
          (EMemLeaks, EResLeaks, ExceptionLog7, EAppVCL, ...), DevExpress, Raize --
          and is never expected in DCCReference. The old name-prefix skip list could
          not know that, so it reported every third-party unit as a finding. }
        if not TFile.Exists(TPath.Combine(ExtractFilePath(ADprojPath), Pair.Value + '.pas')) then Continue;
        Finding:= Default(TLintFinding);
        Finding.RuleId  := 'unit-not-in-dpr';
        Finding.Severity:= 'info';
        Finding.Message:= Format(
          'Unit "%s" is in %s uses clause but missing from .dproj ' + 'DCCReference list. Compiles via search path today; IDE may not ' + 'track it as a build input.',
          [Pair.Value, ExtractFileName(ProgramPath)]);
        Finding.FilePath := ADprojPath;
        Finding.StartLine:= 1;
        Finding.StartCol := 1;
        Findings.Add(Finding);
      end; // if
    end; // for

    { THIRD DIRECTION: in the COMPILE CLOSURE but in NEITHER project file.

      The two loops above are set differences between the .dproj DCCReference
      list and the .dpr uses clause. A unit reached only TRANSITIVELY -- unit A
      is listed, A uses B, B is listed nowhere -- is in neither input set, so it
      is not merely unreported: it is structurally invisible to both directions.

      Measured on this repo 2026-08-26: DRagLint.Project.Coherence and
      DRagLint.Project.Members are both in the live compile closure and both
      indexed, and appear 0 times in drag-lint.dpr and 0 times in
      drag-lint.dproj. Such a unit builds today via the search path, but the IDE
      does not track it as a build input, it is absent from the project view,
      and nothing carries it if the search path changes.

      SCOPE COMES FROM THE CALLER, deliberately. AClosureFiles is the scoped
      project file list the caller already computed (own roots honoured,
      exclude_paths applied). Resolving the closure here would mean src\lint
      depending on src\index -- a new cycle in the very tool that reports them
      -- and would also re-derive a scope the caller has already decided. When
      the list is empty this direction is SKIPPED rather than half-answered:
      silence beats a wrong answer, and a project whose closure could not be
      resolved must not have every one of its units reported as missing. }
    { 1.52.2 Q5 (owner): the WHOLE compile closure minus the library / third-party roots. }
    Closure:= WithoutRoots(AClosureFiles, AExcludeRoots);
    if Length(Closure) > 0 then
    begin
      var ProgBase: string := '';
      if ProgramPath <> '' then ProgBase:= TPath.GetFileNameWithoutExtension(ProgramPath);
      for var ClosureFile: string in Closure do
      begin
        if not SameText(ExtractFileExt(ClosureFile), '.pas') then Continue;
        var UnitBase: string := TPath.GetFileNameWithoutExtension(RealCasedFileName(ClosureFile));
        if (ProgBase <> '') and SameText(UnitBase, ProgBase) then Continue;
        if DCCSet .ContainsKey(NormUnitQualified(UnitBase)) then Continue;
        if UsesSet.ContainsKey(NormUnitQualified(UnitBase)) then Continue;
        if StemSatisfies(NormUnit(UnitBase), DCCStemSet ) then Continue;
        if StemSatisfies(NormUnit(UnitBase), UsesStemSet) then Continue;
        Finding:= Default(TLintFinding);
        Finding.RuleId  := 'unit-not-in-dpr';
        Finding.Severity:= 'warning';
        Finding.Message := Format(
          'Unit "%s" is in the compile closure but appears in NEITHER %s nor ' +
          'the .dproj DCCReference list. It builds via the search path today, ' +
          'but the IDE does not track it as a build input and it is invisible ' +
          'in the project view. Add it to both.',
          [UnitBase, ExtractFileName(ProgramPath)]);
        Finding.FilePath := TPath.Combine(ExtractFilePath(ClosureFile),
                                          RealCasedFileName(ClosureFile));
        Finding.StartLine:= 1;
        Finding.StartCol := 1;
        Findings.Add(Finding);
      end; // for
    end; // if

    if AWithLinks then Findings.AddRange(CheckNonUsesLinks(ADprojPath, Closure));
    Result:= Findings.ToArray;
  finally
    DCCSet.Free;
    UsesSet.Free;
    DCCStemSet.Free;
    UsesStemSet.Free;
    Findings.Free;
  end; // try
end; // function

{ v151 EXCL helpers for CheckNonUsesLinks. }

const
  /// <summary>A class declaration (not a forward `= class;`, not a metaclass `= class of`).</summary>
  CLASS_DECL_PATTERN = '\b([A-Za-z_]\w*)\s*=\s*(?:packed\s+)?class\b(?!\s*(?:of\b|;))';
  /// <summary>A .dfm component line: `object|inherited|inline [Name:] TClass`.</summary>
  DFM_CLASS_PATTERN = '^\s*(?:object|inherited|inline)\s+(?:[A-Za-z_]\w*\s*:\s*)?([A-Za-z_]\w*)';
  /// <summary>A class looked up by its name in a string literal.</summary>
  BY_NAME_PATTERN = '\b(?:GetClass|FindClass)\s*\(\s*''([A-Za-z_]\w*)''';
  /// <summary>One Pascal string literal on one line (a doubled quote splits it in two; both blank).</summary>
  STRING_LITERAL_PATTERN = '''[^''\r\n]*''';
  /// <summary>A dotted name chain A.B[.C...] not preceded by a word character or a dot.</summary>
  QUALIFIED_CHAIN_PATTERN = '(?<![\w.])[A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)+';

type
  /// <summary>One project-local .pas outside the closure, read on first need.</summary>
  TLinkCandidate = class
    UnitName  : string;                       // as the file system spells it
    Path      : string;
    Classes   : TDictionary<string, Boolean>; // lowercase class names declared anywhere in it
    IntfWords : TDictionary<string, Boolean>; // lowercase identifiers of its interface section
    constructor Create(const APath: string);
    destructor Destroy; override;
  end;

{ The file's text, or '' when it cannot be read (locked, vanished, not text):
  a link scan is advisory and must never stop the lint run. }
function ReadTextOrEmpty(const APath: string): string;
begin
  try
    Result:= TFile.ReadAllText(APath);
  except
    on E: Exception do Result:= ''; // advisory scan: an unreadable, locked or vanished file has no links
  end;
end;

function LineOfOffset(const AText: string; AOffset: Integer): Integer;
begin
  Result:= 1;
  for var I: Integer:= 1 to AOffset - 1 do
    if AText[I] = #10 then Inc(Result);
end;

procedure AddMatches(const AText, APattern: string; ADest: TDictionary<string, Boolean>);
begin
  for var M: TMatch in TRegEx.Matches(AText, APattern, [roIgnoreCase]) do
    ADest.AddOrSetValue(LowerCase(M.Groups[1].Value), True);
end;

constructor TLinkCandidate.Create(const APath: string);
begin
  inherited Create;
  Path:= APath;
  UnitName:= TPath.GetFileNameWithoutExtension(RealCasedFileName(APath));
  Classes:= TDictionary<string, Boolean>.Create;
  IntfWords:= TDictionary<string, Boolean>.Create;
  var Text: string:= StripPasCommentsKeepLayout(ReadTextOrEmpty(APath));
  AddMatches(Text, CLASS_DECL_PATTERN, Classes);
  var Impl: TMatch:= TRegEx.Match(Text, '\bimplementation\b', [roIgnoreCase]);
  if Impl.Success then Text:= Copy(Text, 1, Impl.Index - 1);
  AddMatches(Text, '\b([A-Za-z_]\w*)\b', IntfWords);
end;

destructor TLinkCandidate.Destroy;
begin
  Classes.Free;
  IntfWords.Free;
  inherited Destroy;
end;

class function TProjectChecks.CheckNonUsesLinks(const ADprojPath: string;
                                                const AClosureFiles: TArray<string>): TArray<TLintFinding>;
var
  ClosurePaths  : TDictionary<string, Boolean>; // lowercase full path
  ClosureUnits  : TDictionary<string, Boolean>; // lowercase unit names AND each dotted prefix of one
  ClosureClasses: TDictionary<string, Boolean>; // lowercase class names the closure declares
  Candidates    : TObjectDictionary<string, TLinkCandidate>; // lowercase unit name -> candidate
  ClassOwner    : TDictionary<string, TLinkCandidate>;       // lowercase class name -> its only candidate
  Reported      : TDictionary<string, Boolean>;
  Findings      : TList<TLintFinding>;
  Sources       : TList<string>;  // closure .pas plus the program file

  procedure Report(const AAnchor: string; ALine: Integer; const AUnit, AKind, AMessage: string);
  begin
    var Key: string:= LowerCase(AAnchor + '|' + AUnit + '|' + AKind);
    if Reported.ContainsKey(Key) then Exit;
    Reported.Add(Key, True);
    var F: TLintFinding:= Default(TLintFinding);
    F.RuleId   := 'unit-not-in-dpr';
    F.Severity := 'warning';
    F.Message  := AMessage;
    F.FilePath := AAnchor;
    F.StartLine:= ALine;
    F.StartCol := 1;
    Findings.Add(F);
  end;

  function AddAdvice(const AUnit, AUser: string): string;
  begin
    Result:= Format(' By the project rules it is a member: add %s to the uses clause of %s and to the ' +
      'project files (.dpr uses and .dproj DCCReference).', [AUnit, AUser]);
  end;

  procedure CollectCandidates;
  begin
    var Dirs: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
    try
      Dirs.AddOrSetValue(LowerCase(ExcludeTrailingPathDelimiter(ExtractFilePath(TPath.GetFullPath(ADprojPath)))), True);
      for var F: string in Sources do
        Dirs.AddOrSetValue(LowerCase(ExcludeTrailingPathDelimiter(ExtractFilePath(F))), True);
      for var D: string in Dirs.Keys do
      begin
        if not TDirectory.Exists(D) then Continue;
        for var P: string in TDirectory.GetFiles(D, '*.pas', TSearchOption.soTopDirectoryOnly) do
        begin
          var Key: string:= LowerCase(TPath.GetFileNameWithoutExtension(P));
          if ClosurePaths.ContainsKey(LowerCase(TPath.GetFullPath(P))) or ClosureUnits.ContainsKey(Key)
             or Candidates.ContainsKey(Key) then Continue;
          Candidates.Add(Key, TLinkCandidate.Create(P));
        end;
      end;
    finally
      Dirs.Free;
    end;
    { A class two candidates both declare names no single unit: no link is claimed for it. }
    var Ambiguous: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
    try
      for var C: TLinkCandidate in Candidates.Values do
        for var K: string in C.Classes.Keys do
          if ClosureClasses.ContainsKey(K) or Ambiguous.ContainsKey(K) then Continue
          else if ClassOwner.ContainsKey(K) then
          begin
            ClassOwner.Remove(K);
            Ambiguous.Add(K, True);
          end
          else ClassOwner.Add(K, C);
    finally
      Ambiguous.Free;
    end;
  end;

  procedure ScanDfm(const APasPath: string);
  begin
    var Dfm: string:= TPath.ChangeExtension(APasPath, '.dfm');
    if not TFile.Exists(Dfm) then Exit;
    var Text: string:= ReadTextOrEmpty(Dfm);
    if not TRegEx.IsMatch(Text, '\A\s*(?:object|inherited|inline)\b', [roIgnoreCase]) then Exit; // binary form
    var User: string:= TPath.GetFileNameWithoutExtension(RealCasedFileName(APasPath));
    for var M: TMatch in TRegEx.Matches(Text, DFM_CLASS_PATTERN, [roIgnoreCase, roMultiLine]) do
    begin
      var Cand: TLinkCandidate;
      if not ClassOwner.TryGetValue(LowerCase(M.Groups[1].Value), Cand) then Continue;
      Report(Dfm, LineOfOffset(Text, M.Index), Cand.UnitName, 'dfm', Format(
        'Unit "%s" is not reached through `uses`, but %s streams class %s, which only that unit declares.',
        [Cand.UnitName, ExtractFileName(Dfm), M.Groups[1].Value]) + AddAdvice(Cand.UnitName, User));
    end;
  end;

  procedure ScanSource(const APath: string);
  begin
    var Text: string:= StripPasCommentsKeepLayout(ReadTextOrEmpty(APath));
    if Text = '' then Exit;
    var User: string:= TPath.GetFileNameWithoutExtension(RealCasedFileName(APath));
    for var M: TMatch in TRegEx.Matches(Text, BY_NAME_PATTERN, [roIgnoreCase]) do
    begin
      var Cand: TLinkCandidate;
      if not ClassOwner.TryGetValue(LowerCase(M.Groups[1].Value), Cand) then Continue;
      Report(APath, LineOfOffset(Text, M.Index), Cand.UnitName, 'byname', Format(
        'Unit "%s" is not reached through `uses`, but %s looks up class %s by name, which only that unit declares.',
        [Cand.UnitName, ExtractFileName(APath), M.Groups[1].Value]) + AddAdvice(Cand.UnitName, User));
    end;
    { Link 2 reads code only: a string literal naming `Unit.Ident` is text, not a reference. }
    var Code: string:= Text;
    for var Lit: TMatch in TRegEx.Matches(Text, STRING_LITERAL_PATTERN) do
      for var I: Integer:= Lit.Index to Lit.Index + Lit.Length - 1 do Code[I]:= ' ';
    { Every dotted chain once (linear), then its leading parts looked up: one alternation of
      hundreds of unit names ran 40 s over a 470-unit closure. }
    for var M: TMatch in TRegEx.Matches(Code, QUALIFIED_CHAIN_PATTERN) do
    begin
      var Parts: TArray<string>:= TRegEx.Replace(M.Value, '\s', '').Split(['.']);
      var Written: string:= '';
      var Ident  : string:= '';
      var Cand   : TLinkCandidate:= nil;
      for var K: Integer:= 0 to High(Parts) - 1 do
      begin
        Written:= if K = 0 then Parts[0] else Written + '.' + Parts[K];
        if Candidates.TryGetValue(LowerCase(Written), Cand) then
        begin
          Ident:= Parts[K + 1];
          Break;
        end;
      end;
      if (Cand = nil) or not Cand.IntfWords.ContainsKey(LowerCase(Ident)) then Continue;
      if ClosureUnits.ContainsKey(LowerCase(Written + '.' + Ident)) then Continue; // a dotted closure unit name
      { The look-alike: the same name declared as an identifier in this file is that identifier. }
      if TRegEx.IsMatch(Code, '(?<![\w.])' + TRegEx.Escape(Written) + '\s*[:=]', [roIgnoreCase]) then Continue;
      Report(APath, LineOfOffset(Code, M.Index), Cand.UnitName, 'qualified', Format(
        'Unit "%s" is not reached through `uses`, but %s names it explicitly (%s.%s).',
        [Cand.UnitName, ExtractFileName(APath), Cand.UnitName, Ident]) + AddAdvice(Cand.UnitName, User));
    end;
  end;

begin
  Result:= nil;
  if Length(AClosureFiles) = 0 then Exit;
  ClosurePaths  := TDictionary<string, Boolean>.Create;
  ClosureUnits  := TDictionary<string, Boolean>.Create;
  ClosureClasses:= TDictionary<string, Boolean>.Create;
  Candidates    := TObjectDictionary<string, TLinkCandidate>.Create([doOwnsValues]);
  ClassOwner    := TDictionary<string, TLinkCandidate>.Create;
  Reported      := TDictionary<string, Boolean>.Create;
  Findings      := TList<TLintFinding>.Create;
  Sources       := TList<string>.Create;
  try
    for var F: string in AClosureFiles do
      if SameText(ExtractFileExt(F), '.pas') and TFile.Exists(F) then
      begin
        var Full: string:= TPath.GetFullPath(F);
        Sources.Add(Full);
        ClosurePaths.AddOrSetValue(LowerCase(Full), True);
        var Name: string:= LowerCase(TPath.GetFileNameWithoutExtension(Full));
        ClosureUnits.AddOrSetValue(Name, True);
        while Name.Contains('.') do
        begin
          Name:= Copy(Name, 1, LastDelimiter('.', Name) - 1);
          ClosureUnits.AddOrSetValue(Name, True);
        end;
        AddMatches(StripPasCommentsKeepLayout(ReadTextOrEmpty(Full)), CLASS_DECL_PATTERN, ClosureClasses);
      end;
    CollectCandidates;
    if Candidates.Count = 0 then Exit;
    var ProgramPath: string:= FindSiblingProgramFile(ADprojPath);


    for var S: string in Sources do
    begin
      ScanDfm(S);
      ScanSource(S);
    end;
    if (ProgramPath <> '') and TFile.Exists(ProgramPath) then ScanSource(ProgramPath);
    Result:= Findings.ToArray;
  finally
    Sources.Free;
    Findings.Free;
    Reported.Free;
    ClassOwner.Free;
    Candidates.Free;
    ClosureClasses.Free;
    ClosureUnits.Free;
    ClosurePaths.Free;
  end;
end;

class function TProjectChecks.CheckUsedUnitResolvable(const AStore: ISymbolStore;
  const ALibDbPath: string; const AProjectFile: string): TArray<TLintFinding>;
var
  Findings   : TList<TLintFinding>;
  Members    : TDictionary<string, Boolean>; { normalized stems of indexed units }
  AllFileIds : TArray<Int64>;
  FileId     : Int64;
  UsesArr    : TArray<TUnitUse>;
  U          : TUnitUse;
  F          : TLintFinding;
  LibConn    : TFDConnection;
  LibQ       : TFDQuery;
  LibUnits   : TDictionary<string, Boolean>; { normalized stems of library units }
  DcuStems   : TDictionary<string, Boolean>; { stems of .dcu files on the library search path }
  DcuLoaded  : Boolean;
  SrcPath    : string;
  UnitStem   : string;
  IsMember   : TFunc<string, Boolean>;
  IsLib      : TFunc<string, Boolean>;

  { A unit installed DCU-only (no source anywhere on the Library/Browsing path)
    can never enter the library INDEX -- drag-lint indexes source. The compiler
    still resolves it, so reporting it as "resolves to no known unit" is wrong.
    Raize/Konopka is the canonical case here: RzButton..RzTreeVw ship as .dcu
    under CatalogRepository\BonusKSVC\...\Lib\RX13\Win32, which IS on the Library
    search path, while their sources are not. Scan that path for <unit>.dcu as a
    last resort. Built lazily -- only when something actually failed to resolve --
    so a clean project never pays for the directory walk. }
  procedure EnsureDcuStems;
  var
    Plat, Dir, Fn: string;
    Resolver     : DRagLint.Project.Resolver.TProjectResolver;
  begin
    if DcuLoaded then Exit;
    DcuLoaded := True;
    { Platform comes from the library DB name: ...\library-Win32.sqlite -> Win32. }
    Plat := ChangeFileExt(ExtractFileName(ALibDbPath), '');
    Plat := if StartsText('library-', Plat) then Copy(Plat, Length('library-') + 1, MaxInt) else '';
    if Plat = '' then Exit;
    Resolver := ResolveTargetStudio(AProjectFile).OpenResolver;
    try
      for Dir in Resolver.ReadPlatformLibraryPaths(Plat) do
      begin
        if not TDirectory.Exists(Dir) then Continue;
        try
          for Fn in TDirectory.GetFiles(Dir, '*.dcu') do
            DcuStems.AddOrSetValue(LowerCase(ChangeFileExt(ExtractFileName(Fn), '')), True);
        except
          { unreadable directory on the search path -- ignore, it just can't contribute }
        end;
      end;
    finally
      Resolver.Free;
    end;
  end;

begin
  Result    := nil;
  Findings  := TList<TLintFinding>.Create;
  Members   := TDictionary<string, Boolean>.Create;
  LibUnits  := TDictionary<string, Boolean>.Create;
  DcuStems  := TDictionary<string, Boolean>.Create;
  DcuLoaded := False;
  LibConn   := nil;
  LibQ      := nil;
  try
    if (ALibDbPath <> '') and TFile.Exists(ALibDbPath) then
    begin
      LibConn := TFDConnection.Create(nil);
      { The shared reader open (same as TSQLiteSymbolStore.Connect). A bare
        OpenMode=ReadOnly connection aborted the whole lint-all run the moment a
        library DB was passed, with "disk I/O error". MEASURED 2026-09-24 (D25,
        SQLite 3.45.3): the cause was FireDAC's default connect-time
        `journal_mode = DELETE` on a read-only WAL handle, not missing write
        access to the -shm as this comment used to say. ConnectReadOnly still
        does NOT open SQLITE_OPEN_READONLY (ruling R21): a read-only connection
        that closes last can neither checkpoint nor delete the -wal/-shm. It
        opens read-write (never create), names the journal mode the file
        already has (so the pragma is a no-op), adds PRAGMA query_only, and
        arms the busy timeout before the connect. }
      ConnectReadOnly(LibConn, ALibDbPath);
      { The old lookup was 'SELECT 1 FROM symbols WHERE unit_name_norm = :N'.
        symbols has no unit_name_norm column in ANY schema version -- that column
        lives on unit_uses, which records what a file USES, not what the library
        DECLARES. So the query raised "no such column" the moment a library DB was
        attached, and the library source could never resolve anything.
        A library unit is simply an indexed FILE, so derive the stems from
        files.path through the SAME NormUnit used for the project-member side --
        that shared normalization is what keeps both sides comparable. }
      LibQ := TFDQuery.Create(nil);
      LibQ.Connection := LibConn;
      LibQ.SQL.Text := 'SELECT path FROM files';
      LibQ.Open;
      while not LibQ.Eof do
      begin
        UnitStem := NormUnit(LibQ.Fields[0].AsString);
        if UnitStem <> '' then LibUnits.AddOrSetValue(UnitStem, True);
        LibQ.Next;
      end;
      LibQ.Close;
    end;

    AllFileIds := AStore.GetAllFileIds;
    for FileId in AllFileIds do
    begin
      UnitStem := NormUnit(AStore.GetFilePath(FileId));
      if UnitStem <> '' then Members.AddOrSetValue(UnitStem, True);
    end;

    { dcc64 37.0 cannot pass a nested function as a TFunc<> argument -- use
      anonymous methods assigned to local TFunc<> variables instead, capturing
      Members / LibQ by closure. }
    IsMember := TFunc<string, Boolean>(
      function(const AN: string): Boolean
      begin
        Result := Members.ContainsKey(AN);
      end);
    IsLib := TFunc<string, Boolean>(
      function(const AN: string): Boolean
      begin
        Result := LibUnits.ContainsKey(AN);
      end);

    for FileId in AllFileIds do
    begin
      SrcPath := AStore.GetFilePath(FileId);
      UsesArr := AStore.GetUnitUsesForFile(FileId);
      for U in UsesArr do
      begin
        if U.InPath <> '' then Continue; { self-locating uses -- not a resolvability question }
        if System.StrUtils.EndsText('_server', NormUnit(U.UnitName)) then Continue; { sibling SERVER project unit -- legitimately absent from this index (FP-9) }
        if ResolveUsedUnit(U.UnitName, IsMember, IsLib).Resolvable then Continue;
        { Last resort before reporting: a DCU-only install (see EnsureDcuStems). }
        EnsureDcuStems;
        if DcuStems.ContainsKey(NormUnit(U.UnitName)) then Continue;
        F := Default(TLintFinding);
        F.RuleId   := 'used-unit-not-resolvable';
        F.Severity := 'warning';
        F.Message  := Format(
          'Unit ''%s'' is used but resolves to no known unit (not a project ' +
          'member, not in the library, not a known alias or RTL unit). Add its ' +
          'folder or library to the index, add the unit to the project, or ' +
          'remove the use.', [U.UnitName]) + U.IncludeSuffix; { N-06 }
        F.FilePath  := SrcPath;
        { N-06: an include row's coordinates are inside the .inc -- anchor at the
          host's include directive instead. }
        F.StartLine := U.HostLine;
        F.StartCol  := U.HostCol;
        F.EndLine   := if U.FromInclude then U.IncludeLine else U.EndLine;
        F.EndCol    := if U.FromInclude then 1 else U.EndCol;
        Findings.Add(F);
      end;
    end;
    Result := Findings.ToArray;
  finally
    LibQ.Free;
    LibConn.Free;
    LibUnits.Free;
    DcuStems.Free;
    Members.Free;
    Findings.Free;
  end;
end; // function

end.
