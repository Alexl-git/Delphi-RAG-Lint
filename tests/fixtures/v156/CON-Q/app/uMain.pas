unit uMain;

{ v156 CON-Q fixture: symbols and code the hand-filled concept_* rows of fill_concept.py point at. }

interface

type
  TDataSetStub = class
    function FieldByName(const pName: string): TDataSetStub;
    function AsString: string;
  end;

  TfrmMain = class(TObject)
    qryCustomers: TDataSetStub;
    qryCustomersNAME: TDataSetStub;
  public
    /// <summary>Reacts to an edit of the buyer.</summary>
    procedure CustomerNameChanged;
    /// <summary>Stores the edited row.</summary>
    procedure Save;
    /// <summary>The title of the form.</summary>
    function Name: string;
    /// <summary>The highest amount the form accepts.</summary>
    function Limit: Integer;
    /// <summary>Reacts to an edit of the allowed debt.</summary>
    procedure CreditLimitChanged;
  end;

implementation

function TDataSetStub.FieldByName(const pName: string): TDataSetStub;
begin
  Result:= Self;
end;

function TDataSetStub.AsString: string;
begin
  Result:= '';
end;

procedure TfrmMain.CustomerNameChanged;
begin
  Save;
end;

procedure TfrmMain.Save;
var
  Text: string;
begin
  Text:= qryCustomers.FieldByName('NAME').AsString;
  Text:= Text + qryCustomersNAME.AsString;
end;

function TfrmMain.Name: string;
begin
  Result:= 'main';
end;

function TfrmMain.Limit: Integer;
begin
  Result:= 0;
end;

procedure TfrmMain.CreditLimitChanged;
begin
  Save;
end;

end.
