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
  /// <remarks>Specific rather than a bare Exception so a caller can tell a
  /// malformed config apart from an I/O failure and report it usefully.</remarks>
  EManifestWriteError = class(Exception);

  TRegisterOutcome = (
    roAdded,          { section written to every manifest copy   }
    roAlreadyOwned,   { a section already claims this project    }
    roAmbiguous,      { several sections claim it -- do not add  }
    roNoManifest,     { no drag-lint.json found to write to      }
    roFailed);        { parse or write error; see the message    }

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
/// <remarks>Refuses when a section already claims the project -- registering a
/// second owner would create the ambiguity the reindex command exists to
/// refuse. Not thread-safe; call from one thread.</remarks>
function RegisterProjectSection(const AEngineDir, AProjectFile, AName: string;
  AApply: Boolean): TRegisterResult;

/// <summary>Every drag-lint.json that a normal install loads: the one beside the
/// engine plus the one beside the design-time BPL.</summary>
/// <param name="AEngineDir">Directory of the running engine.</param>
/// <returns>Absolute paths of the manifest copies that exist.</returns>
function FindManifestCopies(const AEngineDir: string): TArray<string>;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.JSON   ;   { SysUtils comes from the interface uses }

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
    honours .drag-lint-ignore; sqlOnlyMS keeps the MS*.sql convention. }
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
  case ResolveProjectDb(Manifest, ProjAbs, Db, Claim) of
    pdmUnique:
      begin
        Result.Outcome  := roAlreadyOwned;
        Result.Claimants:= Claim;
        Result.Message  := 'already registered; nothing to do';
        Exit;
      end;
    pdmAmbiguous:
      begin
        Result.Outcome  := roAmbiguous;
        Result.Claimants:= Claim;
        Result.Message  := 'several sections already claim this project -- fix the manifest by hand';
        Exit;
      end;
  end;

  Copies:= FindManifestCopies(AEngineDir);
  if Length(Copies) = 0 then
  begin
    Result.Outcome:= roNoManifest;
    Result.Message:= 'no drag-lint.json found at or beside ' + AEngineDir;
    Exit;
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
      Result.Message:= 'dry run -- nothing written';
      Exit;
    end;

    { ALL copies or none: build every new text first, and only then write. A
      half-applied registration leaves the IDE and the CLI disagreeing about
      which projects exist, which is harder to notice than an outright failure. }
    var NewTexts: TArray<string>;
    SetLength(NewTexts, Length(Copies));
    try
      for var i:= 0 to High(Copies) do
        NewTexts[i]:= AppendSectionToText(TFile.ReadAllText(Copies[i]), SectionOb);
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
    Result.Message:= 'section added';
  finally
    SectionOb.Free;
  end;
end;

end.
