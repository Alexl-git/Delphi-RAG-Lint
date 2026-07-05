unit uRoot4;
interface
uses Vcl.Forms, Vcl.StdCtrls, uPlanIntf4;
type
  TfrmRoot4 = class(TForm)
    btnPlan: TButton;
    procedure btnPlanClick(Sender: TObject);
  end;
var frmRoot4: TfrmRoot4;
implementation
uses uPlans4;
{$R *.dfm}
procedure TfrmRoot4.btnPlanClick(Sender: TObject);
var
  APlan: IThingPlan4;
begin
  APlan := TDirectPlan4.Create;
  APlan.EditThing;
end;
end.
