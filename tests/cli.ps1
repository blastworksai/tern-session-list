# Contract-drift test: bin/session-list.ps1 (PowerShell) must behave exactly like
# bin/session-list (POSIX sh). Run with: pwsh -File tests/cli.ps1 [scratch dir]
#
# Part 1, against the DEV copy of the plugin (id "session-list-test") with two
# scratch panes: the same steps run through `sh session-list` as pane A and
# through `pwsh session-list.ps1` as pane B; stdout, stderr and exit codes are
# compared pairwise after normalising list ids (l_xxxxxxxx -> l_X) and pane ids.
# Part 2, against a fake host in the scratch folder: the request FILES both
# commands write are compared byte for byte, and each answer status maps to the
# same output stream and exit code. Part 3: no host at all -> same timeout.
#
# Never touches the real plugin: the real id is never linked, and the real data
# folder's listas/ is hashed before and after (ABSENT when missing).
# Never touches the person's windows: panes live in a dedicated session made
# here (`tern new session`/`tern new tab` do not change what windows show,
# measured 2026-11-02), and every window's "(shown)" markers are compared at the end.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

$P = Split-Path -Parent $PSScriptRoot
$SH_CMD = Join-Path $P 'bin/session-list'
$PS_CMD = Join-Path $P 'bin/session-list.ps1'
$ID = 'session-list-test'
$SESSAO = 'sl-cli-ps-test'
$PWSH = (Get-Process -Id $PID).Path

$TERN_DIR = if ($env:TERN_CONFIG_DIR) { $env:TERN_CONFIG_DIR } else { Join-Path $HOME 'Library/Application Support/Tern' }
$REAL = Join-Path $TERN_DIR 'plugin-data/session-list/listas'
$DEV = Join-Path $TERN_DIR "plugin-data/$ID"

if (-not $DEV.StartsWith('/')) { [Console]::Error.WriteLine("refusing: the dev data folder is not an absolute path: $DEV"); exit 1 }
if ((Split-Path -Leaf $DEV) -cne $ID) { [Console]::Error.WriteLine("refusing: unexpected dev data folder: $DEV"); exit 1 }

$utf8 = New-Object System.Text.UTF8Encoding $false

class Falha : System.Exception { Falha([string]$m) : base($m) {} }
function Fail([string]$m) { throw [Falha]::new($m) }
function Passo([string]$m) { Write-Host "ok - $m" }

# Absolute path, no ~, file by file, then the folders deepest first (never -Recurse).
function Remove-Arvore([string]$dir) {
	if (-not $dir.StartsWith('/') -or $dir.Contains('~')) { throw "refusing to remove a non-absolute path: $dir" }
	if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return }
	Get-ChildItem -LiteralPath $dir -File -Recurse -Force | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
	Get-ChildItem -LiteralPath $dir -Directory -Recurse -Force |
		Sort-Object { $_.FullName.Length } -Descending |
		ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
	Remove-Item -LiteralPath $dir -Force
}

