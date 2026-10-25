unit transitive_osraise;

{ Fixture for run_doc_exception_transitive.ps1 -- the known OS-error raiser
  table (owner ruling D2 "a-narrow", 2026-10-25; INBOX-yadf-fp-options item 2).

  RaiseLastOSError, RaiseLastWin32Error, Win32Check and CheckOSError live in
  System.SysUtils. In a project DB the call is UNRESOLVED (no call_edges row)
  and the RTL body is never mined, so before the table the <exception
  cref="EOSError"> on a routine that calls one was reported as drift, and
  `document` never wrote it.

  Kept in its OWN unit, not in transitive.pas: run_doc_exception_transitive_writer
  reads transitive.pas as its human-written fixture, and a new declaration there
  would move its answers. }

interface

uses
  Winapi.Windows, System.SysUtils;

type
  /// <summary>CONTROL-8 host: a member that merely shares the name Win32Check.</summary>
  TShadow = class
  public
    /// <summary>Raises nothing; shares a known raiser's name.</summary>
    /// <param name="AOk">Ignored.</param>
    procedure Win32Check(AOk: Boolean);
    /// <summary>CONTROL-8: the call RESOLVES to TShadow.Win32Check, which raises
    /// nothing, so the table must not apply and the cref keeps reporting.</summary>
    /// <exception cref="EOSError">Nothing here raises it.</exception>
    procedure Run;
  end;

/// <summary>RED-E: a bare RaiseLastOSError after a failed API call.</summary>
/// <param name="AOk">Result of the API call.</param>
/// <exception cref="EOSError">Raised by RaiseLastOSError when AOk is False.</exception>
procedure OsBare(AOk: Boolean);

/// <summary>RED-F: the unit-qualified spelling.</summary>
/// <exception cref="EOSError">Raised by System.SysUtils.RaiseLastOSError.</exception>
procedure OsQualified;

/// <summary>RED-G: Win32Check raises only when its argument is False.</summary>
/// <param name="AOk">Result of the API call.</param>
/// <exception cref="EOSError">Raised by Win32Check when AOk is False.</exception>
procedure OsWin32(AOk: BOOL);

/// <summary>RED-H: CheckOSError and the deprecated RaiseLastWin32Error.</summary>
/// <param name="ACode">An OS error code.</param>
/// <exception cref="EOSError">Raised by CheckOSError when ACode is non-zero.</exception>
procedure OsCheck(ACode: Integer);

/// <summary>CONTROL-6: no raiser is called; the cref must keep reporting.</summary>
/// <param name="AValue">Value to render.</param>
/// <returns>AValue as text.</returns>
/// <exception cref="EOSError">Nothing here raises it.</exception>
function OsNone(AValue: Integer): string;

/// <summary>CONTROL-7: Abort is NOT in the table (ruling D2 a-narrow); the
/// cref must keep reporting.</summary>
/// <exception cref="EAbort">Abort raises it, but the table does not say so.</exception>
procedure AbortCref;

/// <summary>WRITER-1: `document` must add the EOSError cref.</summary>
/// <param name="AOk">Result of the API call.</param>
procedure OsWriter(AOk: BOOL);

/// <summary>WRITER-C1: `document` must NOT add an EAbort cref.</summary>
procedure AbortWriter;

implementation

procedure TShadow.Win32Check(AOk: Boolean);
begin
  if AOk then Exit;
end;

procedure TShadow.Run;
begin
  Win32Check(False);
end;

procedure OsBare(AOk: Boolean);
begin
  if not AOk then
    RaiseLastOSError;
end;

procedure OsQualified;
begin
  System.SysUtils.RaiseLastOSError;
end;

procedure OsWin32(AOk: BOOL);
begin
  Win32Check(AOk);
end;

procedure OsCheck(ACode: Integer);
begin
  CheckOSError(ACode);
  if ACode < 0 then
    RaiseLastWin32Error;
end;

function OsNone(AValue: Integer): string;
begin
  Result:= IntToStr(AValue);
end;

procedure AbortCref;
begin
  Abort;
end;

procedure OsWriter(AOk: BOOL);
begin
  Win32Check(AOk);
end;

procedure AbortWriter;
begin
  Abort;
end;

end.
