unit uFa1Other;

{ Fixture of tests\autotest\run_v156_FA1.ps1 (1.56 lane FA-1): the callees of uFa1.pas. The
  noreturn directive stands on the interface declaration only, so a unit that calls these
  routines cannot see it in its own source: it is the index that knows. }

interface

type
  TStopper = class
  public
    procedure Stop(const AWhy: string); noreturn;
    procedure Go;
  end;

procedure OtherFail(const AText: string); noreturn;
procedure OtherPlain;

implementation

uses
  System.SysUtils;

procedure TStopper.Stop(const AWhy: string);
begin
  raise Exception.Create(AWhy);
end;

procedure TStopper.Go;
begin
end;

procedure OtherFail(const AText: string);
begin
  raise Exception.Create(AText);
end;

procedure OtherPlain;
begin
end;

end.
