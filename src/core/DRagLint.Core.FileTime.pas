unit DRagLint.Core.FileTime;

/// <summary>One way to read a file's last-write time as the unix epoch the
/// indexer stores, so a reader and the writer cannot drift apart.</summary>
/// <remarks>
/// <para>WHY THIS UNIT EXISTS. The indexer writes mtimes with
/// `DateTimeToUnix(TFile.GetLastWriteTime(P), False)`
/// (DRagLint.Core.Indexer.pas:882). Two readers instead used `FileAge`, which is
/// a DIFFERENT Win32 path, and the RTL says so in its own source
/// (System.SysUtils.FileAgeInternal):</para>
///
/// <para>`// FileAge uses the current TimeZone/time-offset.`
/// `// To use the file's TimeZone, System.IOUtils.TFile.GetLastWriteTime should be used.`</para>
///
/// <para>`FileTimeToLocalFileTime` applies the UTC offset in force NOW;
/// `TFile.GetLastWriteTime` applies the offset in force WHEN THE FILE WAS
/// WRITTEN. So the two agree for every file dated in the current daylight-saving
/// period and disagree by exactly one hour for every file dated in the other
/// one. Measured 2026-09-14: the freshness note claimed 3,258 of 7,001 library
/// files had changed immediately after a complete from-scratch re-parse in which
/// nothing had changed and 100% of the stored stamps were correct.</para>
///
/// <para>WHY THE RAW FILETIME AND NOT A LOCAL TDateTime. A FILETIME is already
/// UTC, so converting it straight to a unix epoch involves no time zone at all
/// and therefore has no DST period to get wrong. That it equals what the writer
/// stores is MEASURED, not argued: across the two library indexes, 16,586 of
/// 16,586 stored stamps equal the floor of the file's true UTC epoch, which is
/// exactly what this computes.</para>
///
/// <para>NON-RAISING BY CONTRACT. A freshness check must not be able to break
/// the command it is advising, so a missing, denied or locked file returns False
/// rather than raising -- the property the callers previously got from FileAge
/// and the reason they chose it over TFile.GetLastWriteTime. The locked-file
/// fallback via FindFirstFile is kept for the same reason the RTL keeps it: a
/// share-exclusive file is common here (the IDE holds units open) and must stay
/// measurable rather than silently counting as absent.</para>
///
/// <para>All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</para>
/// </remarks>

interface

/// <summary>The file's last-write time as seconds since the unix epoch, UTC.</summary>
/// <param name="APath">Full path to a file. A directory is not a file and
/// returns False, matching FileAge.</param>
/// <param name="AMTimeUnix">Set to the epoch on success; 0 otherwise.</param>
/// <returns>False when the path does not exist, is a directory, or cannot be
/// read at all. Never raises.</returns>
/// <remarks>
/// Truncates sub-second precision downwards, which is what
/// `SecondsBetween` does on the writer's side and what the stored stamps show.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Analysis.LintTree.CollectUnchecked (DRagLint.Analysis.LintTree.pas), DRagLint.Analysis.PurityStage.TPurityRun.ScanFiles (DRagLint.Analysis.PurityStage.pas), DRagLint.Core.FileTime.FileMTimeUnix (DRagLint.Core.FileTime.pas), DRagLint.Index.Freshness.StampState (DRagLint.Index.Freshness.pas)</para>
/// <para>Calls: DRagLint.Core.FileTime.FileTimeToUnix, FindFirstFile, GetFileAttributesEx, PChar</para>
/// <para>Returns: False; True</para>
/// <para>Mutates: AMTimeUnix (out)</para>
/// <seealso cref="DRagLint.Core.FileTime.FileTimeToUnix"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function TryGetFileMTimeUnix(const APath: string; out AMTimeUnix: Int64): Boolean;

