inherited XuChild: TXuChild
  Caption = 'XuChild'
  inherited btnXuDead: TButton
    Caption = 'Still dead'
  end
  object btnXuChild: TButton
    Left = 8
    Top = 104
    Caption = 'Child'
    OnClick = xuChildBound
  end
end