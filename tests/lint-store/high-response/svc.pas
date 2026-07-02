unit svc;

interface

type
  TService = class
  public
    procedure DoWork;
    procedure DoMore;
  end;

implementation

uses
  System.SysUtils;

procedure TService.DoWork;
begin
  Alpha;
  Beta;
  Gamma;
end;

procedure TService.DoMore;
begin
  Delta;
  Epsilon;
end;

procedure Alpha; begin end;
procedure Beta; begin end;
procedure Gamma; begin end;
procedure Delta; begin end;
procedure Epsilon; begin end;

end.
