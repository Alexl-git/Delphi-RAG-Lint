unit LmB;

interface

uses
  LmA;

type
  /// <summary>Descends from TLmBase and holds TLmRec by value: both must be complete before it.</summary>
  TLmChild = class(TLmBase)
  public
    Info: TLmRec;
    Name: string;
  end;

implementation

end.
