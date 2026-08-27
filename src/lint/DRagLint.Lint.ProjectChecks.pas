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
  , System  .Generics.Defaults
  , DRagLint.Core    .Model
  , DRagLint.Core    .Interfaces
  , DRagLint.Lint    .ProjectChecks.Parse
  , DRagLint.Project .Resolver
  ;

type
  TProjectChecks = class
    public
      // Compare .dproj <DCCReference Include="..."/> entries vs the matching
      // .dpr/.dpk's `uses` clause. Returns findings for every unit that is
      // present on one side but not the other.
      /// <summary><!-- drag-lint:auto -->Compare .dproj &lt;DCCReference
      /// Include="..."/&gt; entries vs the matching .dpr/.dpk's `uses` clause. Returns
      /// findings for every unit that is present on one side but not the other.</summary>
      /// <param name="ADprojPath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TLintFinding&gt; -- Observed:
      /// Findings.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: Default, DRagLint.Lint.ProjectChecks.Parse.ExtractUsesNames, DRagLint.Lint.ProjectChecks.Parse.FindSiblingProgramFile, DRagLint.Lint.ProjectChecks.Parse.NormUnit, DRagLint.Lint.ProjectChecks.Parse.ReadDCCReferences, ExtractFileName, ExtractFilePath, Format, SameText, StartsText</para>
      /// <para>Complexity: 24 (cyclomatic, outer body), 96 lines (full implementation)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.ExtractUsesNames"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.FindSiblingProgramFile"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.NormUnit"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.ReadDCCReferences"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUsedUnitResolvable"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      /// <param name="AClosureFiles">The project's compile-closure .pas files,
      /// already scoped to its own roots. Optional: when empty the third
      /// direction below is SKIPPED rather than half-answered.</param>
      class function CheckUnitsInDpr( const ADprojPath: string;
                                      const AClosureFiles: TArray<string> = nil): TArray<TLintFinding>;
      /// <summary>Flags every `uses X` whose unit X resolves to no known unit
      /// (project member / platform library / standard alias / RTL namespace).
      /// Findings attach to the `uses` token line on the using file. No .dproj
      /// required. Uses with an explicit `in '&lt;path>'` locator are skipped.</summary>
      /// <param name="AStore">Open project symbol store (the project scope).</param>
      /// <param name="ALibDbPath">Platform library SQLite DB; '' skips the library source.</param>
      /// <returns>One warning per unresolvable used unit.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.DoLintProject (DRagLint.CLI.pas)</para>
      /// <para>Calls: ChangeFileExt, Copy, Default, DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile, DRagLint.Lint.ProjectChecks.Parse.NormUnit, DRagLint.Lint.ProjectChecks.Parse.ResolveUsedUnit, DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUsedUnitResolvable.EnsureDcuStems, ExtractFileName, Format, LowerCase, StartsText</para>
      /// <para>Returns: nil; Findings.ToArray</para>
      /// <para>Complexity: 10 (cyclomatic, outer body), 163 lines (full implementation)</para>
      /// <para>SQL: reads FILES</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.NormUnit"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.ResolveUsedUnit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckUsedUnitResolvable(const AStore: ISymbolStore;
        const ALibDbPath: string): TArray<TLintFinding>;
  end;

implementation

uses
  FireDAC.Comp.Client
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

class function TProjectChecks.CheckUnitsInDpr( const ADprojPath: string;
                                               const AClosureFiles: TArray<string>): TArray<TLintFinding>;
var
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
        Result := ASet.TryGetValue(AStem, Orig) and (Pos('.', NormUnitQualified(Orig)) = 0);
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
        if StartsText('System.', Pair.Value) or StartsText('Vcl.', Pair.Value) or StartsText('Fmx.', Pair.Value) or StartsText('Data.', Pair.Value) or
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
    if Length(AClosureFiles) > 0 then
    begin
      var ProgBase: string := '';
      if ProgramPath <> '' then ProgBase:= TPath.GetFileNameWithoutExtension(ProgramPath);
      for var ClosureFile: string in AClosureFiles do
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

    Result:= Findings.ToArray;
  finally
    DCCSet.Free;
    UsesSet.Free;
    DCCStemSet.Free;
    UsesStemSet.Free;
    Findings.Free;
  end; // try
end; // function

class function TProjectChecks.CheckUsedUnitResolvable(const AStore: ISymbolStore;
  const ALibDbPath: string): TArray<TLintFinding>;
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
    if StartsText('library-', Plat) then Plat := Copy(Plat, Length('library-') + 1, MaxInt) else Plat := '';
    if Plat = '' then Exit;
    Resolver := DRagLint.Project.Resolver.TProjectResolver.Create;
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
      LibConn.DriverName := 'SQLite';
      LibConn.Params.Values['Database'] := ALibDbPath;
      { Do NOT use OpenMode=ReadOnly (SQLITE_OPEN_READONLY): every drag-lint index
        is WAL-mode, and a WAL DB cannot be opened read-only without write access
        to its -shm wal-index, which fails with "disk I/O error" -- that aborted
        the whole lint-all run the moment a library DB was passed. Mirror the
        read path in TSQLiteSymbolStore.Connect: open with the normal params and
        enforce no-writes with PRAGMA query_only. }
      LibConn.Params.Values['LockingMode'] := 'Normal';
      LibConn.Params.Values['JournalMode'] := 'WAL';
      LibConn.Params.Values['Synchronous'] := 'Normal';
      LibConn.LoginPrompt := False;
      LibConn.Connected := True;
      LibConn.ExecSQL('PRAGMA query_only = ON');
      LibConn.ExecSQL('PRAGMA busy_timeout = 5000');
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
          'member, not in the library, not a known alias or RTL unit). Convert ' +
          'it: comment it out, replace it (e.g. Orpheus->DevExpress, BDE-' +
          '>FireDAC), or add it to the project.', [U.UnitName]);
        F.FilePath  := SrcPath;
        F.StartLine := U.StartLine;
        F.StartCol  := U.StartCol;
        F.EndLine   := U.EndLine;
        F.EndCol    := U.EndCol;
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
