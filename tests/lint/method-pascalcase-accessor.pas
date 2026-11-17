unit mpa;
interface
type
  TRec = class
  private
    function GetATTR_SYSTID: Integer;   // DB column accessor: clean
    procedure SetATTR_SYSTID(pV: Integer); // clean
    function do_thing: Integer;         // must fire
    procedure Setup_Form;               // ordinary method: must fire
  end;
implementation
function TRec.GetATTR_SYSTID: Integer; begin Result:= 0 end;
procedure TRec.SetATTR_SYSTID(pV: Integer); begin end;
function TRec.do_thing: Integer; begin Result:= 0 end;
procedure TRec.Setup_Form; begin end;
end.
