unit uRnaDecl;

{ Fixture for the `read-never-assigned` project rule. Declarations live here,
  most reads and writes in uRnaUse.pas, so the rule must see the whole project.
  TRIGGER-* lines must fire; CONTROL-* lines must stay silent.
  ShlObj's IFileViewer.Show(var pvsi) shares the bare name Show with this
  unit's Show and TRnaShower.Show (both const). A call the resolver binds uses
  ONLY the bound declaration's var / out modes (TRIGGER-BARENAME, -QUALIFIED
  fire); an unbound call (the late-bound Variant V.Show) falls back to the
  bare-name merge across project + library and stays silent
  (CONTROL-UNRESOLVED). The other helpers keep the name RnaShow. }

interface

uses
  Classes;

type
  TRnaRec = record
    RX: Integer;
  end;

  TRnaHolder = class
  public
    FNever: Integer;            // TRIGGER-FIELD
    FList: TList;               // TRIGGER-OBJ
    FSetElsewhere: Integer;     // CONTROL-CROSSUNIT
    FSelfSet: Integer;          // CONTROL-SELFWRITE
    FCast: Integer;             // CONTROL-HARDCAST
    FWith: Integer;             // CONTROL-WITH
    FVarArg: Integer;           // CONTROL-VARARG
    FOutArg: Integer;           // CONTROL-OUTARG
    FArr: TArray<Integer>;      // CONTROL-RTLVAR
    FSize: Integer;             // CONTROL-PROPSETTER
    FUnread: Integer;           // CONTROL-UNREAD
    FAddr: Integer;             // CONTROL-ADDR
    FBare: Integer;             // TRIGGER-BARENAME
    FQual: Integer;             // TRIGGER-QUALIFIED
    FLate: Integer;             // CONTROL-UNRESOLVED
    property Size: Integer read FSize write FSize;
    procedure Init;
    function Total: Integer;
  end;

  TRnaShower = class
  public
    procedure Show(const pV: Integer);
    procedure SetTextBuf(const pBuffer: PChar);
  end;

  TRnaForm = class(TComponent)
  published
    Button1: TComponent;        // CONTROL-PUBLISHED
  public
    function Tag2: Integer;
  end;

  TRnaFrame = class(TComponent)
    Label1: TComponent;         // CONTROL-DEFAULTSECTION
  public
    function Tag3: Integer;
  end;

var
  GLimit: Integer;              // TRIGGER-GLOBAL
  GInitSec: Integer;            // CONTROL-INIT
  GInitVal: Integer = 7;        // CONTROL-VALUEINIT
  GBase: Integer;               // CONTROL-ABSBASE
  GAbs: Integer absolute GBase; // CONTROL-ABSOLUTE
  GCounter: Integer;            // CONTROL-INC
  GStdBuf: array[0..1, 0..7] of Byte; // CONTROL-SETTEXTBUF

const
  CTyped: Integer = 5;          // CONTROL-TYPEDCONST

procedure Fill(var pV: Integer);
procedure Produce(out pV: Integer);
procedure RnaShow(const pV: Integer);
procedure Show(const pV: Integer);

implementation

procedure Fill(var pV: Integer);
begin
  pV:= pV + 1;
end;

procedure Produce(out pV: Integer);
begin
  pV:= 3;
end;

procedure RnaShow(const pV: Integer);
begin
  if pV > 0 then Exit;
end;

procedure Show(const pV: Integer);
begin
  if pV > 0 then Exit;
end;

procedure TRnaShower.Show(const pV: Integer);
begin
  if pV > 0 then Exit;
end;

procedure TRnaShower.SetTextBuf(const pBuffer: PChar);
begin
  if pBuffer = nil then Exit;
end;

procedure TRnaHolder.Init;
begin
  FSelfSet:= 1;
  Fill(FVarArg);
  Produce(FOutArg);
  SetLength(FArr, 2);
  Inc(GCounter);
  SetTextBuf(Output, GStdBuf[0]);
end;

function TRnaHolder.Total: Integer;
var
  P: ^Integer;
  S: TRnaShower;
  V: Variant;
begin
  P:= @FAddr;
  RnaShow(FNever);
  Show(FBare);
  S:= TRnaShower.Create;
  S.Show(FQual);
  V.Show(FLate);
  Result:= FNever + FSelfSet + FSetElsewhere + FCast + FWith + FVarArg + FOutArg + FSize + P^;
  Result:= Result + Length(FArr) + FList.Count;
end;

function TRnaForm.Tag2: Integer;
begin
  Result:= Button1.Tag;
end;

function TRnaFrame.Tag3: Integer;
begin
  Result:= Label1.Tag;
end;

initialization
  GInitSec:= 4;
end.
