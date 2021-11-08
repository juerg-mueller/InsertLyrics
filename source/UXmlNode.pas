unit UXmlNode;

interface

uses
  SysUtils, Classes,
  UMyMemoryStream;

type

  KXmlAttr = class
    Name: string;
    Value: string;
  end;


  KXmlNode = class
    ChildNodes: array of KXmlNode;
    Attrs: array of KXmlAttr;
    Value: string;
    Name: string;   // = '': Text

    destructor Destroy; override;


    function AppendChildNode(Name_: string; Value_: string = ''): KXmlNode; overload;
    function AddChild(Name_: string; Value_: string = ''): KXmlNode;

    procedure InsertChildNode(Index: integer; Child_: KXmlNode);
    procedure AppendChildNode(Child_: KXmlNode); Overload;
    function ChildNodesCount: integer;

    procedure AppendAttr(Name_, Value_: string);
    function SaveToXmlFile(const FileName: string; Header: string = ''): boolean;
    procedure BuildStream(Stream: TMyMemoryStream; Level: integer; Wln: boolean);
    procedure RemoveChild(Child: KXmlNode);
    procedure PurgeChild(Index: integer);
    function AttributeIdx(Attribute: string): integer;
    function HasAttribute(Attribute: string): boolean;
    function GetAttribute(const Idx: string): string;
    procedure SetAttributes(const Idx: string; const Value: string);
    function LastNode: KXmlNode;
    function GetXmlValue: string;

    //MuseScore
    procedure MergeStaff(var Staff3: KXmlNode);
    function ExtractVoice(VoiceIndex: integer; StaffId: integer): KXmlNode;

    class function BuildMemoryStream(Root: KXmlNode): TMyMemoryStream;


    property Attributes[const Name: string]: string read GetAttribute write SetAttributes;
    property Count: integer read ChildNodesCount;
    property XmlValue: string read GetXmlValue;
  end;

const
  // Unicode
  // https://de.wikipedia.org/wiki/Unicodeblock_Notenschriftzeichen
  dotRest =         119149;

  doubleWholeRest = 119098;
  wholeRest =       119099;
  halfRest =        119100;
  quarterRest =     119101;

  wholeNoteHead =   119133;
  halfNoteHead =    119127;
  quarterNoteHead = 119128;

  function NewXmlAttr(Name_: string; Value_: string = ''): KXmlAttr;
  function NewXmlNode(Name_: string; Value_: string = ''): KXmlNode;

implementation


function NewXmlAttr(Name_: string; Value_: string = ''): KXmlAttr;
begin
  result := KXmlAttr.Create;
  result.Name := Name_;
  result.Value := Value_;
end;

destructor KXmlNode.Destroy;
var
  i: integer;
begin
  for i := 0 to Length(ChildNodes)-1 do
    ChildNodes[i].Free;
  Value := '';
  Name := '';

  inherited;
end;

function NewXmlNode(Name_: string; Value_: string = ''): KXmlNode;
begin
  result := KXmlNode.Create;
  SetLength(result.ChildNodes, 0);
  SetLength(result.Attrs, 0);
  result.Value := Value_;
  result.Name := Name_;
end;

procedure KXmlNode.InsertChildNode(Index: integer; Child_: KXmlNode);
var
  i: integer;
begin
  if (Index >= 0) and (Index <= Count) then
  begin
    SetLength(ChildNodes, Length(ChildNodes)+1);
    for i := Length(ChildNodes)-2 downto Index do
      ChildNodes[i+1] := ChildNodes[i];
    ChildNodes[Index] := Child_;
  end;
end;

procedure KXmlNode.AppendChildNode(Child_: KXmlNode);
begin
  InsertChildNode(Count, Child_);
end;

function KXmlNode.ChildNodesCount: integer;
begin
  result := Length(ChildNodes);
end;

function KXmlNode.AppendChildNode(Name_: string; Value_: string = ''): KXmlNode;
begin
  result := NewXmlNode(Name_, Value_);
  SetLength(ChildNodes, Length(ChildNodes) + 1);
  ChildNodes[Length(ChildNodes)-1] :=result;
