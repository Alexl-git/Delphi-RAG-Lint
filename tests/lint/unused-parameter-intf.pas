unit upintf;
interface
type
  { A class that lists an interface in its heritage implements that interface's
    methods with the interface's parameter lists -- nothing in the class can
    remove a parameter. The interface here is FOREIGN (declared in another unit,
    like ToolsAPI's IOTACodeFormatter), so the method set is not visible to a
    same-file AST rule. Filed 2026-11-03 against YADFOT.CodeFormatter.pas. }
  TFmt = class(TInterfacedObject, IForeignFormatter)
  private
    procedure Helper(Used, Unused: Integer);
  public
    function FormatLine(const AModule: IInterface; ALen: Integer): Boolean;
    function CanFormatLine(ANumLines: Integer): Boolean;
  end;
  { Positive control: a class with NO interface in its heritage still fires. }
  TPlain = class(TObject)
  public
    function Calc(Used, Unused: Integer): Integer;
  end;
implementation
procedure TFmt.Helper(Used, Unused: Integer); begin WriteLn(Used); end;
function TFmt.FormatLine(const AModule: IInterface; ALen: Integer): Boolean; begin Result := False; end;
function TFmt.CanFormatLine(ANumLines: Integer): Boolean; begin Result := False; end;
function TPlain.Calc(Used, Unused: Integer): Integer; begin Result := Used; end;
end.
