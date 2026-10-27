object LoginForm: TLoginForm
  object edtPassword: TEdit
    Left = 8
  end
  object edtPwdConfirm: TcxTextEdit
    Left = 8
  end
  object edtUserName: TEdit
    Left = 8
  end
  object edtPassMasked: TEdit
    PasswordChar = '*'
  end
  object edtPassCx: TcxTextEdit
    Properties.EchoMode = eemPassword
  end
  object lblPassword: TLabel
    Caption = 'Password'
  end
  object edtOldPass: TMaskEdit
    Left = 8
  end
end
