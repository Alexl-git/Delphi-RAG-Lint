unit uCopy;

{ Fixture of tests\fieldrepo\GridCopyTests.dpr (drag-lint 1.56 lane GCP-M): one grid with a table view that has
  events and columns, a banded table view with one column, and an empty card view. }

interface

uses
  System.SysUtils, System.Classes, System.Variants, Vcl.Controls, Vcl.Forms, Data.DB,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Param, FireDAC.Stan.Error, FireDAC.DatS,
  FireDAC.Phys.Intf, FireDAC.DApt.Intf, FireDAC.Comp.DataSet, FireDAC.Comp.Client,
  cxGraphics, cxControls, cxLookAndFeels, cxLookAndFeelPainters, cxStyles, cxCustomData, cxFilter, cxData,
  cxDataStorage, cxEdit, cxNavigator, cxDBData, cxDropDownEdit, cxGridLevel, cxClasses, cxGridCustomView,
  cxGridCustomTableView, cxGridTableView, cxGridBandedTableView, cxGridCardView, cxGridDBTableView,
  cxGridDBBandedTableView, cxGridDBCardView, cxGrid;

type
  TfrmCopy = class(TForm)
    cxGrid1: TcxGrid;
    tvMain: TcxGridDBTableView;
    tvMainCODE: TcxGridDBColumn;
    tvMainNAME: TcxGridDBColumn;
    tvMainQTY: TcxGridDBColumn;
    bvMain: TcxGridDBBandedTableView;
    bvMainNAME: TcxGridDBBandedColumn;
    cvMain: TcxGridDBCardView;
    cxGrid1Level1: TcxGridLevel;
    memMain: TFDMemTable;
    memMainCODE: TStringField;
    memMainNAME: TStringField;
    memMainQTY: TIntegerField;
    dsMain: TDataSource;
    procedure tvMainCellDblClick(Sender: TcxCustomGridTableView; ACellViewInfo: TcxGridTableDataCellViewInfo;
      AButton: TMouseButton; AShift: TShiftState; var AHandled: Boolean);
    procedure tvMainCustomDrawCell(Sender: TcxCustomGridTableView; ACanvas: TcxCanvas;
      AViewInfo: TcxGridTableDataCellViewInfo; var ADone: Boolean);
    procedure tvMainDataControllerCompare(ADataController: TcxCustomDataController; ARecordIndex1, ARecordIndex2,
      AItemIndex: Integer; const V1, V2: Variant; var Compare: Integer);
    procedure tvMainColumnHeaderClick(Sender: TcxGridTableView; AColumn: TcxGridColumn);
    procedure tvMainCustomization(Sender: TObject);
    procedure tvMainStylesGetContentStyle(Sender: TcxCustomGridTableView; ARecord: TcxCustomGridRecord;
      AItem: TcxCustomGridTableItem; var AStyle: TcxStyle);
    procedure tvMainCODEPropertiesChange(Sender: TObject);
    procedure tvMainCODEGetDisplayText(Sender: TcxCustomGridTableItem; ARecord: TcxCustomGridRecord;
      var AText: string);
    procedure tvMainNAMEGetDisplayText(Sender: TcxCustomGridTableItem; ARecord: TcxCustomGridRecord;
      var AText: string);
    procedure tvMainNAMEHeaderClick(Sender: TObject);
    procedure tvMainQTYCustomDrawCell(Sender: TcxCustomGridTableView; ACanvas: TcxCanvas;
      AViewInfo: TcxGridTableDataCellViewInfo; var ADone: Boolean);
    procedure bvMainNAMEGetDisplayText(Sender: TcxCustomGridTableItem; ARecord: TcxCustomGridRecord;
      var AText: string);
  public
    /// <summary>Names of the handlers that ran, in order, blank-separated.</summary>
    Calls: string;
  end;

var
  frmCopy: TfrmCopy;

implementation

{$R *.dfm}

procedure TfrmCopy.tvMainCellDblClick(Sender: TcxCustomGridTableView; ACellViewInfo: TcxGridTableDataCellViewInfo;
  AButton: TMouseButton; AShift: TShiftState; var AHandled: Boolean);
begin
  Calls := Calls + 'CellDblClick ';
end;

procedure TfrmCopy.tvMainCustomDrawCell(Sender: TcxCustomGridTableView; ACanvas: TcxCanvas;
  AViewInfo: TcxGridTableDataCellViewInfo; var ADone: Boolean);
begin
  Calls := Calls + 'CustomDrawCell ';
end;

procedure TfrmCopy.tvMainDataControllerCompare(ADataController: TcxCustomDataController; ARecordIndex1,
  ARecordIndex2, AItemIndex: Integer; const V1, V2: Variant; var Compare: Integer);
begin
  Compare := 0;
end;

procedure TfrmCopy.tvMainColumnHeaderClick(Sender: TcxGridTableView; AColumn: TcxGridColumn);
begin
  Calls := Calls + 'ColumnHeaderClick ';
end;

procedure TfrmCopy.tvMainCustomization(Sender: TObject);
begin
  Calls := Calls + 'Customization ';
end;

procedure TfrmCopy.tvMainStylesGetContentStyle(Sender: TcxCustomGridTableView; ARecord: TcxCustomGridRecord;
  AItem: TcxCustomGridTableItem; var AStyle: TcxStyle);
begin
  AStyle := nil;
end;

procedure TfrmCopy.tvMainCODEPropertiesChange(Sender: TObject);
begin
  Calls := Calls + 'CodeChange ';
end;

procedure TfrmCopy.tvMainCODEGetDisplayText(Sender: TcxCustomGridTableItem; ARecord: TcxCustomGridRecord;
  var AText: string);
begin
  AText := '[' + AText + ']';
end;

procedure TfrmCopy.tvMainNAMEGetDisplayText(Sender: TcxCustomGridTableItem; ARecord: TcxCustomGridRecord;
  var AText: string);
begin
  AText := UpperCase(AText);
end;

procedure TfrmCopy.tvMainNAMEHeaderClick(Sender: TObject);
begin
  Calls := Calls + 'NameHeaderClick ';
end;

procedure TfrmCopy.tvMainQTYCustomDrawCell(Sender: TcxCustomGridTableView; ACanvas: TcxCanvas;
  AViewInfo: TcxGridTableDataCellViewInfo; var ADone: Boolean);
begin
  if AViewInfo.Item = tvMainQTY then
    Calls := Calls + 'QtyDraw ';
end;

procedure TfrmCopy.bvMainNAMEGetDisplayText(Sender: TcxCustomGridTableItem; ARecord: TcxCustomGridRecord;
  var AText: string);
begin
  AText := LowerCase(AText);
end;

end.
