unit EncName;

interface

uses
  System.Classes;

procedure SetCurrentStreamWriter(AValue: TObject);
procedure UseIt(const APath: string);

implementation

procedure SetCurrentStreamWriter(AValue: TObject);
begin
end;

procedure UseIt(const APath: string);
var
  W: TStreamWriter;
begin
  SetCurrentStreamWriter(nil);
  W:= TStreamWriter.Create(APath);
  W.Free;
end;

end.