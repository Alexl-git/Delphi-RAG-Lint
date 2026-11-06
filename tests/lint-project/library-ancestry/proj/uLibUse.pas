unit uLibUse;

{ The PROJECT half of run_library_ancestry_rules.ps1. Markers, on the line a finding starts on:
  BOTH-<F>   fires with the library and with --library-db none;
  LIB-ONLY-<F>   fires only with the library: the ancestry that proves it is in the library;
  LIB-SILENT-<F> fires only without it: with the library the receiver is proved to be another class.
  Every ancestor below is in ..\lib\uLibAnc.pas, none in this project. }

interface

uses
  uLibAnc, Vcl.Forms;

type
  TUseWorker = class(TLibWorker)
  public
    procedure Execute; override;
    procedure Tick;
  end;

  /// <summary>Spelled like a thread base in this file; its ancestry is in the library, no TThread.</summary>
  TUseLogThread = class(TLibBase)
  end;

  TUseLog = class(TUseLogThread)
  public
    procedure Execute; override;
  end;

  TUseHttp = class(TLibHttp)
  end;

  TUseLines = class(TStringList)
  end;

  TUseFail = class(ELibFail)
  end;

  IUseThing = interface
  end;

  TUseOwned = class(TLibOwned)
  end;

  TUseKind = class of TUseOwned;

  TUser = class
  private
    FKind  : TUseKind;
    FMaker : TLibMaker;
    FOwned : TUseOwned;
    FLines : TUseLines;
    FTable : TLibStringTable;
    FConfig: TLibConfig;
    FReport: TLibReport;
    FQuery : TLibQuery;
    procedure Files;
    procedure Fails;
    procedure Loops;
    procedure Lookup;
    procedure Makes(K: TUseKind);
    function GetKind: TUseKind;
  end;

procedure UseDatasets(Port: TLibPort; Qry: TLibQuery);
procedure UseLocks(T: TThread; CS: TCriticalSection; Sem: TLibSemaphore);
procedure UseNet;
procedure UseFill;
procedure UseMix(C: TUseOwned);

implementation

procedure DoWork;
begin
end;

procedure TUseWorker.Execute; // LIB-ONLY-THREAD
var
  Lbl: TLabel;
begin
  DoWork;
  Lbl:= nil;
  Lbl.Caption:= 'x'; // LIB-ONLY-UI
end;

procedure TUseWorker.Tick;
begin
  Sleep(10); // LIB-SILENT-SLEEP
end;

procedure TUseLog.Execute; // LIB-SILENT-THREAD
begin
  DoWork;
end;

procedure UseDatasets(Port: TLibPort; Qry: TLibQuery);
begin
  Port.Open; // LIB-SILENT-DS
  Qry.Open; // BOTH-DS
end;

procedure UseLocks(T: TThread; CS: TCriticalSection; Sem: TLibSemaphore);
begin
  CS.Enter;
  T.WaitFor; // BOTH-LOCK
  CS.Leave;
  Sem.Acquire;
  T.WaitFor; // LIB-SILENT-LOCK
  Sem.Release;
end;

procedure UseNet;
var
  H: TUseHttp;
begin
  H:= TUseHttp.Create(nil); // LIB-ONLY-NET
end;

procedure UseFill;
var
  Buf: array[0..3] of Byte;
  F  : TLibFiller;
begin
  F:= TLibFiller.Create;
  F.Fill(Buf[0], 4); // LIB-SILENT-UBA
  F.Free;
end;

procedure UseMix(C: TUseOwned);
var
  I: IUseThing;
begin
  I:= C;
  C.Free; // LIB-SILENT-MIX
end;

procedure TUser.Files;
begin
  FLines.LoadFromFile('a.txt'); // LIB-ONLY-ENC
  FTable.LoadFromFile('a.bin'); // LIB-SILENT-ENC
end;

procedure TUser.Fails;
begin
  TUseFail.Create('x'); // LIB-ONLY-EXC
end;

procedure TUser.Loops;
begin
  while not FQuery.Eof do
  begin
    Writeln(FQuery.FieldByName('a').ClassName); // BOTH-FBN
    FQuery.Next;
  end;
  while not FReport.Eof do
  begin
    Writeln(FReport.FieldByName('a').ClassName); // LIB-SILENT-FBN
    FReport.Next;
  end;
end;

function TUser.GetKind: TUseKind;
begin
  Result:= FKind;
end;

{ The metaclass receivers allocate, so only FOwned and the marked one are findings. }
procedure TUser.Makes(K: TUseKind);
begin
  FKind.Create;
  K.Create;
  GetKind.Create;
  FMaker.Create; // LIB-SILENT-CTOR
  FOwned.Create; // BOTH-CTOR
end;

procedure TUser.Lookup;
begin
  if FConfig.ContainsKey('k') then // LIB-SILENT-DDL
    Writeln(FConfig['k']);
end;

end.
