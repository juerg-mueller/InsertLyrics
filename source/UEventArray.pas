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

  TEventArray = class
  protected
    TrackName_: TAnsiStringArray; // 03
    TrackArr_: TTrackEventArray;
  public
    Text_: AnsiString;     // 01
    Copyright: AnsiString; // 02
    Instrument: AnsiString;// 04
    Maker: AnsiString;     // 06
    DetailHeader: TDetailHeader;
    SingleTrack: TMidiEventArray;
    ChannelArray: TChannelEventArray;

    constructor Create;
    destructor Destroy; override;
    function LoadMidiFromFile(FileName: string): boolean;
    function SaveMidiToFile(FileName: string; Lyrics: boolean): boolean;
    function SaveSimpleMidiToFile(FileName: string; Lyrics: boolean = false): boolean;
    procedure Clear;
    procedure Move_var_len; overload;
    function Transpose(Delta: integer): boolean; overload;
    procedure SetNewTrackCount(Count: integer);
    function TrackCount: integer;
    function GetHeaderTrack: TMidiEventArray;

    property TrackName: TAnsiStringArray read TrackName_;
    property TrackArr: TTrackEventArray read TrackArr_;
    property Track: TTrackEventArray read TrackArr_;

    class procedure ClearEvents(var Events: TMidiEventArray);
    class procedure AppendEvent(var MidiEventArray: TMidiEventArray;
                                const MidiEvent: TMidiEvent);
    class function SplitEventArray(var ChannelEvents: TChannelEventArray;
                                   const Events: TMidiEventArray;
                                   count: cardinal): boolean;
    class function MakePairs(var Events: TMidiEventArray): boolean;
    class procedure MakeOergeliEvents(var ChannelEvents: TChannelEventArray);
    class procedure MakeHarmonikaEvents(var ChannelEvents: TChannelEventArray);
    class procedure Move_var_len(var Events: TMidiEventArray); overload;
    class procedure MakeSingleTrack(var Events: TMidiEventArray; const ChannelEvents: TChannelEventArray); overload;
    class procedure MergeTracks(var Events1: TMidiEventArray; const Events2: TMidiEventArray);
    class procedure ReduceBass(var Events: TMidiEventArray);
    class function GetDuration(const Events: TMidiEventArray; Index: integer): integer;
    class function Transpose(var Events: TMidiEventArray; Delta: integer): boolean; overload;
    class function HasSound(const MidiEventArr: TMidiEventArray): boolean;
    class function InstrumentIdx(const MidiEventArr: TMidiEventArray): integer;
    class function PlayLength(const MidiEventArr: TMidiEventArray): integer;
    class function MakeSingleTrack(var MidiEventArray: TMidiEventArray; const TrackArr: TTrackEventArray): boolean; overload;
    class function GetDelayEvent(const EventTrack: TMidiEventArray; iEvent: integer): integer;
    class procedure MoveLyrics(var Events: TMidiEventArray);
    class procedure InsertSecond(var Events: TMidiEventArray; const Event: TMidiEvent);
  end;


  procedure CopyEventArray(var OutArr: TMidiEventArray; const InArr: TMidiEventArray);


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

function TEventArray.LoadMidiFromFile(FileName: string): boolean;
var
  Midi: TMidiDataStream;
begin
  result := false;
  Midi := TMidiDataStream.Create;
  try
    Midi.LoadFromFile(FileName);
    result := Midi.MakeEventArray(self);
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
    AppendMetaEvent(1, Text_);
  if Copyright <> '' then
    AppendMetaEvent(2, Copyright);
  if Maker <> '' then
    AppendMetaEvent(6, Maker);
end;

function TEventArray.SaveMidiToFile(FileName: string; Lyrics: boolean): boolean;
var
  i: integer;
  SaveStream: TMidiSaveStream;
begin
  SaveStream := TMidiSaveStream.Create;
  try
    if not Lyrics then
    begin
      SaveStream.SetHead(DetailHeader.DeltaTimeTicks);
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

