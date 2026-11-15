unit FrUse;

interface

/// <summary>Creates both forms and prints the names the streaming bound to the fields.</summary>
procedure RunAll;

implementation

uses
  System.SysUtils, Vcl.Forms, FrMain, FrKid;

procedure RunAll;
begin
  var M:= TFrmMain.Create(nil);
  var K:= TFrmKid.Create(nil);
  try
    M.Poke;
    Writeln('main=', M.BtnGo.Name, ' focus=', M.Lbl.FocusControl.Name, ' kid=', K.BtnGo.Name, ' ', K.KidCaption);
  finally
    K.Free;
    M.Free;
  end;
end;

end.
