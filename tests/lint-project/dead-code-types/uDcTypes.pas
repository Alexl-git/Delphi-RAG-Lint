unit uDcTypes;

{ Fixture for run_dead_code_types.ps1 (1.45 lane lg). Markers on the line a finding starts on:
  ALWAYS-<T> fires with and without the index facts; ORACLE-ONLY-<T> fires only WITH them;
  SILENCED-<T> fires without them, silent WITH them; CONTROL-<T> never fires. }

interface

uses
  System.SysUtils, System.Classes;

type
  TMyFail = class(Exception);
  EDIParser = class
  public
    constructor Create(const AName: string);
  end;
  TLines = class(TStrings);
  TPic = class
  public
    procedure LoadFromFile(const AName: string);
  end;
  THolder = class
  public
    Pic: TPic;
    Lines: TLines;
  end;
  TBuilder = class
  public
    Total: TPic;
    function Add(AValue: Integer): TBuilder;
    function Next: TBuilder;
    function Peer: TPic;
  end;
  TN6 = class end;
  TN5 = class Nxt: TN6; end;
  TN4 = class Nxt: TN5; end;
  TN3 = class Nxt: TN4; end;
  TN2 = class Nxt: TN3; end;
  TN1 = class Nxt: TN2; end;
  TPicHolder = class
  public
    Owner: TBuilder;
  end;
  TUser = class
  private
    FHolder: THolder;
    FBuilder: TBuilder;
    FOuter: TPicHolder;
    FN: TN1;
    FLines: TLines;
    procedure Run;
  end;

implementation

constructor EDIParser.Create(const AName: string);
begin
  inherited Create;
end;

procedure TPic.LoadFromFile(const AName: string);
begin
end;

function TBuilder.Add(AValue: Integer): TBuilder;
begin
  Result:= Self;
end;

function TBuilder.Next: TBuilder;
begin
  Result:= Self;
end;

function TBuilder.Peer: TPic;
begin
  Result:= Total;
end;

procedure TUser.Run;
begin
  TMyFail.Create('x'); // ORACLE-ONLY-EXC
  EInvalidOp.Create('x'); // ALWAYS-EXC
  TBuilder.Create; // CONTROL-EXC
  EDIParser.Create('x'); // SILENCED-EXC
  FHolder.Lines.LoadFromFile('a.txt'); // ALWAYS-ENC
  FLines.LoadFromFile('a.txt'); // ORACLE-ONLY-ENC
  FHolder.Pic.LoadFromFile('a.bin'); // SILENCED-ENC
  FHolder.Pic.LoadFromFile('a.bin', TEncoding.UTF8); // CONTROL-ENC
  FOuter.Owner.Total.LoadFromFile('x', TEncoding.UTF8); // CONTROL-ENC
  Writeln(FBuilder.Add(1).Add(2).Add(3).Add(4).Next.Total); // SILENCED-CHAIN
  Writeln(FN.Nxt.Nxt.Nxt.Nxt.Nxt); // ALWAYS-CHAIN
  Writeln(FOuter.Owner.Total); // CONTROL-CHAIN
end;

end.
