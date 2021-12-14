// Damit die Zuordnung Notensystem -- Midi-Track eindeutig ist, müssen die
// die Namen der Notensysteme eindeutig gewählt werden. Die Tracks erhalten
// dieselben Namen wie die Notensysteme.

// Resultat (Midi-Datei) mit verschiedenen Programme einlesen:
//
// Finale hat keine Lyrics-Unterstützung
//
// PrimusFree liest es fast korrekt ein: Keine UTF-8-Unterstützung es fehlen Silben
//
// Sibelius liest die Lyrics ein, setzt aber alle Strophen in dieselbe Linie
//
// MuseScore: Nur jeweils die erste Strophe und weist die Lyrics nicht dem richtigen Notensystem zu
unit UMS_Patch;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, ShellApi;

type
  TfrmMS_Patch = class(TForm)
    Memo1: TMemo;
    OpenDialog1: TOpenDialog;
    SaveDialog1: TSaveDialog;
    cbxKaraokeTrack: TCheckBox;
    Label1: TLabel;
    Label4: TLabel;
    cbxCodePage: TComboBox;
    procedure Button1Click(Sender: TObject);
    procedure WMDropFiles(var Msg: TWMDropFiles); message WM_DROPFILES;
    procedure FormCreate(Sender: TObject);
  private
    { Private-Deklarationen }
  public
    function Merge(FileName: string): boolean;
  end;

var
  frmMS_Patch: TfrmMS_Patch;

implementation

{$R *.dfm}

{$define _TEST}

uses
  UMyMidiStream, UMidiDataStream, UEventArray, UXmlParser, UXmlNode;


procedure TfrmMS_Patch.WMDropFiles(var Msg: TWMDropFiles);
var
  DropH: HDROP;               // drop handle
  DroppedFileCount: Integer;  // number of files dropped
  FileNameLength: Integer;    // length of a dropped file name
  FileName: string;           // a dropped file name
  i: integer;
  ext: string;
begin
  inherited;

  DropH := Msg.Drop;
  try
    DroppedFileCount := DragQueryFile(DropH, $FFFFFFFF, nil, 0);
    if (DroppedFileCount > 0) then
    begin
      for i := 0 to DroppedFileCount-1 do
      begin
        FileNameLength := DragQueryFile(DropH, i, nil, 0);
        SetLength(FileName, FileNameLength);
        DragQueryFile(DropH, i, PChar(FileName), FileNameLength + 1);
        ext := LowerCase(ExtractFileExt(Filename));
        if (ext = '.mscz') or
           (ext = '.mscx') or
           (ext = '.mid') then
        begin
          Merge(FileName);
        end;
      end;
    end;
  finally
    DragFinish(DropH);
  end;
  Msg.Result := 0;
end;

procedure TfrmMS_Patch.FormCreate(Sender: TObject);
begin
  DragAcceptFiles(Self.Handle, true);
end;

function TfrmMS_Patch.Merge(FileName: string): boolean;
var
  i, j, k, d: integer;
  Root, Score, Staff, Measure, Voice, Chord, Child, Child1, Child2: KXmlNode;
  Event: TMidiEvent;
  Events: TEventArray;
  iMidiEvent, iMidiLength: integer;
  MidiEvents: array of TMidiEventArray;
  delta, no: integer;
  duration, dots: string;
  style, value: string;
  Title, Composer, Subtitle: string;
  iLyricsTrack, iScore: integer;
  UsesLyrics: boolean;
  Hyphen: boolean;
  s: string;
  Ext: string;
  InTuplet: boolean;
  tupletFactor: double;
  strictKaraoke: boolean;
  nameCount: integer;
  trackName: array of string;
  instrumentName: array of string;
  vers: double;
  CodePage: integer;

  procedure AppendEvent;
  begin
    inc(iMidiLength);
    SetLength(MidiEvents[iMidiEvent-1], iMidiLength);
    MidiEvents[iMidiEvent-1][iMidiLength-1] := Event;
  end;

  procedure InsertFirstEvent;
  var
    i: integer;
  begin
    inc(iMidiLength);
    SetLength(MidiEvents[iMidiEvent-1], iMidiLength);
    for i := iMidiLength-2 downto 1 do
      MidiEvents[iMidiEvent-1][i+1] := MidiEvents[iMidiEvent-1][i];
    MidiEvents[iMidiEvent-1][1] := Event;
    MidiEvents[iMidiEvent-1][1].var_len := MidiEvents[iMidiEvent-1][0].var_len;
    MidiEvents[iMidiEvent-1][0].var_len := 0;
  end;

  function GetChild(Name: string; var Child: KXmlNode; Parent: KXmlNode): boolean;
  begin
    Child := Parent.hasChild(Name);
    result := Child <> nil;
  end;

