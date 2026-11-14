unit WritelnInGuiApp;

interface

uses
  Vcl.Forms;

type
  TMainForm = class(TForm)
    procedure Log(const S: string);
    procedure ToFile(const S: string);
  end;

implementation

procedure TMainForm.Log(const S: string);
begin
  Writeln(S);
  System.Write('x');
end;

procedure TMainForm.ToFile(const S: string);
var
  F: TextFile;
begin
  AssignFile(F, 'x.txt');
  Rewrite(F);
  Writeln(F, S);
  CloseFile(F);
end;

end.
