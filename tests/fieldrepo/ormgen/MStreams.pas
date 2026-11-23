unit MStreams;

{ Stub of the ORM3 unit of the same name: the signatures the generated units call, no transport. }

interface

uses
  System.Classes,
  System.SysUtils,
  Vcl.Graphics,
  Data.DB,
  Data.SqlTimSt,
  Data.FmtBcd,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param;

type
  TABZMemoryStream = class(TMemoryStream)
  public
    function WriteB(const S: string): Boolean; overload;
    function WriteB(const S: TStringList): Boolean; overload;
    function WriteB(const ABytes: TBytes; ACount: Longint = -1): Boolean; overload;
    function WriteB(const ABool: Boolean): Boolean; overload;
    function WriteB(const A8Bit: Byte): Boolean; overload;
    function WriteB(const Stamp: TSQLTimeStamp): Boolean; overload;
    function WriteB(const ABcd: TBcd): Boolean; overload;
    function WriteB(const A16Bit: SmallInt): Boolean; overload;
    function WriteB(const A32Bit: Integer): Boolean; overload;
    function WriteB(const A64Bit: Int64): Boolean; overload;
    function WriteB(const ADouble: Double): Boolean; overload;
    function WriteB(const ADT: TDateTime): Boolean; overload;
    function WriteB(const APic: TPicture): Boolean; overload;
    function Read(var ABytes: TBytes; const ACount: Longint): Boolean; reintroduce; overload;
    function Read(var S: string): Boolean; overload;
    function Read(var S: TStringList): Boolean; overload;
    function Read(var ABool: Boolean): Boolean; overload;
    function Read(var A8Bit: Byte): Boolean; overload;
    function Read(var Stamp: TSQLTimeStamp): Boolean; overload;
    function Read(var ABcd: TBcd): Boolean; overload;
    function Read(var A16Bit: SmallInt): Boolean; overload;
    function Read(var A32Bit: Integer): Boolean; overload;
    function Read(var A64Bit: Int64): Boolean; overload;
    function Read(var ADouble: Double): Boolean; overload;
    function Read(var ADT: TDateTime): Boolean; overload;
    function Read(var APic: TPicture): Boolean; overload;
    function WriteStream(const AName: string; AStream: TStream; ASize: Int64): Boolean;
    function ReadStream(const AName: string; AStream: TStream; var ALen: Integer): Boolean;
  end;

function Get1Byte(AField: TField): Byte;
procedure Set1Byte(AParam: TFDParam; const B: Byte);
function GetBytes(AField: TField): TBytes;
procedure SetBytes(AParam: TFDParam; const B: TBytes);
procedure LoadImageField(const qry: TFDQuery; const F: TField; const IMG: TPicture);
procedure SaveImageField(qry: TFDCommand; F: TFDParam; const IMG: TPicture);
function NewName(AOwner: TComponent; const SName: string): string;

implementation

function TABZMemoryStream.WriteB(const S: string): Boolean; begin Result := True; end;
function TABZMemoryStream.WriteB(const S: TStringList): Boolean; begin Result := True; end;
function TABZMemoryStream.WriteB(const ABytes: TBytes; ACount: Longint): Boolean; begin Result := True; end;
function TABZMemoryStream.WriteB(const ABool: Boolean): Boolean; begin Result := True; end;
function TABZMemoryStream.WriteB(const A8Bit: Byte): Boolean; begin Result := Write(A8Bit, 1) = 1; end;
function TABZMemoryStream.WriteB(const Stamp: TSQLTimeStamp): Boolean; begin Result := True; end;
function TABZMemoryStream.WriteB(const ABcd: TBcd): Boolean; begin Result := True; end;
function TABZMemoryStream.WriteB(const A16Bit: SmallInt): Boolean; begin Result := True; end;
function TABZMemoryStream.WriteB(const A32Bit: Integer): Boolean; begin Result := True; end;
function TABZMemoryStream.WriteB(const A64Bit: Int64): Boolean; begin Result := True; end;
function TABZMemoryStream.WriteB(const ADouble: Double): Boolean; begin Result := True; end;
function TABZMemoryStream.WriteB(const ADT: TDateTime): Boolean; begin Result := True; end;
function TABZMemoryStream.WriteB(const APic: TPicture): Boolean; begin Result := True; end;
function TABZMemoryStream.Read(var ABytes: TBytes; const ACount: Longint): Boolean; begin Result := True; end;
function TABZMemoryStream.WriteStream(const AName: string; AStream: TStream; ASize: Int64): Boolean; begin Result := True; end;
function TABZMemoryStream.ReadStream(const AName: string; AStream: TStream; var ALen: Integer): Boolean; begin Result := True; end;
function TABZMemoryStream.Read(var S: string): Boolean; begin Result := True; end;
function TABZMemoryStream.Read(var S: TStringList): Boolean; begin Result := True; end;
function TABZMemoryStream.Read(var ABool: Boolean): Boolean; begin Result := True; end;
function TABZMemoryStream.Read(var A8Bit: Byte): Boolean; begin Result := (inherited Read(A8Bit, 1)) = 1; end;
function TABZMemoryStream.Read(var Stamp: TSQLTimeStamp): Boolean; begin Result := True; end;
function TABZMemoryStream.Read(var ABcd: TBcd): Boolean; begin Result := True; end;
function TABZMemoryStream.Read(var A16Bit: SmallInt): Boolean; begin Result := True; end;
function TABZMemoryStream.Read(var A32Bit: Integer): Boolean; begin Result := True; end;
function TABZMemoryStream.Read(var A64Bit: Int64): Boolean; begin Result := True; end;
function TABZMemoryStream.Read(var ADouble: Double): Boolean; begin Result := True; end;
function TABZMemoryStream.Read(var ADT: TDateTime): Boolean; begin Result := True; end;
function TABZMemoryStream.Read(var APic: TPicture): Boolean; begin Result := True; end;

function Get1Byte(AField: TField): Byte;
begin
  Result := Byte(AField.AsInteger);
end;

procedure Set1Byte(AParam: TFDParam; const B: Byte);
begin
  AParam.AsByte := B;
end;

function GetBytes(AField: TField): TBytes;
begin
  Result := AField.AsBytes;
end;

procedure SetBytes(AParam: TFDParam; const B: TBytes);
begin
  AParam.Clear;
end;

procedure LoadImageField(const qry: TFDQuery; const F: TField; const IMG: TPicture);
begin
end;

procedure SaveImageField(qry: TFDCommand; F: TFDParam; const IMG: TPicture);
begin
end;

function NewName(AOwner: TComponent; const SName: string): string;
begin
  Result := SName;
end;

end.
