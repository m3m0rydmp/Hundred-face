$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'Hundred Face'
$startup = [Environment]::GetFolderPath('Startup')
$launcher = Join-Path $startup 'Hundred Face.vbs'

Write-Host 'Hundred Face'
Write-Host 'Tracks detected games on this Windows account, including time left open.'
Write-Host 'It sends game names, session times and daily and weekly totals to a Discord channel.'
Write-Host 'It starts when you sign in and runs in the background.'
Write-Host 'Only continue if you agree to share this activity with people who can see that channel.'
if ((Read-Host 'Install Hundred Face on your account? Type YES to continue') -cne 'YES') { exit 0 }

$secret = Read-Host 'Paste the Discord channel webhook URL and press Enter' -AsSecureString
$url = [System.Net.NetworkCredential]::new('', $secret).Password
if ($url -cnotmatch '^https://discord\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+/?$') {
    Write-Host 'Enter a Discord webhook URL beginning with https://discord.com/api/webhooks/.'
    exit 1
}

try {
    $payload = @{ content = 'Hundred Face setup check. Game activity notifications will appear in this channel.'; allowed_mentions = @{ parse = @() } }
    Invoke-RestMethod -Uri ($url.TrimEnd('/') + '?wait=true') -Method Post -ContentType 'application/json' -Body ($payload | ConvertTo-Json -Compress) -TimeoutSec 15 -ErrorAction Stop | Out-Null
} catch {
    Write-Host 'Discord could not deliver the setup message. Check the webhook and internet connection, then run setup again.'
    exit 1
}

New-Item -ItemType Directory -Path $root -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Monitor.ps1') -Destination $root -Force
$secret | ConvertFrom-SecureString | Set-Content -LiteralPath (Join-Path $root 'webhook.txt') -Encoding ASCII
@'
Set shell = CreateObject("WScript.Shell")
root = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Hundred Face"
shell.Run "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & root & "\Monitor.ps1""", 0, False
'@ | Set-Content -LiteralPath $launcher -Encoding ASCII
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall Hundred Face.cmd') -Destination $root -Force
$disabled = Join-Path $root 'disabled'
if (Test-Path -LiteralPath $disabled) { Remove-Item -LiteralPath $disabled }
Start-Process -FilePath wscript.exe -ArgumentList ('"{0}"' -f $launcher) -WindowStyle Hidden
Write-Host 'Hundred Face is installed. Check the Discord channel for the setup message.'
Write-Host ('To stop and remove the monitor, run Uninstall Hundred Face.cmd in ' + $root)
