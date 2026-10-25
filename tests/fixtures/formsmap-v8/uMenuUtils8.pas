unit uMenuUtils8;

{ forms-csv v8 fixture: a menu helper in a unit with no other menu code. The
  parent arrives as a PARAMETER, so the external root must be named after the
  caller's identifier (mnuTools), not after pParent. }

interface

uses
  System.Classes
  , Vcl.Menus
  ;

function AddMenuItem(pParent: TMenuItem; const pCaption: string; pClick: TNotifyEvent): TMenuItem;

implementation

function AddMenuItem(pParent: TMenuItem; const pCaption: string; pClick: TNotifyEvent): TMenuItem;
begin
  Result:= TMenuItem.Create(pParent);
  Result.Caption:= pCaption;
  Result.OnClick:= pClick;
  pParent.Add(Result);
end;

end.
