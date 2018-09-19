program RawInputTest;

uses
  Forms,
  fmMain in 'fmMain.pas' {Form1},
  ftRawInputInterceptor in 'ftRawInputInterceptor.pas',
  unRawInput in 'unRawInput.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
