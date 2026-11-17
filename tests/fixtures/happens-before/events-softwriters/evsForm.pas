unit evsForm;

interface

uses
  System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls;

type
  TSoftForm = class(TForm)
    edtName: TEdit;
  private
    FCount: Integer;
  public
    procedure ShowName;
  end;

var
  SoftForm: TSoftForm;

implementation

{$R *.dfm}

procedure TSoftForm.ShowName;
begin
  edtName.Text := IntToStr(FCount);
end;

end.
