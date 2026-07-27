# stage3rt 재빌드 - 지금까지 손으로 하던 것을 스크립트로.
#
# 확장자 변경(.dll/.pcp -> .fpl/.fcp)처럼 툴체인이 바뀌면 이 트리 전체를
# 다시 지어야 하는데, 순서를 기억에만 두면 매번 틀린다. 실제로 stage4
# 바이너리가 RTL 보다 2.5시간 뒤처져 있던 적이 있다.
#
# 순서가 전부다: 담긴 유닛은 -FP 없이 먼저, 패키지는 그 다음, 호스트는 마지막.
# contained 유닛을 -FP 와 함께 컴파일하면 IE 2013053103 으로 죽는다.

param(
  [string]$Ppc = 'C:\works\fpc-unleashed\compiler\fcc64.exe',
  [string]$ResDir = 'C:\fpcunleashed\fpc322\bin\i386-win32'
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# 이미지 베이스가 겹치면 로드가 실패하고 증상이 원인을 가리키지 않는다
$bases = @{
  'rtlpkg'    = '110000000'
  'CommonPkg' = '120000000'
  'SalesPkg'  = '130000000'
  'LazyPkg'   = '140000000'
  'PlainPkg'  = '150000000'
}

# 의존 순서
$packages = @('rtlpkg', 'CommonPkg', 'SalesPkg', 'LazyPkg', 'PlainPkg')
$units    = @{
  'CommonPkg' = @('SharedIntf')
  'SalesPkg'  = @('SalesUnit')
  'LazyPkg'   = @('LazyUnit')
  'PlainPkg'  = @('PlainUnit')
}

Get-ChildItem -Filter '*.fpl' | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Filter '*.fcp' | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Filter '*.exe' | Remove-Item -Force -ErrorAction SilentlyContinue

function Invoke-Ppc {
  param([string[]]$PpcArgs, [string]$What)

  & $Ppc @PpcArgs 2>&1 | Out-String -OutVariable out | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  [FAIL] $What"
    Write-Host $out
    exit 1
  }
}

foreach ($p in $packages) {
  # 담긴 유닛을 먼저, -FP 없이
  if ($units.ContainsKey($p)) {
    foreach ($u in $units[$p]) {
      Invoke-Ppc @('-FE.', '-FU.', "$u.pas") "$p / $u"
    }
  }

  Invoke-Ppc @('-FE.', '-FU.', "-WB$($bases[$p])", '-Xm', "$p.dpk") "패키지 $p"
  Write-Host "  [OK]   $p.fpl"
}

# 호스트.
#
# ⚠️ 담긴 유닛을 uses 하는 호스트는 그 패키지도 -FP 로 소비해야 한다.
#    빠뜨리면 컴파일은 되는데 호스트가 유닛을 정적 링크해 **클래스 사본이
#    둘**이 되고, 크로스 패키지 `is` 가 조용히 FALSE 가 된다. 빌드는
#    성공하므로 실행해 봐야 안다.
$unitOwner = @{
  'SharedIntf' = 'CommonPkg'
  'SalesUnit'  = 'SalesPkg'
  'LazyUnit'   = 'LazyPkg'
  'PlainUnit'  = 'PlainPkg'
}

foreach ($h in (Get-ChildItem -Filter 'host*.pas' | Sort-Object Name)) {
  $n = $h.BaseName
  $src = Get-Content $h.FullName -Raw

  $consumed = @('rtlpkg')
  foreach ($u in $unitOwner.Keys) {
    if ($src -match "(?m)^\s*$u\s*[,;]") {
      $consumed += $unitOwner[$u]
    }
  }

  $ppcArgs = @()
  foreach ($p in ($consumed | Select-Object -Unique)) {
    $ppcArgs += "-FP$p"
  }
  $ppcArgs += "-FD$ResDir"
  $ppcArgs += "$n.pas"

  Invoke-Ppc $ppcArgs "호스트 $n"
  Write-Host "  [OK]   $n.exe  ($($consumed -join ' '))"
}

# requires 절로 짓는 것 - -FP 없이
foreach ($h in (Get-ChildItem -Filter '*.fpr' -ErrorAction SilentlyContinue | Sort-Object Name)) {
  $n = $h.BaseName
  Invoke-Ppc @("-FD$ResDir", "$n.fpr") "호스트 $n (requires)"
  Write-Host "  [OK]   $n.exe (requires)"
}

Write-Host ''
Write-Host '재빌드 완료'
