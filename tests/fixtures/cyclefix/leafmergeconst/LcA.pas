unit LcA;

interface

uses
  LcB;

const
  /// <summary>Upper bound of TLcB.Slots.</summary>
  CLcTop = 3;

type
  /// <summary>Names TLcB.</summary>
  TLcA = class
  public
    Partner: TLcB;
  end;

implementation

end.
