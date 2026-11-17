unit EscUnit;

interface

uses
  System.Classes;

type
  TEscPub = class(TPersistent)
  published
    procedure PubMethod;
  end;

  TEscMsg = class(TObject)
  private
    procedure WMNull(var Msg: TObject); message 0;
  end;

  IEscJob = interface
    ['{8B4B7C61-2F4E-4C55-9D7A-6C1D3E2B9A01}']
    procedure Run;
  end;

  TEscJob = class(TInterfacedObject, IEscJob)
  public
    procedure Run;
  end;

  TEscThread = class(TThread)
  protected
    procedure Execute; override;
  end;

  TEscCls = class(TObject)
  public
    class constructor CreateCls;
  end;

  TEscEvent = procedure of object;

  TEscHolder = class(TObject)
  private
    FOnEvt: TEscEvent;
  public
    procedure HandlerEvt;
    function GetCount: Integer;
    property OnEvt: TEscEvent read FOnEvt write FOnEvt;
  end;

  TEscBase = class(TObject)
  public
    procedure DoIt; virtual;
  end;

  TEscChild = class(TEscBase)
  public
    procedure DoIt; override;
  end;

procedure EscDriver;
procedure EscPlain;
procedure EscAddrProc;
procedure EscOrphan;
procedure EscExported; stdcall;
function EscValue: Integer;

implementation

var
  GProc: procedure;
  GVal: Integer;

procedure TEscPub.PubMethod;
begin
end;

procedure TEscMsg.WMNull(var Msg: TObject);
begin
end;

procedure TEscJob.Run;
begin
end;

procedure TEscThread.Execute;
begin
end;

class constructor TEscCls.CreateCls;
begin
end;

procedure TEscHolder.HandlerEvt;
begin
end;

function TEscHolder.GetCount: Integer;
begin
  Result:= 1;
end;

function EscValue: Integer;
begin
  Result:= 2;
end;

procedure TEscBase.DoIt;
begin
end;

procedure TEscChild.DoIt;
begin
end;

procedure EscPlain;
begin
end;

procedure EscAddrProc;
begin
end;

procedure EscOrphan;
begin
end;

procedure EscExported; stdcall;
begin
end;

procedure EscDriver;
var
  H: TEscHolder;
  B: TEscBase;
begin
  EscPlain;
  GProc:= @EscAddrProc;
  H:= TEscHolder.Create;
  H.OnEvt:= H.HandlerEvt;
  GVal:= EscValue;
  GVal:= GVal + H.GetCount;
  B:= TEscChild.Create;
  B.DoIt;
end;

initialization
  EscPlain;

finalization
  GProc:= nil;
end.