function TEventArray.Transpose(Delta: integer): boolean;
var
  i: integer;
begin
  result := true;
  for i := 0 to Length(TrackArr)-1 do
    if not TEventArray.Transpose(TrackArr[i], Delta) then
      result := false;
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

class procedure TEventArray.MakeOergeliEvents(var ChannelEvents: TChannelEventArray);
const
  Diskant = 0;
  Bass1 = 1;
  Bass2 = 2;
var
  i, j, k: integer;
  max: integer;
  event: TMidiEvent;
  add: integer;
begin
  // Kanäle 0 und 3: diskant
  // Kanäle 1 und 4: 3-Klang Bass
  // Kanal 2:        Bass (monophon) / Grundton von Kanal 1 liegt eine Oktave höher
  // Kanal 5:        Kanal 2 genau eine Oktave höher

  // kurze Töne entfernen
  max := Length(ChannelEvents[Diskant]);
  i := 0;
  k := i;
  while (i < max) do
  begin
    event := ChannelEvents[Diskant][i];
    if (i+1 < max) and (event.Event = 9) and
       (event.var_len < 20) and
       (ChannelEvents[Diskant][i+1].command xor $10 = event.command) and
       (ChannelEvents[Diskant][i+1].d1 = event.d1) then
    begin
      if k > 0 then
      begin
        inc(ChannelEvents[Diskant][k-1].var_len, event.var_len);
        inc(ChannelEvents[Diskant][k-1].var_len, ChannelEvents[Diskant][i+1].var_len);
      end;
      inc(i, 2);
    end else begin
      ChannelEvents[Diskant][k] := event;
      inc(k);
      inc(i);
    end;
  end;
  SetLength(ChannelEvents[Diskant], k);

  // delete 3-Klang   (triad)
  ReduceBass(ChannelEvents[Bass1]);

  // Bass2 prellt!
  max := Length(ChannelEvents[Bass2]);
  if max > 0 then begin
    i := 0;
    while (i < max) and (ChannelEvents[Bass2][i].Event <> 9) do
      inc(i);
    k := i;
    while (i + 1 < max) do
    begin
      event := ChannelEvents[Bass2][i];
      j := i;
      while (j + 1 < max) and
            (event.d1 = ChannelEvents[Bass2][j + 1].d1) do
        inc(j);

      add := 0;
      while (j - i >= 3) do
      begin
        if (ChannelEvents[Bass2][i].var_len < 20) and
           (ChannelEvents[Bass2][i+1].var_len < 20) then
        begin
          inc(add, ChannelEvents[Bass2][i].var_len);
          inc(add, ChannelEvents[Bass2][i+1].var_len);
        end else
        if (ChannelEvents[Bass2][i+2].var_len < 20) then
        begin
          ChannelEvents[Bass2][k] := ChannelEvents[Bass2][i];
          inc (ChannelEvents[Bass2][k].var_len, add);
          inc (ChannelEvents[Bass2][k].var_len, ChannelEvents[Bass2][i+2].var_len);
          add := 0;
          ChannelEvents[Bass2][k+1] := ChannelEvents[Bass2][i+1];
          inc (ChannelEvents[Bass2][k+1].var_len, ChannelEvents[Bass2][i+3].var_len);
          inc(k, 2);
          inc(i, 2);
        end else begin
          ChannelEvents[Bass2][k] := ChannelEvents[Bass2][i];
          inc (ChannelEvents[Bass2][k].var_len, add);
          add := 0;
          ChannelEvents[Bass2][k+1] := ChannelEvents[Bass2][i+1];
          inc(k, 2);
        end;
        inc(i, 2);
      end;

      while i <= j do
      begin
        ChannelEvents[Bass2][k] := ChannelEvents[Bass2][i];
        inc (ChannelEvents[Bass2][k].var_len, add);
        add := 0;
        inc(i);
        inc(k);
      end;
    end;
    SetLength(ChannelEvents[Bass2], k);
    MergeTracks(ChannelEvents[Bass1], ChannelEvents[Bass2]);
    SetLength(ChannelEvents[Bass2], 0);
  end;


  for i := 3 to 15 do
    SetLength(ChannelEvents[i], 0);
