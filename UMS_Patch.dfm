object frmMS_Patch: TfrmMS_Patch
  Left = 0
  Top = 0
  Caption = 'Inserts MuseScore Lyrics into Midi File'
  ClientHeight = 255
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
    255)
  PixelsPerInch = 96
  TextHeight = 13
  object Label1: TLabel
    Left = 144
    Top = 136
    Width = 244
    Height = 24
    Alignment = taCenter
    Anchors = [akLeft, akTop, akRight]
    Caption = 'Now drop .mscz/x file here.'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clRed
    Font.Height = -20
    Font.Name = 'Tahoma'
    Font.Style = []
    ParentFont = False
  end
  object Memo1: TMemo
    Left = 0
    Top = 0
    Width = 535
    Height = 105
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
      '')
    ParentFont = False
    ReadOnly = True
    TabOrder = 0
  end
  object cbxKaraokeTrack: TCheckBox
    Left = 132
    Top = 203
    Width = 272
    Height = 20
    Alignment = taLeftJustify
    Anchors = [akLeft, akTop, akRight]
    Caption = 'Lyrics in karaoke track (kar format)'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -16
    Font.Name = 'Tahoma'
    Font.Style = []
    ParentFont = False
    TabOrder = 1
  end
  object OpenDialog1: TOpenDialog
    Filter = 'MuseScore Files|*.mscz;*.mscx'
    Left = 24
    Top = 8
  end
  object SaveDialog1: TSaveDialog
    Left = 480
    Top = 16
  end
end
