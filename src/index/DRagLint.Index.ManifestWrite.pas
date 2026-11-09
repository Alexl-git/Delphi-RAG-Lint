unit DRagLint.Index.ManifestWrite;

{ Adding a project SECTION to the index manifest -- the write half of
  DRagLint.Index.Manifest, which is read-only.

  WHY THIS EXISTS. Opening a brand-new project and asking the IDE to index it
  produced a dead end (owner, 2026-08-24):

      drag-lint: no index section owns this project, so there is nothing to
      rebuild. ... Add a section for this project to the manifest (or check the
      manifest parses), then run this again.

  The refusal itself is RIGHT and is not relaxed here. Its comment in
  DragLint.Plugin.Editor records what it is protecting against: `--rebuild`
  clears an entire database, and resolving the target by folder prefix once
  meant a SIBLING project's index was emptied and refilled with the wrong
  compile closure. Refusing costs a click; guessing destroys an index.

  What was missing was never leniency -- it was any way at all to REGISTER the
  project. The engine had no manifest writer, so there was no verb the plugin
  could have called even if it had wanted to.

  TWO THINGS THIS IS CAREFUL ABOUT.

  1. IT EDITS THE JSON, IT DOES NOT RE-SERIALISE IT. Round-tripping through
     TIndexManifest would silently drop every key the reader does not model --
     `_comment` blocks, unknown future keys, key order, formatting. A config
     file that quietly loses content on write is a worse defect than the one
     being fixed, so the section object is appended to the existing
     `indexes.sections` array and nothing else is touched.

  2. IT WRITES EVERY COPY, OR IT WRITES NONE. The manifest exists twice on a
     normal install: beside the engine (`dll-win64\`) and beside the design-time
     BPL (`dll-win32\`), because each side loads the one next to itself. They
     are byte-identical today. Updating one would leave the IDE and the CLI
     disagreeing about which projects exist -- a silent split-brain, which is
     exactly the failure shape this codebase keeps paying for. All copies are
     written, and the caller is told each path. }

interface

uses
  System.SysUtils        ,
  DRagLint.Index.Manifest;

type
  /// <summary>A manifest copy could not be parsed or understood well enough to
  /// be edited safely.</summary>
  /// <remarks>
  /// Specific rather than a bare Exception so a caller can tell a
  /// malformed config apart from an I/O failure and report it usefully.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Index.ManifestWrite.AppendSectionToText (DRagLint.Index.ManifestWrite.pas), DRagLint.Index.ManifestWrite.RebasedManifestText (DRagLint.Index.ManifestWrite.pas)</para>
  /// <para>Used in units: DRagLint.Index.ManifestWrite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  EManifestWriteError = class(Exception);

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Index.ManifestWrite.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRegisterOutcome = (
    roAdded,          { section written to every manifest copy   }
    roAlreadyOwned,   { a section already claims this project    }
    roAmbiguous,      { several sections claim it -- do not add  }
    roNoManifest,     { no drag-lint.json found to write to      }
    roFailed,         { parse or write error; see the message    }
    roManifestUnparsed); { Load could not parse a manifest it found;
                        Message is its LoadError -- nothing written }

  /// <remarks>
  /// <!-- drag-lint:auto -->Message is its LoadError -- nothing written
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Index.ManifestWrite.pas) ?, DRagLint.CLI.DoRegisterProject (DRagLint.CLI.pas) ?, DRagLint.Index.ManifestWrite.RegisterProjectSection (DRagLint.Index.ManifestWrite.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Index.ManifestWrite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRegisterResult = record
    Outcome  : TRegisterOutcome;
    Section  : string          ; { the section name added or found      }
    Claimants: TArray<string>  ; { for roAlreadyOwned / roAmbiguous     }
    Written  : TArray<string>  ; { manifest paths written (or would be) }
    Json     : string          ; { the section object, for --dry-run    }
    Message  : string          ;
  end;

/// <summary>Registers a .dproj/.dpr as its own index section in every manifest
/// copy, so `index --all` and the IDE's reindex command can see it.</summary>
/// <param name="AEngineDir">Directory of the running engine; the search for
/// manifest copies starts here.</param>
/// <param name="AProjectFile">Absolute path to the project file.</param>
/// <param name="AName">Section name; '' derives it from the project file's base
/// name, matching the existing per-project-closure convention.</param>
/// <param name="AApply">False reports what would be written and touches
/// nothing.</param>
/// <returns>A result whose Outcome says what happened; Written lists every
/// manifest path affected.</returns>
/// <exception cref="EManifestError"><!-- drag-lint:auto exc -->via DRagLint.Index.Manifest.TInstalledLayout.Enabled: (root): expected object, got</exception>
/// <remarks>
/// Refuses when a section already claims the project -- registering a
/// second owner would create the ambiguity the reindex command exists to
/// refuse. Refuses (roManifestUnparsed, nothing written, dry run or not) when
/// TManifestIO.Load could not parse a manifest it found. Not thread-safe; call
/// from one thread.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoRegisterProject (DRagLint.CLI.pas)</para>
/// <para>Calls: Default, DRagLint.Index.Manifest.ResolveProjectDb, DRagLint.Index.Manifest.TInstalledLayout.AppDataManifestFor, DRagLint.Index.Manifest.TInstalledLayout.Enabled, DRagLint.Index.Manifest.TInstalledLayout.WriteTarget, DRagLint.Index.Manifest.TManifestIO.Load, DRagLint.Index.ManifestWrite.AppendSectionToText, DRagLint.Index.ManifestWrite.BuildSectionJson, DRagLint.Index.ManifestWrite.FindManifestCopies, ExtractFileDir, GetEnvironmentVariable, SameText</para>
/// <para>Returns: Default(TRegisterResult)</para>
/// <para>Complexity: 16 (cyclomatic, outer body), 116 lines (full implementation)</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Index.Manifest.ResolveProjectDb"/>
/// <seealso cref="DRagLint.Index.Manifest.TInstalledLayout.AppDataManifestFor"/>
/// <seealso cref="DRagLint.Index.Manifest.TInstalledLayout.Enabled"/>
/// <seealso cref="DRagLint.Index.Manifest.TInstalledLayout.WriteTarget"/>
/// <seealso cref="DRagLint.Index.Manifest.TManifestIO.Load"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RegisterProjectSection(const AEngineDir, AProjectFile, AName: string;
  AApply: Boolean): TRegisterResult;

/// <summary>Every drag-lint.json that a normal install loads: the one beside the
/// engine plus the one beside the design-time BPL.</summary>
/// <param name="AEngineDir">Directory of the running engine.</param>
/// <returns>Absolute paths of the manifest copies that exist.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Index.ManifestWrite.RegisterProjectSection (DRagLint.Index.ManifestWrite.pas)</para>
/// <para>Calls: DRagLint.Index.Manifest.TInstalledLayout.ManifestLocation, DRagLint.Index.ManifestWrite.FindManifestCopies.Consider, ExcludeTrailingPathDelimiter</para>
/// <para>Returns: []; [Located.Path]; Acc.ToStringArray</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Index.Manifest.TInstalledLayout.ManifestLocation"/>
/// <seealso cref="DRagLint.Index.ManifestWrite.FindManifestCopies.Consider"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindManifestCopies(const AEngineDir: string): TArray<string>;

type
  /// <summary>What `manifest migrate` did or would do.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Index.ManifestWrite.pas), DRagLint.CLI.DoManifestMigrate (DRagLint.CLI.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TMigrateOutcome = (
    mgMigrated,         { roaming file written, exe-side file renamed (or would be) }
    mgNothingToMigrate, { no drag-lint.json beside the engine                         }
    mgTargetExists,     { the roaming file exists already: nothing written or renamed }
    mgLayoutOff,        { --apply with DRAGLINT_LAYOUT not v2: refused                }
    mgExplicit,         { DRAGLINT_MANIFEST / --manifest in effect: refused           }
    mgNoAppData,        { %APPDATA% is unset: refused                                 }
    mgFailed);          { parse or I/O error; see Message                             }

  /// <summary>Result of <see cref="MigrateExeManifest"/>.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Index.ManifestWrite.pas) ?, DRagLint.Index.ManifestWrite.MigrateExeManifest (DRagLint.Index.ManifestWrite.pas)</para>
  /// <para>Used in units: DRagLint.Index.ManifestWrite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TMigrateResult = record
    Outcome  : TMigrateOutcome;
    Source   : string; { the exe-side drag-lint.json                       }
    Target   : string; { %APPDATA%\drag-lint\drag-lint.json                }
    RenamedTo: string; { drag-lint.json.migrated-yyyy-mm-dd[-n]            }
    Json     : string; { the text written (or that would be) to Target     }
    Message  : string;
  end;

/// <summary>`manifest migrate` (installed layout v2, phase 2, ruling 2): copies the
/// exe-side drag-lint.json to %APPDATA%\drag-lint\drag-lint.json and RENAMES the
/// exe-side file to drag-lint.json.migrated-&lt;date&gt;. It never deletes and never
/// overwrites.</summary>
/// <param name="AEngineDir">Directory of the running engine (the exe side).</param>
/// <param name="AApply">False plans and touches nothing; allowed with the layout OFF.</param>
/// <param name="ADate">Date stamped into the renamed file's name.</param>
/// <returns>Outcome plus every path involved.</returns>
/// <exception cref="EManifestError"><!-- drag-lint:auto exc -->via DRagLint.Index.Manifest.TInstalledLayout.Enabled: (root): expected object, got</exception>
/// <remarks>
/// Paths are rebased so that every DB stays where it was: `outDir` becomes
/// absolute (the exe dir when it was absent, which also stops the roaming default of
/// ruling 3 from moving the DBs), and every relative section `include` becomes absolute
/// against the exe dir. The roaming file is written first, then the source is renamed;
/// if the rename fails both files remain and the layout-v2 reader answers from the
/// roaming one. The BPL-side sibling copy is not touched (plugin, phase 3). Not
/// thread-safe.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoManifestMigrate (DRagLint.CLI.pas)</para>
/// <para>Calls: Default, DRagLint.Index.Manifest.TInstalledLayout.AppDataManifestFor, DRagLint.Index.Manifest.TInstalledLayout.Enabled, DRagLint.Index.ManifestWrite.RebasedManifestText, ExtractFileDir, FormatDateTime, GetEnvironmentVariable, IntToStr</para>
/// <para>Returns: Default(TMigrateResult)</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Index.Manifest.TInstalledLayout.AppDataManifestFor"/>
/// <seealso cref="DRagLint.Index.Manifest.TInstalledLayout.Enabled"/>
/// <seealso cref="DRagLint.Index.ManifestWrite.RebasedManifestText"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function MigrateExeManifest(const AEngineDir: string; AApply: Boolean;  // dl:ok doc-drift@f4f7 -- the <exception> tag is engine-generated via a callee (TInstalledLayout.Enabled); doc-drift judges the body only: engine disagreement, 148 row
  ADate: TDateTime): TMigrateResult;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.JSON   ;   { SysUtils comes from the interface uses }

const
  { The roaming manifest register-project creates when none exists (layout v2). }
  NEW_MANIFEST_TEXT = '{"settings":{},"indexes":{"sections":[]}}';

function FindManifestCopies(const AEngineDir: string): TArray<string>;
var
  Acc   : TStringList;
  Parent: string     ;

  procedure Consider(const ADir: string);
  var P: string;
  begin
    if ADir = '' then Exit;
    P:= TPath.Combine(ADir, 'drag-lint.json');
    if TFile.Exists(P) and (Acc.IndexOf(P) < 0) then Acc.Add(P);
  end;

begin
  { Explicit or APPDATA (layout v2): the one file the read answered, no sibling walk. }
  var Located:= TInstalledLayout.ManifestLocation(AEngineDir);
  if Located.Origin <> moExeDir then
  begin
    Result:= [];
    if Located.Exists then Result:= [Located.Path];
    Exit;
  end;

  Acc:= TStringList.Create;
  try
    Consider(AEngineDir);
    { The BPL's copy is a SIBLING of the engine's, not a parent or a child:
      third_party\dll-win64\ (engine) and third_party\dll-win32\ (BPL). Walking
      the parent's children is what finds it without hard-coding either name. }
    Parent:= TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(AEngineDir));
    if (Parent <> '') and TDirectory.Exists(Parent) then
      for var D: string in TDirectory.GetDirectories(Parent) do Consider(D);
    Result:= Acc.ToStringArray;
  finally
    Acc.Free;
  end;
end;

function BuildSectionJson(const AName, AProjectFile: string): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('name', AName);
  var Inc_: TJSONArray:= TJSONArray.Create;
  Inc_.Add(AProjectFile);
  Result.AddPair('include', Inc_);
  { Matches what every existing per-project section carries. useIgnoreFiles
    honours .gitignore / .hgignore files found during the walk; sqlOnlyMS keeps the MS*.sql convention. }
  Result.AddPair('useIgnoreFiles', TJSONBool.Create(True));
  Result.AddPair('sqlOnlyMS'     , TJSONBool.Create(True));
end;

{ Appends ASectionObj to indexes.sections in the JSON text of AManifestPath and
  returns the new text. Raises on anything unexpected rather than writing a file
  it does not understand. }
function AppendSectionToText(const AText: string; const ASectionObj: TJSONObject): string;
var
  Root: TJSONObject;
begin
  Root:= TJSONObject.ParseJSONValue(AText) as TJSONObject;
  if Root = nil then raise EManifestWriteError.Create('manifest is not a JSON object');
  try
    var Indexes: TJSONObject:= Root.GetValue('indexes') as TJSONObject;
    if Indexes = nil then raise EManifestWriteError.Create('manifest has no "indexes" object');
    var Sections: TJSONArray:= Indexes.GetValue('sections') as TJSONArray;
    if Sections = nil then raise EManifestWriteError.Create('manifest has no "indexes.sections" array');
    Sections.Add(ASectionObj.Clone as TJSONObject);
    Result:= Root.Format(2);
  finally
    Root.Free;
  end;
end;

function RegisterProjectSection(const AEngineDir, AProjectFile, AName: string;
  AApply: Boolean): TRegisterResult;
var
  Manifest : TIndexManifest;
  Db       : string        ;
  Claim    : TArray<string>;
  Copies   : TArray<string>;
  SecName  : string        ;
  ProjAbs  : string        ;
  SectionOb: TJSONObject   ;
begin
  Result:= Default(TRegisterResult);

  ProjAbs:= TPath.GetFullPath(AProjectFile);
  if not TFile.Exists(ProjAbs) then
  begin
    Result.Outcome:= roFailed;
    Result.Message:= 'project file not found: ' + ProjAbs;
    Exit;
  end;

  { Ownership is asked of the SAME resolver the reindex command refuses on, so
    the two can never disagree about whether a project is already claimed. }
  Manifest:= TManifestIO.Load(AEngineDir, TPath.GetDirectoryName(ProjAbs));
  { A manifest Load had to SKIP is not asked about ownership: the part that did
    parse can miss the very section that claims this project, and --apply would
    then write a SECOND claimant -- an ambiguity every later index refuses on. }
  if Manifest.LoadError <> '' then
  begin
    Result.Outcome:= roManifestUnparsed;
    Result.Message:= Manifest.LoadError;
  end
  else
    case ResolveProjectDb(Manifest, ProjAbs, Db, Claim) of
      pdmUnique:
        begin
          Result.Outcome  := roAlreadyOwned;
          Result.Claimants:= Claim;
          Result.Message  := 'already registered; nothing to do';
        end;
      pdmAmbiguous:
        begin
          Result.Outcome  := roAmbiguous;
          Result.Claimants:= Claim;
          Result.Message  := 'several sections already claim this project -- fix the manifest by hand';
        end;
    end;
  { Every arm above that decided the outcome moved it off roAdded, the ordinal-0
    value Default(TRegisterResult) left there; only "nobody owns it yet" goes on. }
  if Result.Outcome <> roAdded then Exit;

  Copies:= FindManifestCopies(AEngineDir);
  { Layout v2, phase 2: with no manifest anywhere, the roaming file is created
    (WriteTarget names it only when the layout is on and nothing exists). }
  var Created:= '';
  if Length(Copies) = 0 then
  begin
    var Target:= TInstalledLayout.WriteTarget(AEngineDir);
    if TInstalledLayout.Enabled and (Target <> '') and not TFile.Exists(Target) and
      SameText(Target, TInstalledLayout.AppDataManifestFor(GetEnvironmentVariable('APPDATA'))) then
    begin
      Created:= Target;
      Copies := [Target];
    end
    else
    begin
      Result.Outcome:= roNoManifest;
      Result.Message:= 'no drag-lint.json found at or beside ' + AEngineDir;
      Exit;
    end;
  end;

  SecName:= AName;
  if SecName = '' then SecName:= TPath.GetFileNameWithoutExtension(ProjAbs);

  SectionOb:= BuildSectionJson(SecName, ProjAbs);
  try
    Result.Section:= SecName;
    Result.Json   := SectionOb.Format(2);
    Result.Written:= Copies;

    if not AApply then
    begin
      Result.Outcome:= roAdded;   { reported as WOULD add; the caller prints the mode }
      Result.Message:= if Created = '' then 'dry run -- nothing written'
        else 'dry run -- nothing written; would create ' + Created;
      Exit;
    end;

    { ALL copies or none: build every new text first, and only then write. A
      half-applied registration leaves the IDE and the CLI disagreeing about
      which projects exist, which is harder to notice than an outright failure. }
    var NewTexts: TArray<string>;
    SetLength(NewTexts, Length(Copies));
    try
      for var i:= 0 to High(Copies) do
        NewTexts[i]:= AppendSectionToText(
          if Copies[i] = Created then NEW_MANIFEST_TEXT else TFile.ReadAllText(Copies[i]), SectionOb);  // dl:ok taint-path-traversal@38a7 -- REVIEWED 2026-11-08 (X5P): the path IS the user's own %APPDATA% / DRAGLINT_MANIFEST manifest (owner ruling 1); reading the file the environment names is the design, not a traversal
      if Created <> '' then TDirectory.CreateDirectory(ExtractFileDir(Created));  // dl:ok taint-path-traversal@444a -- REVIEWED 2026-11-08 (X5P): creates the folder of %APPDATA%\drag-lint\drag-lint.json for the user who runs the engine (layout v2, phase 2); the environment choosing it is the design
    except
      on E: Exception do
      begin
        Result.Outcome:= roFailed;
        Result.Message:= 'manifest not updated: ' + E.Message;
        Exit;
      end;
    end;

    for var i:= 0 to High(Copies) do
      TFile.WriteAllText(Copies[i], NewTexts[i], TEncoding.UTF8);

    Result.Outcome:= roAdded;
    Result.Message:= if Created = '' then 'section added' else 'section added; created ' + Created;
  finally
    SectionOb.Free;
  end;
end;

{ Rebases one path value written relative to the exe dir so it means the same
  from the roaming folder. Empty, absolute and %VAR% values are kept. }
function RebaseToExeDir(const AValue, AEngineDir: string): string;
begin
  if (AValue = '') or AValue.Contains('%') or TPath.IsPathRooted(AValue) then Exit(AValue);
  Result:= ExcludeTrailingPathDelimiter(TPath.GetFullPath(TPath.Combine(AEngineDir, AValue)));
end;

{ Rebases a section's `include` (string or array) in place. }
procedure RebaseInclude(const ASection: TJSONObject; const AEngineDir: string);
begin
  var Pair:= ASection.Get('include');
  if Pair = nil then Exit;
  if Pair.JsonValue is TJSONArray then
  begin
    var NewArr:= TJSONArray.Create;
    for var Item in TJSONArray(Pair.JsonValue) do NewArr.Add(RebaseToExeDir(Item.Value, AEngineDir));
    Pair.JsonValue:= NewArr;
  end
  else if Pair.JsonValue is TJSONString then
    Pair.JsonValue:= TJSONString.Create(RebaseToExeDir(Pair.JsonValue.Value, AEngineDir));
end;

{ The migrated text: outDir and every relative include made absolute against the
  exe dir; every other key kept as it was. Raises on a shape it does not know. }
function RebasedManifestText(const AText, AEngineDir: string): string;
begin
  var Root:= TJSONObject.ParseJSONValue(AText);
  if Root is not TJSONObject then
  begin
    Root.Free;
    raise EManifestWriteError.Create('manifest is not a JSON object');
  end;
  try
    var Indexes:= TJSONObject(Root).GetValue('indexes');
    if Indexes is not TJSONObject then raise EManifestWriteError.Create('manifest has no "indexes" object');
    var OutPair:= TJSONObject(Indexes).Get('outDir');
    var OutDir := ExcludeTrailingPathDelimiter(TPath.GetFullPath(AEngineDir));
    if (OutPair <> nil) and (OutPair.JsonValue.Value <> '') then
      OutDir:= RebaseToExeDir(OutPair.JsonValue.Value, AEngineDir);
    if OutPair <> nil then OutPair.JsonValue:= TJSONString.Create(OutDir)
    else TJSONObject(Indexes).AddPair('outDir', OutDir);
    var Sections:= TJSONObject(Indexes).GetValue('sections');
    if Sections is TJSONArray then
      for var S in TJSONArray(Sections) do
        if S is TJSONObject then RebaseInclude(TJSONObject(S), AEngineDir);
    Result:= Root.Format(2);
  finally
    Root.Free;
  end;
end;

function MigrateExeManifest(const AEngineDir: string; AApply: Boolean;  // dl:ok too-many-exit-points@e030 -- REVIEWED 2026-11-08 (X5P): each exit is a DISTINCT TMigrateOutcome (explicit, no APPDATA, nothing, target exists, unparsable, dry run, layout off, write failed, rename failed); the guard asserts them apart, one exit would thread a state flag through I/O steps whose order is the contract
  ADate: TDateTime): TMigrateResult;
begin
  Result:= Default(TMigrateResult);
  Result.Source:= TPath.Combine(AEngineDir, 'drag-lint.json');
  Result.Target:= TInstalledLayout.AppDataManifestFor(GetEnvironmentVariable('APPDATA'));
  if GetEnvironmentVariable(TInstalledLayout.MANIFEST_ENV) <> '' then
  begin
    Result.Outcome:= mgExplicit;
    Result.Message:= 'an explicit manifest is in effect (DRAGLINT_MANIFEST / --manifest); nothing to migrate';
    Exit;
  end;
  if Result.Target = '' then
  begin
    Result.Outcome:= mgNoAppData;
    Result.Message:= '%APPDATA% is not set';
    Exit;
  end;
  if not TFile.Exists(Result.Source) then
  begin
    Result.Outcome:= mgNothingToMigrate;
    Result.Message:= 'no drag-lint.json beside the engine; nothing to migrate';
    Exit;
  end;
  if TFile.Exists(Result.Target) then
  begin
    Result.Outcome:= mgTargetExists;
    Result.Message:= 'the roaming manifest exists already; nothing written or renamed';
    Exit;
  end;
  var Stem:= Result.Source + '.migrated-' + FormatDateTime('yyyy-mm-dd', ADate);
  Result.RenamedTo:= Stem;
  var N:= 1;
  while TFile.Exists(Result.RenamedTo) do
  begin
    Inc(N);
    Result.RenamedTo:= Stem + '-' + IntToStr(N);
  end;
  try
    Result.Json:= RebasedManifestText(TFile.ReadAllText(Result.Source), AEngineDir);
  except
    on E: Exception do
    begin
      Result.Outcome:= mgFailed;
      Result.Message:= 'manifest not migrated: ' + E.Message;
      Exit;
    end;
  end;
  if not AApply then
  begin
    Result.Outcome:= mgMigrated;
    Result.Message:= 'dry run -- nothing written or renamed';
    Exit;
  end;
  if not TInstalledLayout.Enabled then
  begin
    Result.Outcome:= mgLayoutOff;
    Result.Message:= 'refused: DRAGLINT_LAYOUT is not v2, so the engine would lose its manifest after the rename';
    Exit;
  end;
  try
    TDirectory.CreateDirectory(ExtractFileDir(Result.Target));
    TFile.WriteAllText(Result.Target, Result.Json, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      Result.Outcome:= mgFailed;
      Result.Message:= 'roaming manifest not written: ' + E.Message;
      Exit;
    end;
  end;
  try
    TFile.Move(Result.Source, Result.RenamedTo);
  except
    on E: Exception do
    begin
      Result.Outcome:= mgFailed;
      Result.Message:= 'roaming manifest written, but the exe-side file was not renamed: ' + E.Message;
      Exit;
    end;
  end;
  Result.Outcome:= mgMigrated;
  Result.Message:= 'migrated';
end;

end.
