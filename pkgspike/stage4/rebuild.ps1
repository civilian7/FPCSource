# stage4 의 등록/언로드 재현 케이스 재빌드.
#
# stage4 전체가 아니라 REGPROCS·언로드 관련 픽스처만 짓는다
# (DirOk/DirBad/DirRun/RunPkg/Host1 은 컴파일러 진단용이라 여기 없다).
#
# ⚠️ 그래서 이 스크립트는 stage4 를 완전히 되살리지 못한다. 아래
#    'Remove-Item *.ppu, *.o, *.a' 는 **디렉터리 전체**를 지우는데
#    DirOk/DirBad/DirRun/RunPkg/Host1 은 다시 짓지 않는다. 즉 그것들은
#    중간 산출물만 잃고 옛 .dll/.exe 로 남는다 - 이 스크립트가 없애려던
#    바로 그 함정(RTL 을 다시 지어도 stage4 가 조용히 옛 바이너리로
#    남는 것)이 그 픽스처들에는 그대로 남아 있다. 그쪽이 필요하면
#    손으로 다시 지어야 한다.
#
# stage3rt\rebuild.ps1 과 같은 순서 규칙을 따른다:
#   ① contained 유닛을 -FP **없이** 선컴파일
#   ② 패키지(.dpk)
#   ③ 호스트만 -FP 를 받는다
#
# 각 패키지는 -WB 로 ImageBase 를 분리한다.
#
#   .\rebuild.ps1

param(
  [string]$Ppc = 'C:\works\fpc-unleashed\compiler\ppcx64_pkg.exe'
)

$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot

function Invoke-Ppc {
  param([string]$What, [string[]]$PpcArgs)

  $out = & $Ppc @PpcArgs 2>&1
  if ($LASTEXITCODE -ne 0) {
    $out | Select-String -Pattern 'Error:|Fatal:' | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkRed }
    throw "$What 실패 (exit $LASTEXITCODE)"
  }

  Write-Host ("  [OK] {0}" -f $What)
}

try {
  Write-Host '중간 산출물 제거'
  Remove-Item *.ppu, *.o, *.a -ErrorAction SilentlyContinue

  Write-Host 'RTL 패키지'
  # -Xm: 맵 파일. 있어야 장애 주소를 "이미지 범위 안" 추정이 아니라
  # 심볼로 확정할 수 있다 (stage3rt 도 같은 이유로 넘긴다).
  Invoke-Ppc 'rtlpkg.dpk' @('-WB110000000', '-Xm', 'rtlpkg.dpk')

  Write-Host '유닛 선컴파일 (-FP 없이)'
  foreach ($u in @('BaseRegUnit.pas', 'RegUnit.pas', 'RegUnit2.pas', 'Reg2Unit.pas')) {
    Invoke-Ppc $u @($u)
  }

  Write-Host '패키지'
  Invoke-Ppc 'BasePkg.dpk' @('-WB22000000', 'BasePkg.dpk')
  Invoke-Ppc 'RegPkg.dpk'  @('-WB23000000', 'RegPkg.dpk')
  # Reg2Pkg 도 BasePkg 를 requires 한다 - host14 가 요구하는 공유 의존.
  Invoke-Ppc 'Reg2Pkg.dpk' @('-WB24000000', 'Reg2Pkg.dpk')

  Write-Host '호스트 (-FP 는 여기서만)'
  # host13/host14 는 rtlpkg 만 링크한다. BasePkg 를 링크하면 핀 고정되어
  # 의존 언매핑이 일어나지 않고 회귀가 무의미해진다.
  Invoke-Ppc 'host13.pas' @('-FPrtlpkg', 'host13.pas')
  Invoke-Ppc 'host14.pas' @('-FPrtlpkg', 'host14.pas')
  Invoke-Ppc 'Probe.pas'  @('Probe.pas')

  Write-Host '재빌드 완료' -ForegroundColor Green
}
finally {
  Pop-Location
}
