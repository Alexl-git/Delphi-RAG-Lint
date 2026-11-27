unit AppMain;

{ Fixture: first-party (under the project folder). FixRtl is a bare name the unit scope System completes;
  NoSrcLib and cxFixSourceless have no source anywhere. }

interface

uses
  FixRtl, AcmeGrid, SharedUnit, VendUnit;

procedure RunApp;

implementation

uses
  NoSrcLib, cxFixSourceless;

procedure RunApp;
begin
end;

end.
