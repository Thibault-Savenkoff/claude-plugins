# Shared helpers for the jev-guard hooks, PowerShell side.
# Mirrors hooks/lib.sh -- keep the two in step.

$JgUrl = if ($env:JEV_GUARD_API_URL) { $env:JEV_GUARD_API_URL } else { "https://api.typesafe.ai/v1/systemone" }
# Windows PowerShell 5.1 pipes to native programs in ASCII by default, which
# would mangle any non-ASCII text in a diff on the way to curl.
$OutputEncoding = New-Object Text.UTF8Encoding $false
# And read git's output as UTF-8, or non-ASCII paths come back garbled.
[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
$Inv = [Globalization.CultureInfo]::InvariantCulture

function Jg-Config([string]$Name, [string]$Default = "") {
  $v = (git config --get "jev-guard.$Name" 2>$null)
  if ([string]::IsNullOrWhiteSpace($v)) { return $Default }
  return $v.Trim()
}

# See lib.sh: a typo must never turn blocking on.
function Jg-Mode {
  switch (Jg-Config "mode" "strict") { "off" { "off" } "strict" { "strict" } default { "warn" } }
}

function Jg-Active {
  if (-not ((git rev-parse --is-inside-work-tree 2>$null))) { return $false }
  if ((Jg-Mode) -eq "off") { return $false }
  return [bool]$env:TYPESAFE_API_KEY
}

function Jg-Dir {
  $d = Join-Path (git rev-parse --git-dir) "jev-guard"
  New-Item -ItemType Directory -Force -Path (Join-Path $d "cache") | Out-Null
  return $d
}

function Jg-Log([string]$Line) {
  Add-Content -Path (Join-Path (Jg-Dir) "error.log") -Value "$(Get-Date -Format s) $($Line -replace "`r?`n", " ")"
}

function Jg-Excluded([string]$Path) {
  git check-ignore -q -- $Path 2>$null
  if ($LASTEXITCODE -eq 0) { return $true }
  foreach ($g in @(git config --get-all jev-guard.exclude 2>$null)) {
    if ($g -and $Path -like $g) { return $true }
  }
  return $false
}

# See lib.sh. An untracked file is read whole; a NUL byte means binary.
function Jg-Added([string]$Base, [string]$Tree, [string]$Path) {
  if ($Tree) { $d = git diff --no-color $Base $Tree -- $Path 2>$null }
  else {
    git ls-files --error-unmatch -- $Path *> $null
    if ($LASTEXITCODE -ne 0) {
      $t = [IO.File]::ReadAllText((Join-Path (git rev-parse --show-toplevel) $Path))
      if ($t.Contains([char]0)) { return "" }
      return $t.TrimEnd("`r", "`n")
    }
    $d = git diff --no-color $Base -- $Path 2>$null
  }
  return (@($d) | Where-Object { $_ -like "+*" -and $_ -notlike "+++ *" } |
          ForEach-Object { $_.Substring(1) }) -join "`n"
}

function Jg-Ask([string]$Path, [string]$Text) {
  $q = Get-Content -Raw (Join-Path $PSScriptRoot "questions.json")
  $key = ("$Path`n$Text" + $q) | git hash-object --stdin
  $c = Join-Path (Jg-Dir) "cache/$key"
  if (Test-Path $c) { return (Get-Content $c -Raw).Trim() -split " " }
  $down = Join-Path (Jg-Dir) "api-down"
  if ((Test-Path $down) -and (Get-Item $down).LastWriteTime -gt (Get-Date).AddMinutes(-1)) { return $null }
  $body = @{ model = "jev-latest"; state = @{ path = $Path; added_lines = $Text };
             questions = ($q | ConvertFrom-Json) } | ConvertTo-Json -Depth 10 -Compress
  # curl, not Invoke-RestMethod: same client as the sh side, present on
  # Windows 10+ as curl.exe (plain "curl" is an alias there), and it lets the
  # tests stand in for the API with a file:// URL.
  $curl = if ($env:OS -eq "Windows_NT") { "curl.exe" } else { "curl" }
  try {
    # See lib.sh: only a network error or a 5xx marks the service as down.
    $raw = @($body | & $curl -sS --max-time 2 -w "`n%{http_code}" -H "Authorization: Bearer $env:TYPESAFE_API_KEY" `
             -H "Content-Type: application/json" --data-binary "@-" $JgUrl 2>&1)
    if ($LASTEXITCODE -ne 0) { Set-Content -Path $down -Value ""; throw "$raw" }
    $code = "$($raw[-1])"
    $text = ($raw | Select-Object -SkipLast 1) -join "`n"
    if ($code -like "5*") { Set-Content -Path $down -Value ""; throw "HTTP $code $text" }
    if ($code -like "4*") { throw "HTTP $code $text" }
    $r = $text | ConvertFrom-Json
    $n = $r.answers.secret.noul
    if ($null -eq $n) { throw "unexpected response: $raw" }
  } catch { Jg-Log "api: $_"; return $null }
  $k = if ($r.answers.kind.choice) { $r.answers.kind.choice } else { "unknown" }
  $f = if ($null -ne $r.answers.kind.confidence) { $r.answers.kind.confidence } else { 0 }
  $ans = "{0} {1} {2}" -f ([double]$n).ToString($Inv), $k, ([double]$f).ToString($Inv)
  Set-Content -Path $c -Value $ans
  return $ans -split " "
}

# See lib.sh: jg_prob. A threshold that is not a plain number in [0, 1] falls
# back to its default.
function Jg-Prob([string]$Name, [string]$Default) {
  $v = Jg-Config $Name $Default
  $x = 0.0
  if ($v -match '^[0-9.]+$' -and [double]::TryParse($v, [Globalization.NumberStyles]::Float, $Inv, [ref]$x) -and $x -le 1) { return $x }
  return [double]::Parse($Default, $Inv)
}

function Jg-Decide([string]$P, [string]$Kind, [string]$Conf) {
  $d = { param($s) [double]::Parse($s, $Inv) }
  $p = & $d $P
  if ($p -ge (Jg-Prob "blockThreshold" "0.70")) { if ((Jg-Mode) -eq "strict") { return "block" } else { return "warn" } }
  if ($p -ge (Jg-Prob "warnThreshold" "0.60")) { return "warn" }
  if ($Kind -eq "artifact" -and (& $d $Conf) -ge (Jg-Prob "artifactConfidence" "0.80")) { return "artifact" }
  return "pass"
}

# See lib.sh: jg_scan. Returns a "<verdict>`t<path>`t<why>" line, or nothing.
function Jg-Scan([string]$Base, [string]$Tree, [string]$Path) {
  if (Jg-Excluded $Path) { return }
  $add = Jg-Added $Base $Tree $Path
  if (-not $add) { return }
  if (Get-Command gitleaks -ErrorAction SilentlyContinue) {
    $add | gitleaks stdin --no-banner -l error --exit-code 42 *> $null
    if ($LASTEXITCODE -eq 42) {
      $v = if ((Jg-Mode) -eq "strict") { "block" } else { "warn" }
      return "$v`t$Path`tgitleaks"
    }
  }
  # See lib.sh: maxKb gates the API call only, and falls back on bad input.
  $kb = 0
  if (-not [int]::TryParse((Jg-Config "maxKb" "64"), [ref]$kb) -or $kb -lt 0) { $kb = 64 }
  $sz = [Text.Encoding]::UTF8.GetByteCount($add)
  if ($sz -gt $kb * 1024) { return "skipped`t$Path`tnot sent, $([math]::Floor($sz / 1024)) KB added (maxKb $kb)" }
  $a = Jg-Ask $Path $add
  if (-not $a) { return }
  switch (Jg-Decide $a[0] $a[1] $a[2]) {
    "pass" { }
    "artifact" { "artifact`t$Path`tlooks generated ($($a[2]))" }
    default { "$_`t$Path`tsecret p=$($a[0])" }
  }
}

# See lib.sh: jg_wire. Runs the pre-checkpoint with this very PowerShell.
function Jg-Wire {
  $exe = (Get-Process -Id $PID).Path
  # See lib.sh: the Test-Path turns a stale path into a no-op.
  # Apostrophes doubled for the single quotes: C:\Users\O'Brien must not turn
  # the command into a syntax error that silently disarms the guard.
  $s = (Join-Path $PSScriptRoot "pre-checkpoint.ps1").Replace("'", "''")
  $exe = $exe.Replace("'", "''")
  $want = "if (Test-Path '$s') { & '$exe' -NoProfile -ExecutionPolicy Bypass -File '$s' }"
  $have = (git config --get git-sync.preCheckpoint 2>$null)
  if ($have -and $have -notlike "*jev-guard*") { return }
  if ($have -ne $want) { git config git-sync.preCheckpoint $want }
}

function Jg-Report([string[]]$Lines) {
  ($Lines | Where-Object { $_ } | ForEach-Object {
    $v, $p, $why = $_ -split "`t"
    if ($v -eq "skipped") { "- ${p}: $why" }
    elseif ($v -eq "artifact") { "- ${p}: $why, consider git-sync ignore-patterns" }
    elseif ($v -eq "block") { "- ${p}: BLOCKED, plaintext secret ($why)" }
    else { "- ${p}: possible plaintext secret ($why)" }
  }) -join "`n"
}
