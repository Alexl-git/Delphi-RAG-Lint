unit basic;

interface

uses
  System.Classes, System.SysUtils;

type
  TImporter = class
  private
    FStream: TFileStream;
    FLines : TStringList;
  public
    constructor Create(const AFile: string);
    destructor Destroy; override;
  end;

implementation

constructor TImporter.Create(const AFile: string);
begin
  inherited Create;
  FStream:= TFileStream.Create(AFile, fmOpenRead);
  FLines:= TStringList.Create;
end;

destructor TImporter.Destroy;
begin
  FLines.Clear;
  FLines.Free;
  FStream.Free;
  inherited Destroy;
end;

end.
