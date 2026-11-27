unit USvc;

interface

uses
  Vcl.SvcMgr, UFoo;

type
  TMySvc = class(TService)
  private
    FFoo: TFoo;
  public
    procedure DoStart;
    procedure DoQuiet;
    procedure DoLoop;
  end;

implementation

procedure TMySvc.DoStart;
begin
  FFoo.Greet;
  FFoo.Wrap;
end;

procedure TMySvc.DoQuiet;
begin
  FFoo.Quiet;
end;

procedure TMySvc.DoLoop;
begin
  FFoo.Loop1;
end;

end.
