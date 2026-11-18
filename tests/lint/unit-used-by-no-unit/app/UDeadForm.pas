unit UDeadForm;

{ A form listed only by App.dpr that nothing opens. }

interface

uses
  Vcl.Forms;

type
  TDeadForm = class(TForm)
  end;

var
  DeadForm: TDeadForm;

implementation

{$R *.dfm}

end.