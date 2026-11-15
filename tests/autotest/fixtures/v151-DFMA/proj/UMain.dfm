object MainForm: TMainForm
  Left = 0
  Top = 0
  ClientHeight = 200
  ClientWidth = 300
  OnCreate = FormCreate
  object lblUser: TLabel
    Caption = 'user'
  end
  object DataSource1: TDataSource
    DataSet = dmMain.qryItems
  end
end
