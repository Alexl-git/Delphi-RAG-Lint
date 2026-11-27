unit uFb2Ind;

{ Fixture of tests\autotest\run_v156_FB2.ps1 (1.56 lane FB-2): check-init reads indirect_edges.
  Each routine that READS a unit variable is reached only through a procedural slot. The expected
  verdict of every case is in the runner. A SET case and its twin differ by one construct. }

interface

uses
  System.Classes;

type
  TFbProc = procedure(pTag: Integer);
  TFbNotify = procedure(pTag: Integer) of object;

  TFbEmitter = class
  private
    FOnTick: TFbNotify;
  public
    procedure Fire;
    property OnTick: TFbNotify read FOnTick write FOnTick;
  end;

  TFbListener = class
  public
    procedure Tick(pTag: Integer);
    procedure Hook(pEmitter: TFbEmitter);
  end;

var
  GCfg1: TStringList;
  GCfg2: TStringList;
  GCfg3: TStringList;
  GCfg4: TStringList;
  GCfg5: TStringList;
  GCfg6: TStringList;
  GCfg7: TStringList;
  GHook4: TFbProc;
  GHook5: TFbProc;
  GKeep3: TFbProc;

implementation

{ I1 -- callback argument, called after the write: SET }
procedure UseCfg1(pTag: Integer);
begin
  GCfg1.Add('1');
end;

procedure Each1(pCb: TFbProc);
begin
  pCb(1);
end;

{ I2 -- twin of I1: the callback runs before the write: MAY-BE-UNSET }
procedure UseCfg2(pTag: Integer);
begin
  GCfg2.Add('2');
end;

procedure Each2(pCb: TFbProc);
begin
  pCb(2);
end;

{ I3 -- twin of I1: the slot is also copied away, so another caller cannot be excluded: MAY-BE-UNSET }
procedure UseCfg3(pTag: Integer);
begin
  GCfg3.Add('3');
end;

procedure Each3(pCb: TFbProc);
begin
  GKeep3 := pCb;
  pCb(3);
end;

{ I4 -- unit-level procedural variable, bound and called after the write: SET }
procedure UseCfg4(pTag: Integer);
begin
  GCfg4.Add('4');
end;

procedure Fire4;
begin
  if Assigned(GHook4) then
    GHook4(4);
end;

{ I5 -- twin of I4: the binding spans two lines, the index holds no edge for it: MAY-BE-UNSET }
procedure UseCfg5(pTag: Integer);
begin
  GCfg5.Add('5');
end;

procedure Fire5;
begin
  if Assigned(GHook5) then
    GHook5(5);
end;

{ I6 -- event property of a class of the index, fired after the write: SET }
procedure TFbEmitter.Fire;
begin
  if Assigned(FOnTick) then
    FOnTick(6);
end;

procedure TFbListener.Tick(pTag: Integer);
begin
  GCfg6.Add('6');
end;

procedure TFbListener.Hook(pEmitter: TFbEmitter);
begin
  pEmitter.OnTick := Tick;
end;

procedure Run6;
var
  E: TFbEmitter;
  L: TFbListener;
begin
  E := TFbEmitter.Create;
  L := TFbListener.Create;
  try
    L.Hook(E);
    E.Fire;
  finally
    L.Free;
    E.Free;
  end;
end;

{ I7 -- callback argument that sets the variable itself before it reads it: SET by its own routine,
  whatever its callers do (the proof relies on no edge) }
procedure UseCfg7(pTag: Integer);
begin
  GCfg7 := TStringList.Create;
  GCfg7.Add('7');
end;

procedure Each7(pCb: TFbProc);
begin
  pCb(7);
end;

initialization
  GCfg1 := TStringList.Create;
  Each1(UseCfg1);
  Each2(UseCfg2);
  GCfg2 := TStringList.Create;
  GCfg3 := TStringList.Create;
  Each3(UseCfg3);
  GCfg4 := TStringList.Create;
  GHook4 := UseCfg4;
  Fire4;
  GCfg5 := TStringList.Create;
  GHook5 :=
    UseCfg5;
  Fire5;
  GCfg6 := TStringList.Create;
  Run6;
  Each7(UseCfg7);

end.
