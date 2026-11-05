unit LcB;

interface

uses
  LcA;

type
  /// <summary>Names TLcA and CLcTop.</summary>
  TLcB = class
  public
    Partner: TLcA;
    Slots: array[0..CLcTop] of Integer;
  end;

implementation

end.
