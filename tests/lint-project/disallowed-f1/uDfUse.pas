unit uDfUse;

interface

implementation

uses
  System.SysUtils, System.Classes;

type
  TWorker = class
  public
    procedure Sleep(AMs: Integer);
  end;

  TMyList = class
  public
    procedure LoadFromFile(const AName: string);
  end;

procedure TWorker.Sleep(AMs: Integer);
begin
end;

procedure TMyList.LoadFromFile(const AName: string);
begin
end;

procedure Probe;
var
  Obj : TWorker;
  List: TStringList;
  Mine: TMyList;
begin
  Obj := TWorker.Create;
  List:= TStringList.Create;
  Mine:= TMyList.Create;
  Sleep(10);                  // TRIGGER-DISM-BARE
  Obj.Sleep(10);              // CONTROL-DISM-OWNER
  List.LoadFromFile('a.txt'); // TRIGGER-DISM-RECV
  Mine.LoadFromFile('a.txt'); // CONTROL-DISM-RECV
end;

end.
