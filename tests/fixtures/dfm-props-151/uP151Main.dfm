object frmP151Main: TfrmP151Main
  Left = 10
  Caption = 'Main '#252'ber'
  Font.Name = 'Tahoma'
  Anchors = [akLeft,
    akTop]
  Ratio = 1.5
  object btnOpen: TButton
    Caption = '&Open dialog'
    OnClick = btnOpenClick
  end
  object btnAct: TButton
    Action = actDlg
    OnClick = actDlgExecute
  end
  object btnMdi: TButton
    Caption = 'Gr'#252'n MDI'
    OnClick = btnMdiClick
  end
  object alMain: TActionList
    object actDlg: TAction
      Caption = 'Open &dialog via action'
      OnExecute = actDlgExecute
    end
    object actOth: TAction
      Caption = 'Other path'
    end
    object actChild: TAction
      Caption = 'Show ' +
        'child'
      OnExecute = actChildExecute
    end
  end
  object lstMain: TListBox
    Items.Strings = (
      'one'
      'it''s')
  end
  object sbMain: TStatusBar
    Panels = <
      item
        Text = 'p1'
        Width = 40
      end
      item
        Text = 'p2'
        Sub = <
          item
            Tag = 7
          end>
      end>
  end
  object imgMain: TImage
    Picture.Data = {
      0A54}
  end
  object btnHelp: TButton
    Caption = 'Help &route'
    OnClick = btnHelpClick
  end
  object btnHelp2: TButton
    Action = actHelp2
    OnClick = btnHelp2Click
  end
  object alHelp: TActionList
    object actHelp2: TAction
      Caption = 'Second &help'
    end
  end
end