unit uLibGeneric;

{ Stand-in library unit of run_v151_RTTI2_generic.ps1: generic types only the library index knows. }

interface

type
  TLibPair<K, V> = record
    Key  : K;
    Value: V;
  end;

  TLibBag<T> = class(TObject)
  private
    FItem: T;
  public
    property Item: T read FItem write FItem;
  end;

implementation

end.
