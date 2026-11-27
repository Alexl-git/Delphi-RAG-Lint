unit System.SysUtils;

{ Fixture of tests\autotest\run_v156_EXTA1_facts.ps1 (1.56 lane EXT-A1): a stand-in for the RTL
  unit, so the library-DB fact of B1 (NORETURN_KNOWN, matched by unit-qualified name) has a
  declaration to land on. Index-only. }

interface

type
  TAborter = class
  public
    procedure Abort;
  end;

procedure Abort;
procedure Beep;
procedure RaiseLastOSError; overload;
procedure RaiseLastOSError(LastError: Integer); overload;

implementation

procedure Abort;
begin
end;

procedure Beep;
begin
end;

procedure RaiseLastOSError;
begin
end;

procedure RaiseLastOSError(LastError: Integer);
begin
end;

procedure TAborter.Abort;
begin
end;

end.
