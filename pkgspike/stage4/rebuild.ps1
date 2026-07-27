# stage4 의 등록/언로드 재현 케이스 재빌드.
#
# stage4 전체가 아니라 REGPROCS·언로드 관련 픽스처만 짓는다
# (DirOk/DirBad/DirRun/RunPkg/Host1 은 컴파일러 진단용이라 여기 없다).
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
  Invoke-Ppc 'rtlpkg.dpk' @('-WB110000000', 'rtlpkg.dpk')

  Write-Host '유닛 선컴파일 (-FP 없이)'
  foreach ($u in @('BaseRegUnit.pas', 'RegUnit.pas', 'RegUnit2.pas')) {
    Invoke-Ppc $u @($u)
  }

  Write-Host '패키지'
  Invoke-Ppc 'BasePkg.dpk' @('-WB22000000', 'BasePkg.dpk')
  Invoke-Ppc 'RegPkg.dpk'  @('-WB23000000', 'RegPkg.dpk')

  Write-Host '호스트 (-FP 는 여기서만)'
  # host13 은 rtlpkg 만 링크한다. BasePkg 를 링크하면 핀 고정되어
  # 의존 언매핑이 일어나지 않고 회귀가 무의미해진다.
  Invoke-Ppc 'host13.pas' @('-FPrtlpkg', 'host13.pas')
  Invoke-Ppc 'Probe.pas'  @('Probe.pas')

  Write-Host '재빌드 완료' -ForegroundColor Green
}
finally {
  Pop-Location
}
