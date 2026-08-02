unit Unit2;

{ The "other form" that owns the grid targeted by the datamodule's report link.
  Its existence in a separate module is essential to the repro: the report link
  in DMStyles references Form2.cxGrid1 across module boundaries. }

interface

uses
  Winapi.Windows
  , Winapi.Messages
  , System.SysUtils
  , System.Variants
  , System.Classes
  , Vcl.Graphics
  , Vcl.Controls
  , Vcl.Forms
  , Vcl.Dialogs
  , cxGraphics
  , cxControls
  , cxLookAndFeels
  , cxLookAndFeelPainters
  , cxStyles
  , cxCustomData
  , cxData
  , cxEdit
  , cxClasses
  , cxGridLevel
  , cxGridCustomView
  , cxGridCustomTableView
  , cxGridTableView
  , cxGrid
  ;

type
  TForm2 = class(TForm)
    cxGrid1          : TcxGrid         ;
    cxGrid1Level1    : TcxGridLevel    ;
    cxGrid1TableView1: TcxGridTableView;
  end;

var
  Form2: TForm2;

implementation

{$R *.dfm}

end.
