$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$statePath = Join-Path $root 'activity.json'
$secretPath = Join-Path $root 'webhook.txt'
$disabled = Join-Path $root 'disabled'

function Get-GameFolders {
    $folders = @{}
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { $steam = Join-Path ${env:ProgramFiles(x86)} 'Steam' }
    $libraries = @($steam)
    $libraryFile = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $libraryFile) {
        $libraries += [regex]::Matches((Get-Content -LiteralPath $libraryFile -Raw), '"path"\s+"([^"]+)"') |
            ForEach-Object { $_.Groups[1].Value.Replace('\\', '\') }
    }
    foreach ($library in $libraries) {
        $steamApps = Join-Path $library 'steamapps'
        foreach ($manifest in Get-ChildItem -LiteralPath $steamApps -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue) {
            $data = Get-Content -LiteralPath $manifest.FullName -Raw
            $folder = [regex]::Match($data, '"installdir"\s+"([^"]+)"').Groups[1].Value
            $name = [regex]::Match($data, '"name"\s+"([^"]+)"').Groups[1].Value
            if ($folder -and $name) {
                $path = Join-Path (Join-Path $steamApps 'common') $folder
                $folders[[IO.Path]::GetFullPath($path).TrimEnd('\') + '\'] = $name
            }
        }
    }
    $epic = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    foreach ($manifest in Get-ChildItem -LiteralPath $epic -Filter '*.item' -ErrorAction SilentlyContinue) {
        try {
            $item = Get-Content -LiteralPath $manifest.FullName -Raw | ConvertFrom-Json
            if ($item.InstallLocation -and $item.DisplayName -and $item.LaunchExecutable) {
                $exe = Join-Path $item.InstallLocation $item.LaunchExecutable
                $folders[[IO.Path]::GetFullPath($exe)] = $item.DisplayName
            }
        } catch { continue }
    }
    return $folders
}

function Get-RunningGames($folders) {
    $games = @{}
    $sessionId = (Get-Process -Id $PID).SessionId
    foreach ($process in Get-Process) {
        if ($process.SessionId -ne $sessionId -or $process.MainWindowHandle -eq 0) { continue }
        $path = $process.Path
        if (-not $path) { continue }
        foreach ($gamePath in $folders.Keys) {
            if ($path.Equals($gamePath, [StringComparison]::OrdinalIgnoreCase) -or
                ($gamePath.EndsWith('\') -and $path.StartsWith($gamePath, [StringComparison]::OrdinalIgnoreCase))) {
                $games[$gamePath] = $folders[$gamePath]
                break
            }
        }
        if ($path -match '^([A-Z]:\\XboxGames\\([^\\]+)\\Content\\)') {
            $games[$Matches[1]] = $Matches[2]
        }
    }
    return $games
}

function Format-Time([long]$seconds) {
    return [DateTimeOffset]::FromUnixTimeSeconds($seconds).LocalDateTime.ToString('yyyy-MM-dd HH:mm')
}

function Format-Duration([long]$seconds) {
    $minutes = [math]::Floor($seconds / 60)
    if ($minutes -lt 1) { return 'under 1 minute' }
    return ('{0}h {1}m' -f [math]::Floor($minutes / 60), ($minutes % 60))
}

function Save-Activity {
    $tmp = "$statePath.tmp"
    $state | ConvertTo-Json -Depth 8 -Compress | Set-Content -LiteralPath $tmp -Encoding UTF8
    if ([IO.File]::Exists($statePath)) {
        $backup = "$statePath.bak"
        [IO.File]::Replace($tmp, $statePath, $backup)
        [IO.File]::Delete($backup)
    }
    else { [IO.File]::Move($tmp, $statePath) }
}

function Add-Summary($label, [datetime]$start, [datetime]$end) {
    $from = ([DateTimeOffset]$start).ToUnixTimeSeconds()
    $to = ([DateTimeOffset]$end).ToUnixTimeSeconds()
    $totals = @{}
    $intervals = foreach ($session in (@($state.history.ToArray()) + @($state.active.Values))) {
        $first = [math]::Max($from, [long]$session.start)
        $last = [math]::Min($to, [long]$session.end)
        if ($last -gt $first) {
            $totals[$session.name] += $last - $first
            [pscustomobject]@{ start = $first; end = $last }
        }
    }
    $total = 0
    $covered = $from
    foreach ($interval in ($intervals | Sort-Object start)) {
        $total += [math]::Max(0, $interval.end - [math]::Max($covered, $interval.start))
        $covered = [math]::Max($covered, $interval.end)
    }
    $message = "Hundred Face | $label ($($start.ToString('yyyy-MM-dd')))`nTotal game time: $(Format-Duration $total)"
    if ($total -eq 0) { $message = "Hundred Face | $label ($($start.ToString('yyyy-MM-dd')))`nNo detected game time." }
    foreach ($name in ($totals.Keys | Sort-Object)) {
        $line = "`n$name ($(Format-Duration $totals[$name]))"
        if ($message.Length + $line.Length -gt 1920) { $message += "`nAdditional games omitted."; break }
        $message += $line
    }
    $state.queue.Add($message)
}

$mutex = [Threading.Mutex]::new($false, "Local\HundredFace-$([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)")
try {
    try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { return }
    $today = (Get-Date).Date
    $monday = $today.AddDays(-(([int]$today.DayOfWeek + 6) % 7))
    $state = @{
        active = @{}; history = [Collections.Generic.List[object]]::new()
        queue = [Collections.Generic.List[string]]::new()
        day = $today.ToString('yyyy-MM-dd'); week = $monday.ToString('yyyy-MM-dd')
    }
    if (Test-Path -LiteralPath $statePath) {
        $saved = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        foreach ($entry in $saved.active.PSObject.Properties) { $state.active[$entry.Name] = $entry.Value }
        foreach ($entry in $saved.history) { $state.history.Add($entry) }
        foreach ($entry in $saved.queue) { $state.queue.Add($entry) }
        $state.day = $saved.day
        $state.week = $saved.week
    }
    $refresh = 0
    $retryAfter = 0
    while (-not (Test-Path -LiteralPath $disabled) -and (Test-Path -LiteralPath $secretPath)) {
        try {
            $clock = [DateTimeOffset]::Now
            $now = $clock.ToUnixTimeSeconds()
            if ($now -ge $refresh) { $folders = Get-GameFolders; $refresh = $now + 300 }
            $games = Get-RunningGames $folders
            $changed = $false
            foreach ($key in @($state.active.Keys)) {
                $session = $state.active[$key]
                if ($games.ContainsKey($key) -and ($now - $session.end) -lt 90) {
                    $session.end = $now
                } else {
                    $state.active.Remove($key)
                    $state.history.Add($session)
                    $state.queue.Add("Hundred Face | Game ended`n$($session.name)`nLast seen: $(Format-Time $session.end)`nDuration: $(Format-Duration ($session.end - $session.start))")
                }
                $changed = $true
            }
            foreach ($key in $games.Keys) {
                if ($state.active.ContainsKey($key)) { continue }
                $state.active[$key] = [pscustomobject]@{ name = $games[$key]; start = $now; end = $now }
                $state.queue.Add("Hundred Face | Game started`n$($games[$key])`nStarted: $(Format-Time $now)")
                $changed = $true
            }
            $today = $clock.LocalDateTime.Date
            $monday = $today.AddDays(-(([int]$today.DayOfWeek + 6) % 7))
            if ($state.day -lt $today.ToString('yyyy-MM-dd')) {
                Add-Summary 'Daily summary' ($today.AddDays(-1)) $today
                $state.day = $today.ToString('yyyy-MM-dd')
                $changed = $true
            }
            if ($state.week -lt $monday.ToString('yyyy-MM-dd')) {
                Add-Summary 'Weekly summary' ($monday.AddDays(-7)) $monday
                $state.week = $monday.ToString('yyyy-MM-dd')
                $changed = $true
            }
            if ($changed) { Save-Activity }
            if ($state.queue.Count -and $now -ge $retryAfter -and -not (Test-Path -LiteralPath $disabled)) {
                $secret = Get-Content -LiteralPath $secretPath | ConvertTo-SecureString
                $url = [System.Net.NetworkCredential]::new('', $secret).Password.TrimEnd('/')
                $message = $state.queue[0]
                $payload = @{ content = $message.Substring(0, [math]::Min(2000, $message.Length)); allowed_mentions = @{ parse = @() } }
                $json = $payload | ConvertTo-Json -Compress
                try {
                    Invoke-RestMethod -Uri ($url + '?wait=true') -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 10 | Out-Null
                    $state.queue.RemoveAt(0)
                    Save-Activity
                } catch { $retryAfter = $now + 60 }
            }
        } catch {
            Set-Content -LiteralPath (Join-Path $root 'monitor-status.txt') -Value ("Monitor error at {0}. Error type: {1}" -f (Get-Date), $_.Exception.GetType().Name)
        }
        Start-Sleep -Seconds 20
    }
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
