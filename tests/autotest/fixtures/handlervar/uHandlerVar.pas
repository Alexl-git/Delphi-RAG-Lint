unit uHandlerVar;

interface

procedure RunTwo;
procedure RunBare;
procedure RunShadow;

implementation

uses
  System.SysUtils;

procedure RunTwo;
var
  S: string;
begin
  try
    S := 'a';
  except
    on E: EConvertError do
      S := E.Message;
    on E: Exception do
      S := E.ClassName;
  end;
end;

procedure RunBare;
var
  S: string;
begin
  try
    S := 'b';
  except
    on Exception do
      S := 'bare';
  end;
end;

procedure RunShadow;
var
  E: Integer;
  S: string;
begin
  E := 1;
  try
    S := 'c';
  except
    on E: System.SysUtils.Exception do
      S := E.Message;
  end;
end;

end.
