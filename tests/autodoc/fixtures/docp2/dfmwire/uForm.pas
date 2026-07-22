unit uForm;

// Fixture for Auto-Document Phase 2 Task 6 (DFM event-wiring fact): a form
// class with ONE control (Button1) wired to Button1Click via the paired
// uForm.dfm's `OnClick = Button1Click`, plus a second method (Unwired) that
// exists on the class but is NOT referenced by any On*-property in the .dfm
// at all -- expected to carry NO 'Handles:' fact line (absence over a
// guessed/wrong fact).
//
// NOTE the blank line between the two procedure decls below: it is
// deliberate, working around a PRE-EXISTING, orthogonal bug in
// DRagLint.Doc.Document's FindDocRegionAbove (confirmed empirically during
// this task, out of Task 6's scope to fix -- see the task report's
// "concerns" section): its gap-tolerance arithmetic (AAllowGap=1) checks
// only the LINE-NUMBER distance between a comment's end and a symbol's
// start, never whether an intervening line is itself ANOTHER declaration.
// With Button1Click and Unwired back-to-back (zero blank lines) and only
// Button1Click carrying a managed comment, Unwired's own gap-tolerance
// window reaches back across Button1Click's bare declaration line and
// misattributes Button1Click's comment as Unwired's own "existing" content
// -- so re-running `document --apply` deletes Button1Click's comment
// (replacing it with Unwired's own, empty-facts one). The blank line widens
// the gap by one line, which is enough for THIS AAllowGap=1 tolerance to
// correctly miss.

interface

uses
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, System.Classes;

type
  TForm1 = class(TForm)
    Button1: TButton;
    procedure Button1Click(Sender: TObject);

    procedure Unwired(Sender: TObject);
  end;

implementation

{$R *.dfm}

procedure TForm1.Button1Click(Sender: TObject);
begin
end;

procedure TForm1.Unwired(Sender: TObject);
begin
end;

end.
