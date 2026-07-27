# 스파이크 트리 전체 재빌드.
#
# 툴체인이 바뀌면(확장자·.fcp 형식·ABI 플래그) 이 트리 전체가 무효가 된다.
# 순서와 플래그를 기억에만 두면 틀린다 - 실제로 stage4 바이너리가 RTL 보다
# 2.5시간 뒤처져 있던 적이 있고, 그때 회귀는 초록이었다(이미 링크된 것이
# 계속 돌았기 때문이다).
#
# stage3rt 와 stage4 는 자기 스크립트가 있다. 여기서는 stage1~3 을 짓고
# 그 둘을 호출한다.

param(
  [string]$Ppc = 'C:\works\fpc-unleashed\compiler\ppcx64_pkg.exe',
  [string]$ResDir = 'C:\fpcunleashed\fpc322\bin\i386-win32',
  [switch]$CleanStale
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# stage1~3 에는 로컬 fpc.cfg 가 없어 RTL 유닛 경로를 여기서 준다.
# stage3rt·stage4 는 자기 fpc.cfg 가 툴체인 설정을 #INCLUDE 하므로 무관하다
# (컴파일러는 cwd 의 fpc.cfg 를 찾으면 그것만 읽고 기본 설정으로 대체하지 않는다).
$env:PPC_CONFIG_PATH = Join-Path (Split-Path $PSScriptRoot -Parent) 'cfg'

if ($CleanStale) {
  # 낡은 확장자의 산출물. 컴파일러가 더 이상 만들지도 찾지도 않으므로
  # 남겨 두면 "있는데 안 쓰이는" 혼선만 남는다.
  $stale = Get-ChildItem -Recurse -Include '*.dll', '*.pcp', '*.ppl' -File
  if ($stale) {
    Write-Host "낡은 산출물 $($stale.Count) 개 제거"
    $stale | Remove-Item -Force
  }
}

function Invoke-Ppc {
  param([string[]]$PpcArgs, [string]$What)

  & $Ppc @PpcArgs 2>&1 | Out-String -OutVariable out | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  [FAIL] $What"
    Write-Host $out
    exit 1
  }
}

# stage 이름 -> (패키지 순서, 패키지별 담긴 유닛, 호스트)
$stages = @(
  @{ Dir = 'stage1'
     Bases = @{ 'rtlpkg' = '110000000'; 'TestPkg' = '120000000' }
     Order = @('rtlpkg', 'TestPkg')
     Units = @{ 'TestPkg' = @('PkgUnit') }
     Hosts = @('host') }

  @{ Dir = 'stage2'
     Bases = @{ 'rtlpkg' = '110000000'; 'CommonPkg' = '120000000'; 'SalesPkg' = '130000000' }
     Order = @('rtlpkg', 'CommonPkg', 'SalesPkg')
     Units = @{ 'CommonPkg' = @('BaseUnit'); 'SalesPkg' = @('SalesUnit') }
     Hosts = @('host2') }

  @{ Dir = 'stage3'
     Bases = @{ 'rtlpkg' = '110000000'; 'CommonPkg' = '120000000' }
     Order = @('rtlpkg', 'CommonPkg')
     Units = @{ 'CommonPkg' = @('InitUnit') }
     Hosts = @('host3') }
)

foreach ($s in $stages) {
  Write-Host "--- $($s.Dir) ---"
  Push-Location $s.Dir
  try {
    foreach ($p in $s.Order) {
      if ($s.Units.ContainsKey($p)) {
        foreach ($u in $s.Units[$p]) {
          Invoke-Ppc @('-FE.', '-FU.', "$u.pas") "$($s.Dir)/$p/$u"
        }
      }

      Invoke-Ppc @('-FE.', '-FU.', "-WB$($s.Bases[$p])", '-Xm', "$p.dpk") "$($s.Dir)/$p"
      Write-Host "  [OK]   $p.fpl"
    }

    foreach ($h in $s.Hosts) {
      # 호스트가 담긴 유닛을 uses 하면 그 패키지도 소비해야 한다.
      # 빠뜨리면 정적 링크되어 클래스 사본이 둘이 되고 `is` 가 조용히 FALSE 가 된다.
      $src = Get-Content "$h.pas" -Raw
      $ppcArgs = @('-FPrtlpkg')
      foreach ($p in $s.Order) {
        if ($p -eq 'rtlpkg') { continue }
        foreach ($u in $s.Units[$p]) {
          if ($src -match "(?m)^\s*$u\s*[,;]") { $ppcArgs += "-FP$p"; break }
        }
      }
      $ppcArgs += "-FD$ResDir"
      $ppcArgs += "$h.pas"

      Invoke-Ppc $ppcArgs "$($s.Dir)/$h"
      Write-Host "  [OK]   $h.exe"
    }
  }
  finally {
    Pop-Location
  }
}

foreach ($d in @('stage3rt', 'stage4')) {
  Write-Host "--- $d ---"
  & pwsh -NoProfile -File (Join-Path $d 'rebuild-spike.ps1') -Ppc $Ppc -ResDir $ResDir
  if ($LASTEXITCODE -ne 0) { exit 1 }
}

Write-Host ''
Write-Host '스파이크 전체 재빌드 완료'
