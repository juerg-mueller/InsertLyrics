unit UXmlParser;

interface

uses
  SysUtils, System.Zip, Dialogs, Forms, Windows,
  UMyMemoryStream, UXmlNode;

type
  // xml Grammar:
  //
  // body ::= [comment] "<" Name (attribute)* ( "/>" | ">" (body)* "</" Name ">")
  // attribute ::= AttributeId "="  """"  Value  """"
  // alternativ "comment":   <!-- comment -->
  KXmlParser = class(TMyMemoryStream)
    private
      stream: string;
      mActualPos: integer;      // actual parser position

      mErrorPos: integer;       // error position in mStream

    public
      mRecursionDepth: integer; // recursion depth within xml stream
      mStatusOk: boolean;      // parser status

      // GetAttribute results
      // GetAttribute parses the xml stream
      //   Attr="Value"
      //   ^     ^- mValueLen
      //   +------- mAttribute
      mValuePos: integer;
      mValueLen: integer;
      mAttribute: string;

      function SubString(Len: integer): string;

      constructor Create;

      procedure GetAttribute();

      procedure GetTagName(var TagName: string);

      procedure SetError(ErrPos: integer);

      // init. parser
      procedure Initialize();
      // parses header of the form:
      //   <?xml version="1.0" encoding="UTF-8"?> analysieren.
      function ParseXmlHeader(): boolean;

      // the character at the parser position might not be:
      //   0, '/', '>', or '<'
      function IsActualPositionValid: boolean;

      function GetIdentifier(var Id: string): integer;

      // skips blanks, line feeds and tabulator characters
      function SkipSpaces(): char;

      // skips comments
      // if the result is true: the next parsing character is an '<'
      function StartNewBody(XmlNode: KXmlNode = nil): boolean;

      // EinBody sollte mit "</BodyName>" abgeschlossen sein.
      procedure TestBodyEnd(TagName: string);

      // it expects Char at the parser position (all other characters are an
      // error)
      procedure NeedChar(c: Char);
      // true, if Char is at the parser position
      function TestChar(c: Char): boolean;
      // "/>": there is not a subbody
      // ">": there is a subbody
      function HasSubBody(): boolean;

      function GenerateFromXml(parent: KXmlNode): boolean;

      function Parse(Root: KXmlNode): boolean;

      function ParseStream_(Root: KXmlNode): boolean;

      class function ParseFile(FileName: string; var Root: KXmlNode): boolean;
      class function ParseStream(const Stream: TBytes; var Root: KXmlNode): boolean;
  end;



implementation


function IsFirstIdentChar(c: char): boolean;
begin
  result := CharInSet(c, ['_', 'a'..'z', 'A'..'Z']);
end;

function IsIdentifierChar(c: char): boolean;
begin
  result := CharInSet(c, ['_', 'a'..'z', 'A'..'Z', '0'..'9', '-']);
end;

////////////////////////////////////////////////////////////////////////////////
//
// KXmlParser
//
////////////////////////////////////////////////////////////////////////////////


function KXmlParser.SubString(Len: integer): string;
begin
  result := '';
  if mActualPos + Len <= Length(Stream) then
    result := Copy(Stream, mActualPos, Len);
end;

constructor KXmlParser.Create;
begin
  Initialize();
end;

procedure KXmlParser.Initialize();
begin
  mAttribute := '';
  // if there is no stream: it is an error
  mStatusOk := true;
  mActualPos := 1;
  mRecursionDepth := 0;
  mErrorPos := 0;
  mValuePos := 1;
  mValueLen := 0;
end;

procedure KXmlParser.GetAttribute();
var
  loop: boolean;
begin
  if not mStatusOk then
    exit;

  // attribute  ::= AttributeId "="  """"  Value  """"
  GetIdentifier(mAttribute);

  NeedChar('=');
  NeedChar('"');
  mValuePos := mActualPos;
  mValueLen := 0;
  if (mStatusOk) then
  begin
    Loop := true;
    repeat
      case Stream[mActualPos] of
        '"': begin
              inc(mActualPos);
              Loop := false;
             end;    // alles i.o.

        #0,
        '>',
        '<': begin
              SetError(mValuePos);
              Loop := false;
             end;

        else begin
              inc(mValueLen);
              inc(mActualPos);
             end;
      end;
    until not Loop;
  end;
end;

procedure KXmlParser.GetTagName(var TagName: string);
begin
  NeedChar('<');
  SkipSpaces();

  GetIdentifier(TagName);
end;

