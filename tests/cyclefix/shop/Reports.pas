unit Reports;

interface

procedure PrintReport;

implementation

uses
  System.SysUtils, AppMain;

procedure PrintReport;
begin
  AppMainForm.Log.Add('report: ' + IntToStr(AppMainForm.OrderCount) + ' orders');
end;

end.
