# PostToolUse on Edit|Write|MultiEdit. See hooks/post-edit.sh.
. (Join-Path $PSScriptRoot "lib.ps1")

try { $file = ([Console]::In.ReadToEnd() | ConvertFrom-Json).tool_input.file_path } catch { exit 0 }
if (-not $file -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { exit 0 }
Set-Location (Split-Path -Parent $file)
if (-not (Jg-Active)) { exit 0 }
git rev-parse -q --verify HEAD *> $null
if ($LASTEXITCODE -ne 0) { exit 0 }

Jg-Wire
# See post-edit.sh: the relative path comes from git, not from string surgery.
$rel = "$(git rev-parse --show-prefix)$(Split-Path -Leaf $file)"
Set-Location (git rev-parse --show-toplevel)

$out = @(Jg-Scan "HEAD" "" $rel)
if (-not $out) { exit 0 }
$report = Jg-Report $out

if ($out[0] -like "block*") {
  @{ decision = "block"; reason = "jev-guard (strict): $report`nRemove the secret from this file (read it from an environment variable instead) before continuing. git-sync will refuse to push a checkpoint while it is there." } |
    ConvertTo-Json -Compress
} else {
  @{ systemMessage = "jev-guard: $report"; hookSpecificOutput = @{ hookEventName = "PostToolUse";
     additionalContext = "jev-guard flagged the file just written: $report`nIf this is a real credential, move it to an environment variable. If it is a placeholder or test value, say so to the user and carry on." } } |
    ConvertTo-Json -Compress
}
exit 0
