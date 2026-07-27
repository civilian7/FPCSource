program host10;

{ 검증 1: host8 크래시의 원인이 "CommonPkg 가 SalesPkg 의존성으로만 로드되어
  FreeLibrary(SalesPkg) 에 딸려 언맵" 이라면, CommonPkg 를 미리 핀해두면
  FreeLibrary 후에도 GetClass 순회(잔존 TPluginBase 항목 포함)가 안전해야 한다. }

{$mode delphi}

uses
  Windows,
  SysUtils,
  Classes,
  SharedIntf;

type
  TProcedure = procedure;
  TInitFinalRec = record
    InitProc: TProcedure;
    FinalProc: TProcedure;
    UnitName: ^ShortString;
  end;
  PInitFinalTable = ^TInitFinalTable;
  TInitFinalTable = record
    TableCount: PtrUInt;
    InitCount: PtrUInt;
    Procs: array[1..1024] of TInitFinalRec;
  end;

procedure Probe(const AName: string);
var
  LCls: TPersistentClass;
begin
  LCls := GetClass(AName);
  if LCls = nil then
    WriteLn(Format('    %-16s (none)', [AName]))
  else
    WriteLn(Format('    %-16s vmt=%p', [AName, Pointer(LCls)]));
end;

var
  GPin: HMODULE;
  GLib: HMODULE;
  GTable: PInitFinalTable;
  I: PtrUInt;
begin
  { CommonPkg 를 명시적으로 핀 - FreeLibrary(SalesPkg) 가 언맵하지 못하게 }
  GPin := LoadLibrary('CommonPkg.fpl');
  WriteLn('CommonPkg pinned : ', GPin <> 0);

  GLib := LoadLibrary('SalesPkg.fpl');
  GTable := PInitFinalTable(GetProcAddress(GLib, 'INITFINAL'));
  for I := 1 to GTable^.TableCount do
  begin
    if Assigned(GTable^.Procs[I].InitProc) then
      GTable^.Procs[I].InitProc();
    GTable^.InitCount := I;
  end;

  while GTable^.InitCount > 0 do
  begin
    Dec(GTable^.InitCount);
    if Assigned(GTable^.Procs[GTable^.InitCount + 1].FinalProc) then
      GTable^.Procs[GTable^.InitCount + 1].FinalProc();
  end;

  FreeLibrary(GLib);

  WriteLn('== FreeLibrary 후 (CommonPkg 핀 유지) ==');
  Probe('TSalesPlugin');
  Probe('TPluginBase');
  Probe('TPersistent');

  WriteLn('host10 ok');
end.
