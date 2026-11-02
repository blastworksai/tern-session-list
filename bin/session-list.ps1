# session-list: this Tern tab's session list, as a command (PowerShell).
# The Windows twin of bin/session-list (POSIX sh): same verbs, flags, request
# content, outputs and exit codes, held to them by tests/cli.ps1.
# Talks to the session-list plugin's host half through request files, exactly
# as THE REQUEST PROTOCOL in plans/tern-session-list-plugin.md fixes it:
# D/pedidos/N.req (written as .tmp, then Move-Item) -> D/respostas/N.res + N.done.
# Runs on Windows PowerShell 5.1 and PowerShell 7+.

$ErrorActionPreference = 'Stop'

# These two texts MUST match lib/textos.luau (English: semResposta, ajuda) and bin/session-list.
$SEM_RESPOSTA = 'Tern''s session-list plugin did not answer: is Tern running with the plugin loaded? Run `tern plugin list`.'
$AJUDA = @'
session-list: this Tern tab's session list (the parts of the work agreed with the person that are still open).

  session-list add "<text>"...      add items, one per argument
      --subject <s>                 also name the list
      --again                       re-add a text the person removed by hand
  session-list doing <id>           mark the item you are working on (one at a time)
  session-list done <id>...         tick items as done
  session-list undo <id>...         untick done items
  session-list remove <id>...       remove items
  session-list name <subject>       name the list
  session-list block <id> <reason>  mark an item as waiting on someone
  session-list unblock <id>         back to open
  session-list show                 show this tab's list and lists closed tabs left
  session-list adopt <listId>       take over a list a closed tab left
  session-list discard <listId>     discard a list a closed tab left
  session-list start                session-start hook: the list and orphan questions
  session-list check                stop hook: reminds of open items
      --hook                        read the hook's JSON on stdin, exit 2 to remind
  session-list help                 this screen

Every answer is the list as it now stands.
'@
# A CRLF checkout must not change the text.
$AJUDA = $AJUDA.Replace("`r`n", "`n")

$utf8 = New-Object System.Text.UTF8Encoding $false

# Exact bytes, UTF-8, "\n" line ends, like the sh command (no console code page involved).
function Escreve([System.IO.Stream]$fluxo, [string]$texto) {
	$w = New-Object System.IO.StreamWriter($fluxo, $utf8)
	$w.Write($texto + "`n")
	$w.Flush()
}
function Sai([string]$texto) { Escreve ([Console]::OpenStandardOutput()) $texto }
function Erro([string]$texto) { Escreve ([Console]::OpenStandardError()) $texto }

# A value goes on one line: every newline becomes a space.
function UmaLinha([string]$s) { return $s.Replace("`n", ' ') }

$a = @($args | ForEach-Object { [string]$_ })

$primeiro = if ($a.Count -gt 0) { $a[0] } else { '' }
if ($primeiro -eq '' -or $primeiro -ceq 'help' -or $primeiro -ceq '-h' -or $primeiro -ceq '--help') {
	Sai $AJUDA
	exit 0
}

if ([string]::IsNullOrEmpty($env:TERN_PANE)) {
	Erro 'session-list only works inside a Tern pane.'
	exit 1
}

# Where the plugin's data folder is.
$naWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or ($IsWindows -eq $true)
if (-not [string]::IsNullOrEmpty($env:SESSION_LIST_DATA)) {
	$D = $env:SESSION_LIST_DATA
} elseif (-not [string]::IsNullOrEmpty($env:TERN_CONFIG_DIR)) {
	$D = Join-Path (Join-Path $env:TERN_CONFIG_DIR 'plugin-data') 'session-list'
} elseif ($naWindows) {
	# Windows: unverified (Tern's folder there was never measured).
	$D = Join-Path $env:APPDATA 'Tern\plugin-data\session-list'
} elseif ($IsMacOS) {
	$D = Join-Path $HOME 'Library/Application Support/Tern/plugin-data/session-list'
} else {
	# Linux: unverified, same guess as the sh command.
	$base = if ([string]::IsNullOrEmpty($env:XDG_CONFIG_HOME)) { Join-Path $HOME '.config' } else { $env:XDG_CONFIG_HOME }
	$D = Join-Path $base 'tern/plugin-data/session-list'
}

