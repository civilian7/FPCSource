# stage3rt 재현 케이스 전체 재빌드.
#
# 컴파일러를 고칠 때마다 필요하다. 특히 .pcp 형식이 바뀌면 옛 .pcp 는
# "Error reading PCP-File" 로 거부되므로 패키지를 전부 다시 지어야 한다.
# 이미 링크된 .exe 는 계속 돌기 때문에 이 상태를 놓치기 쉽다 —
# 회귀가 통과하는데 정작 아무것도 다시 지을 수 없는 상황이 된다.
#
# ⚠️ 순서가 중요하다:
#   ① contained 유닛을 -FP **없이** 선컴파일한다.
#      -FP 와 함께 컴파일하면 IE 2013053103 으로 죽고, 그 상태로 패키지를
#      지으면 IE 2026032615 가 난다.
#   ② 그 다음 패키지(.dpk), 마지막에 호스트 프로그램만 -FP 를 받는다.
#
# 각 패키지는 -WB 로 ImageBase 를 분리해 겹치지 않게 한다.
#
#   .\rebuild.ps1

param(
  [string]$Ppc = 'C:\works\fpc-unleashed\compiler\ppcx64_pkg.exe'
)

$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot

function Invoke-Ppc {
  # ⚠️ 파라미터 이름을 $Args 로 두면 안 된다 — PowerShell 자동 변수와 겹쳐
  #    스플랫이 빈 배열이 되고, 컴파일러가 인자 없이 불려 도움말을 뱉는다.
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
  Invoke-Ppc 'rtlpkg.dpk' @('-WB110000000', '-Xm', 'rtlpkg.dpk')

  Write-Host '유닛 선컴파일 (-FP 없이)'
  foreach ($u in @('SharedIntf.pas', 'SalesUnit.pas', 'PlainUnit.pas', 'LazyUnit.pas')) {
    if (Test-Path $u) {
      Invoke-Ppc $u @($u)
    }
  }

  Write-Host '패키지'
  $pkgs = @(
    @{ Name = 'CommonPkg.dpk'; Base = '-WB12000000' },
    @{ Name = 'SalesPkg.dpk';  Base = '-WB13000000' },
    @{ Name = 'PlainPkg.dpk';  Base = '-WB14000000' },
    @{ Name = 'LazyPkg.dpk';   Base = '-WB15000000' }
  )
  foreach ($p in $pkgs) {
    if (Test-Path $p.Name) {
      Invoke-Ppc $p.Name @($p.Base, $p.Name)
    }
  }

  Write-Host '호스트 (-FP 는 여기서만)'
  $hosts = @(
    @{ Name = 'host4';  Pkgs = @('-FPrtlpkg', '-FPCommonPkg') },
    @{ Name = 'host7';  Pkgs = @('-FPrtlpkg') },
    @{ Name = 'host8';  Pkgs = @('-FPrtlpkg', '-FPCommonPkg') },
    @{ Name = 'host9';  Pkgs = @('-FPrtlpkg', '-FPCommonPkg') },
    @{ Name = 'host10'; Pkgs = @('-FPrtlpkg', '-FPCommonPkg') },
    @{ Name = 'host11'; Pkgs = @('-FPrtlpkg', '-FPCommonPkg') },
    @{ Name = 'host12'; Pkgs = @('-FPrtlpkg') }
  )
  foreach ($h in $hosts) {
    $src = "$($h.Name).pas"
    if (Test-Path $src) {
      Invoke-Ppc $src ($h.Pkgs + @($src))
    }
  }

  Write-Host '재빌드 완료' -ForegroundColor Green
}
finally {
  Pop-Location
}
