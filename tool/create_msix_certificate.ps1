# Creates your own self-signed code-signing certificate for the MSIX installer.
# Run once:  powershell -ExecutionPolicy Bypass -File tool\create_msix_certificate.ps1
#
# Output (outside the repo, never commit these):
#   %USERPROFILE%\fptu-brain-signing\fptu-brain-signing.pfx  private key -> GitHub secret MSIX_CERT_BASE64
#   %USERPROFILE%\fptu-brain-signing\fptu-brain.cer          public cert users trust to install the .msix
# The Subject must equal msix_config.publisher in pubspec.yaml.

$ErrorActionPreference = 'Stop'
$subject = 'CN=FPTU SE Second Brain'
$outDir = Join-Path $env:USERPROFILE 'fptu-brain-signing'
New-Item -ItemType Directory -Force $outDir | Out-Null

$secure = Read-Host -AsSecureString 'Đặt mật khẩu cho file .pfx (dùng làm secret MSIX_CERT_PASSWORD)'

$cert = New-SelfSignedCertificate `
  -Type CodeSigningCert `
  -Subject $subject `
  -FriendlyName 'FPTU SE Second Brain MSIX signing' `
  -KeyUsage DigitalSignature `
  -KeyExportPolicy Exportable `
  -CertStoreLocation 'Cert:\CurrentUser\My' `
  -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}') `
  -NotAfter (Get-Date).AddYears(3)

$pfx = Join-Path $outDir 'fptu-brain-signing.pfx'
$cer = Join-Path $outDir 'fptu-brain.cer'
Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $secure | Out-Null
Export-Certificate -Cert $cert -FilePath $cer | Out-Null

[Convert]::ToBase64String([IO.File]::ReadAllBytes($pfx)) | Set-Clipboard

Write-Host ''
Write-Host "Đã tạo chứng chỉ trong $outDir" -ForegroundColor Green
Write-Host 'Nội dung base64 của file .pfx đã được copy vào clipboard.'
Write-Host 'Tiếp theo, trên GitHub: repo > Settings > Secrets and variables > Actions > New repository secret:'
Write-Host '  MSIX_CERT_BASE64   = dán nội dung clipboard'
Write-Host '  MSIX_CERT_PASSWORD = mật khẩu vừa đặt'
Write-Host 'Giữ file .pfx ở nơi an toàn; có thể xóa sau khi đã tạo secret.'
