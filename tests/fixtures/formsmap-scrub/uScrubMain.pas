unit uScrubMain;

// Fixture for the FormsMap comment-scrub guard.
//
// The launch of TfrmRealS lives in OpenReal, which no control is bound to.
// CaptionForHandler therefore falls through to its step (3): a text scan of
// this unit for callers of OpenReal, first match wins. THREE handlers appear
// to call it and only the LAST one really does -- the two above are comments,
// in all three Delphi comment forms. A scanner reading raw text captions the
// navigation edge 'Brace'; one that scrubs first captions it 'Real'.
//
// Handler order is load-bearing: the decoys must come FIRST, or the real call
// wins by position and the test passes for the wrong reason.
//
// The blank lines below are load-bearing too, not formatting. A re-split of
// the scrubbed text that drops empty elements collapses them, which shortens
// the line array and silently disables the scrubbing on every real file.

interface

uses Vcl.Forms, Vcl.StdCtrls, uScrubReal;

type
  TfrmRootS = class(TForm)
    btnBrace: TButton;
    btnGhost: TButton;
    btnReal: TButton;
    procedure btnBraceClick(Sender: TObject);
    procedure btnGhostClick(Sender: TObject);
    procedure btnRealClick(Sender: TObject);
  public
    procedure OpenReal;
  end;

var frmRootS: TfrmRootS;

implementation

{$R *.dfm}

procedure TfrmRootS.OpenReal;
begin

  TfrmRealS.Create(Self).ShowModal;

end;

procedure TfrmRootS.btnBraceClick(Sender: TObject);
begin

  { a brace comment spanning two lines, the second of which says
    OpenReal; and is still not code }

end;

procedure TfrmRootS.btnGhostClick(Sender: TObject);
begin

  // OpenReal;

  (* OpenReal; *)

end;

procedure TfrmRootS.btnRealClick(Sender: TObject);
begin

  OpenReal;

end;

end.
