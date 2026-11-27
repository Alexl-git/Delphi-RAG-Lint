unit uLock;

{ v156 HB6 fixture: --preset lock-held-when. One lock and one guarded field per case. }

interface

uses
  System.SyncObjs;

type
  TAcct = class
  private
    FLock1, FLock2, FLock3, FLock4, FLock5: TCriticalSection;
    FBal1, FBal2, FBal3, FBal4, FBal5: Integer;
    procedure Drop5;
  public
    constructor Create;
    procedure Held;
    procedure Released;
    procedure Branch(pLock: Boolean);
    procedure Never;
    procedure CalleeLeaves;
  end;

implementation

constructor TAcct.Create;
begin
  inherited Create;
  FLock4 := TCriticalSection.Create;
end;

procedure TAcct.Held;
begin
  FLock1.Enter;
  try
    FBal1 := 1;
  finally
    FLock1.Leave;
  end;
end;

procedure TAcct.Released;
begin
  FLock2.Enter;
  FLock2.Leave;
  FBal2 := 1;
end;

procedure TAcct.Branch(pLock: Boolean);
begin
  if pLock then
    FLock3.Enter;
  FBal3 := 1;
end;

procedure TAcct.Never;
begin
  FBal4 := 1;
end;

procedure TAcct.Drop5;
begin
  FLock5.Leave;
end;

procedure TAcct.CalleeLeaves;
begin
  FLock5.Enter;
  Drop5;
  FBal5 := 1;
end;

end.
