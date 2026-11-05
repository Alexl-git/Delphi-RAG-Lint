unit LmA;

interface

uses
  LmB;

type
  /// <summary>Holds a child by reference; the child holds this record by value.</summary>
  TLmRec = record
    Owner: TLmChild;
    Size: Integer;
  end;

  /// <summary>The ancestor of TLmChild; names its own descendant.</summary>
  TLmBase = class
  public
    Child: TLmChild;
    Tag: Integer;
  end;

/// <summary>Builds a child and returns its name.</summary>
/// <returns>The name.</returns>
function LmMakeName: string;

implementation

uses
  System.SysUtils;

function LmMakeName: string;
begin
  var C:= TLmChild.Create;
  try
    C.Info.Size:= 3;
    C.Name:= 'child';
    Result:= C.Name + IntToStr(C.Info.Size);
  finally
    C.Free;
  end;
end;

end.