begin
  result := false;
  strictKaraoke := cbxKaraokeTrack.Checked;
  case cbxCodePage.ItemIndex of
    0: CodePage := CP_UTF8;
    1: CodePage := 28591; // Ansi-Code iso-8859-1
    else CodePage := CP_UTF8;
  end;
  Ext := ExtractFileExt(FileName);
  SetLength(FileName, Length(FileName) - Length(Ext));

  if not FileExists(FileName + '.mid') then
  begin
    Application.MessageBox(
      PChar(Format('File "%s.mid" does not exist!',
                   [FileName])), 'Error', MB_OK);
    exit;
  end;

  Events := TEventArray.Create;
  if not Events.LoadMidiFromFile(FileName + '.mid', true) then
  begin
    Application.MessageBox(
      PChar(Format('File "%s.mid" not read!', [FileName])), 'Error', MB_OK);
    exit;
  end;

  Events.DetailHeader.smallestFraction := 64; // 64th
{$ifdef TEST}
  Events.SaveSimpleMidiToFile(FileName + '.txt', true);
{$endif}
  if not FileExists(FileName + '.mscz') and
     not FileExists(FileName + '.mscx') then
  begin
    Application.MessageBox(
      PChar(Format('Neither the file "%s.mscz" nor the file "%s.mscx exists!',
                   [FileName, FileName])), 'Error', MB_OK);
    exit;
  end;

  if ((Ext = '.mscx') or (Ext = '.mscz')) and
     FileExists(FileName + Ext) then
  begin
    if not KXmlParser.ParseFile(FileName + Ext, Root) then
      exit;
  end else
  if not KXmlParser.ParseFile(FileName + '.mscz', Root) and
     not KXmlParser.ParseFile(FileName + '.mscx', Root) then
    exit;

  s := Root.Attributes['version'];
  vers := StrToFloatDef(s, 1);
  if s = '' then
  begin
    Application.MessageBox('Error in MuseScore file!', 'Error');
    exit;
  end;
  if (vers < 3.0) then
  begin
    Application.MessageBox(PChar('MuseScore version ' + IntToStr(trunc(vers)) + ' is not supported!'), 'Error');
    exit;
  end;
  GetChild('Score', Score, Root);
  if (Score = nil) or
     not GetChild('Staff', Staff, Score) then
  begin
    Application.MessageBox('Error in MuseScore file!', 'Error');
    exit;
  end;

  Title := '';
  Composer := '';
  Subtitle := '';
  InTuplet := false;
  tupletFactor := 1.0;

  SetLength(trackName, 0);
  SetLength(instrumentName, 0);
  nameCount := 0;

  iLyricsTrack := 0;
  iMidiEvent := 0;
  iMidiLength := 0;
  SetLength(MidiEvents, 0);
  for iScore := 0 to Score.Count-1 do
  begin
    Staff := Score.ChildNodes[iScore];
    if Staff.Name = 'Part' then
    begin
      inc(nameCount);
      SetLength(trackName, nameCount);
      SetLength(instrumentName, nameCount);
      for i := 0 to Staff.Count-1 do
      begin
        Child := Staff.ChildNodes[i];
        if Child.Name = 'trackName' then
          trackName[nameCount-1] := Child.Value
        else
        if Child.Name = 'Instrument' then
          instrumentName[nameCount-1] := Child.Attributes['id'];
      end;
    end else
    if Staff.Name = 'Staff' then
    begin
      iMidiLength := 0;
      inc(iMidiEvent);
      SetLength(MidiEvents, iMidiEvent);
      Event.Clear;
      AppendEvent;
      UsesLyrics := false;
      i := StrToIntDef(Staff.Attributes['id'], -1);
      if (i > 0) and (i <= Length(trackName)) then
      begin
        dec(i);
        s := trackName[i];
        for i := 0 to Length(Events.TrackName)-1 do
          if (Events.TrackName[i] = s) and (s <> '') then
           begin
             iLyricsTrack := i;
             break;
           end;
      end;
      for i := 0 to Staff.Count-1 do
      begin
        Measure := Staff.ChildNodes[i];
        if Measure.Name = 'VBox' then
        begin
          for j := 0 to Measure.Count-1 do // VBox
          begin
            Child := Measure.ChildNodes[j];
            if Child.Name = 'Text' then
            begin
              style := '';
              value := '';
              for k := 0 to Child.Count-1 do
              begin
                if Child.ChildNodes[k].Name = 'style' then
                  style := Child.ChildNodes[k].Value
                else
                if Child.ChildNodes[k].Name = 'text' then
                  value := Child.ChildNodes[k].XmlValue;
              end;
              if style = 'Title' then
                Title := value
              else
              if style = 'Composer' then
                Composer := value
              else
              if style = 'Subtitle' then
                Subtitle := value;
            end;
          end;
        end else
        if Measure.Name = 'Measure' then
        begin
          // nur die erste Stimme (voice) wird untersucht
          if GetChild('voice', Voice, Measure) then
          begin
            for j := 0 to Voice.Count-1 do
            begin
              // berücksichtigt mehrere Lyrics im selben Chord
              Chord := Voice.ChildNodes[j];
              if Chord.Name = 'Tuplet' then
              begin
                InTuplet := false;
                if GetChild('normalNotes', Child, Chord) and
                   GetChild('actualNotes', Child1, Chord) and
                   (StrToIntDef(Child1.Value, 0) > 0) then
                begin
                  InTuplet := true;
                  tupletFactor := double(StrToIntDef(Child.Value, 1)) /
                                  double(StrToInt(Child1.Value));
                end;
              end else
              if Chord.Name = 'endTuplet' then
              begin
                InTuplet := false;
              end else
              if (Chord.Name = 'Chord') or
                 (Chord.Name = 'Rest') then
              begin
                if GetChild('duration', Child, Voice.ChildNodes[j]) or
                   GetChild('durationType', Child, Voice.ChildNodes[j]) then
                  begin
                  duration := Child.Value;
                  dots := '';
                  if GetChild('dots', Child, Chord) then
                    dots := Child.Value;

                  Child := Voice.ChildNodes[j];
                  no := 0;
                  for k := 0 to Child.Count-1 do
                  begin
                    Child1 := Child.ChildNodes[k];
                    if Child1.Name = 'Lyrics' then
                    begin
                      Child2 := Child1.HasChild('no');
                      if Child2 <> nil then
                      begin
                        // für Karaoke wird nur die erste Textzeile genommen,
                        // alse kein "no"
                        if strictKaraoke then
                          break;
                        while not strictKaraoke and
                              (no < StrToIntDef(Child2.Value, 0)) do
                        begin
                          // Muss mindestens ein Zeichen enthalten!
                          Event.MakeMetaEvent(5, ' ');
                          AppendEvent;
                          inc(no);
                        end;
                      end;
                      inc(no);
                      hyphen := GetChild('syllabic', Child2, Child1);
                      if hyphen then
                        hyphen := (Child2.Value = 'begin') or
                                  (Child2.Value = 'middle');
                      if GetChild('text', Child2, Child1) then
                      begin
                        s := UTF8Decode(Child2.XmlValue);
                        if not hyphen and (s <> '') then
                          s := s + ' ';
                        Event.MakeMetaEvent(5, s, CodePage);
                        AppendEvent;
                        if not UsesLyrics and
                           strictKaraoke then
                        begin
                          Event.MakeMetaEvent(3, 'Soft Karaoke');
                          InsertFirstEvent;
                          Event.MakeMetaEvent(1, '@KMIDI KARAOKE FILE');
                          InsertFirstEvent;
                          if Events.Copyright <> '' then
                          begin
                            Event.MakeMetaEvent(1, '@C' + UTF8encode(Events.Copyright));
                            InsertFirstEvent;
                          end;
                        end;
                        UsesLyrics := true;
                      end;
                    end;
                  end;
                end;
                if Pos('/', duration) = 0 then
                begin
                  d := GetFraction_(duration);
                  if d > 0 then
                    duration := '1/' + IntToStr(d);
                end;
                delta := Events.DetailHeader.GetChordTicks(duration, dots);
                if InTuplet then
                  delta := round(tupletFactor*delta);
                inc(MidiEvents[iMidiEvent-1][iMidiLength-1].var_len, delta);
              end;
            end;
          end;
        end;
      end;

      if (iLyricsTrack >= 0) and (iLyricsTrack < Length(Events.TrackArr)) and
         UsesLyrics then
      begin
        if strictKaraoke then
        begin
          Events.InsertTrack(0, 'Lyrics', MidiEvents[iMidiEvent-1]);
          break;
        end else begin
          TEventArray.MergeTracks(Events.TrackArr[iLyricsTrack], MidiEvents[iMidiEvent-1]);
          TEventArray.MoveLyrics(Events.TrackArr[iLyricsTrack]);
        end;
      end;
      inc(iLyricsTrack);
    end;
  end;

  if (Events.Text_ = '') then
    Events.Text_ := UTF8Encode(Title);
  if (Events.Subtitle = '') then
    Events.Subtitle := UTF8Encode(Subtitle);
  if (Events.Maker = '') then
    Events.Maker := UTF8Encode(Composer);

  SaveDialog1.FileName := FileName + '_.mid';
  if SaveDialog1.Execute then
  begin
    if FileExists(SaveDialog1.FileName) then
      if Application.MessageBox(PChar(SaveDialog1.FileName + ' exists! Overwrite it?'),
                                'Overwrite', MB_YESNO) <> ID_YES then
        exit;
    result := Events.SaveMidiToFile(SaveDialog1.FileName, true);
{$ifdef TEST}
    Events.SaveSimpleMidiToFile(FileName + '_.txt', true);
{$endif}
  end;
  SetLength(MidiEvents, 0);
  Root.Free;
  Events.Free;
end;

procedure TfrmMS_Patch.Button1Click(Sender: TObject);
var
  FileName: string;
begin
  if OpenDialog1.Execute then
  begin
    FileName := OpenDialog1.FileName;
    Merge(FileName);
  end;
end;

end.
