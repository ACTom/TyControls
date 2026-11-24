# Helpers for driving our own invisible Word instance. ASCII only.
$script:WordPid = 0
$script:Word = $null
$script:Pre = @()
$script:Heart = $null

function Start-OurWord {
    param([string]$HeartFile)
    $script:Pre = @(Get-Process WINWORD -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    $script:Heart = $HeartFile
    $w = New-Object -ComObject Word.Application
    $w.Visible = $false
    $w.DisplayAlerts = 0
    $w.ScreenUpdating = $false
    try { $w.AutomationSecurity = 3 } catch {}
    # NEVER write $w.Options.* or $w.UserName: those are the user's Word settings and persist
    # after Quit (SaveInterval = 0 switched the user's AutoRecover off until it was noticed).
    $post = @(Get-Process WINWORD -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    $new = @($post | Where-Object { $script:Pre -notcontains $_ })
    if ($new.Count -ne 1) {
        # not our own fresh instance: do not touch anything
        $script:Word = $null
        throw "could not identify a fresh Word process (new pids: $($new -join ','))"
    }
    $script:WordPid = $new[0]
    $script:Word = $w
    return $w
}

function Beat {
    if ($script:Heart) { [IO.File]::WriteAllText($script:Heart, [string](Get-Date).Ticks) }
}

function Stop-OurWord {
    if ($script:Word -ne $null) {
        try { $script:Word.Quit(0) } catch {}
        try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($script:Word) } catch {}
        $script:Word = $null
    }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    $waited = 0
    while ($waited -lt 30 -and (Get-Process -Id $script:WordPid -ErrorAction SilentlyContinue)) { Start-Sleep -Seconds 1; $waited++ }
    if ($script:WordPid -gt 0) {
        $p = Get-Process -Id $script:WordPid -ErrorAction SilentlyContinue
        if ($p) { Stop-Process -Id $script:WordPid -Force; "killed our Word pid $($script:WordPid) 30 s after Quit" }
        else { "our Word pid $($script:WordPid) exited by itself $waited s after Quit" }
    }
    $post = @(Get-Process WINWORD -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    "WINWORD pids before: [$($script:Pre -join ',')]  after: [$($post -join ',')]"
}
