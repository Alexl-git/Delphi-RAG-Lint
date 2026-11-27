unit uFpprShort;
interface
uses
  Spring.Container.Common;
type
  TShortSvc = class
  public
    [Inject]
    constructor Create;
  end;
implementation
constructor TShortSvc.Create;
begin
  inherited Create;
end;
end.