end;

class procedure TEventArray.MakeHarmonikaEvents(var ChannelEvents: TChannelEventArray);
var
  i: integer;
begin
  MergeTracks(ChannelEvents[1], ChannelEvents[2]);
  SetLength(ChannelEvents[2], 0);

  for i := 3 to 15 do
    SetLength(ChannelEvents[i], 0);
end;


class procedure TEventArray.ReduceBass(var Events: TMidiEventArray);
var
  i, j, k, max, l, n: integer;
  event: array [0..3] of TMidiEvent;
  BassDone: boolean;

  procedure ExchangeD1(var e1, e2: TMidiEvent);
  var
    temp: byte;
  begin
    if e1.d1 > e2.d1 then
    begin
      temp := e1.d1; e1.d1 := e2.d1; e2.d1 := temp;
    end;
  end;

  procedure SetEvent(Idx: integer);
  begin
    if j + 1 < max then
    begin
      inc(j);
      event[Idx+1] := Events[j];
      if event[Idx].var_len < 8 then
      begin
        inc(event[Idx+1].var_len, event[Idx].var_len);
        event[Idx].var_len := 0;
      end;
    end;
  end;

begin
   max := Length(Events);
  i := 0;
  while (i < max) and (Events[i].Event <> 9) do
    inc(i);
  k := i;
  while (i < max) do
  begin
    for l := 0 to 3 do
      event[l].Clear;

    event[0] := Events[i];
    j := i;
    SetEvent(0);
    SetEvent(1);
    SetEvent(2);
    j := 1;
    while (j < 4) and
          (event[0].command = event[j].command) do
      inc(j);

    dec(j);
    for n := 0 to j-1 do
      if event[n].var_len <> 0 then
      begin
        j := n;
        break;
      end;


    for l := 0 to j-1 do
      for n := l + 1 to j do
        ExchangeD1(event[l], event[n]);

    BassDone := false;
    for l := 1 to j do
      if event[0].d1 + 12 = event[l].d1 then
      begin
        Events[k] := event[0];
        inc(k);
        inc(i);
        for n := 1 to j-1 do
          event[n-1] := event[n];
        dec(j);
        if j < 3 then
          inc(i);
        BassDone := true;
        break;
      end;

    if j >= 3 then
    begin
      if ((event[0].d1 + 4 = event[1].d1) and (event[1].d1 + 3 = event[2].d1)) or
         ((event[0].d1 + 3 = event[1].d1) and (event[1].d1 + 5 = event[2].d1)) or
         ((event[0].d1 + 5 = event[1].d1) and (event[1].d1 + 4 = event[2].d1)) then
      begin
        if (event[0].d1 + 3 = event[1].d1) and (event[1].d1 + 5 = event[2].d1) then
          dec(event[0].d1, 4)
        else
        if (event[0].d1 + 5 = event[1].d1) and (event[1].d1 + 4 = event[2].d1) then
          event[0].d1 := event[1].d1;
        if event[0].d1 > 56 then
          dec(event[0].d1, 12);
        event[0].var_len := event[2].var_len;
        inc(i, 3);
        Events[k] := event[0];
        inc(k);
        BassDone := true;
      end
    end;
    if not BassDone then
    begin
      Events[k] := Events[i];
      inc(k);
      inc(i);
    end;
  end;
  SetLength(Events, k);
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
    SetLength(Events1, 0);
    CopyEventArray(Events1, Events2);
    exit;
  end;
  CopyEventArray(temp, Events1);

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
        Events1[k] := Ev;
        Events1[k+1].Clear;
        inc(iEvent[i]);
        if (i = 1) and (iEvent[i] = 82) then
          k := k;

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
      Events1[k] := Events[i]^[iEvent[i]];
      inc(k);
      inc(iEvent[i]);
    end;
  end;

  SetLength(Events1, k);
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
{
  i := 0;
  while i < UsedEvents do
  begin
    while (i < UsedEvents) and not (Events[i].event in [8, 9]) do
      inc(i);
    if i >= UsedEvents then
      break;

    ev := Events[i].event;
    k := i;
    while (k + 1 < UsedEvents) and (Events[k + 1].event = ev) do
      inc(k);
    while i < k do
    begin
      if Events[i].var_len > 0 then
      begin
        inc(Events[k].var_len, Events[i].var_len);
        Events[i].var_len := 0;
      end;
      inc(i);
    end;
    inc(i);
  end;
 }
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
  //    Events[k].var_len := SmallestTicks*((Events[k].var_len  +
  //                         (SmallestTicks div 2)) div SmallestTicks);

  result := true;
