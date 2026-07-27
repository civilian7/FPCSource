program Probe;

{$mode delphi}

uses
  Windows;

var
  GLib: HMODULE;
  GPtr: ^LongWord;
begin
  if ParamCount < 1 then
  begin
    WriteLn('사용법: Probe <package.dll>');
    Halt(2);
  end;

  GLib := LoadLibrary(PChar(ParamStr(1)));
  if GLib = 0 then
  begin
    WriteLn('로드 실패: ', GetLastError);
    Halt(1);
  end;

  GPtr := GetProcAddress(GLib, 'PACKAGEFLAGS');
  if GPtr = nil then
  begin
    WriteLn('PACKAGEFLAGS 없음');
    Halt(1);
  end;

  WriteLn('PACKAGEFLAGS = ', GPtr^);
end.
