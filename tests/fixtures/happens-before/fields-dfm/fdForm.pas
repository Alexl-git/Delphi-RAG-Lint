unit fdForm;

interface

uses
  System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls;

type
  TDfmForm = class(TForm)
    edtName: TEdit;
    lblIdle: TLabel;
  private
    FCount: TObject;
  public
    procedure Init;
    procedure ShowName;
  end;

var
  DfmForm: TDfmForm;

implementation

{$R *.dfm}

procedure TDfmForm.Init;
begin
  FCount:= TObject.Create;
end;

procedure TDfmForm.ShowName;
begin
  edtName.Text:= 'x';    // USE-EDT
  Writeln(FCount.ToString);    // USE-COUNT
end;

end.