unit uExtrOwnA;

interface

uses
  uExtrOwnZ;

type
  TExtrUser = class
  private
    FWidget: Widget;
    FThing: TZThing;
  public
    function GetWidget: Widget;
    function GetThing: TZThing;
  end;

implementation

function TExtrUser.GetWidget: Widget;
begin
  Result := FWidget;
end;

function TExtrUser.GetThing: TZThing;
begin
  Result := FThing;
end;

end.