/// <summary>The real UTC clock as a TDateTime, read straight from the OS.</summary>
/// <returns>UTC now. Never consults a time zone, so it has no daylight-saving day to get wrong.</returns>
/// <remarks>
/// WHY NOT `TTimeZone.Local.ToUniversalTime(Now)` / `DateTimeToUnix(Now, False)`: on a transition day
/// (2026-11-01 here) the RTL converted a plain afternoon `Now` one hour off for the WHOLE day, so
/// every stamp written by the indexer and every `Z` log line was +1 h (lane 140-cli DST;
/// pinned by tests\autotest\run_index_utc_stamps.ps1). Thread-safe.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Charts.Ask.AskChartQuestion (DRagLint.Charts.Ask.pas), DRagLint.Core.UsageLog.RecordUsage (DRagLint.Core.UsageLog.pas), DRagLint.Project.ContextFile.SaveProjectContext (DRagLint.Project.ContextFile.pas)</para>
/// <para>Calls: GetSystemTime, SystemTimeToDateTime</para>
/// <para>Returns: SystemTimeToDateTime(ST)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function NowUtc: TDateTime;

/// <summary>The wall clock in the machine's local time zone, for log lines a person reads.</summary>
/// <returns>Local date and time, derived from the real UTC instant converted with the zone offset in force
/// AT THAT INSTANT (SystemTimeToTzSpecificLocalTime).</returns>
/// <remarks>
/// Replaces the RTL's Now for stamps: on a daylight-saving transition day (2026-11-01 here) the
/// RTL's Now printed started HH:MM one hour ahead of the real clock for the whole day (1.41 DST-LOGSTAMP;
/// pinned by tests\autotest\run_cli141_followups.ps1). Thread-safe.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoConvertApply.PerformApplyWrites (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.Run (DRagLint.CLI.pas) (+1 more)</para>
/// <para>Calls: GetSystemTime, SystemTimeToDateTime, SystemTimeToTzSpecificLocalTime</para>
/// <para>Returns: if SystemTimeToTzSpecificLocalTime(nil, UtcST, LocalST) then SystemTimeToDateTime(LocalST)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function NowLocal: TDateTime;

/// <summary>The real UTC clock as unix epoch seconds (what files.parsed_at stores).</summary>
/// <returns>Whole seconds since 1970-01-01 UTC. Same source as NowUtc.</returns>
/// <remarks>
/// Thread-safe.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CommitIndexerFingerprint (DRagLint.CLI.pas), DRagLint.CLI.DoImportLog (DRagLint.CLI.pas), DRagLint.CLI.FinishLibraryResolve (DRagLint.CLI.pas), DRagLint.CLI.OpenInObsidian (DRagLint.CLI.pas), DRagLint.CLI.RefreshProjectFindingsCore (DRagLint.CLI.pas) (+3 more)</para>
/// <para>Calls: DRagLint.Core.FileTime.FileTimeToUnix, GetSystemTimeAsFileTime</para>
/// <para>Returns: FileTimeToUnix(Stamp)</para>
/// <seealso cref="DRagLint.Core.FileTime.FileTimeToUnix"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function NowUnixUtc: Int64;

/// <summary>A file's last-write time as unix epoch seconds, UTC, raising like TFile.</summary>
/// <param name="APath">Full path to an existing file.</param>
/// <returns>Floor of the file's true UTC epoch -- the value TryGetFileMTimeUnix reports.</returns>
/// <exception cref="EFileNotFoundException">Raised when the path is missing, a directory, or unreadable.</exception>
/// <remarks>
/// Replaces `DateTimeToUnix(TFile.GetLastWriteTime(P), False)`: that round-trips through a LOCAL
/// TDateTime, which is ambiguous for the repeated hour at DST end (stored +3600 s). This reads the
/// UTC FILETIME and never touches a time zone.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.FileStampIsCurrent (DRagLint.CLI.CycleFix.pas), DRagLint.Convert.Apply.FileStampIsCurrent (DRagLint.Convert.Apply.pas), DRagLint.Core.Indexer.TIndexer.IndexFileBody (DRagLint.Core.Indexer.pas), DRagLint.Index.CallResolver.TCallResolver.LinesOf (DRagLint.Index.CallResolver.pas), DRagLint.Index.DispatchResolver.TDispatchResolver.LinesOf (DRagLint.Index.DispatchResolver.pas) (+6 more)</para>
/// <para>Calls: DRagLint.Core.FileTime.TryGetFileMTimeUnix</para>
/// <seealso cref="DRagLint.Core.FileTime.TryGetFileMTimeUnix"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FileMTimeUnix(const APath: string): Int64;
implementation