function KXmlParser.IsActualPositionValid: boolean;
begin
  result := false;
  if mStatusOk then
    result := not CharInSet(SkipSpaces(), [#0, '<', '/', '>']);
end;

function KXmlParser.GetIdentifier(var Id: string): integer;
begin
  result := 0;
  Id := '';
  if mStatusOk then
  begin
    SkipSpaces();

    if (IsFirstIdentChar(Stream[mActualPos])) then
    begin
      while (IsIdentifierChar(Stream[mActualPos])) do
      begin
        SetLength(Id, Length(Id)+1);
        Id[Length(Id)] := Stream[mActualPos];
        inc(result);
        inc(mActualPos);
      end;
    end;
    if result = 0 then
      SetError(-1);
  end;
end;

function KXmlParser.ParseXmlHeader(): boolean;
var
  Pos: integer;
begin
  result := false;
  if not mStatusOk or (Stream[mActualPos] = #0) then
    exit;

  // UTF-8 BOM (byte order mark)
  if SubString(3) = #$EF#$BB#$BF then
    inc(mActualPos, 3);

  if (Stream[mActualPos] = '<') and
     (Stream[mActualPos + 1] = '?') then
  begin
    NeedChar('<');
    NeedChar('?');
    if (mStatusOk) then
    begin
      SkipSpaces();
      if SubString(3) = 'xml' then
        inc(mActualPos, 3)
      else
        SetError(-1);
    end;
    if (mStatusOk) then
    begin
      Pos := mActualPos;

      while (Stream[mActualPos] <> #0) and (Stream[mActualPos] <> '?') do
        inc(mActualPos);
      if (Stream[mActualPos] = '?') then
        inc(mActualPos)
      else
        SetError(Pos);
    end;
    NeedChar('>');
  end;

  SkipSpaces();
  if (SubString(2) = '<!') and
     (SubString(4) <> '!--') then  // DOCTYPE
  begin
    while not CharInSet(Stream[mActualPos], [#0, '>']) do
      inc(mActualPos);
    if Stream[mActualPos] = '>' then
      inc(mActualPos);
  end;

  result := StartNewBody(nil);
end;

procedure KXmlParser.SetError(ErrPos: integer);
begin
  if (mStatusOk) then
  begin
    mStatusOk := false;
    if (ErrPos >= 0) then
      mErrorPos := ErrPos
    else
      mErrorPos := mActualPos;
  end;
end;

function KXmlParser.SkipSpaces(): char;
begin
  result := #0;
  if (mStatusOk) then
  begin
    result := Stream[mActualPos];
    while CharInSet(result, [#1..' ']) do
    begin
      inc(mActualPos);
      result := Stream[mActualPos];
    end;
  end;
end;

function KXmlParser.StartNewBody(XmlNode: KXmlNode): boolean;
var
  IsComment: boolean;
  c: char;
  Pos: integer;
begin
  result := false;
  if not mStatusOk then
    exit;

  repeat
    // [comment]                            skip comment
    Pos := mActualPos;

    while not CharInSet(Stream[mActualPos], [#0, '<', '>']) do
      inc(mActualPos);

    // "<" Name (attribute)* ...            a tag starts with "<"
    if (Stream[mActualPos] <> '<') then
    begin
      mActualPos := Pos;

      exit;    // '<' is missing (it is an error)
    end;
    // Stream[mActualPos] = '<'

    IsComment := false;
    // <!-- Sample XML file -->
    if SubString(4) = '<!--' then
    begin
      inc(mActualPos, 4);
      SkipSpaces();
      Pos := mActualPos;
      repeat
        if SubString(3) = '-->' then
        begin
          XmlNode.AppendChildNode('').Value := trim(Copy(Stream, Pos, mActualPos-Pos));
          inc(mActualPos, 3);
          IsComment := true;
          break;
        end;
        inc(mActualPos);
      until Stream[mActualPos] = #0;
      if not IsComment then
        exit;  // end of comment is missing (it is an error)
    end;

  until not IsComment;

  // test for body end:
  //   if there is "< /": jump back
  Pos := mActualPos;
  inc(mActualPos);
  c := SkipSpaces();
  mActualPos := Pos;
  if c = '/' then
  begin
    exit; // body end found
  end;
  // there is:
  //   itsXmlParser.mActualPos[0] = '<'

  result := mStatusOk;
end;

procedure KXmlParser.TestBodyEnd(TagName: string);
var
  EndTag: string;
  ErrPos: integer;
begin
  // test for "Body" end: </TagName>
  NeedChar('<');
  NeedChar('/');
  if (mStatusOk) then
  begin
    SkipSpaces();
    ErrPos := mActualPos;
    GetIdentifier(EndTag);
    if TagName <> EndTag then
      SetError(ErrPos);
  end;
  NeedChar('>');
end;

procedure KXmlParser.NeedChar(c: char);
begin
  if not TestChar(c) then
    SetError(-1);
end;

function KXmlParser.TestChar(c: char): boolean;
var
  ch: char;
begin
  result := false;
  if (mStatusOk) then
  begin
    ch := SkipSpaces();
    if (ch = c) then
    begin
      inc(mActualPos);
      result := true;
    end
  end;
end;

function KXmlParser.HasSubBody(): boolean;
var
  NoSubBody: boolean;
begin
  //                        v will be tested
  // "<" Name (attribute)* "/>"                   there is no subbody
  //
  // "<" Name (attribute)* ">" (body)* "</" Name ">"
  //                        ^ will be tested

  NoSubBody := TestChar('/');

  NeedChar('>');

  result := mStatusOk and not NoSubBody;
end;

function KXmlParser.GenerateFromXml(Parent: KXmlNode): boolean;
var
  TagName: string;
  Val: string;
  NewNode: KXmlNode;
  StartPos, EndPos: integer;
  i, MeasureNr: integer;
begin
  result := false;
  if not mStatusOk then
    exit;

  inc(mRecursionDepth);

  GetTagName(TagName);
  if mRecursionDepth = 1 then
  begin
    NewNode := Parent;
    NewNode.Name := TagName;
  end else
    NewNode := Parent.AppendChildNode(TagName);

  while IsActualPositionValid do
  begin
    GetAttribute();
    if (NewNode <> nil) then
    begin
      Val := Copy(Stream, mValuePos, mValueLen);
      NewNode.AppendAttr(mAttribute, Val);
    end;
  end;

  if (HasSubBody()) then
  begin
    SkipSpaces();

    StartPos := mActualPos;
    while (StartNewBody(NewNode)) do
    begin
      GenerateFromXml(NewNode);
      StartPos := mActualPos;
    end;

    if  Stream[mActualPos] = '<' then
    begin
      EndPos := mActualPos-1;
      while (EndPos >= StartPos) and
             (#0 < Stream[EndPos]) and (Stream[EndPos] <= ' ') do
        dec(EndPos);
      if (EndPos >= StartPos) then
      begin
        NewNode.Value := (Copy(Stream, StartPos, mActualPos - StartPos));
        if NewNode.Value <> trim(NewNode.Value) then
          NewNode.Value := NewNode.Value;
        if Copy(NewNode.Value, 1, 4) = '<!--' then
          NewNode.Value := '';
      end;
    end;

    if NewNode.Name = 'Staff' then
    begin
      MeasureNr := 1;
      for i := 0 to NewNode.Count-1 do
      begin
        if NewNode.ChildNodes[i].Name = 'Measure' then
        begin
          NewNode.ChildNodes[i].AppendAttr('id', IntToStr(MeasureNr));
          inc(MeasureNr);
        end;
      end;
    end;

    TestBodyEnd(TagName);
  end;

  dec(mRecursionDepth);

  result := mStatusOk;
end;

function KXmlParser.Parse(Root: KXmlNode): boolean;
var
  i: integer;
  MyStream: TMyMemoryStream;
  err: string;
begin
  Initialize();
  ParseXmlHeader();
  GenerateFromXml(Root);
  result := mStatusOk;
  if not Result and
     (0 <= mErrorPos) and (mErrorPos <= Length(Stream)) then
  begin
    err := 'xml-parser error pos: ';
    i := 0;
    while (i < 80) and (mErrorPos + i <= Length(Stream)) do
    begin
      err := err + Stream[mErrorPos + i];
      inc(i);
    end;
{$ifdef CONSOLE}
    system.writeln(err);
{$else}
    Application.MessageBox(PChar(err), 'Error', MB_OK);
{$endif}
  end else begin
    MyStream := KXmlNode.BuildMemoryStream(Root);
{$ifdef TEST}
    if MyStream <> nil then
      MyStream.SaveToFile('test_.mscx');
{$endif}
    MyStream.Free;
  end;
end;

function KXmlParser.ParseStream_(Root: KXmlNode): boolean;
var
  Utf8: AnsiString;
begin
  SetLength(Utf8, Size);
  Move(PByte(Memory)[0], Utf8[1], Size);

  stream := UTF8ToString(utf8);
  result := Parse(Root);
end;

class function KXmlParser.ParseFile(FileName: string; var Root: KXmlNode): boolean;
var
  Parser: KXmlParser;
  Zip_: TZipFile;
  outp: TBytes;
  ext: string;
begin
  result := false;
  if not FileExists(FileName) then
    exit;

  Root := KXmlNode.Create;
  Parser := KXmlParser.Create;
  try
    ext := ExtractFileExt(FileName);
    if (ext <> '.mscz') and (ext <> '.mxl') then
    begin
        Parser.LoadFromFile(FileName);

        result := Parser.ParseStream_(Root);
    end else begin
      Zip_ := TZipFile.Create;
      try
        Zip_.Open(Filename, zmRead);
        SetLength(Filename, Length(FileName)-Length(ext));
        if ext = '.mscz' then
          ext := '.mscx'
        else
          ext := 'xml';
        FileName := FileName + ext;
        Zip_.Read(ExtractFileName(FileName), Outp);
      finally
        Zip_.Free;
      end;
      result := Parser.ParseStream(Outp, Root);
      SetLength(Outp, 0);
    end;
  finally
    Parser.Free;
    if not result then
      FreeAndNil(Root);
  end;
end;

class function KXmlParser.ParseStream(const Stream: TBytes; var Root: KXmlNode): boolean;
var
  Parser: KXmlParser;
begin
  result := false;
  Root := KXmlNode.Create;
  Parser := KXmlParser.Create;
  try
    Parser.Size := Length(Stream);
    Move(Stream[0], PByte(Parser.Memory)[0], Length(Stream));
    result := Parser.ParseStream_(Root);
  finally
    Parser.Free;
    if not result then
      FreeAndNil(Root);
  end;

end;

end.


