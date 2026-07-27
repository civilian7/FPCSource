program host2;

{$mode delphi}

uses
  BaseUnit,
  SalesUnit;

var
  GBase: TBase;
begin
  { 생성: TSales 의 VMT 는 SalesPkg.dll, 조상 코드는 CommonPkg.dll }
  GBase := TSales.Create('acme');

  { 가상 디스패치 - 자식 override 가 불려야 한다 }
  WriteLn(GBase.Describe);

  { is / as - VMT 상속 사슬을 DLL 경계 너머로 걷는다 }
  WriteLn('is TSales  : ', GBase is TSales);
  WriteLn('is TBase   : ', GBase is TBase);
  WriteLn('ClassName  : ', GBase.ClassName);
  WriteLn('Parent     : ', GBase.ClassParent.ClassName);

  (GBase as TSales).Free;
  WriteLn('host2 ok');
end.
