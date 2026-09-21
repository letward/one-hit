# Lädt den OneHit-Windows-Build ins Neocrom-Store-Backend hoch.
# Voraussetzung: API läuft, JWT via Login besorgen, GAME_ID aus Seed/Listing.
#
#   $jwt = (Invoke-RestMethod "$Api/api/auth/login" -Method Post `
#     -ContentType "application/json" `
#     -Body '{"identifier":"letward","password":"..."}').jwt
#   .\upload-build.ps1 -Api "https://neocrom.pro/api" -Jwt $jwt -GameId 1
param(
  [string]$Api = "https://neocrom.pro/api",
  [Parameter(Mandatory = $true)][string]$Jwt,
  [Parameter(Mandatory = $true)][int]$GameId,
  [string]$Version = "1.0.0",
  [string]$BuildDir = "$PSScriptRoot\..\builds\windows"
)

$H = @{ Authorization = "Bearer $Jwt" }
$exe = Join-Path $BuildDir "OneHit.exe"
if (-not (Test-Path $exe)) { throw "Build fehlt: $exe (erst exportieren)" }

Write-Output "-- Artifact-Upload (kann dauern) --"
# Multipart: Feldname 'file' (siehe POST /api/developer/games/:id/artifact)
$up = Invoke-RestMethod -Uri "$Api/developer/games/$GameId/artifact" `
  -Method Post -Headers $H -Form @{ file = Get-Item $exe }
$artifact = $up.artifact_path
Write-Output "artifact: $artifact"

Write-Output "-- Release 1.0.0 --"
Invoke-RestMethod -Uri "$Api/developer/games/$GameId/releases" -Method Post `
  -Headers $H -ContentType "application/json" -Body (@{
    version = $Version
    notes   = "OneHit Preview: Solo vs. Bots, Online-Lobbys, 6 Waffen, Shop, Skins, Realistisch-Modus."
    artifact_path = $artifact
  } | ConvertTo-Json) | ConvertTo-Json -Compress

Write-Output "-- Changelog --"
Invoke-RestMethod -Uri "$Api/developer/games/$GameId/changelog" -Method Post `
  -Headers $H -ContentType "application/json" -Body (@{
    version = $Version
    body    = "Preview-Release: gratis bis 01.10.2026 exklusiv für Members."
  } | ConvertTo-Json) | ConvertTo-Json -Compress

Write-Output "FERTIG: Build $Version live (Preview)."
