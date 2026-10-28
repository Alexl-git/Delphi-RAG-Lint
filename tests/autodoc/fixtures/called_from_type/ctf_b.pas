unit ctf_b;

interface

type
  { A second TOther: a call through a TOther-typed receiver is ambiguous by NAME. }
  TOther = class
  public
    procedure Add(X: Integer);
  end;

implementation

procedure TOther.Add(X: Integer); begin end;

end.
