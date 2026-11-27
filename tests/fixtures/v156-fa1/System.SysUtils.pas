unit System.SysUtils;

{ Fixture of tests\autotest\run_v156_FA1.ps1 (1.56 lane FA-1): a stand-in for the Delphi 13 RTL
  unit, which declares these routines with the noreturn directive. Index-only. }

interface

type
  Exception = class
  public
    constructor Create(const AText: string);
  end;

procedure Abort; noreturn;
procedure Beep;
procedure RaiseLastOSError; overload; noreturn;
procedure RaiseLastOSError(LastError: Integer); overload; noreturn;

implementation

constructor Exception.Create(const AText: string);
begin
end;

procedure Abort;
begin
  raise Exception.Create('abort');
end;

procedure Beep;
begin
end;

procedure RaiseLastOSError;
begin
  raise Exception.Create('os');
end;

procedure RaiseLastOSError(LastError: Integer);
begin
  raise Exception.Create('os');
end;

end.
