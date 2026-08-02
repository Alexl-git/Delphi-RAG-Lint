unit Unit1;

{ The main ribbon form, mirroring the real "uMain" (TfrmMAIN). It USES DMStyles
  for styling/printing. Opening THIS form in the RAD Studio designer is what
  crashes the IDE: the module load pulls in DMStyles, whose dxPrinter report
  link references a control on Form2 (another module), and resolving that
  cross-module link during design-time load faults. }

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
  , dxRibbonForm
  , dxBar
  , dxRibbon
  , dxRibbonSkins
  , cxGraphics
  , cxControls
  , cxLookAndFeels
  , cxLookAndFeelPainters
  , cxClasses
  , dxSkinsForm
  , dxCore
  , dxRibbonCustomizationForm
  , DMStyles
  ;

type
  TForm1 = class(TdxRibbonForm)
    dxRibbon1    : TdxRibbon    ;
    dxBarManager1: TdxBarManager;
    dxRibbon1Tab1: TdxRibbonTab ;
    private
    public
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

end.
