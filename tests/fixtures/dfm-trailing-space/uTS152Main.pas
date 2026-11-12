unit uTS152Main;

interface

uses
  Vcl.Forms, Vcl.Menus, Vcl.StdCtrls, System.Classes;

const
  /// <summary>A literal whose two trailing spaces are part of the value.</summary>
  TS152_PADDED = 'Pad  ';
  /// <summary>Control: a literal without trailing space.</summary>
  TS152_PLAIN = 'Plain';

type
  /// <summary>Form whose menu captions carry trailing spaces (O5).</summary>
  TfrmTS152Main = class(TForm)
    MainMenu1: TMainMenu;
    mnuOgp: TMenuItem;
    mnuPlain: TMenuItem;
    lblLead: TLabel;
  end;

var
  /// <summary>The auto-created main form.</summary>
  frmTS152Main: TfrmTS152Main;

implementation

{$R *.dfm}

end.
