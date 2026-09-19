# Called by git-sync before it pushes a checkpoint. See hooks/pre-checkpoint.sh
# for the contract: stdout is shown, exit 75 stops the push, anything else not.
. (Join-Path $PSScriptRoot "lib.ps1")

if (-not (Jg-Active)) { exit 0 }
git rev-parse -q --verify HEAD *> $null
if ($LASTEXITCODE -ne 0) { exit 0 }
Set-Location (git rev-parse --show-toplevel)
$base = if ($env:GS_BASE) { $env:GS_BASE } else { "HEAD" }
$files = if ($env:GS_TREE) { git -c core.quotePath=false diff --name-only --no-renames $base $env:GS_TREE }
         else { @(git -c core.quotePath=false diff --name-only --no-renames HEAD) +
                @(git -c core.quotePath=false ls-files -o --exclude-standard) }
$now = { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
$deadline = if ($env:GS_DEADLINE) { [long]$env:GS_DEADLINE } else { (& $now) + 8 }

# ponytail: sequential calls, see pre-checkpoint.sh.
# See pre-checkpoint.sh: time budget under git-sync's 15 s Stop timeout.
$out = @($files | Where-Object { $_ } | ForEach-Object {
  if ((& $now) + 3 -gt $deadline) { "skipped`t$_`tnot scanned, time budget" }
  else { Jg-Scan $base $env:GS_TREE $_ }
})
if (-not $out) { exit 0 }
if ($out | Where-Object { $_ -like "block*" }) {
  "jev-guard: checkpoint NOT pushed, plaintext secret found:`n$(Jg-Report $out)"
  exit 75
}
"jev-guard:`n$(Jg-Report $out)"
exit 0
