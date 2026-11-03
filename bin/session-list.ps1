# English-first interactive checkpoint reader. CodexBWAI, COMMANDER-993.
$reader = Join-Path $PSScriptRoot 'estate_session_list.py'
if (Get-Command py -ErrorAction SilentlyContinue) { & py -3 -I $reader @args }
elseif (Get-Command python3 -ErrorAction SilentlyContinue) { & python3 -I $reader @args }
else { Write-Error 'Python 3 is required on this machine.'; exit 1 }
if ($LASTEXITCODE -eq 2) { exit 1 }
exit $LASTEXITCODE
