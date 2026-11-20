unit AppMain;

interface

uses
  System.Classes, System.SysUtils;

type
  TAppMain = class(TComponent)
  public
    Log: TStringList;
    OrderCount: Integer;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Note(const pText: string);
    function Ready: Boolean;
  end;

var
  AppMainForm: TAppMain;

procedure Run;

implementation

uses
  Orders, Stock, Reports;

constructor TAppMain.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Log:= TStringList.Create;
end;

destructor TAppMain.Destroy;
begin
  Log.Free;
  inherited Destroy;
end;

procedure TAppMain.Note(const pText: string);
begin
  Log.Add(pText);
end;

function TAppMain.Ready: Boolean;
begin
  Result:= OrderCount > 0;
end;

procedure Run;
begin
  AppMainForm:= TAppMain.Create(nil);
  try
    TakeOrders;
    CheckStock;
    PrintReport;
    Write(AppMainForm.Log.Text);
  finally
    AppMainForm.Free;
  end;
end;

end.
