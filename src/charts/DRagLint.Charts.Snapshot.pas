unit DRagLint.Charts.Snapshot;

{ The snapshot folder of Compare (spec F1, F2, S3b): where saved answers live, what
  they are called, and the retention of the 'auto' subfolder. Pure file-system work;
  no VCL. The folder comes from the project's own declaration so it follows the
  ownRoots convention (one anchor, one _D-RAG\drag-lint-project.json). }

interface

/// <summary>Where a project's snapshots are kept (F1).</summary>
/// <param name="pProjectFile">The .dproj; its folder is the anchor when pDbPath says
/// none.</param>
/// <param name="pDbPath">The project's index database, or ''. A DB inside a _D-RAG
/// folder names the anchor (DRagLint.Project.OwnRoots.AnchorDirForDb).</param>
/// <returns>The folder, no trailing separator: the "reportsDir" key of
/// &lt;anchor&gt;\_D-RAG\drag-lint-project.json (absolute, or relative to that _D-RAG
/// folder, like ownRoots), else &lt;anchor&gt;\drag-lint-reports.</returns>
/// <remarks>A missing, malformed or empty declaration falls back to the default; it
/// never raises. Does not create the folder. Pure apart from reading the JSON.</remarks>
function ResolveSnapshotDir(const pProjectFile, pDbPath: string): string;

/// <summary>Makes a report target safe for a file name.</summary>
/// <param name="pTarget">The target, e.g. 'OPERAT.NAME' or 'A -> B'.</param>
/// <returns>pTarget with every character outside [A-Za-z0-9_.-] replaced by '_'
/// ('A -> B' gives 'A_-__B').</returns>
function SanitiseTargetForFileName(const pTarget: string): string;

/// <summary>The F2 name of a snapshot.</summary>
/// <param name="pQuestion">Question id, e.g. 'who-writes'.</param>
/// <param name="pTarget">The target (sanitised here).</param>
/// <param name="pWhen">When the question was asked.</param>
/// <returns>'&lt;question&gt;--&lt;target&gt;--&lt;yyyymmdd-hhmm&gt;.txt', with a
/// 24-hour clock whatever the regional settings.</returns>
function SnapshotFileName(const pQuestion, pTarget: string; pWhen: TDateTime): string;

/// <summary>Saves an answer as a snapshot file.</summary>
/// <param name="pDir">The snapshot folder (ResolveSnapshotDir).</param>
/// <param name="pAuto">True saves under &lt;pDir&gt;\auto and prunes that routine's
/// snapshots to 20.</param>
/// <param name="pQuestion">Question id.</param>
/// <param name="pTarget">Target.</param>
/// <param name="pPlainText">The answer in plain form, full header included.</param>
/// <param name="pWhen">When the question was asked.</param>
/// <param name="pPath">The file written; '' when the result is False.</param>
/// <returns>False when the folder or file cannot be written.</returns>
/// <remarks>Written as UTF-8 without BOM with CRLF line ends. A second snapshot of the
/// same question and target in the same minute replaces the first. Creates the folder.
/// </remarks>
function SaveSnapshot(const pDir: string; pAuto: Boolean; const pQuestion, pTarget, pPlainText: string;
  pWhen: TDateTime; out pPath: string): Boolean;

/// <summary>Keeps the newest snapshots of one routine and deletes the rest (S3b).</summary>
/// <param name="pAutoDir">The auto folder itself.</param>
/// <param name="pQuestion">Question id.</param>
/// <param name="pTarget">Target (sanitised here).</param>
/// <param name="pKeep">How many to keep; default 20.</param>
/// <remarks>Only files named exactly '&lt;question&gt;--&lt;target&gt;--&lt;stamp&gt;.txt'
/// with a digit stamp count, so another target that merely shares the prefix is never
/// touched. Ordered by the stamp in the name, never by file time; oldest removed first.
/// A file that cannot be deleted is skipped.</remarks>
procedure PruneAutoSnapshots(const pAutoDir, pQuestion, pTarget: string; pKeep: Integer = 20);

/// <summary>The newest auto snapshot of one routine.</summary>
/// <param name="pAutoDir">The auto folder itself.</param>
/// <param name="pQuestion">Question id.</param>
/// <param name="pTarget">Target (sanitised here).</param>
/// <returns>Full path of the snapshot with the greatest stamp, or '' when none.</returns>
function LatestAutoSnapshot(const pAutoDir, pQuestion, pTarget: string): string;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Generics.Collections,
  System.Generics.Defaults, DRagLint.Core.Model, DRagLint.Project.OwnRoots;

const
  DEFAULT_DIR = 'drag-lint-reports';
  AUTO_DIR = 'auto';
  PROJECT_JSON = 'drag-lint-project.json';
  KEY_REPORTS_DIR = 'reportsDir';
  PART_SEPARATOR = '--';
  STAMP_FORMAT = 'yyyymmdd-hhnn';
  STAMP_LEN = 13;
  STAMP_DASH = 9;
  FILE_EXT = '.txt';
  REPLACEMENT = '_';

function ReadReportsDirKey(const pJsonPath: string): string;
begin
  Result:= '';
  if not TFile.Exists(pJsonPath) then
    Exit;
  try
    var Val:= TJSONObject.ParseJSONValue(TFile.ReadAllText(pJsonPath));
    try
      if Val is TJSONObject then
      begin
        // PS trap handled: a missing JSON property reads $null there; GetValue is nil here.
        var V:= TJSONObject(Val).GetValue(KEY_REPORTS_DIR);
        if V is TJSONString then
          Result:= V.Value.Trim;
      end;
    finally
      Val.Free;
    end;
  except
    on Exception do Result:= '';
  end;
