unit DragLint.Plugin.OpenSourcePath;

{ What the open-in-IDE pipe may open.

  Anything that reaches \\.\pipe\drag-lint-open-source -- the graph viewer, the
  draglint:// browser handler, or any other local process -- names a file the
  IDE will open. Before 2026-09-29 DoOpenInIDE called FileExists on that name
  and opened whatever existed: a UNC path made the IDE process authenticate to
  the named server (an NTLM hash leak), and project/package files (.dproj,
  .dpk, .bpl) opened as readily as a unit.

  This unit is the gate, kept free of ToolsAPI so a console test can drive it
  (tests\fixtures\T66_open_source_path.dpr). Its rules mirror the browser-side
  handler, charts\src\Open-DragLintUri.ps1; the one deliberate difference is
  that .dpr is allowed here (owner ruling 2026-09-29: it loads the project into
  the IDE, and nothing builds). }

interface

/// <summary>True when APath is a file the open-in-IDE pipe may open: an
/// absolute local drive path to a Delphi source file.</summary>
/// <param name="APath">The path exactly as it arrived on the pipe.</param>
/// <param name="AReason">On False, a short reason for the refusal; '' on True.</param>
/// <returns>True only for an X:\ path with an allow-listed extension (.pas
/// .dfm .dpr .inc .sql .fmx) and none of the refused shapes.</returns>
/// <remarks>Pure and thread-safe; it never touches the file system, so it can
/// run BEFORE FileExists -- which is the point: FileExists on a UNC path is
/// already the network access this gate exists to prevent. Refused: control
/// characters, UNC and device namespaces (\\server, \\?\, \\.\), relative and
/// drive-relative paths, a ':' after the drive (NTFS streams), wildcards and
/// the other characters Windows forbids in a name, a segment ending in a dot
/// or a space, and reserved device names (CON, NUL, COM1-9, LPT1-9, the
/// superscript COM/LPT digits, CONIN$, CONOUT$) as a segment's base name. A
/// mapped drive letter can still be a network share the user has mapped; a
/// path cannot name a NEW server.</remarks>
function IsOpenableSourcePath(const APath: string; out AReason: string): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  ALLOWED_EXTS: array[0..5] of string = ('.pas', '.dfm', '.dpr', '.inc', '.sql', '.fmx');
  { Longer than any real source path; a cap keeps a hostile message cheap. }
  MAX_OPEN_PATH    = 1024;
  { 'X:\' -- drive letter, colon, backslash. }
  DRIVE_PREFIX_LEN = 3;
  { COM1..COM9 / LPT1..LPT9: three letters and one digit. }
  NUMBERED_DEVICE_LEN = 4;
  { Everything below a space, and DEL, is a control character. }
  FIRST_PRINTABLE  = #32;
  DEL_CHAR         = #127;
  { Windows also reserves COM/LPT with a superscript 1, 2 or 3; written as
    char codes to keep this unit 7-bit ASCII. }
  SUPERSCRIPT_DIGITS: array[0..2] of Char = (#$00B9, #$00B2, #$00B3);
  FORBIDDEN_AFTER_DRIVE: TSysCharSet = [':', '*', '?', '"', '<', '>', '|', '/'];

{ True when ABase (a segment's name with its extension removed) is a Windows
  reserved device name. }
function IsReservedDeviceName(const ABase: string): Boolean;
var
  U    : string;
  Digit: Char  ;
begin
  U:= UpperCase(ABase);
  Result:= MatchStr(U, ['CON', 'PRN', 'AUX', 'NUL', 'CONIN$', 'CONOUT$']);
  if Result or (Length(U) <> NUMBERED_DEVICE_LEN) then Exit;
  if not MatchStr(Copy(U, 1, NUMBERED_DEVICE_LEN - 1), ['COM', 'LPT']) then Exit;
  Digit:= U[NUMBERED_DEVICE_LEN];
  Result:= CharInSet(Digit, ['1'..'9'])
        or (Digit = SUPERSCRIPT_DIGITS[0])
        or (Digit = SUPERSCRIPT_DIGITS[1])
        or (Digit = SUPERSCRIPT_DIGITS[2]);
end;

{ Each Check* returns '' when the path passes, else the refusal reason. }

function CheckLengthAndChars(const APath: string): string;
var
  C: Char;
begin
  Result:= '';
  if APath = '' then Exit('empty path');
  if Length(APath) > MAX_OPEN_PATH then Exit('path too long');
  for C in APath do
    if (C < FIRST_PRINTABLE) or (C = DEL_CHAR) then Exit('control character');
end;

{ X:\ and nothing else rules out \\server, \\?\, \\.\, //server, relative and
  drive-relative (C:foo) paths in one test; then no ':' (streams), wildcard or
  other name-forbidden character may follow the drive. }
function CheckDrive(const APath: string): string;
var
  I: Integer;
begin
  Result:= '';
  if not ((Length(APath) >= DRIVE_PREFIX_LEN)
          and CharInSet(APath[1], ['A'..'Z', 'a'..'z'])
          and (APath[2] = ':')
          and (APath[DRIVE_PREFIX_LEN] = '\')) then
    Exit('not a local drive path (X:\...)');
  for I:= DRIVE_PREFIX_LEN to Length(APath) do
    if CharInSet(APath[I], FORBIDDEN_AFTER_DRIVE) then
      Exit(Format('character "%s" not allowed after the drive', [APath[I]]));
end;

function CheckExtension(const APath: string): string;
begin
  Result:= '';
  if not MatchText(ExtractFileExt(APath), ALLOWED_EXTS) then
    Result:= Format('extension "%s" is not a source file', [ExtractFileExt(APath)]);
end;

function CheckSegments(const APath: string): string;
var
  Seg: string;
begin
  Result:= '';
  for Seg in Copy(APath, DRIVE_PREFIX_LEN + 1, MaxInt).Split(['\']) do
  begin
    if Seg = '' then Exit('empty path segment');
    if CharInSet(Seg[Length(Seg)], ['.', ' ']) then Exit('a path segment ends in a dot or a space');
    if IsReservedDeviceName(ChangeFileExt(Seg, '')) then
      Exit(Format('reserved device name "%s"', [ChangeFileExt(Seg, '')]));
  end;
end;

function IsOpenableSourcePath(const APath: string; out AReason: string): Boolean;
begin
  AReason:= CheckLengthAndChars(APath);
  if AReason = '' then AReason:= CheckDrive(APath);
  if AReason = '' then AReason:= CheckExtension(APath);
  if AReason = '' then AReason:= CheckSegments(APath);
  Result:= AReason = '';
end;

end.
