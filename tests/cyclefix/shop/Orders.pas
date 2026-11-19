unit Orders;

interface

procedure TakeOrders;

implementation

uses
  System.SysUtils, AppMain;

procedure TakeOrders;
begin
  Inc(AppMainForm.OrderCount, 3);
  AppMainForm.Note('orders taken: ' + IntToStr(AppMainForm.OrderCount));
end;

end.
