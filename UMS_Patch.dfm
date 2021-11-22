object frmMS_Patch: TfrmMS_Patch
  Left = 0
  Top = 0
  Caption = 'Inserts MuseScore Lyrics into Midi File'
  ClientHeight = 254
  ClientWidth = 535
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poDesigned
  Visible = True
  OnCreate = FormCreate
  DesignSize = (
    535
    254)
  PixelsPerInch = 96
  TextHeight = 13
  object Memo1: TMemo
    Left = 0
    Top = 0
    Width = 535
    Height = 193
    TabStop = False
    Align = alTop
    Alignment = taCenter
    BevelEdges = []
    BevelInner = bvNone
    BevelOuter = bvNone
    BorderStyle = bsNone
    Color = clBtnFace
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -16
    Font.Name = 'Tahoma'
    Font.Style = []
    Lines.Strings = (
      ''
      'You have a score with lyrics open in MuseScore.'
      ''
      '- Save the score either as mscz or as mscx file.'
      
        '- Export the score as midi file with same name as the mscz / msc' +
        'x file'
      ''
      ''
      'Now, use the button "Open to Insert Lyrics" or'
      'drop .mscz/x file here.')
    ParentFont = False
    ReadOnly = True
    TabOrder = 0
  end
  object Button1: TButton
    Left = 200
    Top = 208
    Width = 131
    Height = 25
    Anchors = [akLeft, akTop, akRight, akBottom]
    Caption = 'Open to Insert Lyrics'
    TabOrder = 1
    OnClick = Button1Click
  end
  object OpenDialog1: TOpenDialog
    Filter = 'MuseScore Files|*.mscz;*.mscx'
    Left = 24
    Top = 168
  end
  object SaveDialog1: TSaveDialog
    Left = 480
    Top = 168
  end
end
