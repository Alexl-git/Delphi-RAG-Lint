unit DragLint.Plugin.BookmarksCore;

/// <summary>The pure half of drag-lint > Bookmarks (E-BOOKMARKS, IDE half): the command
/// lines of the bookmarks / bookmarks-strip / bookmarks-restore verbs, the readers of their
/// --json answers, and the per-user sidecar path.</summary>
/// <remarks>No ToolsAPI and no VCL, so tests\BookmarksCoreTests.dpr links it headless.
/// Verb contract: lane 147 G2 (features\entries\bookmarks.json and the bookmarks-strip /
/// bookmarks-restore entries). Every writing verb is a dry run without --apply; the IDE
/// half always runs the dry run first and asks before the --apply.</remarks>

interface

type
  /// <summary>One `dl:bk` anchor as `bookmarks --json` reports it.</summary>
  TBookmarkRow = record
    /// <summary>Absolute path of the unit.</summary>
    FilePath: string;
    /// <summary>1-based line of the anchor.</summary>
    Line    : Integer;
    /// <summary>'user' (`dl:bk3`) or 'dl' (`dl:bk:CODE -- reason`).</summary>
    Kind    : string;
    /// <summary>The number of a user mark, the CODE of a tagged one.</summary>
    Code    : string;
    /// <summary>A tagged mark's reason; '' for a user mark.</summary>
    Reason  : string;
  end;

  /// <summary>The counts a bookmarks-strip or bookmarks-restore --json object carries.</summary>
  TBookmarkVerbCounts = record
    /// <summary>strip: anchors found (stripped, or would be).</summary>
    Count   : Integer;
    /// <summary>restore: anchors restored (or would be).</summary>
    Restored: Integer;
    /// <summary>restore: anchors already in place.</summary>
    Already : Integer;
    /// <summary>restore: anchors that could not be re-placed; their files are left untouched.</summary>
    Unplaced: Integer;
    /// <summary>The distinct files the answer's bookmarks[] names.</summary>
    Files   : TArray<string>;
  end;

/// <summary>`bookmarks --in <unit> [--name <code>] --json` (read-only).</summary>
/// <param name="AExe">drag-lint.exe.</param>
/// <param name="AIn">The unit (or folder) to list.</param>
/// <param name="ACode">'' lists every anchor; else only the one with this number / CODE.</param>
/// <returns>The full command line.</returns>
function BookmarksListCmdLine(const AExe, AIn, ACode: string): string;

/// <summary>`bookmarks-strip --in <unit> --output <sidecar> [--apply] --json`.</summary>
/// <param name="AExe">drag-lint.exe.</param>
/// <param name="AIn">The unit to strip.</param>
/// <param name="ASidecar">The sidecar to write; the verb never overwrites an existing one.</param>
/// <param name="AApply">False = dry run (writes nothing).</param>
/// <returns>The full command line.</returns>
function BookmarksStripCmdLine(const AExe, AIn, ASidecar: string; AApply: Boolean): string;

/// <summary>`bookmarks-restore --from <sidecar> [--apply] --json`.</summary>
/// <param name="AExe">drag-lint.exe.</param>
/// <param name="ASidecar">A sidecar bookmarks-strip wrote.</param>
/// <param name="AApply">False = dry run (writes nothing).</param>
/// <returns>The full command line.</returns>
function BookmarksRestoreCmdLine(const AExe, ASidecar: string; AApply: Boolean): string;

/// <summary>Reads the JSON array `bookmarks --json` prints.</summary>
/// <param name="AOutput">stdout and stderr interleaved; text before the first '[' is ignored.</param>
/// <param name="ARows">Receives the rows; empty on False.</param>
/// <returns>False when no array could be read (an error text, not JSON).</returns>
/// <remarks>Pure; never raises.</remarks>
function ParseBookmarkRows(const AOutput: string; out ARows: TArray<TBookmarkRow>): Boolean;

/// <summary>Reads the JSON object bookmarks-strip / bookmarks-restore print.</summary>
/// <param name="AOutput">stdout and stderr interleaved; text before the first '{' is ignored.</param>
/// <param name="ACounts">Receives the counts; all 0 on False.</param>
/// <returns>False when no object could be read.</returns>
/// <remarks>Pure; never raises.</remarks>
function ParseBookmarkVerbCounts(const AOutput: string; out ACounts: TBookmarkVerbCounts): Boolean;

/// <summary>Where the IDE writes a unit's strip sidecar.</summary>
/// <param name="ALocalAppData">%LOCALAPPDATA%.</param>
/// <param name="APas">The unit being stripped.</param>
/// <param name="ANow">The time stamp in the name, so a second strip never meets the
/// verb's refuse-to-overwrite.</param>
/// <returns>`<ALocalAppData>\drag-lint\bookmarks\<unit name>-yyyymmdd-hhnnss.json`.</returns>
/// <remarks>Per user and outside the repo: a sidecar holds the personal marks a
/// strip took out of a file (DECISION-2026-10-28-comment-anchors), so it is never
/// committed.</remarks>
function BookmarkSidecarPath(const ALocalAppData, APas: string; ANow: TDateTime): string;

/// <summary>The folder BookmarkSidecarPath writes into.</summary>
/// <param name="ALocalAppData">%LOCALAPPDATA%.</param>
/// <returns>`<ALocalAppData>\drag-lint\bookmarks`.</returns>
function BookmarkSidecarFolder(const ALocalAppData: string): string;

