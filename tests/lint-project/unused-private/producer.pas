unit producer;

interface

type
  TProducer = class
  private
    FUnusedField: Integer;
    procedure UnusedPrivateMethod;
  public
    procedure UsedPublicMethod;
  end;

implementation

procedure TProducer.UnusedPrivateMethod;
begin
end;

procedure TProducer.UsedPublicMethod;
begin
end;

end.
