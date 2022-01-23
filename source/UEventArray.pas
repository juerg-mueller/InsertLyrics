//
// Copyright (C) 2021 Jürg Müller, CH-5524
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation version 3 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with this program. If not, see http://www.gnu.org/licenses/ .
//
unit UEventArray;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface

uses
  UMyMidiStream, SysUtils, Classes, Forms;

type

  TMidiEventArray = array of TMidiEvent;
  PMidiEventArray = ^TMidiEventArray;
  TChannelEventArray = array [0..15] of TMidiEventArray;
  TTrackEventArray = array of TMidiEventArray;
  TAnsiStringArray = array of AnsiString;
  TStringArray = array of string;

  TEventArray = class
  protected
    TrackName_: TStringArray; // 03
    TrackArr_: TTrackEventArray;
  public
    Text_: String;     // 01
    Subtitle: string;
    Copyright: String; // 02
    Instrument: String;// 04
    Maker: String;     // 06
    DetailHeader: TDetailHeader;
    SingleTrack: TMidiEventArray;
    ChannelArray: TChannelEventArray;

    constructor Create;
    destructor Destroy; override;
    function LoadMidiFromFile(FileName: string; Lyrics: boolean): boolean;
    function SaveMidiToFile(FileName: string; Lyrics: boolean): boolean;
    function SaveSimpleMidiToFile(FileName: string; Lyrics: boolean = false): boolean;
    procedure Clear;
    procedure Move_var_len; overload;
    procedure SetNewTrackCount(Count: integer);
    function TrackCount: integer;
    function GetHeaderTrack: TMidiEventArray;
    procedure InsertTrack(Index: integer; Name: string; const MidiEvents: TMidiEventArray);

    property TrackName: TStringArray read TrackName_;
    property TrackArr: TTrackEventArray read TrackArr_;
    property Track: TTrackEventArray read TrackArr_;

    class procedure ClearEvents(var Events: TMidiEventArray);
    class procedure AppendEvent(var MidiEventArray: TMidiEventArray;
                                const MidiEvent: TMidiEvent);
    class function SplitEventArray(var ChannelEvents: TChannelEventArray;
                                   const Events: TMidiEventArray;
                                   count: cardinal): boolean;
    class function MakePairs(var Events: TMidiEventArray): boolean;
    class procedure Move_var_len(var Events: TMidiEventArray); overload;
    class procedure MakeSingleTrack(var Events: TMidiEventArray; const ChannelEvents: TChannelEventArray); overload;
    class procedure MergeTracks(var Events1: TMidiEventArray; const Events2: TMidiEventArray);
    class function HasSound(const MidiEventArr: TMidiEventArray): boolean;
    class function InstrumentIdx(const MidiEventArr: TMidiEventArray): integer;
    class function PlayLength(const MidiEventArr: TMidiEventArray): integer;
    class function MakeSingleTrack(var MidiEventArray: TMidiEventArray; const TrackArr: TTrackEventArray): boolean; overload;
    class procedure MoveLyrics(var Events: TMidiEventArray);
    class procedure InsertSecond(var Events: TMidiEventArray; const Event: TMidiEvent);
    class procedure CopyEventArray(var OutArr: TMidiEventArray; const InArr: TMidiEventArray);

  end;


implementation

uses
{$ifdef LINUX}
  Urtmidi,
{$else}
  AnsiStrings,
{$endif}
  UMidiDataStream;

constructor TEventArray.Create;
begin
  inherited;

  DetailHeader.Clear;
  Clear;
end;

destructor TEventArray.Destroy;
begin
  Clear;

  inherited;
end;

procedure TEventArray.Clear;
begin
  Text_ := '';
  Subtitle := '';
  Copyright := '';
  Instrument := '';
  Maker := '';

  DetailHeader.Clear;
  SetNewTrackCount(0);
end;

procedure TEventArray.SetNewTrackCount(Count: integer);
var
  i: integer;
begin
  for i := Count to Length(TrackArr)-1 do
  begin
    ClearEvents(TrackArr[i]);
    TrackName[i] := '';
  end;
  SetLength(TrackArr_, Count);
  SetLength(TrackName_, Count);
