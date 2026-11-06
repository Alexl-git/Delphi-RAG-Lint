unit uQoUse;

interface

uses
  uQoBase, Vcl.Forms;

type
  TQoWorker = class(TQoBaseWorker)
  public
    procedure Execute;
  end;

  TQoForm = class
  public
    procedure Tick;
  end;

  TQoUser = class
  private
    FStream: TQoFileStream;
    FBox: TQoBox;
    FReply: TIdHTTPResponseInfo;
    FNote: TQoNote;
    procedure Pump;
    procedure Handle(const AInfo: TIdHTTPResponseInfo);
  end;

implementation

function GetV: string;
begin
  Result:= 'v';
end;

procedure TQoUser.Pump;
var
  Buf : array[0..3] of Byte;
  LS  : TQoFileStream;
  LB  : TQoBox;
begin
  FStream.Read(Buf, 4); // ORACLE-ONLY-STREAM
  FBox.Read(Buf, 4); // CONTROL-STREAM
  LS.Read(Buf, 4); // ALWAYS-STREAM
  FBox.Create; // ORACLE-ONLY-CTOR
  TQoBox.Create; // CONTROL-CTOR
  LB.Create; // ALWAYS-CTOR
end;

procedure IfThens(AFlag: Boolean; const V1, V2: string);
begin
  Writeln(IfThen(AFlag, V1, V2)); // SILENCED-IFTHEN
  Writeln(IfThen(AFlag, V1, GetV)); // ALWAYS-IFTHEN
  Writeln(IfThen(AFlag, GetV, V2)); // ALWAYS-IFTHEN
  Writeln(IfThen(AFlag, V1)); // SILENCED-IFTHEN
  Writeln(IfThen(AFlag, GetV)); // ALWAYS-IFTHEN
  Writeln(IfThen(AFlag, 'a', 'b')); // CONTROL-IFTHEN
end;

procedure TQoWorker.Execute;
begin
  Sleep(10); // SILENCED-SLEEP
end;

procedure TQoForm.Tick;
begin
  Sleep(10); // ALWAYS-SLEEP
  FBox.Sleep(10); // CONTROL-SLEEP
end;

procedure Plain;
begin
  Sleep(10); // ALWAYS-SLEEP
end;

procedure TQoUser.Handle(const AInfo: TIdHTTPResponseInfo);
begin
  try
    Plain;
  except
    on E: Exception do
    begin
      FReply.ContentText := E.Message; // ORACLE-ONLY-RESP
      AInfo.ContentText := E.Message; // ALWAYS-RESP
      FNote.ContentText := E.Message; // CONTROL-RESP
    end;
  end;
end;

end.