$verb = ''
$argLinhas = ''
$subject = ''
$again = $false
$hook = $false
$i = 0
while ($i -lt $a.Count) {
	$x = $a[$i]
	if ($x -ceq '--subject') {
		if ($i + 1 -ge $a.Count) {
			Erro 'session-list: --subject needs a value.'
			exit 1
		}
		$subject = UmaLinha $a[$i + 1]
		$i += 2
		continue
	} elseif ($x -ceq '--again') {
		$again = $true
	} elseif ($x -ceq '--hook') {
		$hook = $true
	} elseif ($verb -eq '') {
		$verb = UmaLinha $x
	} else {
		$argLinhas += 'arg=' + (UmaLinha $x) + "`n"
	}
	$i += 1
}

if ($verb -eq '') {
	Sai $AJUDA
	exit 0
}

# --hook only means something for check; only then is stdin read.
if ($verb -cne 'check') {
	$hook = $false
}
$stopinput = ''
if ($hook) {
	$leitor = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), $utf8)
	$entrada = $leitor.ReadToEnd()
	# Same as the sh command's awk: lines joined by a literal \n, a final newline dropped.
	if ($entrada -ne '') {
		$linhas = $entrada.Split("`n")
		if ($entrada.EndsWith("`n")) {
			$linhas = $linhas[0..($linhas.Count - 2)]
		}
		$stopinput = $linhas -join '\n'
	}
}

$bytes = New-Object byte[] 4
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)
$hex = ($bytes | ForEach-Object { $_.ToString('x2') }) -join ''
$N = '{0}-{1}-{2}' -f [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(), $PID, $hex

$pedidos = Join-Path $D 'pedidos'
$respostas = Join-Path $D 'respostas'
try {
	[void][System.IO.Directory]::CreateDirectory($pedidos)
	[void][System.IO.Directory]::CreateDirectory($respostas)
} catch {
	Erro ('session-list: ' + $_.Exception.Message)
	exit 1
}
$req = Join-Path $pedidos "$N.req"
$res = Join-Path $respostas "$N.res"
$done_ = Join-Path $respostas "$N.done"

$texto = "v=1`n"
$texto += 'pane=' + (UmaLinha $env:TERN_PANE) + "`n"
$texto += "verb=$verb`n"
$texto += $argLinhas
if ($subject -ne '') { $texto += "subject=$subject`n" }
if ($again) { $texto += "again=1`n" }
if (-not [string]::IsNullOrEmpty($env:SESSION_LIST_NO_ORPHANS)) { $texto += "noorphans=1`n" }
if ($hook) { $texto += "stopinput=$stopinput`n" }
$texto += "end=1`n"

try {
	[System.IO.File]::WriteAllText("$req.tmp", $texto, $utf8)
	Move-Item -LiteralPath "$req.tmp" -Destination $req
} catch {
	Erro ('session-list: ' + $_.Exception.Message)
	exit 1
}

# Poll for the answer: every 0.1 s up to 5 s.
$vezes = 50
$n = 0
while (-not (Test-Path -LiteralPath $done_ -PathType Leaf)) {
	if ($n -ge $vezes) {
		Erro $SEM_RESPOSTA
		Remove-Item -LiteralPath $req -Force -ErrorAction SilentlyContinue
		exit 1
	}
	Start-Sleep -Milliseconds 100
	$n += 1
}

# First line is the status; the rest is the text, trailing newlines dropped (as sh's $(...)).
$status = ''
$resto = ''
try {
	$conteudo = [System.IO.File]::ReadAllText($res, $utf8)
	$corte = $conteudo.IndexOf("`n")
	if ($corte -lt 0) {
		$status = $conteudo
	} else {
		$status = $conteudo.Substring(0, $corte)
		$resto = $conteudo.Substring($corte + 1).TrimEnd("`n")
	}
} catch {
	$status = ''
	$resto = ''
}
Remove-Item -LiteralPath $res -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $done_ -Force -ErrorAction SilentlyContinue

if ($status -ceq 'status=ok') {
	Sai $resto
	exit 0
} elseif ($status -ceq 'status=remind') {
	if ($hook) {
		Erro $resto
		exit 2
	}
	Sai $resto
	exit 0
} else {
	Erro $resto
	exit 1
}