end;

function TEventArray.TrackCount: integer;
begin
  result := Length(TrackArr_);
end;

function TEventArray.LoadMidiFromFile(FileName: string; Lyrics: boolean): boolean;
var
  Midi: TMidiDataStream;
begin
  result := false;
  Midi := TMidiDataStream.Create;
  try
    Midi.LoadFromFile(FileName);
    result := Midi.MakeEventArray(self, Lyrics);
    MakeSingleTrack(SingleTrack, TrackArr);
    SplitEventArray(ChannelArray, SingleTrack, Length(SingleTrack));
  finally
    Midi.Free;
    if not result then
      Clear;
  end;
end;


function TEventArray.SaveSimpleMidiToFile(FileName: string; Lyrics: boolean): boolean;
var
  iTrack, iEvent: integer;
  Simple: TSimpleDataStream;
  Event: TMidiEvent;
  i: integer;
  d: double;
  takt, offset: integer;
  Events: TMidiEventArray;

  procedure WriteMetaEvent(const Event: TMidiEvent);
  var
    i: integer;
  begin
    with Simple do
    begin
      WriteString(Format('%5d Meta-Event %d %3d %3d',
                         [event.var_len, event.command, event.d1, event.d2]));
      for i := 0 to Length(event.Bytes)-1 do
        WriteString(' ' +IntToStr(event.bytes[i]));
      WriteString('   ');
      for i := 0 to Length(event.Bytes)-1 do
        if (event.bytes[i] > ord(' ')) or
           ((event.bytes[i] = ord(' ')) and
            (i > 0) and (i < Length(event.Bytes)-1)) then
          WriteString(Char(event.bytes[i]))
        else
          WriteString('.');
    end;
  end;

begin
  Simple := TSimpleDataStream.Create;
  try
    with Simple do
    begin
      with MidiHeader do
      begin
        Clear;
        FileFormat := 1;
        TrackCount := Length(TrackArr) + 1;
        Details := DetailHeader;
      end;
      WriteHeader(MidiHeader);

      if not Lyrics then
      begin
        WriteTrackHeader(0);

        Events := GetHeaderTrack;
        for i := 1 to Length(Events)-1 do
        begin
          WriteMetaEvent(Events[i]);
          Writeln;
        end;

        WritelnString('    0 ' + cSimpleMetaEvent + ' 255 47 0'); // end of track
      end;

      for iTrack := 0 to Length(TrackArr)-1 do
      begin
        WriteTrackHeader(TrackArr[iTrack][0].var_len);
        offset := TrackArr[iTrack][0].var_len;
        for iEvent := 1 to Length(TrackArr[iTrack])-1 do
        begin
          Event := TrackArr[iTrack][iEvent];
          if Event.Event = $f then
          begin
            WriteMetaEvent(Event);
          end else
          if Event.Event in [8..14] then
          begin
            if HexOutput then
              WriteString(Format('%5d $%2.2x $%2.2x $%2.2x',
                                 [event.var_len, event.command, event.d1, event.d2]))
            else
              WriteString(Format('%5d %3d %3d %3d',
                                 [event.var_len, event.command, event.d1, event.d2]));
          end;
          if Event.Event = 9 then
          begin
            takt := Offset div MidiHeader.Details.DeltaTimeTicks;
            if MidiHeader.Details.measureDiv = 8 then
              takt := 2*takt;
            d := MidiHeader.Details.measureFact;
            WriteString(Format('  Takt: %.2f', [takt / d + 1]));
          end;
          inc(offset, Event.var_len);
          WritelnString('');
        end;
        WritelnString('    0 ' + cSimpleMetaEvent + ' 255 47 0'); // end of track
      end;
    end;
    Simple.SaveToFile(FileName);
    result := true;
  finally
    Simple.Free;
  end;
end;

