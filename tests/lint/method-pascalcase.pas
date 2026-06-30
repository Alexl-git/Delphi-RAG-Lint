unit mpc;
interface
procedure doThing;           // should fire: camelCase unit-level routine
procedure DoOther;           // clean
procedure FF;                // clean: short all-caps abbreviation
type
  TForm1 = class
  published
    procedure btnOkClick(Sender: TObject); // clean: published event handler
  end;
implementation
procedure doThing; begin end;
procedure DoOther; begin end;
procedure FF; begin end;
procedure TForm1.btnOkClick(Sender: TObject); begin end;
end.