/// <summary>One line of the IDE's pick list for a row.</summary>
/// <param name="ARow">The anchor.</param>
/// <returns>`bk3  line 12` for a user mark, `bk:CODE  line 12  -- reason` for a tagged one.</returns>
function BookmarkRowText(const ARow: TBookmarkRow): string;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , System.JSON
  ;

const
  KIND_TAGGED = 'dl';
  SIDECAR_SUBDIR = 'drag-lint\bookmarks';
  SIDECAR_STAMP = 'yyyymmdd-hhnnss';
  SIDECAR_EXT = '.json';

function BookmarksListCmdLine(const AExe, AIn, ACode: string): string;
begin
  Result:= Format('"%s" bookmarks --in "%s"', [AExe, AIn]);
  if ACode <> '' then Result:= Result + Format(' --name "%s"', [ACode]);
  Result:= Result + ' --json';
end;

function BookmarksStripCmdLine(const AExe, AIn, ASidecar: string; AApply: Boolean): string;
begin
  Result:= Format('"%s" bookmarks-strip --in "%s" --output "%s"', [AExe, AIn, ASidecar]);
  if AApply then Result:= Result + ' --apply';
  Result:= Result + ' --json';
end;

function BookmarksRestoreCmdLine(const AExe, ASidecar: string; AApply: Boolean): string;
begin
  Result:= Format('"%s" bookmarks-restore --from "%s"', [AExe, ASidecar]);
  if AApply then Result:= Result + ' --apply';
  Result:= Result + ' --json';
end;

{ The JSON value from the first AOpen to the last AClose; nil when there is none or it does
  not parse. Both ends are cut because the merged pipe can put a stderr line on either side. }
function JsonFrom(const AOutput: string; AOpen, AClose: Char): TJSONValue;
var
  Start : Integer;
  Finish: Integer;
begin
  Result:= nil;
  Start := Pos(AOpen, AOutput);
  Finish:= AOutput.LastIndexOf(AClose) + 1; { 1-based; 0 when absent }
  if (Start = 0) or (Finish < Start) then Exit;
  try
    Result:= TJSONObject.ParseJSONValue(Copy(AOutput, Start, Finish - Start + 1)); { nil on malformed text }
  except
    on E: EJSONException do Result:= nil;
  end;
end;

function ParseBookmarkRows(const AOutput: string; out ARows: TArray<TBookmarkRow>): Boolean;
var
  V  : TJSONValue;
  Row: TBookmarkRow;
begin
  SetLength(ARows, 0);
  V:= JsonFrom(AOutput, '[', ']');
  Result:= V is TJSONArray;
  try
    if not Result then Exit;
    for var E in TJSONArray(V) do
    begin
      if E is not TJSONObject then Continue;
      Row:= Default(TBookmarkRow);
      Row.FilePath:= TJSONObject(E).GetValue<string>('file', '');
      Row.Line    := TJSONObject(E).GetValue<Integer>('line', 0);
      Row.Kind    := TJSONObject(E).GetValue<string>('kind', '');
      Row.Code    := TJSONObject(E).GetValue<string>('code', '');
      Row.Reason  := TJSONObject(E).GetValue<string>('reason', '');
      ARows:= ARows + [Row];
    end;
  finally
    V.Free;
  end;
end;

function ParseBookmarkVerbCounts(const AOutput: string; out ACounts: TBookmarkVerbCounts): Boolean;
var
  V  : TJSONValue;
  Arr: TJSONArray;
begin
  ACounts:= Default(TBookmarkVerbCounts);
  V:= JsonFrom(AOutput, '{', '}');
  Result:= V is TJSONObject;
  try
    if not Result then Exit;
    ACounts.Count   := TJSONObject(V).GetValue<Integer>('count', 0);
    ACounts.Restored:= TJSONObject(V).GetValue<Integer>('restored', 0);
    ACounts.Already := TJSONObject(V).GetValue<Integer>('already', 0);
    ACounts.Unplaced:= TJSONObject(V).GetValue<Integer>('unplaced', 0);
    if TJSONObject(V).TryGetValue<TJSONArray>('bookmarks', Arr) then
      for var E in Arr do
        if E is TJSONObject then
        begin
          var F: string:= TJSONObject(E).GetValue<string>('file', '');
          var Seen: Boolean:= False;
          for var Known in ACounts.Files do
            if SameText(Known, F) then Seen:= True;
          if (F <> '') and not Seen then ACounts.Files:= ACounts.Files + [F];
        end;
  finally
    V.Free;
  end;
end;

function BookmarkSidecarFolder(const ALocalAppData: string): string;
begin
  Result:= TPath.Combine(ALocalAppData, SIDECAR_SUBDIR);
end;

function BookmarkSidecarPath(const ALocalAppData, APas: string; ANow: TDateTime): string;
begin
  Result:= TPath.Combine(BookmarkSidecarFolder(ALocalAppData),
             ChangeFileExt(ExtractFileName(APas), '') + '-' + FormatDateTime(SIDECAR_STAMP, ANow) + SIDECAR_EXT);
end;

function BookmarkRowText(const ARow: TBookmarkRow): string;
begin
  if SameText(ARow.Kind, KIND_TAGGED) then
    Result:= Format('bk:%s  line %d', [ARow.Code, ARow.Line])
  else
    Result:= Format('bk%s  line %d', [ARow.Code, ARow.Line]);
  if ARow.Reason <> '' then Result:= Result + '  -- ' + ARow.Reason;
end;

end.
