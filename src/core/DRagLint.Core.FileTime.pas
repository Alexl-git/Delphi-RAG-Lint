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
/// <remarks>Truncates sub-second precision downwards, which is what
/// `SecondsBetween` does on the writer's side and what the stored stamps show.</remarks>
function TryGetFileMTimeUnix(const APath: string; out AMTimeUnix: Int64): Boolean;

implementation

uses
  Winapi.Windows;

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

end.
