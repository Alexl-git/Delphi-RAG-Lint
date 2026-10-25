object frmMain8: TfrmMain8
  Left = 0
  Top = 0
  Caption = 'Demo Eight'
  ClientHeight = 300
  ClientWidth = 400
  Menu = mnuMain
  OnCreate = FormCreate
  object btnSide: TButton
    Left = 8
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Side'
    OnClick = btnSideClick
  end
  object mnuMain: TMainMenu
    object mnuTools: TMenuItem
      Caption = '&Tools'
      object mnuDesign: TMenuItem
        Caption = 'Design Item'
        OnClick = mnuDesignClick
      end
    end
  end
end
