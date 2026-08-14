$ErrorActionPreference = "Stop"

$ProjectDir = Split-Path -Parent $PSScriptRoot
$Manifest = Join-Path $ProjectDir "native/manga_ocr_helper/Cargo.toml"
$OutputDir = Join-Path $ProjectDir "assets/executables"

rustup target add x86_64-pc-windows-msvc
cargo build --manifest-path $Manifest --release --target x86_64-pc-windows-msvc

$BuildDir = Join-Path $ProjectDir "native/manga_ocr_helper/target/x86_64-pc-windows-msvc/release"
Copy-Item (Join-Path $BuildDir "manga-ocr-helper.exe") (Join-Path $OutputDir "manga-ocr-helper-windows-x64.exe") -Force
# `ort` 当前以静态方式链接 ONNX Runtime，但将来切换为动态链接时，
# 仍需将所有实际的运行时 DLL 与 helper 放入同一目录。
Get-ChildItem $BuildDir -Filter "*.dll" -Recurse |
  Where-Object { $_.Length -gt 0 } |
  ForEach-Object {
    Copy-Item $_.FullName (Join-Path $OutputDir $_.Name) -Force
}

Write-Host "Windows x64 helper 已生成到 assets/executables"
