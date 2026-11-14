unit delimited_text_without_strict;

interface

implementation

uses
  System.Classes;

procedure Bad(Zeile: string);
var
  Teile: TStringList;
begin
  Teile := TStringList.Create;
  try
    Teile.Delimiter := ';';
    Teile.DelimitedText := Zeile;
  finally
    Teile.Free;
  end;
end;

procedure Good(Zeile: string);
var
  Teile: TStringList;
begin
  Teile := TStringList.Create;
  try
    Teile.Delimiter := ';';
    Teile.StrictDelimiter := True;
    Teile.DelimitedText := Zeile;
  finally
    Teile.Free;
  end;
end;

end.