# Hash of the real listas/: file names + contents; ABSENT when the folder is missing.
function Hash-Real {
	if (-not (Test-Path -LiteralPath $REAL -PathType Container)) { return 'ABSENT' }
	$sb = New-Object System.Text.StringBuilder
	$fs = @(Get-ChildItem -LiteralPath $REAL -File -Recurse -Force | ForEach-Object { $_.FullName } | Sort-Object -CaseSensitive)
	[Array]::Sort($fs, [StringComparer]::Ordinal)
	foreach ($f in $fs) {
		[void]$sb.Append($f + "`n" + (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash + "`n")
	}
	$h = [System.Security.Cryptography.SHA256]::Create().ComputeHash($utf8.GetBytes($sb.ToString()))
	return (($h | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Tern-Run([string[]]$a) {
	$o = & tern @a 2>&1
	if ($LASTEXITCODE -ne 0) { Fail "tern $($a -join ' ') -> exit $LASTEXITCODE`: $o" }
	return (@($o) -join "`n")
}

# Which session and tab each window shows (the same pipeline as cli.sh).
function Marcadores {
	$script = @'
tern inspect | awk '$2 == "window" { k = $3; gsub(/"/, "", k); print k }' | while IFS= read -r k; do
	echo "window [$k]"
	tern ls --window "$k" | grep '(shown)'
done
'@
	$o = $script | & sh
	return (@($o) -join "`n")
}

function Sessao-Existe { return [bool]((Tern-Run @('ls')) -split "`n" | Where-Object { $_ -match "^$([regex]::Escape($SESSAO))( |$)" }) }
function Pane-Existe([string]$p) { return [bool]((Tern-Run @('ls')) -split "`n" | Where-Object { $_ -match "^ *$p " }) }

function Nova-Pane([string]$tipo) {
	$j = Tern-Run @('new', $tipo, $SESSAO, '--json', '--', '/bin/sh')
	$m = [regex]::Match(($j -replace '[\s]', ''), '"block":(\d+)')
	if (-not $m.Success) { Fail "no pane id in: $j" }
	return $m.Groups[1].Value
}

# Runs one command with exact bytes in and out. $envs: name -> value ($null removes it).
function Roda([string]$exe, [string[]]$argv, [hashtable]$envs, [string]$stdin) {
	$psi = New-Object System.Diagnostics.ProcessStartInfo
	$psi.FileName = $exe
	foreach ($x in $argv) { $psi.ArgumentList.Add($x) }
	$psi.UseShellExecute = $false
	$psi.RedirectStandardInput = $true
	$psi.RedirectStandardOutput = $true
	$psi.RedirectStandardError = $true
	$psi.StandardOutputEncoding = $utf8
	$psi.StandardErrorEncoding = $utf8
	[void]$psi.Environment.Remove('SESSION_LIST_NO_ORPHANS')
	foreach ($k in $envs.Keys) {
		if ($null -eq $envs[$k]) { [void]$psi.Environment.Remove($k) } else { $psi.Environment[$k] = $envs[$k] }
	}
	$pr = [System.Diagnostics.Process]::Start($psi)
	$tOut = $pr.StandardOutput.ReadToEndAsync()
	$tErr = $pr.StandardError.ReadToEndAsync()
	$bin = $utf8.GetBytes($stdin)
	$pr.StandardInput.BaseStream.Write($bin, 0, $bin.Length)
	$pr.StandardInput.Close()
	$pr.WaitForExit()
	return [pscustomobject]@{ Out = $tOut.Result; Err = $tErr.Result; Rc = $pr.ExitCode }
}

function Roda-Sh([string[]]$argv, [hashtable]$envs, [string]$stdin) { return Roda 'sh' (@($SH_CMD) + $argv) $envs $stdin }
function Roda-Ps([string[]]$argv, [hashtable]$envs, [string]$stdin) { return Roda $PWSH (@('-NoProfile', '-File', $PS_CMD) + $argv) $envs $stdin }

function Normaliza([string]$s, [string[]]$panes) {
	$s = [regex]::Replace($s, 'l_[a-z0-9]{8}', 'l_X')
	foreach ($p in $panes) { if ($p) { $s = [regex]::Replace($s, "\b$([regex]::Escape($p))\b", 'PANE') } }
	return $s
}

function Mostra([string]$s) { return ($s.Replace("`n", '\n')) }

# Compares one sh run with one pwsh run; returns the sh run.
function Compara([string]$nome, $r1, $r2, [string[]]$panes, [int]$rcEsperado = -1) {
	$o1 = Normaliza $r1.Out $panes; $o2 = Normaliza $r2.Out $panes
	$e1 = Normaliza $r1.Err $panes; $e2 = Normaliza $r2.Err $panes
	if ($r1.Rc -ne $r2.Rc) { Fail "$nome`: exit sh=$($r1.Rc) pwsh=$($r2.Rc) (sh err: $(Mostra $r1.Err)) (pwsh err: $(Mostra $r2.Err))" }
	if ($o1 -cne $o2) { Fail "$nome`: stdout differs`n  sh:   $(Mostra $o1)`n  pwsh: $(Mostra $o2)" }
	if ($e1 -cne $e2) { Fail "$nome`: stderr differs`n  sh:   $(Mostra $e1)`n  pwsh: $(Mostra $e2)" }
	if ($rcEsperado -ge 0 -and $r1.Rc -ne $rcEsperado) { Fail "$nome`: exit $($r1.Rc), expected $rcEsperado (out: $(Mostra $r1.Out)) (err: $(Mostra $r1.Err))" }
	return $r1
}

$SCRATCH = $null
$FEZ_SCRATCH = $false
$PANES = New-Object System.Collections.Generic.List[string]
$FEZ_SESSAO = $false
$LINKOU = $false
$HASH_ANTES = $null
$MARC_ANTES = $null
$JOB = $null
$rc = 0

try {
	if ($args.Count -ge 1) {
		$SCRATCH = [System.IO.Path]::GetFullPath([string]$args[0])
		[void][System.IO.Directory]::CreateDirectory($SCRATCH)
	} else {
		$SCRATCH = Join-Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) ("sl-cli-ps-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
		[void][System.IO.Directory]::CreateDirectory($SCRATCH)
		$FEZ_SCRATCH = $true
	}

	# ---- 1. the real data folder, before anything ------------------------------
	$HASH_ANTES = Hash-Real
	Passo "1. real listas/ hash before: $HASH_ANTES"

	# ---- 2. scratch panes, without changing what the windows show --------------
	$MARC_ANTES = Marcadores
	if (-not $MARC_ANTES) { Fail "could not read the windows' shown markers" }
	if (Sessao-Existe) {
		$MARC_ANTES = $null
		Fail "a session named $SESSAO already exists; not touching it"
	}
	if ((Tern-Run @('plugin', 'list')) -match [regex]::Escape($ID)) {
		Tern-Run @('plugin', 'unlink', $ID) | Out-Null
	}
	Remove-Arvore $DEV

	$COPIA = (& sh (Join-Path $P 'tests/dev-copy.sh') (Join-Path $SCRATCH 'dev') false)
	if ($LASTEXITCODE -ne 0) { Fail 'dev-copy.sh failed' }
	$toml = Get-Content -Raw -LiteralPath (Join-Path $COPIA 'plugin.toml')
	if ($toml -notmatch "(?m)^id = `"$ID`"$") { Fail "the copy's id is not $ID" }
	if ($toml -match '(?m)^id = "session-list"$') { Fail 'the copy still carries the real id' }
	$LINKOU = $true
	Tern-Run @('plugin', 'link', $COPIA) | Out-Null
	$n = 0
	while (-not ((Tern-Run @('plugin', 'list')) -split "`n" | Where-Object { $_ -match [regex]::Escape($ID) -and $_ -match 'ready' })) {
		$n += 1
		if ($n -gt 50) { Fail "$ID did not load: $(Tern-Run @('plugin','list'))" }
		Start-Sleep -Milliseconds 100
	}

	$FEZ_SESSAO = $true
	$A = Nova-Pane 'session'; $PANES.Add($A)
	$B = Nova-Pane 'tab'; $PANES.Add($B)
	if ((Marcadores) -cne $MARC_ANTES) { Fail "creating the scratch panes changed a window's shown session/tab" }
	Passo "2. dev copy linked, scratch session $SESSAO with panes A=$A (sh) B=$B (pwsh), windows unchanged"

	# ---- 3. the same steps through both commands, against the dev copy --------
	$envA = @{ TERN_PANE = $A; SESSION_LIST_DATA = $DEV }
	$envB = @{ TERN_PANE = $B; SESSION_LIST_DATA = $DEV }
	$panes = @($A, $B)
	$passos = @(
		@{ n = 'add 3 --subject'; a = @('add', 'part one', 'part two', 'part three', '--subject', 'cli test'); i = ''; rc = 0 },
		@{ n = 'done i1'; a = @('done', 'i1'); i = ''; rc = 0 },
		@{ n = 'block i2 reason'; a = @('block', 'i2', 'waiting for X'); i = ''; rc = 0 },
		@{ n = 'show'; a = @('show'); i = ''; rc = 0 },
		@{ n = 'check --hook {}'; a = @('check', '--hook'); i = '{}'; rc = 2 },
		@{ n = 'check --hook again'; a = @('check', '--hook'); i = '{}'; rc = 0 },
		@{ n = 'unknown verb'; a = @('frobnicate'); i = ''; rc = 1 },
		@{ n = 'done i99'; a = @('done', 'i99'); i = ''; rc = 0 },
		@{ n = 'help'; a = @('help'); i = ''; rc = 0 },
		@{ n = 'no arguments'; a = @(); i = ''; rc = 0 },
		@{ n = 'flags only'; a = @('--again'); i = ''; rc = 0 },
		@{ n = '--subject without value'; a = @('add', 'x', '--subject'); i = ''; rc = 1 },
		@{ n = 'add with a newline'; a = @('add', "two`nlines"); i = ''; rc = 0 },
		@{ n = 'check without --hook'; a = @('check'); i = ''; rc = 0 }
	)
	foreach ($s in $passos) {
		$r1 = Roda-Sh $s.a $envA $s.i
		$r2 = Roda-Ps $s.a $envB $s.i
		$r = Compara $s.n $r1 $r2 $panes $s.rc
		if ($s.n -eq 'show' -and -not $r.Out.Contains("☐ i3 part three")) { Fail "show: no open line: $(Mostra $r.Out)" }
		if ($s.n -eq 'check --hook {}' -and (-not $r.Err.Contains('i3 part three') -or $r.Out -ne '')) { Fail "check --hook: reminder not on stderr: $(Mostra $r.Err)" }
	}
	$r1 = Roda-Sh @('show') @{ TERN_PANE = $null; SESSION_LIST_DATA = $DEV } ''
	$r2 = Roda-Ps @('show') @{ TERN_PANE = $null; SESSION_LIST_DATA = $DEV } ''
	[void](Compara 'no TERN_PANE' $r1 $r2 $panes 1)
	Passo "3. $($passos.Count + 1) steps: sh (A) and pwsh (B) give the same stdout, stderr and exit codes"

	# ---- 4. the request files, byte for byte, through a fake host --------------
	$FAKE = Join-Path $SCRATCH 'fake'
	$CAPT = Join-Path $SCRATCH 'captured'
	foreach ($d in @("$FAKE/pedidos", "$FAKE/respostas", $CAPT)) { [void][System.IO.Directory]::CreateDirectory($d) }
	$PARE = Join-Path $SCRATCH 'fake.stop'
	$JOB = Start-Job -ArgumentList $FAKE, $CAPT, $PARE -ScriptBlock {
		param($fake, $capt, $pare)
		$u = New-Object System.Text.UTF8Encoding $false
		while (-not (Test-Path -LiteralPath $pare)) {
			foreach ($f in [System.IO.Directory]::GetFiles("$fake/pedidos")) {
				if (-not $f.EndsWith('.req')) { continue }
				$b = [System.IO.File]::ReadAllBytes($f)
				$t = $u.GetString($b)
				if (-not $t.EndsWith("end=1`n")) { continue }
				$nome = [System.IO.Path]::GetFileName($f)
				[System.IO.File]::WriteAllBytes("$capt/$nome", $b)
				[System.IO.File]::Delete($f)
				$N = $nome.Substring(0, $nome.Length - 4)
				$verb = ([regex]::Match($t, '(?m)^verb=(.*)$')).Groups[1].Value
				$ans = switch ($verb) {
					'check' { "status=remind`nremind line 1`nremind line 2`n`n" }
					'fail' { "status=error`nfake error" }
					'garbage' { "nonsense`n" }
					'nores' { $null }
					default { "status=ok`nfake ok ☐ çã`n" }
				}
				if ($null -ne $ans) { [System.IO.File]::WriteAllText("$fake/respostas/$N.res", $ans, $u) }
				[System.IO.File]::WriteAllText("$fake/respostas/$N.done", '', $u)
			}
			Start-Sleep -Milliseconds 20
		}
	}
	$envF = @{ TERN_PANE = '777'; SESSION_LIST_DATA = $FAKE }
	$envFN = @{ TERN_PANE = "7`n77"; SESSION_LIST_DATA = $FAKE; SESSION_LIST_NO_ORPHANS = '1' }
	$casos = @(
		@{ n = 'add, newline, =, subject, again'; a = @('add', "a`nb", 'k=v=w', '', '--again', '--subject', "s`nt", 'ação ☐'); i = ''; e = $envF; rc = 0 },
		@{ n = 'noorphans, pane with newline'; a = @('show'); i = ''; e = $envFN; rc = 0 },
		@{ n = 'check --hook, multi-line stdin'; a = @('check', '--hook'); i = "{`"a`":1,`n`"b`":`"x\\y`"}`n`n"; e = $envF; rc = 2 },
		@{ n = 'check --hook, stdin no final newline'; a = @('--hook', 'check', 'extra'); i = "{}"; e = $envF; rc = 2 },
		@{ n = 'check --hook, empty stdin'; a = @('check', '--hook'); i = ''; e = $envF; rc = 2 },
		@{ n = 'check (remind on stdout)'; a = @('check'); i = 'ignored'; e = $envF; rc = 0 },
		@{ n = '--hook on another verb'; a = @('show', '--hook'); i = 'ignored'; e = $envF; rc = 0 },
		@{ n = 'status=error'; a = @('fail'); i = ''; e = $envF; rc = 1 },
		@{ n = 'unknown status'; a = @('garbage'); i = ''; e = $envF; rc = 1 },
		@{ n = 'done with no .res'; a = @('nores'); i = ''; e = $envF; rc = 1 }
	)
	foreach ($c in $casos) {
		$lidos = @()
		$rs = @()
		foreach ($quem in @('sh', 'pwsh')) {
			$r = if ($quem -eq 'sh') { Roda-Sh $c.a $c.e $c.i } else { Roda-Ps $c.a $c.e $c.i }
			$rs += $r
			$fs = @([System.IO.Directory]::GetFiles($CAPT))
			if ($fs.Count -ne 1) { Fail "$($c.n) ($quem): expected 1 captured request, found $($fs.Count) (err: $(Mostra $r.Err))" }
			$nome = [System.IO.Path]::GetFileName($fs[0])
			if ($nome -notmatch '^\d+-\d+-[0-9a-f]{8}\.req$') { Fail "$($c.n) ($quem): bad request name $nome" }
			$lidos += , [System.IO.File]::ReadAllBytes($fs[0])
			[System.IO.File]::Delete($fs[0])
		}
		$t1 = $utf8.GetString($lidos[0]); $t2 = $utf8.GetString($lidos[1])
		if ($lidos[0].Length -ne $lidos[1].Length -or $t1 -cne $t2) { Fail "$($c.n): request bytes differ`n  sh:   $(Mostra $t1)`n  pwsh: $(Mostra $t2)" }
		if ($lidos[1].Length -ge 3 -and $lidos[1][0] -eq 0xEF -and $lidos[1][1] -eq 0xBB) { Fail "$($c.n): request has a BOM" }
		if (-not $t1.StartsWith("v=1`n") -or -not $t1.EndsWith("end=1`n")) { Fail "$($c.n): request framing wrong: $(Mostra $t1)" }
		[void](Compara $c.n $rs[0] $rs[1] @() $c.rc)
	}
	foreach ($f in @([System.IO.Directory]::GetFiles("$FAKE/pedidos")) + @([System.IO.Directory]::GetFiles("$FAKE/respostas"))) {
		Fail "left behind: $f"
	}
	Passo "4. $($casos.Count) fake-host cases: request files byte-identical, same streams and exit codes"

	# ---- 5. no host at all: the same timeout -----------------------------------
	$SEM = Join-Path $SCRATCH 'nohost'
	$r1 = Roda-Sh @('show') @{ TERN_PANE = '777'; SESSION_LIST_DATA = $SEM } ''
	$r2 = Roda-Ps @('show') @{ TERN_PANE = '777'; SESSION_LIST_DATA = $SEM } ''
	$r = Compara 'no host' $r1 $r2 @() 1
	if (-not $r.Err.Contains('did not answer')) { Fail "no host: wrong message: $(Mostra $r.Err)" }
	if (@([System.IO.Directory]::GetFiles("$SEM/pedidos")).Count -ne 0) { Fail 'no host: a request was left behind' }
	Passo '5. no host: both time out after 5 s with the same message, exit 1, request removed'
} catch [Falha] {
	[Console]::Error.WriteLine("FAIL: $($_.Exception.Message)")
	$rc = 1
} catch {
	[Console]::Error.WriteLine("FAIL (error): $($_.Exception.Message) at $($_.InvocationInfo.PositionMessage)")
	$rc = 1
} finally {
	if ($JOB) {
		if ($SCRATCH) { [System.IO.File]::WriteAllText((Join-Path $SCRATCH 'fake.stop'), '') }
		Stop-Job $JOB -ErrorAction SilentlyContinue
		Remove-Job $JOB -Force -ErrorAction SilentlyContinue
	}
	foreach ($p in $PANES) {
		try { if (Pane-Existe $p) { & tern close $p *> $null } } catch {}
	}
	if ($FEZ_SESSAO) {
		# Seen once: a kill racing the session's own end left it empty but listed; retry up to 3 s.
		for ($k = 0; $k -lt 30; $k++) {
			& tern kill session $SESSAO *> $null
			Start-Sleep -Milliseconds 100
			try { if (-not (Sessao-Existe)) { break } } catch { break }
		}
	}
	if ($LINKOU) {
		& tern plugin unlink $ID *> $null
		if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine("FAIL: could not unlink $ID"); $rc = 1 }
	}
	try { Remove-Arvore $DEV } catch { [Console]::Error.WriteLine("FAIL: $($_.Exception.Message)"); $rc = 1 }
	if (Test-Path -LiteralPath $DEV) { [Console]::Error.WriteLine("FAIL: the dev data folder is still there: $DEV"); $rc = 1 }
	if ($SCRATCH) {
		if ($FEZ_SCRATCH) {
			try { Remove-Arvore $SCRATCH } catch { [Console]::Error.WriteLine("FAIL: $($_.Exception.Message)"); $rc = 1 }
		} else {
			foreach ($d in @('dev', 'fake', 'captured', 'nohost', 'fake.stop')) {
				$x = Join-Path $SCRATCH $d
				if (Test-Path -LiteralPath $x -PathType Leaf) { Remove-Item -LiteralPath $x -Force } else { try { Remove-Arvore $x } catch { $rc = 1 } }
			}
		}
	}
	if ($null -ne $HASH_ANTES) {
		$h = Hash-Real
		if ($h -eq $HASH_ANTES) { Passo "6. cleanup: real listas/ hash unchanged ($h)" }
		else { [Console]::Error.WriteLine("FAIL: the real listas/ changed: $HASH_ANTES -> $h"); $rc = 1 }
	}
	if ($MARC_ANTES) {
		$m = Marcadores
		if ($m -ceq $MARC_ANTES) { Passo '6. cleanup: every window shows what it showed at the start' }
		else { [Console]::Error.WriteLine("FAIL: a window's shown session/tab changed`nbefore:`n$MARC_ANTES`nafter:`n$m"); $rc = 1 }
	}
	if ($FEZ_SESSAO -and (Sessao-Existe)) { [Console]::Error.WriteLine("FAIL: session $SESSAO is still there"); $rc = 1 }
	if ($rc -eq 0) { Write-Host 'PASS' }
}
exit $rc
