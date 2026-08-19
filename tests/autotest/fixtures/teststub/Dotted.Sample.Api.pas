unit Dotted.Sample.Api;

{ Fixture for run_generate_test_stub_guard.ps1.

  THE UNIT NAME IS THE POINT. It has three dotted segments, so the segment
  before the routine name ("Sample") is a UNIT segment and not a class. The old
  generator took that segment to be the enclosing type and emitted
  `var Subject: Sample; Subject := Sample.Create;`. A single-segment unit name
  would hide the bug completely, which is why this fixture cannot be called
  something like `SampleApi`.

  It carries BOTH shapes deliberately: a free routine (where there is no class
  at all) and a real method (where there is one). A method-only fixture passed
  even before the fix. }

interface

type
  TSampleWorker = class
    public
      function Describe(const AName: string; ACount: Integer): string;
      procedure Reset;
  end;

function AddNumbers(const A, B: Integer): Integer;
procedure LogSomething(const AMessage: string);

implementation

uses
  System.SysUtils
  ;

function TSampleWorker.Describe(const AName: string; ACount: Integer): string;
begin
  Result:= Format('%s x%d', [AName, ACount]);
end;

procedure TSampleWorker.Reset;
begin
end;

function AddNumbers(const A, B: Integer): Integer;
begin
  Result:= A + B;
end;

procedure LogSomething(const AMessage: string);
begin
end;

end.
