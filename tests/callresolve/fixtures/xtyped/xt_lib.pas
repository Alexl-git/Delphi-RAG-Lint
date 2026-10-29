unit xt_lib;

{ The LIBRARY of the xtyped pair (item 4): indexed alone. }

interface

uses System.SysUtils;

type
  TLibBase = class
  private
    FPos: Integer;
  public
    procedure Base;
    property Pos: Integer read FPos write FPos;
  end;

  TLibDefs = class
  public
    procedure Add(const N: string);
  end;

  TLibStream = class(TLibBase)
  public
    function Read(var B; N: Integer): Integer; overload;
    function Read(var S: string): Boolean; overload;
    function Defs: TLibDefs;
  end;

  TLibEnc = class
  private
    class function GetUTF8: TLibEnc; static;
  public
    class property UTF8: TLibEnc read GetUTF8;
    function GetBytes(const S: string): TBytes;
  end;

  { Same-named member on an unrelated type: the fabrication control. }
  TOtherLib = class
  public
    procedure Add(const N: string);
  end;

  { P8: an exception class whose member comes from a LIBRARY ancestor. }
  ELibError = class(TLibBase)
  end;

var
  LibApp: TLibBase;

function LibFormat(const F: string): string;

implementation

procedure TLibBase.Base; begin end;
procedure TLibDefs.Add(const N: string); begin end;
function TLibStream.Read(var B; N: Integer): Integer; begin Result := 0; end;
function TLibStream.Read(var S: string): Boolean; begin Result := False; end;
function TLibStream.Defs: TLibDefs; begin Result := nil; end;
class function TLibEnc.GetUTF8: TLibEnc; begin Result := nil; end;
function TLibEnc.GetBytes(const S: string): TBytes; begin Result := nil; end;
procedure TOtherLib.Add(const N: string); begin end;
function LibFormat(const F: string): string; begin Result := F; end;

end.