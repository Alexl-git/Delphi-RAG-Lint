unit DsTypes;

interface

type
  TRec = record
    Count: Integer;
    Other: Integer;
  end;

  { Same field name on an unrelated record: must stay. }
  TOtherRec = record
    Count: Integer;
  end;

  { Property specifiers with a DOTTED head: `read FRec.Count`. }
  TBox = class
  private
    FRec: TRec;
    function GetOther: Integer;
  public
    property Tally: Integer read FRec.Count write FRec.Count;
    property Spare: Integer read GetOther;
  end;

  TBoxKid = class(TBox)
  private
    FOth: TOtherRec;
  public
    property Extra: Integer read FOth.Count write FOth.Count;
  end;

implementation

function TBox.GetOther: Integer;
begin
  Result:= FRec.Other;
end;

end.