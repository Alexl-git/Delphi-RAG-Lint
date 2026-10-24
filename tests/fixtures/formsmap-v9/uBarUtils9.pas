unit uBarUtils9;

{ dxBar fixture: a bar helper in a unit with no other bar code. The popup
  arrives as a PARAMETER, so the code link must be named after the caller's
  identifier (popGrid), not after pPopup. }

interface

uses
  System.Classes
  , dxBar
  ;

function AddBarButton(pPopup: TdxBarPopupMenu; const pCaption: string; pClick: TNotifyEvent): TdxBarButton;

implementation

function AddBarButton(pPopup: TdxBarPopupMenu; const pCaption: string; pClick: TNotifyEvent): TdxBarButton;
begin
  Result:= TdxBarButton.Create(pPopup.Owner);
  Result.Caption:= pCaption;
  Result.OnClick:= pClick;
  pPopup.ItemLinks.Add.Item:= Result;
end;

end.