end;

class function TEventArray.GetDuration(const Events: TMidiEventArray; Index: integer): integer;
var
  com, d1: integer;
begin
  result := 0;
  if (Index < 0) or (Index >= Length(Events)) or
     (Events[Index].Event <> 9) then
    exit;

  com := Events[Index].command xor $10;
  d1 := Events[Index].d1;
  repeat
    inc(result, Events[Index].var_len);
    inc(Index);
  until (Index >= Length(Events)) or
        ((Events[Index].command = com) and (Events[Index].d1 = d1));
end;

class function TEventArray.Transpose(var Events: TMidiEventArray; Delta: integer): boolean;
var
  i: integer;
begin
  result := true;
  if (Delta <> 0) and (abs(Delta) <= 20) then
    for i := 0 to Length(Events)-1 do
      if (Events[i].Event in [8, 9]) then
      begin
        if (Events[i].d1 + Delta > 20) and (Events[i].d1 + Delta <= 127) then
          Events[i].d1 := Events[i].d1 + Delta
        else
          result := false;
      end;
end;

class function TEventArray.GetDelayEvent(const EventTrack: TMidiEventArray; iEvent: integer): integer;
var
  i: integer;
  cmd: integer;
begin
  result := -1;
  cmd := EventTrack[iEvent].command;
  if (cmd shr 4) <> 9 then
    exit;

  result := EventTrack[iEvent].var_len;
  i := iEvent + 1;
  dec(cmd, $10);
  while (i < Length(EventTrack)) and
        ((EventTrack[i].command <> cmd) or
         (EventTrack[iEvent].d1 <> EventTrack[i].d1)) do
  begin
    inc(result, EventTrack[i].var_len);
    inc(i);
  end;
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
  i, j1, j2, k: integer;
  dist1, dist2: integer;
  Event: TMidiEvent;
begin
  i := 0;
  while i < Length(Events) do
  begin
    Event := Events[i];
    if (Event.command = $ff) and (Event.d1 = 5) then
    begin
      if Event.var_len > 0 then
      begin
        dist1 := 0;
        j1 := i;
        while (j1 > 0) do
        begin
          dec(j1);
          inc(dist1, Events[j1].var_len);
          if Events[j1].Event = 9 then
            break;
        end;
        dist2 := 0;
        j2 := i;
        while (j2 < Length(Events)) do
        begin
          inc(dist2, Events[j2].var_len);
          if Events[j2].Event = 9 then
            break;
          inc(j2);
        end;

        inc(Events[i-1].var_len, Event.var_len);
        Event.var_len := 0;

        if dist2 <= dist1 then
        begin
          if (j2 < Length(Events)) and (dist2 < 10) then
          begin
            dec(j2);
            for k := i to j2-1 do
              Events[k] := Events[k+1];
            Events[j2] := Event;
          end;
        end else
        if (j1 > 1) and (dist1 < 10) then
        begin
          for k := i-1 downto j1 do
            Events[k+1] := Events[k];
          Events[j1] := Event;
        end;
      end;
    end;
    inc(i);
  end;
end;

procedure CopyEventArray(var OutArr: TMidiEventArray; const InArr: TMidiEventArray);
var
  i: integer;
begin
  SetLength(OutArr, Length(InArr));
  for i := Low(InArr) to High(InArr) do
    OutArr[i] := InArr[i];

end;



end.

