unit WriteOnly;

interface

type
  TGen = class
  private
    FTable: string;          // write-only: never read, stays silent
    FTemp: Integer;          // FIRE field-could-be-local
    FHold: IInterface;       // write-only lifetime holder, stays silent
  public
    procedure Run;
  end;

implementation

procedure TGen.Run;
begin
  FTable:= 'X';
  FTemp:= 5;
  Writeln(FTemp);
  FHold:= nil;
end;

end.