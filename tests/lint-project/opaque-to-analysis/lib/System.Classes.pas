unit System.Classes;

{ Stand-in platform library for the opaque-to-analysis fixture. }

interface

type
  TStream = class
  public
    procedure ReadBuf;
    procedure WriteBuf;
    procedure Seek;
    procedure Flush;
    procedure Reset;
  end;

  TComponent = class
  public
    procedure Loaded;
    procedure Notify;
    procedure Update;
    procedure Refresh;
  end;

var
  Application: TComponent;

implementation

procedure TStream.ReadBuf;
begin
end;

procedure TStream.WriteBuf;
begin
end;

procedure TStream.Seek;
begin
end;

procedure TStream.Flush;
begin
end;

procedure TStream.Reset;
begin
end;

procedure TComponent.Loaded;
begin
end;

procedure TComponent.Notify;
begin
end;

procedure TComponent.Update;
begin
end;

procedure TComponent.Refresh;
begin
end;

end.