end;

function KXmlNode.AddChild(Name_: string; Value_: string = ''): KXmlNode;
begin
  result := AppendChildNode(Name_, Value_);
end;

procedure KXmlNode.AppendAttr(Name_, Value_: string);
var
  Attr_: KXmlAttr;
begin
  Attr_ := NewXmlAttr(Name_, Value_);
  SetLength(Attrs, Length(Attrs)+1);
  Attrs[Length(Attrs)-1] := Attr_;
end;

procedure KXmlNode.RemoveChild(Child: KXmlNode);
var
  i: integer;
begin
  i := 0;
  while (i < Length(ChildNodes)) and (ChildNodes[i] <> Child) do
    inc(i);

  PurgeChild(i);
end;

procedure KXmlNode.PurgeChild(Index: integer);
var
  i: integer;
begin
  if (0 <= Index) and (Index < Count) then
  begin
    ChildNodes[Index].Free;
    for i := Index+1 to Count-1 do
      ChildNodes[i-1] := ChildNodes[i];
    SetLength(ChildNodes, Count-1);
  end;
end;

function KXmlNode.AttributeIdx(Attribute: string): integer;
begin
  result := Length(Attrs)-1;
  while (result >= 0) and (Attrs[result].Name <> Attribute) do
    dec(result);
end;

function KXmlNode.HasAttribute(Attribute: string): boolean;
begin
  result := AttributeIdx(Attribute) >= 0;
end;

function KXmlNode.GetAttribute(const Idx: string): string;
var
  i: integer;
begin
  result := '';
  i := AttributeIdx(Idx);
  if i >= 0 then
    result := Attrs[i].Value;
end;

procedure KXmlNode.SetAttributes(const Idx: string; const Value: string);
var
  i: integer;
begin
  i := AttributeIdx(Idx);
  if i >= 0 then
    Attrs[i].Value := Value
  else
    AppendAttr(Idx, Value);
end;

function KXmlNode.LastNode: KXmlNode;
begin
  result := nil;
  if High(ChildNodes) >= 0 then
    result := ChildNodes[High(ChildNodes)];
end;

procedure KXmlNode.BuildStream(Stream: TMyMemoryStream; Level: integer; Wln: boolean);
var
  i: integer;

  function Special: boolean;
  begin
    result := (name <> 'text') and (name <> 'appoggiatura');
  end;

begin
  if Wln then
    for i := 0 to Level-1 do
      Stream.WriteString('  ');

  Stream.WriteString('<');
  if Name = '' then
  begin
    Stream.WriteString('!-- ' + Value + ' -->');
    if Wln then
      Stream.Writeln;
  end else begin
    Stream.WriteString(Name);

    for i := 0 to Length(Attrs)-1 do
    begin
      Stream.WriteString(' ');
      Stream.WriteString(Attrs[i].Name);
      Stream.WriteString('="');
      Stream.WriteString(Attrs[i].Value);
      Stream.WriteString('"');
    end;

    if (Length(ChildNodes) > 0) or (Value <> '') {or
       ((Length(Attrs) = 0) and (Name <> 'startRepeat'))} then
    begin
      Stream.WriteString('>');
      if Wln and (Value = '') and Special then
        Stream.Writeln;

      for i := 0 to Length(ChildNodes)-1 do
      begin
        ChildNodes[i].BuildStream(Stream, Level+1, Wln and Special);
      end;
      if (Value <> '') then
        Stream.WriteString(Value)
      else
      if Wln and Special then
        for i := 0 to Level do
          Stream.WriteString('  ');
      Stream.WriteString('</');
      Stream.WriteString(Name);
    end else
      Stream.WriteString('/');
    Stream.WriteString('>');
    if Wln then
      Stream.Writeln;
  end;
end;

class function KXmlNode.BuildMemoryStream(Root: KXmlNode): TMyMemoryStream;
var
  Stream: TMyMemoryStream;

