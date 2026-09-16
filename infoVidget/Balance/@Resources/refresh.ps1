[CmdletBinding()]
param(
    [string]$TokenFile = '',
    [string]$SettingsFile = '',
    [string]$Url = '',
    [string]$JsonPath = 'data.balance',
    [string]$ErrorPath = 'code'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}

$logFile = Join-Path $PSScriptRoot 'balance.log'
if ([string]::IsNullOrWhiteSpace($TokenFile)) {
    $TokenFile = Join-Path $PSScriptRoot 'token.txt'
}

function Write-BalanceLog {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
    try {
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

function Out-Result {
    param([string]$Text)
    Write-BalanceLog $Text
    $outFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'last.txt'
    try {
        [IO.File]::WriteAllText($outFile, $Text, (New-Object System.Text.UTF8Encoding($false)))
    } catch {}
    Write-Output $Text
}

function Get-JsonValue {
    param($Obj, [string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Obj }
    $tokens = New-Object System.Collections.Generic.List[object]
    foreach ($m in [regex]::Matches($Path, '\[([^\]]*)\]|([^\.\[\]]+)')) {
        if ($m.Groups[1].Success) {
            $inner = $m.Groups[1].Value.Trim()
            if ($inner.Length -ge 2 -and (($inner[0] -eq '"' -and $inner[-1] -eq '"') -or ($inner[0] -eq "'" -and $inner[-1] -eq "'"))) {
                $tokens.Add(@{ Type = 'key'; Value = $inner.Substring(1, $inner.Length - 2) })
            } elseif ($inner -match '^\d+$') {
                $tokens.Add(@{ Type = 'index'; Value = [int]$inner })
            } else {
                $tokens.Add(@{ Type = 'key'; Value = $inner })
            }
        } else {
            $tokens.Add(@{ Type = 'key'; Value = $m.Groups[2].Value })
        }
    }
    $cur = $Obj
    foreach ($t in $tokens) {
        if ($null -eq $cur) { return $null }
        if ($t.Type -eq 'index') {
            if (($cur -is [System.Array] -or $cur -is [System.Collections.IList]) -and $t.Value -lt $cur.Count) {
                $cur = $cur[$t.Value]
            } else {
                return $null
            }
        } else {
            if ($cur -is [System.Collections.IDictionary]) {
                if (-not $cur.Contains($t.Value)) { return $null }
                $cur = $cur[$t.Value]
            } elseif ($cur -is [PSCustomObject]) {
                if (-not $cur.PSObject.Properties[$t.Value]) { return $null }
                $cur = $cur.PSObject.Properties[$t.Value].Value
            } else {
                return $null
            }
        }
    }
    return $cur
}

Write-BalanceLog 'START'

if ([string]::IsNullOrWhiteSpace($SettingsFile)) {
    $SettingsFile = Join-Path $PSScriptRoot 'settings.txt'
}
if (Test-Path -LiteralPath $SettingsFile) {
    try {
        foreach ($line in [IO.File]::ReadAllLines($SettingsFile)) {
            $t = $line.Trim()
            if ($t -eq '' -or $t.StartsWith('#')) { continue }
            $i = $t.IndexOf('=')
            if ($i -lt 1) { continue }
            $k = $t.Substring(0, $i).Trim().ToLowerInvariant()
            $v = $t.Substring($i + 1).Trim()
            switch ($k) {
                'url' { if (-not [string]::IsNullOrWhiteSpace($v)) { $Url = $v } }
                'json' { $JsonPath = $v }
                'err' { $ErrorPath = $v }
            }
        }
    } catch {
        Write-BalanceLog ("SETTINGS-READ: " + $_.Exception.Message)
    }
} else {
    Write-BalanceLog "SETTINGS-MISSING"
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
    Out-Result "ERR:NET:tls-init"
    exit 0
}

$token = $null
$haveToken = $false
try {
    if (Test-Path -LiteralPath $TokenFile) {
        $raw = Get-Content -LiteralPath $TokenFile -Raw -Encoding UTF8 -ErrorAction Stop
        $token = ($raw -replace "`uFEFF", "" -replace "`r", "" -replace "`n", "").Trim().Trim("'").Trim('"')
        if (-not [string]::IsNullOrWhiteSpace($token)) { $haveToken = $true }
    }
} catch {
    Write-BalanceLog ("TOKEN-READ: " + $_.Exception.Message)
    $haveToken = $false
}

$headers = @{ 'User-Agent' = 'Rainmeter-VidgetInfo/1.0' }
if ($haveToken) {
    $token = ($token -replace '\s', '').Trim()
    if ($token -match '^(?i)(Basic|Bearer)(.+)$') {
        $headers['Authorization'] = $Matches[1] + ' ' + $Matches[2]
    } else {
        $headers['Authorization'] = "Bearer $token"
    }
} else {
    Write-BalanceLog 'AUTH:none'
}

$uri = $Url

try {
    $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 15 -ErrorAction Stop

    if (-not [string]::IsNullOrWhiteSpace($ErrorPath)) {
        $errVal = Get-JsonValue $resp $ErrorPath
        if ($null -ne $errVal) {
            $errNum = 0
            if ([int]::TryParse("$errVal", [ref]$errNum)) {
                if ($errNum -ne 0) {
                    Out-Result "ERR:API:${errNum}"
                    exit 0
                }
            }
        }
    }

    $val = Get-JsonValue $resp $JsonPath
    if ($null -eq $val -or "$val" -eq '') {
        Out-Result "ERR:API:no-field"
        exit 0
    }

    $text =
        if ($val -is [bool]) { if ($val) { 'true' } else { 'false' } }
        elseif ($val -is [string]) { $val }
        elseif ($val -is [ValueType]) { [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $val) }
        else { ($val | ConvertTo-Json -Compress -Depth 10) }

    Out-Result ($text.Trim())
} catch {
    $ex = $_.Exception
    $code = $null
    try {
        if ($ex.Response -and $ex.Response.StatusCode) {
            $code = [int]$ex.Response.StatusCode
        }
    } catch {}

    $msg = ($ex.Message -split "`n")[0]
    Write-BalanceLog ("EX: " + $msg)

    if ($code) {
        if ($code -eq 401 -or $code -eq 403) {
            Out-Result "ERR:401"
        } else {
            Out-Result "ERR:HTTP:$code"
        }
    } else {
        if ($msg -match 'timeout|timed out') {
            Out-Result "ERR:TIMEOUT"
        } elseif ($msg -match 'name resolution|dns|host') {
            Out-Result "ERR:NET:dns"
        } elseif ($msg -match 'ssl|tls|trust') {
            Out-Result "ERR:NET:tls"
        } else {
            Out-Result "ERR:NET"
        }
    }
}
