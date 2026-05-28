unit Docs;

interface

type
  /// <summary>Demo class for v0.16 doc extraction</summary>
  /// <remarks>Used by tests/run_v016_doctests.bat</remarks>
  TDocDemo = class
  public
    /// <summary>Computes the baz</summary>
    /// <param name="value">input, must be > 0</param>
    /// <returns>the baz</returns>
    /// <exception cref="EArgumentException">when value <= 0</exception>
    function GetBaz(value: Integer): string;

    {**
     * Adds two numbers.
     * @param A first number
     * @param B second number
     * @returns sum
     * @since 1.0
     *}
    function Add(A, B: Integer): Integer;

    ///1 One-liner doc above this method
    procedure DoOne;

    //1 Another one-liner style
    procedure DoTwo;

    /// Plain one-liner without XML
    procedure DoThree;

    FName: string; // user name trailing

    (** Older PasDoc paren style.
        @deprecated use NewProc instead *)
    procedure OldProc;
  end;

implementation

function TDocDemo.GetBaz(value: Integer): string;
begin Result := IntToStr(value); end;

function TDocDemo.Add(A, B: Integer): Integer;
begin Result := A + B; end;

procedure TDocDemo.DoOne;  begin end;
procedure TDocDemo.DoTwo;  begin end;
procedure TDocDemo.DoThree; begin end;
procedure TDocDemo.OldProc; begin end;

end.