begin
  result := TMyMemoryStream.Create;
  Stream := result;
  Stream.Size := 10000000;
  while (Root.Name = '') and (Root.Count > 0) do
    Root := Root.ChildNodes[0];

  Root.BuildStream(Stream, 0, true);
  Stream.Size := Stream.Position;
end;

function KXmlNode.SaveToXmlFile(const FileName: string; Header: string): boolean;
var
  i, l: integer;
  Stream: TMyMemoryStream;
begin
  Stream := BuildMemoryStream(self);
  l := Length(Header);
  if l > 0 then  
  begin
    Stream.Size := Stream.Size + l;
    for i := Stream.Size - 1 downto 0 do
      PAnsiChar(Stream.Memory)[i+l] := PAnsiChar(Stream.Memory)[i];
    for i := 1 to l do
      PAnsiChar(Stream.Memory)[i-1] := AnsiChar(Header[i]);
  end;
  Stream.SaveToFile(FileName);
  result := true;
end;

function KXmlNode.GetXmlValue: string;

  procedure Change(from, to_: string);
  var
    p: integer;
  begin
    repeat
      p := Pos(from, result);
      if p > 0 then
      begin
        Delete(result, p, Length(from));
        Insert(to_, result, p);
      end;
    until p = 0;
  end;

begin
  result := Value;
  Change('&amp;', '&');
  Change('&lt;', '<');
  Change('&gt;', '>');

//  result := UTF8Encode(result);
end;



///////////////////////////// MuseScore ////////////////////////////////////////

procedure KXmlNode.MergeStaff(var Staff3: KXmlNode);
var
  mea1, mea3, p: integer;
  Child: KXmlNode;
begin
  if (Name <> 'Staff') or (Staff3.Name <> 'Staff') then
    exit;

  mea1 := -1;
  mea3 := -1;
  while (mea1 < Count) and (mea3 < Staff3.Count) do
  begin
    inc(mea1);
    while (mea1 < Count) and (ChildNodes[mea1].Name <> 'Measure') do
      inc(mea1);
    inc(mea3);
    while (mea3 < Staff3.Count) and (Staff3.ChildNodes[mea3].Name <> 'Measure') do
      inc(mea3);
    if (mea1 < Count) and (mea3 < Staff3.Count) then
    begin
      Child := Staff3.ChildNodes[mea3]; // measure
      // startRepeat und endRepeat überspringen
      p := Child.Count-1;
      while (p > 0) and (Child.ChildNodes[p].Name <> 'voice') do
        dec(p);
      ChildNodes[mea1].AppendChildNode(Child.ChildNodes[p]);
      Child.ChildNodes[p] := nil;
    end;
  end;
end;

function KXmlNode.ExtractVoice(VoiceIndex: integer; StaffId: integer): KXmlNode;
var
  i, iMeasure: integer;
  j, iVoice: integer;
  Voice: KXmlNode;
  Mea: KXmlNode;
  Ok: boolean;
begin
  Ok := false;
  result := NewXmlNode('Staff');
  result.AppendAttr('id', IntToStr(StaffId));
  iMeasure := 1;
  for i := 0 to Count-1 do
    if ChildNodes[i].Name = 'Measure' then
    begin
      result.AppendChildNode('', 'Measure ' + IntToStr(iMeasure));
      mea := result.AppendChildNode('Measure');
      inc(iMeasure);
      iVoice := -1;
      for j := 0 to ChildNodes[i].Count-1 do
      begin
        Voice := ChildNodes[i].ChildNodes[j];
        if Voice.Name = 'voice' then
          inc(iVoice);
        if iVoice = VoiceIndex then
        begin
          Mea.AppendChildNode(Voice);
          ChildNodes[i].ChildNodes[j] := nil;
          ChildNodes[i].PurgeChild(j);
          Ok := true;
          break;
        end;
      end;
    end;
  if not Ok then
    FreeAndNil(result);
end;

end.

