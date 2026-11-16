unit uResShadow;

{ Negative side of run_v1511_RES_library_reads.ps1: this unit declares its own
  GResOwn and ResOwn, so a bare read of either is the project's and must never
  be answered from the library, although ResLib is in the uses clause. }

interface

uses
  ResLib;

type
  { A MEMBER named like the library object (ORM3: a property APPLICATION on four classes).
    It is visible only through a TResOther, so a bare GResApp elsewhere is still the library's. }
  TResOther = class
  private
    FValue: Integer;
  public
    property GResApp: Integer read FValue;
  end;

var
  GResOwn: Integer;

function ResOwn: Boolean;
function ReadOwn: Integer;
function CallOwn: Boolean;

implementation

function ResOwn: Boolean;
begin
  Result := False;
end;

function ReadOwn: Integer;
begin
  Result := GResOwn + 1;
end;

function CallOwn: Boolean;
begin
  Result := ResOwn;
end;

end.
