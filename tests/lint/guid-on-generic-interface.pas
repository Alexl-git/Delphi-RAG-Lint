unit GuidOnGenericInterface;

interface

type
  IBad<T> = interface
    ['{1B6F0C52-7D2A-4E8B-A3C4-5F9E8D7C6B20}']
    function Get: T;
  end;

  IBad2<K, V> = interface(IInterface)
    ['{2C7A1D63-8E3B-4F9C-B4D5-6A0F9E8D7C31}']
    function Get(const AKey: K): V;
  end;

  IGood<T> = interface
    function Get: T;
  end;

  IPlain = interface
    ['{3D8B2E74-9F4C-4A0D-85E6-7B1A0F9E8D42}']
    procedure Run;
  end;

implementation

end.
