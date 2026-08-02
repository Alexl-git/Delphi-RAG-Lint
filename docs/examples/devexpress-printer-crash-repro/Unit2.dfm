object Form2: TForm2
  Left = 0
  Top = 0
  Caption = 'Form2 (grid targeted by the report link)'
  ClientHeight = 300
  ClientWidth = 500
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  TextHeight = 13
  object cxGrid1: TcxGrid
    Left = 0
    Top = 0
    Width = 500
    Height = 300
    Align = alClient
    TabOrder = 0
    object cxGrid1TableView1: TcxGridTableView
    end
    object cxGrid1Level1: TcxGridLevel
      GridView = cxGrid1TableView1
    end
  end
end
