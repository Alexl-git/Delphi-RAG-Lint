object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'Dispatch Forms'
  ClientHeight = 200
  ClientWidth = 300
  OnCreate = FormCreate
  object btnEdit: TButton
    Left = 8
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Edit Plan'
    TabOrder = 0
    OnClick = btnEditClick
  end
  object btnOpen: TButton
    Left = 8
    Top = 40
    Width = 75
    Height = 25
    Caption = 'Open C'
    TabOrder = 1
    OnClick = btnOpenClick
  end
  object btnOpenVar: TButton
    Left = 8
    Top = 72
    Width = 75
    Height = 25
    Caption = 'Open D'
    TabOrder = 2
    OnClick = btnOpenVarClick
  end
end