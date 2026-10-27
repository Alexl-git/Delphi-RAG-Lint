unit DF.Base;

{ dispatch-forms fixture (spec 2026-10-26-extract-polymorphic-form-launches).
  IPlan.EditForm is what a caller binds; the form is opened by an OVERRIDE
  that nobody calls directly. }

interface

uses
  System.SysUtils;

type
  IPlan = interface
    ['{6C1F7F0A-3D5B-4E2B-9B1D-0D5A2E3C4B11}']
    procedure EditForm;
  end;

  TPlanBase = class(TInterfacedObject, IPlan)
  public
    procedure EditForm; virtual;
  end;

  { E1 negative controls: genuine subclasses stay kind=class. }
  EBar = class(Exception);
  EFoo = class(EBar) end;

implementation

procedure TPlanBase.EditForm;
begin
end;

end.
