unit uRnaDecl;

{ Fixture for the `read-never-assigned` project rule. Declarations live here,
  most reads and writes in uRnaUse.pas, so the rule must see the whole project.
  TRIGGER-* lines must fire; CONTROL-* lines must stay silent.
  The helpers carry a fixture-unique name (RnaShow, not Show): the rule merges
  the var / out modes of every project AND platform-library routine of the same
  bare name, and ShlObj's IFileViewer.Show(var pvsi) made every Show(X) read
  count as a possible write (silencing TRIGGER-FIELD and four run-3 controls). }

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
    property Size: Integer read FSize write FSize;
    procedure Init;
    function Total: Integer;
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

const
  CTyped: Integer = 5;          // CONTROL-TYPEDCONST

procedure Fill(var pV: Integer);
procedure Produce(out pV: Integer);
procedure RnaShow(const pV: Integer);

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

procedure TRnaHolder.Init;
begin
  FSelfSet:= 1;
  Fill(FVarArg);
  Produce(FOutArg);
  SetLength(FArr, 2);
  Inc(GCounter);
end;

function TRnaHolder.Total: Integer;
var
  P: ^Integer;
begin
  P:= @FAddr;
  RnaShow(FNever);
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
