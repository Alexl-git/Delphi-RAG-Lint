unit UOwn;

{ member-could-be-private fixture. (+) must be reported, (-) must not.
  Every (-) is one exemption of the rule; every (+) is its positive control. }

interface

uses
  UIface;

type
  TMyAttribute = class(TCustomAttribute);

  TOwn = class(TInterfacedObject, IThing)
  public
    procedure FlaggedProc; { (+) }
    FlaggedField: Integer; { (+) }
    procedure UsedElsewhere; { (-) }
    procedure VirtProc; virtual; { (-) }
    procedure Execute; { (-) }
    procedure Unreferenced; { (-) }
    [TMyAttribute]
    procedure Tagged; { (-) }
    procedure Run;
  published
    procedure PubProc; { (-) }
  end;

implementation

procedure TOwn.FlaggedProc;
begin
  FlaggedField:= 1;
end;

procedure TOwn.UsedElsewhere;
begin
end;

procedure TOwn.VirtProc;
begin
end;

procedure TOwn.Execute;
begin
end;

procedure TOwn.Unreferenced;
begin
end;

procedure TOwn.Tagged;
begin
end;

procedure TOwn.PubProc;
begin
end;

procedure TOwn.Run;
begin
  FlaggedProc;
  VirtProc;
  Execute;
  Tagged;
  PubProc;
end;

end.
