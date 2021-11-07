program InsertLyrics;

uses
  Vcl.Forms,
  UMS_Patch in 'UMS_Patch.pas' {frmMS_Patch},
  UEventArray in 'source\UEventArray.pas',
  UMidiDataStream in 'source\UMidiDataStream.pas',
  UMyMemoryStream in 'source\UMyMemoryStream.pas',
  UMyMidiStream in 'source\UMyMidiStream.pas',
  UXmlNode in 'source\UXmlNode.pas',
  UXmlParser in 'source\UXmlParser.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmMS_Patch, frmMS_Patch);
  Application.Run;
end.
