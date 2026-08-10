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
      /// <param name="ADprojPath"><!-- drag-lint:auto --></param>
      /// <returns><!-- drag-lint:auto -->Observed: Findings.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)
      /// Calls: Default, DRagLint.Lint.ProjectChecks.Parse.ExtractUsesNames, DRagLint.Lint.ProjectChecks.Parse.FindSiblingProgramFile, DRagLint.Lint.ProjectChecks.Parse.NormUnit, DRagLint.Lint.ProjectChecks.Parse.ReadDCCReferences, ExtractFileName, ExtractFilePath, Format, SameText, StartsText
      /// Complexity: 24 (cyclomatic, outer body), 96 lines (full implementation)
      /// Touches: file system
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.ExtractUsesNames"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.FindSiblingProgramFile"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.NormUnit"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.ReadDCCReferences"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUsedUnitResolvable"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckUnitsInDpr( const ADprojPath: string): TArray<TLintFinding>;
      /// <summary>Flags every `uses X` whose unit X resolves to no known unit
      /// (project member / platform library / standard alias / RTL namespace).
      /// Findings attach to the `uses` token line on the using file. No .dproj
      /// required. Uses with an explicit `in '&lt;path>'` locator are skipped.</summary>
      /// <param name="AStore">Open project symbol store (the project scope).</param>
      /// <param name="ALibDbPath">Platform library SQLite DB; '' skips the library source.</param>
      /// <returns>One warning per unresolvable used unit.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.DoLintProject (DRagLint.CLI.pas)
      /// Calls: ChangeFileExt, Copy, Default, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile, DRagLint.Lint.ProjectChecks.Parse.NormUnit, DRagLint.Lint.ProjectChecks.Parse.ResolveUsedUnit, DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUsedUnitResolvable.EnsureDcuStems, ExtractFileName, Format, LowerCase, StartsText
      /// Returns: nil; Findings.ToArray
      /// Complexity: 10 (cyclomatic, outer body), 163 lines (full implementation)
      /// SQL: reads FILES
      /// Touches: file system
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.NormUnit"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.ResolveUsedUnit"/>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUsedUnitResolvable.EnsureDcuStems"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CheckUsedUnitResolvable(const AStore: ISymbolStore;
        const ALibDbPath: string): TArray<TLintFinding>;
  end;

implementation

uses
  FireDAC.Comp.Client
  ;

class function TProjectChecks.CheckUnitsInDpr( const ADprojPath: string): TArray<TLintFinding>;
var
  DCCRefs    : TArray<string>             ;
  ProgramUses: TArray<string>             ;
  ProgramPath: string                     ;
  DCCSet     : TDictionary<string, string>;
  UsesSet    : TDictionary<string, string>;
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

    // Normalize BOTH sides identically (NormUnit) so dotted unit names like
    // 'Foo.ViewModel' / 'Foo.ViewModel.pas' compare equal (FP-9 class of bug).
    for RefPath in DCCRefs     do DCCSet .AddOrSetValue(NormUnit(RefPath), RefPath);
    for Name    in ProgramUses do UsesSet.AddOrSetValue(NormUnit(Name   ), Name   );

    // In .dproj but not in .dpr/.dpk uses -> most dangerous case.
    for Pair in DCCSet do
    begin
      if not UsesSet.ContainsKey(Pair.Key) then
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
      if not DCCSet.ContainsKey(Pair.Key) then
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

    Result:= Findings.ToArray;
  finally
    DCCSet.Free;
    UsesSet.Free;
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
