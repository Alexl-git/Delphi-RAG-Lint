unit DRagLint.CLI.UnitContext;

{ A unit does not exist by itself (owner Q2, 2026-11-04): with a file and no --db,
  the question is which project it belongs to. These are the file-only parts of
  that answer, with no index and no manifest; DRagLint.CLI puts them together. }

interface

/// <summary>The project files that may own AFile: every .dproj and .dpk in its
/// folder and its ancestors, and every .dpr with no .dproj of the same base.</summary>
/// <param name="AFile">The unit; need not exist.</param>
/// <returns>Full paths, nearest folder first.</returns>
/// <remarks>Top level of each folder only: the search climbs, it never descends.
/// A folder that cannot be listed is skipped.</remarks>
function ProjectFilesNear(const AFile: string): TArray<string>;

/// <summary>True when a project file names AFile.</summary>
/// <param name="AProjectFile">A .dproj, .dpr or .dpk. A .dproj's sibling .dpr is read too.</param>
/// <param name="AFile">The unit, or the project's own main source.</param>
/// <returns>True for a DCCReference or an `in '...'` path that resolves to AFile, or
/// when AFile is the project's own main source file.</returns>
/// <remarks>A unit reached only through a search path is not named here; the
/// project's index answers for those.</remarks>
function ProjectListsFile(const AProjectFile, AFile: string): Boolean;

/// <summary>The unit names in every uses clause of a source file.</summary>
/// <param name="AFile">A .pas file.</param>
/// <returns>The names, dotted as written, without duplicates; empty when the file
/// cannot be read.</returns>
/// <remarks>Text scan with comments and strings removed. Both branches of an $IFDEF
/// count, which is the conservative reading for "does it need a project".</remarks>
function UnitsUsedBy(const AFile: string): TArray<string>;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.RegularExpressions;

function ReadTextOrEmpty(const AFile: string): string;
begin
  Result:= '';
  try
    if TFile.Exists(AFile) then Result:= TFile.ReadAllText(AFile, TEncoding.ANSI);
  except
    on E: EInOutError do Result:= '';
  end;
end;

function ProjectFilesNear(const AFile: string): TArray<string>;
const
  MAX_LEVELS = 8;
var
  Dir: string;
begin
  Result:= nil;
  Dir:= ExcludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(AFile)));
  for var Level: Integer:= 1 to MAX_LEVELS do
  begin
    try
      for var F: string in TDirectory.GetFiles(Dir, '*.dproj') do Result:= Result + [F];
      for var F: string in TDirectory.GetFiles(Dir, '*.dpk') do Result:= Result + [F];
      for var F: string in TDirectory.GetFiles(Dir, '*.dpr') do
        if not TFile.Exists(ChangeFileExt(F, '.dproj')) then Result:= Result + [F];
    except
      on E: EInOutError do ; { an unreadable folder owns nothing we can see }
      on E: EDirectoryNotFoundException do ;
    end;
    var Parent: string:= ExcludeTrailingPathDelimiter(ExtractFilePath(Dir));
    if (Parent = '') or SameText(Parent, Dir) then Break;
    Dir:= Parent;
  end;
end;

function TextNamesFile(const AText, ABaseDir, AFile: string): Boolean;
const
  REFERENCE = 'DCCReference\s+Include="([^"]+)"|\bin\s+''([^'']+)''';
begin
  Result:= False;
  for var M: TMatch in TRegEx.Matches(AText, REFERENCE, [roIgnoreCase]) do
  begin
    var Rel: string:= if M.Groups[1].Success and (M.Groups[1].Value <> '') then M.Groups[1].Value else M.Groups[2].Value;
    try
      if SameText(TPath.GetFullPath(TPath.Combine(ABaseDir, Rel)), AFile) then Exit(True);
    except
      on E: EArgumentException do Continue; { `in '` inside program text, not a path }
    end;
  end;
end;

function ProjectListsFile(const AProjectFile, AFile: string): Boolean;
begin
  var Abs: string:= ExpandFileName(AFile);
  var Dir: string:= ExtractFilePath(ExpandFileName(AProjectFile));
  if SameText(ChangeFileExt(ExpandFileName(AProjectFile), ''), ChangeFileExt(Abs, ''))
     and (not SameText(ExtractFileExt(Abs), '.pas')) then Exit(True);
  Result:= TextNamesFile(ReadTextOrEmpty(AProjectFile), Dir, Abs);
  if (not Result) and SameText(ExtractFileExt(AProjectFile), '.dproj') then
    Result:= TextNamesFile(ReadTextOrEmpty(ChangeFileExt(AProjectFile, '.dpr')), Dir, Abs);
end;

function UnitsUsedBy(const AFile: string): TArray<string>;
const
  NOISE = '\{[^}]*\}|\(\*.*?\*\)|//[^\r\n]*|''[^''\r\n]*''';
  USES_CLAUSE = '\buses\b([^;]*);';
  UNIT_NAME = '^\s*([A-Za-z_][\w.]*)';
var
  Seen: TDictionary<string, Boolean>;
begin
  Result:= nil;
  var Text: string:= TRegEx.Replace(ReadTextOrEmpty(AFile), NOISE, ' ', [roSingleLine]);
  Seen:= TDictionary<string, Boolean>.Create;
  try
    for var M: TMatch in TRegEx.Matches(Text, USES_CLAUSE, [roIgnoreCase]) do
      for var Item: string in M.Groups[1].Value.Split([',']) do
      begin
        var N: TMatch:= TRegEx.Match(Item, UNIT_NAME);
        if not N.Success then Continue;
        var Key: string:= LowerCase(N.Groups[1].Value);
        if Seen.ContainsKey(Key) then Continue;
        Seen.Add(Key, True);
        Result:= Result + [N.Groups[1].Value];
      end;
  finally
    Seen.Free;
  end; // try
end; // function

end.
