unit A_User;

{ Fixture for run_returns_owner_order.ps1 (151 X2R, 152b DF/O7). A_User sorts
  BEFORE Z_Kinds, so on a fresh `index <dir>` this unit's facts pass runs while
  Widget / TZThing / HWND / DWORD are not yet in the store. Do not rename
  either unit. }

interface

uses
  Z_Kinds;

type
  Local = class
  public
    N: Integer;
  end;

  TUser = class
  private
    FWidget: Widget;
    FThing : TZThing;
    FLocal : Local;
    FHandle: HWND;
    FFlags : DWORD;
  public
    function GetWidget: Widget;
    function GetThing: TZThing;
    function GetLocal: Local;
    function GetHandle: HWND;
    function GetFlags: DWORD;
  end;

implementation

function TUser.GetWidget: Widget;
begin
  Result:= FWidget;
end;

function TUser.GetThing: TZThing;
begin
  Result:= FThing;
end;

function TUser.GetLocal: Local;
begin
  Result:= FLocal;
end;

function TUser.GetHandle: HWND;
begin
  Result:= FHandle;
end;

function TUser.GetFlags: DWORD;
begin
  Result:= FFlags;
end;

end.