{
      META_TITLE           = 0x10,     // mscore extension
      META_SUBTITLE        = 0x11,     // mscore extension
      META_COMPOSER        = 0x12,   // mscore extension

}
function TEventArray.GetHeaderTrack: TMidiEventArray;

  procedure AppendMetaEvent(EventNr: integer; b: AnsiString);
  var
    Event: TMidiEvent;
  begin
    Event.MakeMetaEvent(EventNr, b);
    SetLength(result, Length(result)+1);
    result[Length(result)-1] := Event;
  end;

begin
  SetLength(result, 1);
  result[0].Clear;

  AppendMetaEvent($51, DetailHeader.GetMetaBeats51);
  if (DetailHeader.CDur <> 0) or DetailHeader.Minor then
    AppendMetaEvent($59, DetailHeader.GetMetaDurMinor59);
  AppendMetaEvent($58, DetailHeader.GetMetaMeasure58);

  if Text_ <> '' then
  begin
    AppendMetaEvent(1, UTF8encode(Text_));
  end;
  if Subtitle <> '' then
    AppendMetaEvent(1, UTF8encode(Subtitle));
  if Maker <> '' then
    AppendMetaEvent(6, UTF8encode(Maker));
end;

function TEventArray.SaveMidiToFile(FileName: string; Lyrics: boolean): boolean;
var
  i: integer;
  SaveStream: TMidiSaveStream;
begin
  SaveStream := TMidiSaveStream.Create;
  try
    SaveStream.SetHead(DetailHeader.DeltaTimeTicks);
    if not Lyrics then
    begin
      SaveStream.AppendTrackHead;
      SaveStream.AppendEvents(GetHeaderTrack);
      SaveStream.AppendTrackEnd(false);
    end;
    for i := 0 to Length(TrackArr)-1 do
    begin
      SaveStream.AppendTrackHead;
      SaveStream.AppendEvents(TrackArr[i]);
      SaveStream.AppendTrackEnd(false);
    end;
    SaveStream.Size := SaveStream.Position;
    SaveStream.SaveToFile(FileName);
  finally
    SaveStream.Free;
  end;
  result := true;
end;

procedure TEventArray.Move_var_len;
var
  i: integer;
begin
  for i := 0 to Length(TrackArr)-1 do
    TEventArray.Move_var_len(TrackArr[i]);
end;

procedure TEventArray.InsertTrack(Index: integer; Name: string; const MidiEvents: TMidiEventArray);
var
  i: integer;
begin
  if (Index >= 0) and (Index <= Length(TrackArr)) then
  begin
    SetLength(TrackArr_, Length(TrackArr)+1);
    SetLength(TrackName_, Length(TrackArr)+1);
    for i := Length(TrackArr)-2 downto Index do
    begin
      CopyEventArray(TrackArr_[i+1], TrackArr[i]);
      TrackName_[i+1] := TrackName_[i];
    end;
    TrackName_[Index] := Name;
    CopyEventArray(TrackArr_[Index], MidiEvents);
  end;
end;

////////////////////////////////////////////////////////////////////////////////

class function TEventArray.HasSound(const MidiEventArr: TMidiEventArray): boolean;
var
  i: integer;
begin
  result := false;
  i := 0;
  while (i < Length(MidiEventArr)) and not result do
    if MidiEventArr[i].Event = 9 then
      result := true
    else
      inc(i);
end;

class function TEventArray.InstrumentIdx(const MidiEventArr: TMidiEventArray): integer;
var
  i: integer;
begin
  result := -1;
  i := 0;
  while (i < Length(MidiEventArr)) do
    if MidiEventArr[i].Event = 12 then
    begin
      result := MidiEventArr[i].d1;
      break;
    end else
      inc(i);
end;

class function TEventArray.MakeSingleTrack(var MidiEventArray: TMidiEventArray; const TrackArr: TTrackEventArray): boolean;
var
  i: integer;
begin
  SetLength(MidiEventArray, 0);
  for i := 0 to Length(TrackArr)-1 do
    TEventArray.MergeTracks(MidiEventArray, TrackArr[i]);
  result := true;
end;

class function TEventArray.PlayLength(const MidiEventArr: TMidiEventArray): integer;
var
  i: integer;
