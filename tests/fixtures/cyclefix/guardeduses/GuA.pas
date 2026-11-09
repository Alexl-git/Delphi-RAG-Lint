unit GuA;

interface

uses
{$IFDEF GU_EXTRA}
  GuB,
{$ENDIF}
  System.SysUtils;

type
  /// <summary>Names itself.</summary>
  TGuA = class
  public
    /// <summary>The name.</summary>
    function Name: string;
  end;

implementation

function TGuA.Name: string;
begin
  Result := UpperCase('gu-a');
end;

end.