uses
  Winapi.Windows, System.SysUtils;

const
  { 100-ns intervals between 1601-01-01 (the FILETIME epoch) and 1970-01-01. }
  FILETIME_UNIX_DELTA = Int64(116444736000000000);
  FILETIME_PER_SECOND = Int64(10000000);
  { A FILETIME is a 64-bit count split across two DWORDs; this is the width of
    the low half, i.e. how far the high half has to move to sit above it. }
  DWORD_BITS          = 32;

function FileTimeToUnix(const AFileTime: TFileTime): Int64;
var
  Q: Int64;
begin
  Q := (Int64(AFileTime.dwHighDateTime) shl DWORD_BITS) or Int64(AFileTime.dwLowDateTime);
  Result := (Q - FILETIME_UNIX_DELTA) div FILETIME_PER_SECOND;
end;

function TryGetFileMTimeUnix(const APath: string; out AMTimeUnix: Int64): Boolean;
var
  Attr    : TWin32FileAttributeData;
  FindData: TWin32FindData          ;
  Handle  : THandle                 ;
  Got     : Boolean                 ;
  Written : TFileTime               ;
begin
  AMTimeUnix := 0;
  Result     := False;

  Got := GetFileAttributesEx(PChar(APath), GetFileExInfoStandard, @Attr);
  if Got then
    Written := Attr.ftLastWriteTime
  else
  begin
    { Locked or share-exclusive: GetFileAttributesEx refuses where FindFirstFile
      still answers. The RTL's FileAge does the same dance, and dropping it here
      would quietly reclassify every file the IDE holds open as absent. }
    Handle := FindFirstFile(PChar(APath), FindData);
    if Handle = INVALID_HANDLE_VALUE then Exit;
    Winapi.Windows.FindClose(Handle);
    Attr.dwFileAttributes := FindData.dwFileAttributes;
    Written               := FindData.ftLastWriteTime;
  end;

  if (Attr.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then Exit;

  AMTimeUnix := FileTimeToUnix(Written);
  Result     := True;
end;

function NowUtc: TDateTime;
var
  ST: TSystemTime;
begin
  GetSystemTime(ST);
  Result:= SystemTimeToDateTime(ST);
end;

function NowLocal: TDateTime;
var
  UtcST  : TSystemTime;
  LocalST: TSystemTime;
begin
  GetSystemTime(UtcST);
  Result:= if SystemTimeToTzSpecificLocalTime(nil, UtcST, LocalST) then SystemTimeToDateTime(LocalST)
    else Now; { no zone data: the RTL clock is all there is }
end;

function NowUnixUtc: Int64;
var
  Stamp: TFileTime;
begin
  GetSystemTimeAsFileTime(Stamp);
  Result:= FileTimeToUnix(Stamp);
end;

function FileMTimeUnix(const APath: string): Int64;
begin
  { Raw FILETIME, NOT TFile.GetLastWriteTimeUtc: that one is measured to round-trip through the LOCAL
    zone too, so it collapses the repeated DST hour exactly like the call it replaces. }
  if not TryGetFileMTimeUnix(APath, Result) then
    raise EFileNotFoundException.CreateFmt('Cannot read the last-write time of %s', [APath]);
end;
end.