begin
  result := 0;
  for i := 0 to Length(MidiEventArr)-1 do
    if MidiEventArr[i].var_len > 0 then
      inc(result, MidiEventArr[i].var_len);
end;

class procedure TEventArray.ClearEvents(var Events: TMidiEventArray);
var
  i: integer;
begin
  for i := 0 to Length(Events)-1 do
    SetLength(Events[i].bytes, 0);
  SetLength(Events, 0);
end;

class procedure TEventArray.AppendEvent(var MidiEventArray: TMidiEventArray;
                                        const MidiEvent: TMidiEvent);
begin
  SetLength(MidiEventArray, Length(MidiEventArray)+1);
  MidiEventArray[Length(MidiEventArray)-1] := MidiEvent;
end;

class function TEventArray.SplitEventArray(var ChannelEvents: TChannelEventArray;
                                           const Events: TMidiEventArray;
                                           count: cardinal): boolean;
var
  channel: byte;
  delay: integer;
  i, iMyEvent: integer;
begin
  result := false;
  for channel := 0 to 15 do
  begin
    SetLength(ChannelEvents[channel], 1000);
    ChannelEvents[channel][0].Clear;
    iMyEvent := 1;
    delay := 0;
    for i := 0 to count-1 do
    begin
      if (i = 0) and (Events[0].command = 0) then
      begin
        delay := Events[0].var_len; // mit wave synchronisieren
      end else
      if (Events[i].Channel = channel) and
         (Events[i].Event in [8..14]) then
      begin
        if High(ChannelEvents[channel]) < iMyEvent then
          SetLength(ChannelEvents[channel], 2*Length(ChannelEvents[channel]));

        ChannelEvents[channel][iMyEvent] := Events[i];
        inc(iMyEvent);
      end else
      if Events[i].Event in [8..14] then
      begin
        if iMyEvent > 1 then
          inc(ChannelEvents[channel][iMyEvent - 1].var_len, Events[i].var_len)
        else
          inc(delay, Events[i].var_len);
      end;
    end;
    if iMyEvent > 1 then
    begin
      ChannelEvents[channel][0].var_len := delay;
      SetLength(ChannelEvents[channel], iMyEvent);
      result := true;
    end else
      SetLength(ChannelEvents[channel], 0);
  end;
end;



class procedure TEventArray.Move_var_len(var Events: TMidiEventArray);
var
  iEvent: integer;
begin
  for iEvent := length(Events)-1 downto 1 do
    if not (Events[iEvent].Event in [8, 9]) then
    begin
      inc(Events[iEvent-1].var_len, Events[iEvent].var_len);
      Events[iEvent].var_len := 0;
    end;
end;

class procedure TEventArray.MakeSingleTrack(var Events: TMidiEventArray; const ChannelEvents: TChannelEventArray);
var
  i: integer;
begin
  SetLength(Events, 0);
  for i := 0 to 15 do
  begin
    TEventArray.MergeTracks(Events, ChannelEvents[i]);
  end;
end;

class procedure TEventArray.MergeTracks(var Events1: TMidiEventArray; const Events2: TMidiEventArray);
var
  i, k: integer;
  Ev: TMidiEvent;
  iEvent: array [0..1] of integer;
  iOffset: array [0..1] of integer;
  Offset: integer;
  temp: TMidiEventArray;
  Events: array [0..1] of PMidiEventArray;

  function MidiEvent(i: integer): TMidiEvent;
  begin
    result := Events[i]^[iEvent[i]];
  end;

  function Valid(i: integer): boolean;
  begin
    result := iEvent[i] < Length(Events[i]^);
  end;