end;

function ResolveSnapshotDir(const pProjectFile, pDbPath: string): string;
begin
  var Anchor:= AnchorDirForDb(pDbPath);
  if Anchor = '' then
    Anchor:= ExtractFileDir(ExpandFileName(pProjectFile));
  var HomeDir:= TPath.Combine(Anchor, DRAG_HOME_DIR);
  var Key:= ReadReportsDirKey(TPath.Combine(HomeDir, PROJECT_JSON));
  if Key = '' then
    Exit(TPath.Combine(Anchor, DEFAULT_DIR));
  Key:= StringReplace(Key, '/', '\', [rfReplaceAll]);
  Result:= ExcludeTrailingPathDelimiter(
    TPath.GetFullPath(if TPath.IsRelativePath(Key) then TPath.Combine(HomeDir, Key) else Key));
end;

function SanitiseTargetForFileName(const pTarget: string): string;
begin
  var Chars:= pTarget.ToCharArray;
  for var I:= 0 to High(Chars) do
    if not CharInSet(Chars[I], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '-']) then
      Chars[I]:= REPLACEMENT;
  Result:= string.Create(Chars);
end;

function NamePrefix(const pQuestion, pTarget: string): string;
begin
  Result:= SanitiseTargetForFileName(pQuestion) + PART_SEPARATOR
    + SanitiseTargetForFileName(pTarget) + PART_SEPARATOR;
end;

function SnapshotFileName(const pQuestion, pTarget: string; pWhen: TDateTime): string;
begin
  Result:= NamePrefix(pQuestion, pTarget) + FormatDateTime(STAMP_FORMAT, pWhen) + FILE_EXT;
end;

function StampOf(const pFileName, pPrefix: string): string;
begin
  Result:= '';
  if not pFileName.StartsWith(pPrefix, True) or not pFileName.EndsWith(FILE_EXT, True) then
    Exit;
  var Stamp:= Copy(pFileName, Length(pPrefix) + 1, Length(pFileName) - Length(pPrefix) - Length(FILE_EXT));
  if Length(Stamp) <> STAMP_LEN then
    Exit;
  for var I:= 1 to STAMP_LEN do
    if (I = STAMP_DASH) and (Stamp[I] <> '-') then
      Exit
    else if (I <> STAMP_DASH) and not CharInSet(Stamp[I], ['0'..'9']) then
      Exit;
  Result:= Stamp;
end;

{ The routine's snapshots as stamp/path pairs, newest first. }
function StampedFiles(const pAutoDir, pQuestion, pTarget: string): TArray<TPair<string, string>>;
begin
  var List:= TList<TPair<string, string>>.Create;
  try
    if TDirectory.Exists(pAutoDir) then
    begin
      var Prefix:= NamePrefix(pQuestion, pTarget);
      for var Path in TDirectory.GetFiles(pAutoDir, '*' + FILE_EXT) do
      begin
        var Stamp:= StampOf(ExtractFileName(Path), Prefix);
        if Stamp <> '' then
          List.Add(TPair<string, string>.Create(Stamp, Path));
      end;
    end;
    // The stamp is digits and one dash: ordinal order is chronological order.
    List.Sort(TComparer<TPair<string, string>>.Construct(
      function(const pA, pB: TPair<string, string>): Integer
      begin
        Result:= CompareStr(pB.Key, pA.Key);
      end));
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

procedure PruneAutoSnapshots(const pAutoDir, pQuestion, pTarget: string; pKeep: Integer);
begin
  var Files:= StampedFiles(pAutoDir, pQuestion, pTarget);
  for var I:= pKeep to High(Files) do
    DeleteFile(Files[I].Value); // False (locked file) is fine: the next prune retries it
end;

function LatestAutoSnapshot(const pAutoDir, pQuestion, pTarget: string): string;
begin
  var Files:= StampedFiles(pAutoDir, pQuestion, pTarget);
  Result:= if Length(Files) > 0 then Files[0].Value else '';
end;

function SaveSnapshot(const pDir: string; pAuto: Boolean; const pQuestion, pTarget, pPlainText: string;
  pWhen: TDateTime; out pPath: string): Boolean;
const
  AUTO_KEEP = 20;
begin
  pPath:= '';
  Result:= False;
  var Dir:= if pAuto then TPath.Combine(pDir, AUTO_DIR) else pDir;
  try
    ForceDirectories(Dir);
    var Text:= StringReplace(pPlainText, #13#10, #10, [rfReplaceAll]);
    Text:= StringReplace(Text, #13, #10, [rfReplaceAll]);
    Text:= StringReplace(Text, #10, #13#10, [rfReplaceAll]);
    var Path:= TPath.Combine(Dir, SnapshotFileName(pQuestion, pTarget, pWhen));
    var Enc:= TUTF8Encoding.Create(False);
    try
      TFile.WriteAllText(Path, Text, Enc);
    finally
      Enc.Free;
    end;
    pPath:= Path;
    if pAuto then
      PruneAutoSnapshots(Dir, pQuestion, pTarget, AUTO_KEEP);
    Result:= True;
  except
    on Exception do
    begin
      pPath:= '';
      Result:= False;
    end;
  end;
end;

end.
