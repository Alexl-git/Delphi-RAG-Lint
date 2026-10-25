unit Alpha;

interface

uses
  System.SysUtils,
  Beta;

type
  /// <summary>A3-a fixture: its interface names nothing of Beta; only the implementation does.</summary>
  TAlpha = class
  public
    function Run: Integer;
  end;
{INTF-EXTRA}
implementation

function TAlpha.Run: Integer;
begin
  Result := {IMPL-USE};
end;

end.