begin
  if not TEventArray.HasSound(Events1) then
  begin
    Events1 := Events2;
    exit;
  end;
  temp := Events1;

  Events[0] := @temp;
  Events[1] := @Events2;
  SetLength(Events1, Length(Events1)+Length(Events2));

  for i := 0 to 1 do
  begin
    iEvent[i] := 0;
    iOffset[i] := 0;
  end;

  Offset := 0;
  k := 0;
  SetLength(Events1, 1);
  if (MidiEvent(0).command = 0) and
     (MidiEvent(1).command = 0) then
  begin
    for i := 0 to 1 do
    begin
      iOffset[i] := MidiEvent(i).var_len;
    end;
    if MidiEvent(0).var_len > MidiEvent(1).var_len then
      Events1[k].var_len := MidiEvent(1).var_len;
    Offset := Events1[k].var_len;
    inc(iEvent[0]);
    inc(iEvent[1]);
    inc(k);
  end;

  while Valid(0) and Valid(1) do
  begin
    for i := 0 to 1 do
    begin
      while Valid(i) and (iOffset[i] = Offset) do
      begin
        Ev := Events[i]^[iEvent[i]];
        if Ev.var_len > 0 then
          inc(iOffset[i], Ev.var_len);
        Ev.var_len := 0;
        SetLength(Events1, k+1);
        Events1[k] := Ev;
        inc(iEvent[i]);
        inc(k);
      end;
    end;
    inc(Offset);
    inc(Events1[k-1].var_len);
  end;

  i := 0;
  if Valid(1) then
    i := 1;
  if Valid(i) then
  begin
    if iOffset[i] > Offset then
      inc(Events1[k-1].var_len, iOffset[i] - Offset);
    while Valid(i) do
    begin
      SetLength(Events1, k+1);
      Events1[k] := Events[i]^[iEvent[i]];
      inc(k);
      inc(iEvent[i]);
    end;
  end;
  SetLength(temp, 0);
end;


class function TEventArray.MakePairs(var Events: TMidiEventArray): boolean;
const
  SmallestTicks = 60;
var
  i, k: integer;
  UsedEvents: integer;
begin
  UsedEvents := Length(Events);

  for i := 0 to UsedEvents-1 do
    if (Events[i].Event = 9) and (Events[i].d2 = 0) then
    begin
      Events[i].command := Events[i].command xor $10;
      Events[i].d2 := $40;
    end;

  i := 0;
  while i < UsedEvents do
  begin
    while (i < UsedEvents) and not (Events[i].event <> 8) do
      inc(i);
    while (i < UsedEvents) and not (Events[i].event = 8) do
      inc(i);
    if i >= UsedEvents then
      break;

    if (i > 0) and (Events[i-1].event = 8) and (Events[i-1].var_len < 20) then
    begin
      k := i;
      while (k < UsedEvents) and not (Events[k].event = 8) and
            (Events[k].var_len = 0) do
        inc(k);
      if k >= UsedEvents then
        dec(k);
      if i < k then
      begin
        inc(Events[k].var_len, Events[i].var_len);
        Events[i].var_len := 0;
      end;
    end;
  end;
  result := true;
end;

class procedure TEventArray.InsertSecond(var Events: TMidiEventArray; const Event: TMidiEvent);
var
  i: integer;
begin
  if Length(Events) < 1 then
    exit;

  SetLength(Events, Length(Events)+1);
  for i := Length(Events)-2 downto 1 do
    Events[i+1] := Events[i];
  Events[1] := Event;
end;


class procedure TEventArray.MoveLyrics(var Events: TMidiEventArray);
var
  i: integer;
  Event: TMidiEvent;
  Ok: boolean;
begin
  repeat
    Ok := false;
    i := 0;
    while i < Length(Events) do
    begin
      Event := Events[i];
      if Event.Event in [9, 11] then
      begin
        while (Event.var_len = 0) and (i < Length(Events)) and
              (Events[i+1].command = $ff) and (Events[i+1].d1 = 5) do
        begin
          Events[i] := Events[i+1];
          inc(Event.var_len, Events[i].var_len);
          Events[i].var_len := 0;
          Events[i+1] := Event;
          inc(i);
          Ok := true;
        end;
      end;
      inc(i);
    end;
  until not Ok;
end;

class procedure TEventArray.CopyEventArray(var OutArr: TMidiEventArray; const InArr: TMidiEventArray);
var
  i: integer;
begin
  SetLength(OutArr, Length(InArr));
  for i := Low(InArr) to High(InArr) do
    OutArr[i] := InArr[i];

end;



end.

