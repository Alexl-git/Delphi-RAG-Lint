unit queue_nil_in_package;

{ queue-nil-in-package fixture: the unit uses ToolsAPI, so it lives in a design-time package.
  HIT marker = rule fires on that line, OK marker = silent. }

interface

uses
  System.Classes, ToolsAPI;

procedure Refresh;

implementation

procedure Refresh;
begin
  TThread.Queue(nil, {HIT}
    procedure
    begin
      Sleep(1);
    end);
  TThread.ForceQueue(nil, {HIT}
    procedure
    begin
      Sleep(1);
    end);
  TThread.Queue(TThread.CurrentThread, {OK}
    procedure
    begin
      Sleep(1);
    end);
end;

end.
