unit uFpprQual;
interface
uses
  Spring.Container.Common;
type
  TQualSvc = class
  public
    [Spring.Container.Common.Inject]
    constructor Create;
  end;
implementation
constructor TQualSvc.Create;
begin
  inherited Create;
end;
end.
