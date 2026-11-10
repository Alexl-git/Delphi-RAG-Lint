unit RG_149;

// Lane 150-RG2: Automation named arguments `Foo(Name := Value)` (grammar v1.4.9, node exprArgNamed).
// Calls here must neither raise assignment-shaped findings nor hide findings about the OTHER arguments.

interface

uses
  System.SysUtils, System.Classes, System.Variants;

type
  TRg149 = class
  private
    FWord: OleVariant;
    FUnusedPriv: Integer;
  public
    procedure Run(const pFile: string; pFormat: Integer);
    function Named(const pFile: string): Boolean;
  end;

implementation

procedure TRg149.Run(const pFile: string; pFormat: Integer);
var
  lTable: OleVariant;
  lSheet: OleVariant;
  lCount: Integer;
begin
  lSheet.SetBackgroundPicture(FileName := pFile);
  lTable.AutoFormat(Format := pFormat, Other := 1);
  lTable.AutoFormat(Format := pFormat, Other := pFormat);
  FWord.Documents.Open(FileName := pFile, ReadOnly := True);
  lCount := lSheet.Count(Item := 1);
  if lCount > 0 then
    lSheet.Delete(Index := lCount);
end;

function TRg149.Named(const pFile: string): Boolean;
var
  lSheet: OleVariant;
begin
  Result := lSheet.Save(FileName := pFile);
end;

end.