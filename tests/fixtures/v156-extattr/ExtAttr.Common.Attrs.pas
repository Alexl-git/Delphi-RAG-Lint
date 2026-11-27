unit ExtAttr.Common.Attrs;

{ Fixture for run_v156_EXTATTR.ps1: the attribute classes the consumer unit applies. }

interface

type
  InjectAttribute = class(TCustomAttribute)
  end;

  NamedAttribute = class(TCustomAttribute)
  private
    FName: string;
  public
    constructor Create(const pName: string);
    property Name: string read FName;
  end;

  WeakRefAttribute = class(TCustomAttribute)
  end;

  TagAttribute = class(TCustomAttribute)
  end;

const
  DefaultName = 'main';

implementation

constructor NamedAttribute.Create(const pName: string);
begin
  inherited Create;
  FName:= pName;
end;

end.
