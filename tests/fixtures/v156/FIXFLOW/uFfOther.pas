unit uFfOther;

{ Fixture of tests\autotest\run_v156_FIXFLOW.ps1 (1.56 lane FIX-FLOW): the noreturn callee lives
  in ANOTHER unit than its caller, directive on the interface declaration only. }

interface

procedure Fail(const AText: string); noreturn;

implementation

uses
  System.SysUtils;

procedure Fail(const AText: string);
begin
  raise Exception.Create(AText);
end;

end.
