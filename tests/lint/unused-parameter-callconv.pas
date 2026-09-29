unit upcc;
interface
type
  { An OS/COM interface implementation: the parameter list is fixed by the
    interface (IDropTarget here), and the method carries only a calling
    convention -- no virtual/override -- so the contract-directive exemption
    never saw it. Filed 2026-09-28 against ConvRules.DropTarget.pas. }
  TDrop = class(TInterfacedObject)
    function DragEnter(const dataObj: IInterface; grfKeyState: Longint; pt: TPoint; var dwEffect: Longint): HResult; stdcall;
    function GetInfo(Index: Integer): HResult; safecall;
    function Compare(A, B: Pointer): Integer; cdecl;
    function Enum(Wnd: THandle; Param: NativeInt): LongBool; winapi;
    { Positive control: an ordinary method in the SAME class, no calling
      convention, with a genuinely unused parameter -- must still fire. }
    procedure Plain(Used, Unused: Integer);
  end;
implementation
function TDrop.DragEnter(const dataObj: IInterface; grfKeyState: Longint; pt: TPoint; var dwEffect: Longint): HResult; begin dwEffect := 0; Result := 0; end;
function TDrop.GetInfo(Index: Integer): HResult; begin Result := 0; end;
function TDrop.Compare(A, B: Pointer): Integer; begin Result := 0; end;
function TDrop.Enum(Wnd: THandle; Param: NativeInt): LongBool; begin Result := True; end;
procedure TDrop.Plain(Used, Unused: Integer); begin WriteLn(Used); end;
end.
