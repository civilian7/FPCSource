program Probe;

{$mode delphi}

uses
  SysUtils,
  Windows;

type
  TProcedure = procedure;

  TRegProcRec = record
    Proc: TProcedure;
    UnitName: ^ShortString;
  end;

  PRegProcTable = ^TRegProcTable;
  TRegProcTable = record
    TableCount: PtrUInt;
    Procs: array[1..1024] of TRegProcRec;
  end;

var
  GLib: HMODULE;
  GPtr: ^LongWord;
  GTable: PRegProcTable;
  I: PtrUInt;
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

  WriteLn('이미지 베이스 = ', IntToHex(PtrUInt(GLib), 16));
  WriteLn('PACKAGEFLAGS = ', GPtr^);

  { "export 자체가 없다" 와 "export 는 있고 TableCount 가 0 이다" 는 다른 결과다.
    앞은 RUNONLY 라 설치 대상이 아니라는 뜻이고, 뒤는 설치할 수 있는 패키지인데
    등록할 유닛이 없다는 뜻이다. 둘을 구분해서 찍는다. }
  GTable := PRegProcTable(GetProcAddress(GLib, 'REGPROCS'));
  if GTable = nil then
  begin
    WriteLn('REGPROCS 없음 (export 자체가 없음)');
  end
  else
  begin
    WriteLn('REGPROCS 있음, TableCount = ', GTable^.TableCount);
    WriteLn('REGPROCS 유닛 ', GTable^.TableCount, '개');
    for I := 1 to GTable^.TableCount do
    begin
      { Proc 필드는 레코드의 첫 필드라 레코드 주소가 곧 그 필드의 주소다.
        delphi 모드에서 `@프로시저변수` 는 변수의 주소가 아니라 값(코드 주소)을
        주므로 이렇게 우회한다. 값이 DLL 이미지 범위 안이어야 정상이다. }
      WriteLn('  - ', GTable^.Procs[I].UnitName^,
              '  proc=', IntToHex(PPtrUInt(@GTable^.Procs[I])^, 16));
    end;
  end;
end.
