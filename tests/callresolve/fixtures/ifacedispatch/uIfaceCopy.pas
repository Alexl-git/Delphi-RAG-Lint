unit uIfaceCopy;

{ Fixture for run_interface_dispatch_bind.ps1 -- the TARGETS.
  ICopy has TWO implementors, so a resolver that fans an interface call out to
  implementors, or picks one by name, is visible. ICopy2 inherits ICopy, so a
  call through the derived interface must climb to ICopy.TransferFile. TSubCopy
  inherits TImplCopy without redeclaring the method. }

interface

type
  ICopy = interface
    ['{2C3A1B10-0000-4000-8000-00000000B001}']
    function TransferFile(const A: string): Boolean;
  end;

  ICopy2 = interface(ICopy)
    ['{2C3A1B10-0000-4000-8000-00000000B002}']
    procedure Extra;
  end;

  TImplCopy = class(TInterfacedObject, ICopy)
  public
    function TransferFile(const A: string): Boolean;
  end;

  TOtherCopy = class(TInterfacedObject, ICopy)
  public
    function TransferFile(const A: string): Boolean;
  end;

  TSubCopy = class(TImplCopy)
  end;

implementation

function TImplCopy.TransferFile(const A: string): Boolean;
begin
  Result:= A <> '';
end;

function TOtherCopy.TransferFile(const A: string): Boolean;
begin
  Result:= A = '';
end;

end.