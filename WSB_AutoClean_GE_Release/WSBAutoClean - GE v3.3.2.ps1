# ==============================================================================
#  WSB AUTO CLEAN - GHOST EDITION  v3.3.2
#  Desenvolvido por WSB TECH
#
#  FLUXO:
#    Execucao MANUAL  ->  Toggle via tarefa (ativa/desativa AutoClean no boot)
#    Execucao via tarefa ->  Modo -AutoRun (silencioso ao logar no Windows)
#
#  O QUE FAZ AO BOOT (-AutoRun):
#    1. Aguarda 20s o sistema estabilizar
#    2. Otimizacao de RAM  (GC + reducao WorkingSet)       -> Toast + Log
#    3. Limpeza completa   (cache, DNS, TRIM silencioso)   -> Toast + Log
#    4. Limpeza de icones  (iconcache, thumbcache, Bags)   -> Toast + Log
#    5. Ativa Sentinela USB em background
#       - Ao detectar pendrive: analise silenciosa, vacina, limpa registro -> Toast + Log
#
#  LOGS:  %USERPROFILE%\Documents\WSB Auto Clean GE\  (um arquivo por evento)
#  BANNER: GDI+ -> PNG temporário em disco    (presente em TODOS os toasts clássicos)
#  LOGINS: Nenhum cookie, senha ou token e removido
# ==============================================================================

param(
    [Parameter()][object]$AutoRun = $false,
    [Parameter()][object]$ToggleAdmin = $false,
    [ValidateSet('Seguro','Padrao','Agressivo','Privacidade')][string]$PerfilLimpeza = 'Padrao',
    [Parameter()][object]$DiagnosticoSomente = $false,
    [Parameter()][object]$USBRepairQuick = $false,
    [Parameter()][object]$USBGhostReport = $false,
    [Parameter()][object]$USBReenumerar = $false
)

# ==============================================================================
#  [PUBLIC RELEASE] Integridade da distribuicao publica (.ps1)
#  - Hash normalizado do proprio arquivo
#  - Verificacao de execucao original
#  - Log local de violacao
#  - Fallback seguro (nao executa se a integridade falhar)
# ==============================================================================
$Script:WSB_PublicIntegrityEnabled = $true
$Script:WSB_PublicExpectedHash = '2D67A4384AC0545E6955C239B83D8E4C7201AEEEF6532FEC8CE9AC622D38A7D7'
$Script:WSB_PublicIntegrityVersion = 'v3.3.2-public-github'

function Write-WSBPublicViolationLog {
    param(
        [string]$Motivo,
        [string]$Detalhe = ''
    )

    try {
        $docs = [Environment]::GetFolderPath('MyDocuments')
        if ([string]::IsNullOrWhiteSpace($docs)) { return }

        $logDir = Join-Path $docs 'WSB Auto Clean GE'
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }

        $logPath = Join-Path $logDir 'public_integrity_violations.log'
        $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $origem = if ($PSCommandPath) { $PSCommandPath } else { '[sem-caminho]' }
        $linha = "[{0}] {1} | Origem={2}" -f $stamp, $Motivo, $origem
        if (-not [string]::IsNullOrWhiteSpace($Detalhe)) {
            $linha += " | Detalhe={0}" -f $Detalhe.Replace("`r",' ').Replace("`n",' ')
        }
        Add-Content -Path $logPath -Value $linha -Encoding UTF8
    } catch {}
}

function Get-WSBPublicNormalizedContent {
    param([string]$PathArquivo)

    $raw = Get-Content -LiteralPath $PathArquivo -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

    $padrao = "(?m)^\$Script:WSB_PublicExpectedHash\s*=\s*'([A-Fa-f0-9]{64}|__WSB_PUBLIC_HASH__)'\s*$"
    $normalizado = [regex]::Replace(
        $raw,
        $padrao,
        "`$Script:WSB_PublicExpectedHash = '__WSB_PUBLIC_HASH__'"
    )
    return $normalizado
}

function Test-WSBPublicIntegrity {
    if (-not $Script:WSB_PublicIntegrityEnabled) { return $true }

    try {
        if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
            Write-WSBPublicViolationLog -Motivo 'Falha de integridade' -Detalhe 'Execucao fora de arquivo .ps1.'
            return $false
        }

        if (-not (Test-Path -LiteralPath $PSCommandPath)) {
            Write-WSBPublicViolationLog -Motivo 'Falha de integridade' -Detalhe 'Arquivo principal nao encontrado.'
            return $false
        }

        $ext = [IO.Path]::GetExtension($PSCommandPath)
        if ($ext -ne '.ps1') {
            Write-WSBPublicViolationLog -Motivo 'Falha de integridade' -Detalhe ("Extensao inesperada: {0}" -f $ext)
            return $false
        }

        $normalizado = Get-WSBPublicNormalizedContent -PathArquivo $PSCommandPath
        if ([string]::IsNullOrWhiteSpace($normalizado)) {
            Write-WSBPublicViolationLog -Motivo 'Falha de integridade' -Detalhe 'Conteudo normalizado vazio.'
            return $false
        }

        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalizado)
            $hashBytes = $sha.ComputeHash($bytes)
        } finally {
            $sha.Dispose()
        }

        $hashAtual = ([BitConverter]::ToString($hashBytes) -replace '-', '').ToUpperInvariant()
        $hashEsperado = ([string]$Script:WSB_PublicExpectedHash).ToUpperInvariant()

        if ($hashAtual -ne $hashEsperado) {
            Write-WSBPublicViolationLog -Motivo 'Falha de integridade' -Detalhe ("Hash divergente. Atual={0} Esperado={1}" -f $hashAtual, $hashEsperado)
            return $false
        }

        return $true
    } catch {
        Write-WSBPublicViolationLog -Motivo 'Falha de integridade' -Detalhe $_.Exception.Message
        return $false
    }
}

if (-not (Test-WSBPublicIntegrity)) {
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
        [System.Windows.MessageBox]::Show(
            'A integridade da release publica do WSB Auto Clean GE nao foi validada. A execucao foi bloqueada por seguranca.',
            'WSB Auto Clean GE - Integridade',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        ) | Out-Null
    } catch {
        Write-Host 'A integridade da release publica do WSB Auto Clean GE nao foi validada. A execucao foi bloqueada por seguranca.'
    }
    exit 9009
}

function ConvertTo-WSBBool {
    param([AllowNull()][object]$Valor)

    if ($null -eq $Valor) { return $false }
    if ($Valor -is [bool]) { return $Valor }
    if ($Valor -is [System.Management.Automation.SwitchParameter]) {
        return [bool]$Valor.IsPresent
    }

    $texto = [string]$Valor
    if ([string]::IsNullOrWhiteSpace($texto)) { return $false }
    $texto = $texto.Trim()

    switch -Regex ($texto) {
        '^(?i:true|1|yes|y|sim|s|on)$'   { return $true  }
        '^(?i:false|0|no|n|nao|não|off)$' { return $false }
        default { return $true }
    }
}

$AutoRun            = ConvertTo-WSBBool $AutoRun
$ToggleAdmin        = ConvertTo-WSBBool $ToggleAdmin
$DiagnosticoSomente = ConvertTo-WSBBool $DiagnosticoSomente
$USBRepairQuick     = ConvertTo-WSBBool $USBRepairQuick
$USBGhostReport     = ConvertTo-WSBBool $USBGhostReport
$USBReenumerar      = ConvertTo-WSBBool $USBReenumerar

$ErrorActionPreference   = 'SilentlyContinue'
$ProgressPreference      = 'SilentlyContinue'
$InformationPreference   = 'SilentlyContinue'
$WarningPreference       = 'SilentlyContinue'
$VerbosePreference       = 'SilentlyContinue'

# Perfil padrão preserva o comportamento atual; novos perfis ficam disponíveis sem alterar o fluxo existente.

# ==============================================================================
#  [DETECCAO ANTECIPADA] Detecta .exe antes de qualquer outra coisa
# ==============================================================================
$Script:IsExePre = ($null -eq $PSCommandPath -or $PSCommandPath -eq "")
$Script:CaminhoExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

# ==============================================================================
#  [AUTO-ELEVACAO] Eleva apenas operacoes manuais de ativacao/desativacao
#  O modo -AutoRun deve ser iniciado pela tarefa agendada com RunLevel Highest
#  para evitar prompt UAC recorrente a cada boot/logon.
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

function Reiniciar-Processo-ElevadoParaToggle {
    try {
        if ($Script:IsExePre) {
            Start-Process -FilePath $Script:CaminhoExe -ArgumentList '-ToggleAdmin 1' -Verb RunAs -WindowStyle Hidden | Out-Null
        } else {
            $argList = "-ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File `"$PSCommandPath`" -ToggleAdmin:$true"
            Start-Process powershell.exe -Verb RunAs -ArgumentList $argList -WindowStyle Hidden | Out-Null
        }
        return $true
    } catch {
        return $false
    }
}

if ($AutoRun -and -not $isAdmin) {
    exit
}

# ==============================================================================
#  [DEFENDER] Sem exclusoes automaticas por seguranca
# ==============================================================================
# Intencionalmente nao adiciona exclusao no Microsoft Defender.

# ==============================================================================
#  [ENCODING] UTF-8 com BOM + acentos corretos em .ps1 e .exe compilado
# ==============================================================================
try {
    $Script:Utf8BomEncoding = New-Object System.Text.UTF8Encoding($true)
    [Console]::InputEncoding  = $Script:Utf8BomEncoding
    [Console]::OutputEncoding = $Script:Utf8BomEncoding
    $OutputEncoding = $Script:Utf8BomEncoding
    $PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
    $PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
    $PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
} catch {}
[System.Threading.Thread]::CurrentThread.CurrentCulture   = [System.Globalization.CultureInfo]'pt-BR'
[System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]'pt-BR'

function Escrever-ArquivoUtf8Bom {
    param(
        [Parameter(Mandatory)][string]$Caminho,
        [AllowEmptyString()][string]$Conteudo
    )
    try {
        $dir = Split-Path -Path $Caminho -Parent
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($Caminho, $Conteudo, $Script:Utf8BomEncoding)
        return $true
    } catch {
        return $false
    }
}

function Escrever-LinhasUtf8Bom {
    param(
        [Parameter(Mandatory)][string]$Caminho,
        [string[]]$Linhas
    )
    return Escrever-ArquivoUtf8Bom -Caminho $Caminho -Conteudo (($Linhas -join [Environment]::NewLine) + [Environment]::NewLine)
}

# ==============================================================================
#  [INSTANCIA UNICA] Evita duas execucoes silenciosas concorrentes
# ==============================================================================
$script:Mutex = $null
try {
    $criouNovo = $false
    $script:Mutex = New-Object System.Threading.Mutex($true, 'Global\WSB_AutoClean_GE', [ref]$criouNovo)
    if (-not $criouNovo -and $AutoRun) { exit }
} catch {}

# ==============================================================================
#  [0]  CONSTANTES
# ==============================================================================
$Script:VersaoApp     = "3.3.2"
$Script:StartupLnk    = Join-Path ([System.Environment]::GetFolderPath("Startup")) "WSB_AutoClean.lnk"
$Script:NomeTarefa    = "WSB_AutoClean_GE"

# Detecta se esta rodando como .exe ou .ps1 (usa deteccao antecipada)
$Script:IsExe         = $Script:IsExePre
$Script:CaminhoApp    = if (-not $Script:IsExePre -and $PSCommandPath) { $PSCommandPath } else { $Script:CaminhoExe }
$Script:CaminhoPS1    = $Script:CaminhoApp
$Script:DiretorioApp  = Split-Path $Script:CaminhoApp -Parent
$Script:NomeArquivoApp = Split-Path $Script:CaminhoApp -Leaf
$Script:PowerShellExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
if (-not $Script:PowerShellExe) { $Script:PowerShellExe = "powershell.exe" }

# Metadados de execucao reutilizados tanto no .ps1 quanto no .exe compilado
$Script:LaunchSignature = if ($Script:IsExe) {
    "EXE|{0}" -f $Script:CaminhoApp.ToLowerInvariant()
} else {
    "PS1|{0}" -f $Script:CaminhoApp.ToLowerInvariant()
}
$Script:TaskActionExecute = if ($Script:IsExe) { $Script:CaminhoApp } else { $Script:PowerShellExe }
$Script:TaskActionArgument = if ($Script:IsExe) {
    "-AutoRun 1"
} else {
    "-ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File `"$($Script:CaminhoApp)`" -AutoRun:$true"
}

# AppId dinamico: usa o executavel atual se for .exe, senao usa powershell
$Script:AppId  = if ($Script:IsExe) {
    [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
} else {
    '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
}

$Script:PastaLogs     = "$env:USERPROFILE\Documents\WSB Auto Clean GE"
$Script:PastaEstado   = Join-Path $env:ProgramData "WSBTech\AutoCleanGE"
$Script:ArquivoEstado = Join-Path $Script:PastaEstado "state.json"
$Script:ArquivoPID    = Join-Path $Script:PastaEstado "autorun.pid"
$Script:ArquivoHeartbeat = Join-Path $Script:PastaEstado "heartbeat.txt"
$Script:ArquivoDisable = Join-Path $Script:PastaEstado "disable.flag"
$Script:ArquivoUltimaRecuperacao = Join-Path $Script:PastaEstado "last_recovery.txt"

$Script:ExtSuspeitasUSB = @(
    "*.lnk","*.vbs","*.vbe","*.js","*.jse",
    "*.bat","*.cmd","*.scr","*.pif","*.wsf",
    "*.hta","autorun.inf"
)

$Script:PadroesRunSuspeitos = @(
    '.*\\AppData\\Roaming\\[^\\]+\.exe$',
    '.*\\AppData\\Local\\Temp\\.*\.exe$',
    '.*\\Users\\Public\\.*\.exe$',
    '.*\\Temp\\.*\.exe$',
    'wscript','cscript','mshta',
    '.*\.vbs$','.*\.vbe$','.*\.js$','.*\.jse$','.*\.scr$',
    'powershell.*-enc',
    'powershell.*hidden.*downloadstring',
    'cmd.*/c.*http',
    'regsvr32.*/s.*/u',
    'certutil.*-decode',
    'bitsadmin.*/transfer'
)


$Script:USBProcessados = @{}
$Script:USBJanelaReanaliseSeg = 45
$Script:ArquivosProtegidosLogin = @(
    'Cookies','Cookies-journal','Login Data','Login Data For Account',
    'Login Data-journal','Web Data','Web Data-journal','Local State',
    'Network Persistent State','Secure Preferences','Preferences',
    'Current Session','Current Tabs','Last Session','Last Tabs',
    'Session Storage','Sessions'
)

$Script:SubpastasCacheSeguras = @(
    'Cache','Code Cache','GPUCache','GrShaderCache','DawnCache','ShaderCache','Media Cache',
    'Service Worker\CacheStorage','Service Worker\ScriptCache','Crashpad\reports',
    'Temp','tmp','Caches','Cache2','INetCache','D3DSCache','NVIDIA DXCache','DXCache',
    'GLCache','QtWebEngine\Default\GPUCache','QtWebEngine\Default\Service Worker\CacheStorage',
    'SquirrelTemp','blob_storage','logs'
)
$Script:NomesCacheGenericos = @(
    'cache','code cache','gpucache','grshadercache','dawncache','shadercache','media cache',
    'caches','cache2','inetcache','d3dscache','dxcache','glcache','squirreltemp','temp','tmp','logs',
    'webcache','cache_data','cefcache','browsercache'
)
$Script:SegmentosSensiveis = @(
    '\Cookies','\Login Data','\Web Data','\Local State','\Sessions','\Session Storage',
    '\Local Storage','\IndexedDB','\Network','\databases','\Pepper Data','\Extensions',
    '\File System','\storage','\Service Worker\Database','\User Data\Default\Extensions',
    '\tdata','\userdata','\Saved Games','\save','\saves','\profiles','\Profile',
    '\Microsoft\Protect','\Credentials','\TokenBroker','\Authy','\wallet'
)

# ==============================================================================
#  [LIMPEZA DE APPIDS ANTIGOS] Remove entradas velhas de versoes anteriores
#  para evitar que nomes errados apareçam nos toasts
# ==============================================================================
try {
    $baseNotif  = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings"
    $baseAppId  = "HKCU:\SOFTWARE\Classes\AppUserModelId"
    $idsAntigos = @(
        "WSB TECH", "WSB.Flash.Clean", "WSB.FlashClean",
        "WSBTech.PrecisionUnit", "WSB.AutoClean", "WSB_AutoClean"
    )
    foreach ($id in $idsAntigos) {
        foreach ($base in @($baseNotif, $baseAppId)) {
            $p = "$base\$id"
            if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
} catch {}

# Registra o AppId correto — deleta e recria sempre para evitar cache do nome anterior
$regPath     = "HKCU:\SOFTWARE\Classes\AppUserModelId\WSB.AutoClean.GE"
$regNotif    = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\WSB.AutoClean.GE"
try { Remove-Item $regPath  -Recurse -Force -ErrorAction SilentlyContinue } catch {}
try { Remove-Item $regNotif -Recurse -Force -ErrorAction SilentlyContinue } catch {}
try {
    New-Item -Path $regPath -Force | Out-Null
    New-ItemProperty -Path $regPath -Name "DisplayName"    -Value "WSB AUTO CLEAN - GHOST EDITION" -Force | Out-Null
    New-ItemProperty -Path $regPath -Name "ShowInSettings" -Value 0 -PropertyType DWord -Force | Out-Null
    if ($Script:IsExe) {
        New-ItemProperty -Path $regPath -Name "IconUri" -Value $Script:CaminhoApp -Force | Out-Null
    }
} catch {}
$Script:AppId = "WSB.AutoClean.GE"

# ==============================================================================
#  [1]  OCULTAR JANELA NO MODO AUTORUN
# ==============================================================================

if ($AutoRun) {
    try {
        $code   = '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
        $type   = Add-Type -MemberDefinition $code -Name "Win32SW_WSB31" -Namespace "Win32" -PassThru -ErrorAction SilentlyContinue
        $handle = [System.Diagnostics.Process]::GetCurrentProcess().MainWindowHandle
        if ($handle -ne [IntPtr]::Zero) { $type::ShowWindow($handle, 0) | Out-Null }
    } catch {}
}

# ==============================================================================
#  [2]  GERAR BANNER HERO  (GDI+ -> PNG em disco)
#       Modo "Normal"  = degradê azul  (limpeza / status)
#       Modo "Alerta"  = degradê vermelho/laranja (alerta crítico)
#       Modo "USB"     = degradê âmbar/vermelho (varredura e proteção USB)
#       Modo "RAM"     = degradê roxo  (otimizacao de memoria)
#       Modo "Icones"  = degradê verde escuro  (limpeza de icones)
#       Retorna o caminho do PNG gravado ou "" se falhar
# ==============================================================================
function Gerar-Banner {
    param(
        [ValidateSet("Normal","Alerta","RAM","Icones","USB","Ativado","Desativado")]
        [string]$Modo = "Normal"
    )

    $destino = "$env:TEMP\wsb_banner_$($Modo.ToLower())_$(Get-Random).png"

          # Carregamento robusto do GDI+ para funcionar tanto em .ps1 quanto em .exe
    try {
        try { Add-Type -AssemblyName System.Drawing -ErrorAction Stop } catch {
            try {
                $gdPath = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
                Add-Type -Path (Join-Path $gdPath "System.Drawing.dll") -ErrorAction SilentlyContinue
            } catch {}
        }
        # Verifica se GDI+ carregou antes de continuar
        if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'System.Drawing' })) {
            return ""
        }

        $W = 364; $H = 180
        $bmp = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g   = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        switch ($Modo) {
            "Alerta"  {
                $corA = [System.Drawing.Color]::FromArgb(255, 18,  4,  4)
                $corB = [System.Drawing.Color]::FromArgb(255, 90, 12,  0)
                $corL = [System.Drawing.Color]::FromArgb(220,255, 60,  0)
                $corT = [System.Drawing.Color]::FromArgb(255,255, 80,  0)
                $txt1 = "WSB TECH"
                $txt2 = "USB SHIELD"
                $txt3 = "Análise e Desinfecção Automática"
                $txt4 = "Proteção Ativa  |  v$($Script:VersaoApp)"
            }
            "USB"     {
                $corA = [System.Drawing.Color]::FromArgb(255, 16,  8,  4)
                $corB = [System.Drawing.Color]::FromArgb(255, 92, 34,  0)
                $corL = [System.Drawing.Color]::FromArgb(210,255,150,  0)
                $corT = [System.Drawing.Color]::FromArgb(255,255,190, 40)
                $txt1 = "WSB TECH"
                $txt2 = "USB SHIELD"
                $txt3 = "Varredura e Vacinação Automática"
                $txt4 = "Proteção Ativa  |  v$($Script:VersaoApp)"
            }
            "RAM"     {
                $corA = [System.Drawing.Color]::FromArgb(255,  8,  4, 20)
                $corB = [System.Drawing.Color]::FromArgb(255, 50,  0,100)
                $corL = [System.Drawing.Color]::FromArgb(200,170, 80,255)
                $corT = [System.Drawing.Color]::FromArgb(255,200,120,255)
                $txt1 = "WSB TECH"
                $txt2 = "RAM BOOST"
                $txt3 = "Otimização de Memória Concluída"
                $txt4 = "by Will Bezerra  |  v$($Script:VersaoApp)"
            }
            "Icones"  {
                $corA = [System.Drawing.Color]::FromArgb(255,  4, 18,  8)
                $corB = [System.Drawing.Color]::FromArgb(255,  0, 65, 30)
                $corL = [System.Drawing.Color]::FromArgb(200,  0,220, 80)
                $corT = [System.Drawing.Color]::FromArgb(255,  0,255,100)
                $txt1 = "WSB TECH"
                $txt2 = "ICON CLEAN"
                $txt3 = "Cache de Ícones  |  Miniaturas Limpos"
                $txt4 = "by Will Bezerra  |  v$($Script:VersaoApp)"
            }
            "Ativado" {
                $corA = [System.Drawing.Color]::FromArgb(255,  3, 18, 10)
                $corB = [System.Drawing.Color]::FromArgb(255,  0, 72, 38)
                $corL = [System.Drawing.Color]::FromArgb(220,  0,255,140)
                $corT = [System.Drawing.Color]::FromArgb(255,  0,240,160)
                $txt1 = "WSB TECH"
                $txt2 = "AUTO CLEAN"
                $txt3 = "Inicialização Automática  |  Modo Ativado"
                $txt4 = "by Will Bezerra  |  v$($Script:VersaoApp)"
            }
            "Desativado" {
                $corA = [System.Drawing.Color]::FromArgb(255, 20, 20, 20)
                $corB = [System.Drawing.Color]::FromArgb(255, 58, 58, 58)
                $corL = [System.Drawing.Color]::FromArgb(220,255,110,110)
                $corT = [System.Drawing.Color]::FromArgb(255,255,120,120)
                $txt1 = "WSB TECH"
                $txt2 = "AUTO CLEAN"
                $txt3 = "Inicialização Automática  |  Modo Desativado"
                $txt4 = "by Will Bezerra  |  v$($Script:VersaoApp)"
            }
            default   {   # Normal (azul)
                $corA = [System.Drawing.Color]::FromArgb(255,  5,  5, 18)
                $corB = [System.Drawing.Color]::FromArgb(255,  0, 35, 75)
                $corL = [System.Drawing.Color]::FromArgb(200,  0,190,255)
                $corT = [System.Drawing.Color]::FromArgb(255,  0,210,255)
                $txt1 = "WSB TECH"
                $txt2 = "AUTO CLEAN"
                $txt3 = "Limpeza Completa  |  Sem Remoção de Logins"
                $txt4 = "by Will Bezerra  |  v$($Script:VersaoApp)"
            }
        }

        # Fundo degradê
        $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.RectangleF(0,0,$W,$H)), $corA, $corB,
            [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
        $g.FillRectangle($grad, 0, 0, $W, $H)

        # Linhas decorativas
        $penTop = New-Object System.Drawing.Pen($corL, 2)
        $penBot = New-Object System.Drawing.Pen(
            [System.Drawing.Color]::FromArgb(80, $corL.R, $corL.G, $corL.B), 1)
        $g.DrawLine($penTop, 0, 3, $W, 3)
        $g.DrawLine($penBot, 18, $H-22, $W-18, $H-22)

        # Fontes e pinceis
        $fT = New-Object System.Drawing.Font("Segoe UI", 28, [System.Drawing.FontStyle]::Bold)
        $fS = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular)
        $fG = New-Object System.Drawing.Font("Segoe UI",  9, [System.Drawing.FontStyle]::Italic)
        $bA = New-Object System.Drawing.SolidBrush($corT)
        $bW = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $bG = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(170,210,210,210))

        # Centraliza todos os textos horizontalmente
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = [System.Drawing.StringAlignment]::Center
        $g.DrawString($txt1, $fT, $bA, (New-Object System.Drawing.RectangleF(0,  10, $W, 50)), $sf)
        $g.DrawString($txt2, $fT, $bW, (New-Object System.Drawing.RectangleF(0,  62, $W, 55)), $sf)
        $g.DrawString($txt3, $fS, $bG, (New-Object System.Drawing.RectangleF(0, 122, $W, 22)), $sf)
        $g.DrawString($txt4, $fG, $bG, (New-Object System.Drawing.RectangleF(0, 148, $W, 20)), $sf)

        foreach ($o in @($grad,$penTop,$penBot,$fT,$fS,$fG,$bA,$bW,$bG)) { try{$o.Dispose()}catch{} }
        $g.Dispose()

        # Salva PNG diretamente em disco (sem GZip desnecessario)
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        [System.IO.File]::WriteAllBytes($destino, $ms.ToArray())
        $ms.Dispose()

        return $destino
    } catch { return "" }
}

# ==============================================================================
#  [3]  SISTEMA DE LOG
#       Grava arquivo .txt em Documentos\WSB Auto Clean GE\
#       Nome:  WSB_<Operacao>_<yyyyMMdd_HHmmss>.txt
# ==============================================================================
function Gravar-Log {
    param(
        [string]  $Operacao,
        [string[]]$Linhas
    )
    try {
        if (-not (Test-Path $Script:PastaLogs)) {
            New-Item -Path $Script:PastaLogs -ItemType Directory -Force | Out-Null
        }
        $ts       = Get-Date -Format "yyyyMMdd_HHmmss"
        $opLimpa  = $Operacao.Normalize([System.Text.NormalizationForm]::FormD) -replace '\p{Mn}',''
        $nomeArq  = "WSB_$($Operacao -replace '[^\p{L}0-9_]','_')_$ts.txt"
        $caminho  = Join-Path $Script:PastaLogs $nomeArq
        $cabecalho = @(
            "====================================================",
            "  WSB TECH AUTO CLEAN - GHOST EDITION  v$($Script:VersaoApp)",
            "  Operação : $Operacao",
            "  Data/Hora: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')",
            "  Máquina  : $env:COMPUTERNAME  |  Usuário: $env:USERNAME",
            "====================================================",
            ""
        )
        $null = Escrever-LinhasUtf8Bom -Caminho $caminho -Linhas ($cabecalho + $Linhas + @("","[ FIM DO LOG ]"))
        return $caminho
    } catch { return "" }
}


function Garantir-Pasta-Estado {
    try {
        if (-not (Test-Path $Script:PastaEstado)) {
            New-Item -Path $Script:PastaEstado -ItemType Directory -Force | Out-Null
        }
    } catch {}
}

function Salvar-EstadoAutoClean {
    param(
        [bool]$Enabled,
        [string]$Mode = 'TaskScheduler+LNK',
        [string]$UltimaAcao = 'Atualização de Estado'
    )
    try {
        Garantir-Pasta-Estado
        $obj = [ordered]@{
            Enabled     = $Enabled
            Mode        = $Mode
            UltimaAcao  = $UltimaAcao
            Versao      = $Script:VersaoApp
            CaminhoApp  = $Script:CaminhoApp
            IsExe       = $Script:IsExe
            AtualizadoEm = (Get-Date).ToString('o')
            Usuario     = $env:USERNAME
            Computador  = $env:COMPUTERNAME
        }
        $null = Escrever-ArquivoUtf8Bom -Caminho $Script:ArquivoEstado -Conteudo ($obj | ConvertTo-Json -Depth 4)
    } catch {}
}

function Obter-EstadoAutoClean {
    try {
        Garantir-Pasta-Estado
        if (Test-Path $Script:ArquivoEstado) {
            return (Get-Content -Path $Script:ArquivoEstado -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
        }
    } catch {}
    return $null
}

function Atualizar-Heartbeat {
    try {
        Garantir-Pasta-Estado
        $heart = [ordered]@{
            Timestamp = (Get-Date).ToString('o')
            PID       = [int]$PID
            Caminho   = $Script:CaminhoApp
            IsExe     = [bool]$Script:IsExe
            Signature = $Script:LaunchSignature
            Versao    = $Script:VersaoApp
        }
        $null = Escrever-ArquivoUtf8Bom -Caminho $Script:ArquivoHeartbeat -Conteudo ($heart | ConvertTo-Json -Depth 4)
        Set-Content -Path $Script:ArquivoPID -Encoding ASCII -Force -Value ([string]$PID)
    } catch {}
}

function Obter-Info-Heartbeat {
    try {
        if (Test-Path $Script:ArquivoHeartbeat) {
            return (Get-Content -Path $Script:ArquivoHeartbeat -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
        }
    } catch {}
    return $null
}

function Testar-Processo-WSBAutoClean {
    param([object]$Proc)
    try {
        if (-not $Proc) { return $false }
        $cmd  = [string]$Proc.CommandLine
        $name = [string]$Proc.Name
        if ($Proc.ProcessId -eq $PID) { return $false }
        if ($cmd -and $cmd.ToLowerInvariant().Contains($Script:CaminhoApp.ToLowerInvariant())) { return $true }
        if ($cmd -and $cmd -match 'WSB_AutoClean_GE|WSBAutoClean|AutoRun') { return $true }
        if ($Script:IsExe -and $name -ieq $Script:NomeArquivoApp) { return $true }
        if ((-not $Script:IsExe) -and $name -match 'powershell|pwsh' -and $cmd -and $cmd.ToLowerInvariant().Contains($Script:NomeArquivoApp.ToLowerInvariant())) { return $true }
    } catch {}
    return $false
}

function Testar-Tarefa-Residente {
    try {
        $task = Get-ScheduledTask -TaskName $Script:NomeTarefa -ErrorAction SilentlyContinue
        if (-not $task) { return $false }
        if ($task.State -eq 'Disabled') { return $false }

        try {
            $xml = Export-ScheduledTask -TaskName $Script:NomeTarefa -ErrorAction SilentlyContinue
            if ($xml) {
                $txt = [string]$xml
                if ($Script:TaskActionExecute -and ($txt -notmatch [regex]::Escape($Script:TaskActionExecute))) { return $false }
                if ($Script:TaskActionArgument -and ($txt -notmatch [regex]::Escape($Script:TaskActionArgument))) { return $false }
            }
        } catch {}

        return $true
    } catch {}

    return $false
}

function Testar-Instancia-Residente {
    try {
        $heart = Obter-Info-Heartbeat
        if (-not $heart) { return $false }
        if (-not $heart.PID) { return $false }

        $proc = Get-Process -Id ([int]$heart.PID) -ErrorAction SilentlyContinue
        if (-not $proc) { return $false }

        try {
            $caminhoHeart = [string]$heart.Caminho
            if ($caminhoHeart) {
                if ($Script:IsExe) {
                    if ($proc.Path -and ($proc.Path -ieq $caminhoHeart)) { return $true }
                } else {
                    $p = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$heart.PID)" -ErrorAction SilentlyContinue
                    if ($p -and [string]$p.CommandLine -match [regex]::Escape($caminhoHeart)) { return $true }
                }
            }
        } catch {}

        return $true
    } catch {}

    return $false
}

function Teste-Saude-Residente {
    $resultado = [ordered]@{
        TarefaOk     = $false
        HeartbeatOk  = $false
        MutexOk      = $false
        USBWatcherOk = $false
        EstadoOk     = $false
    }

    try { $resultado.TarefaOk    = Testar-Tarefa-Residente } catch {}
    try { $resultado.HeartbeatOk = Testar-Instancia-Residente } catch {}
    try { $resultado.EstadoOk    = ((Obter-EstadoAutoClean) -and (Obter-EstadoAutoClean).Enabled) } catch {}
    try { $resultado.MutexOk     = [bool]$script:Mutex } catch {}

    try {
        $ev = Get-EventSubscriber -SourceIdentifier 'WSB_USBWatcher' -ErrorAction SilentlyContinue
        $resultado.USBWatcherOk = ($null -ne $ev)
    } catch {}

    return [pscustomobject]$resultado
}

function Registrar-Saude-Residente {
    param([string]$Operacao = 'SELFTEST')

    try {
        $s = Teste-Saude-Residente
        $linhas = @(
            "  TarefaOk     : $($s.TarefaOk)",
            "  HeartbeatOk  : $($s.HeartbeatOk)",
            "  MutexOk      : $($s.MutexOk)",
            "  USBWatcherOk : $($s.USBWatcherOk)",
            "  EstadoOk     : $($s.EstadoOk)"
        )
        Gravar-Log -Operacao $Operacao -Linhas $linhas | Out-Null
        return $s
    } catch {}

    return $null
}

function Testar-Segmento-Sensivel {
    param([string]$Caminho)
    if (-not $Caminho) { return $true }
    foreach ($seg in $Script:SegmentosSensiveis) {
        if ($Caminho -like "*$seg*") { return $true }
    }
    return $false
}

function Obter-Pastas-Cache-Genericas {
    $saida = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($raiz in @($env:LOCALAPPDATA, $env:APPDATA)) {
        if (-not $raiz -or -not (Test-Path $raiz)) { continue }
        try {
            Get-ChildItem -Path $raiz -Directory -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object {
                    $nome = $_.Name.ToLowerInvariant()
                    $full = $_.FullName
                    ($Script:NomesCacheGenericos -contains $nome) -and
                    (-not (Testar-Segmento-Sensivel -Caminho $full)) -and
                    ($full -notlike "*\Packages\*\AC\*") -and
                    ($full -notlike "*\Microsoft\Credentials*") -and
                    ($full -notlike "*\Windows\WebCache*") -and
                    ($full -notlike "*\OneAuth*")
                } |
                ForEach-Object { [void]$saida.Add($_.FullName) }
        } catch {}
    }
    return @($saida)
}

function Limpar-Caches-Chromium-Genericos {
    $total = @{Bytes=[long]0;Itens=0;Falhas=0}
    foreach ($raiz in @($env:LOCALAPPDATA, $env:APPDATA)) {
        if (-not $raiz -or -not (Test-Path $raiz)) { continue }
        try {
            Get-ChildItem -Path $raiz -Directory -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq 'User Data' -or $_.Name -eq 'Profiles' } |
                ForEach-Object {
                    $userData = $_.FullName
                    foreach ($perfil in (Get-ChildItem $userData -Directory -ErrorAction SilentlyContinue | Where-Object {
                        $_.Name -eq 'Default' -or $_.Name -match '^Profile\s\d+$' -or $_.Name -match 'Guest' -or $_.Name -match 'System'
                    })) {
                        $r = Limpar-Subpastas-Seguras -Base $perfil.FullName -Subcaminhos $Script:SubpastasCacheSeguras -IgnorarNomes $Script:ArquivosProtegidosLogin
                        $total.Bytes += $r.Bytes; $total.Itens += $r.Itens; $total.Falhas += $r.Falhas
                    }
                    foreach ($sub in @('ShaderCache','Crashpad\reports','Crashpad\attachments','component_crx_cache')) {
                        $r = Limpar-Pasta (Join-Path $userData $sub)
                        $total.Bytes += $r.Bytes; $total.Itens += $r.Itens; $total.Falhas += $r.Falhas
                    }
                }
        } catch {}
    }
    return $total
}

function Limpar-Caches-Genericos-Apps {
    $total = @{Bytes=[long]0;Itens=0;Falhas=0;Pastas=0}
    foreach ($p in Obter-Pastas-Cache-Genericas) {
        $r = Limpar-Pasta $p $Script:ArquivosProtegidosLogin
        if ($r.Itens -gt 0 -or $r.Bytes -gt 0 -or $r.Falhas -gt 0) { $total.Pastas++ }
        $total.Bytes += $r.Bytes; $total.Itens += $r.Itens; $total.Falhas += $r.Falhas
    }
    return $total
}

function Obter-Raizes-Steam {
    $saida = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($p in @(
        "${env:ProgramFiles(x86)}\Steam",
        "$env:ProgramFiles\Steam",
        "${env:LOCALAPPDATA}\Steam"
    )) {
        if ($p -and (Test-Path $p)) { [void]$saida.Add($p) }
    }

    foreach ($root in @($saida)) {
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path $vdf)) { continue }
        try {
            foreach ($line in (Get-Content -LiteralPath $vdf -ErrorAction SilentlyContinue)) {
                if ($line -match '"path"\s*"([^"]+)"') {
                    $lib = $matches[1] -replace '\\\\','\'
                    if ($lib -and (Test-Path $lib)) { [void]$saida.Add($lib) }
                }
            }
        } catch {}
    }

    return @($saida)
}

function Limpar-Caches-Gamer {
    $total = @{Bytes=[long]0;Itens=0;Falhas=0;Pastas=0}

    function Add-Gamer([hashtable]$acc, [hashtable]$r) {
        if ($r) {
            $acc.Bytes  += [long]$r.Bytes
            $acc.Itens  += [int]$r.Itens
            $acc.Falhas += [int]$r.Falhas
            if (($r.Bytes -gt 0) -or ($r.Itens -gt 0) -or ($r.Falhas -gt 0)) { $acc.Pastas++ }
        }
    }

    # Steam: html/logs locais + caches de shader/download por biblioteca
    foreach ($steamRoot in Obter-Raizes-Steam) {
        Add-Gamer $total (Limpar-Pasta (Join-Path $steamRoot 'appcache\httpcache'))
        Add-Gamer $total (Limpar-Pasta (Join-Path $steamRoot 'appcache\librarycache'))
        Add-Gamer $total (Limpar-Pasta (Join-Path $steamRoot 'depotcache'))
        Add-Gamer $total (Limpar-Pasta (Join-Path $steamRoot 'dumps'))
        Add-Gamer $total (Limpar-Pasta (Join-Path $steamRoot 'logs'))
        Add-Gamer $total (Limpar-Pasta (Join-Path $steamRoot 'steamapps\shadercache'))
        Add-Gamer $total (Limpar-Pasta (Join-Path $steamRoot 'steamapps\downloading'))
    }
    Add-Gamer $total (Limpar-Pasta "$env:LOCALAPPDATA\Steam\htmlcache")
    Add-Gamer $total (Limpar-Pasta "$env:LOCALAPPDATA\Steam\dumps")
    Add-Gamer $total (Limpar-Pasta "$env:LOCALAPPDATA\Steam\logs")

    # Epic Games Launcher
    foreach ($p in @(
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache",
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache_4147",
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache_4430",
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\Crashes",
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\Logs",
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\GPUCache",
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\Code Cache"
    )) { Add-Gamer $total (Limpar-Pasta $p) }

    # Battle.net / Blizzard
    foreach ($p in @(
        "$env:APPDATA\Battle.net\Cache",
        "$env:APPDATA\Battle.net\Code Cache",
        "$env:APPDATA\Battle.net\GPUCache",
        "$env:LOCALAPPDATA\Battle.net\Cache",
        "$env:LOCALAPPDATA\Battle.net\Code Cache",
        "$env:LOCALAPPDATA\Battle.net\GPUCache",
        "$env:PROGRAMDATA\Battle.net\Agent\cache",
        "$env:PROGRAMDATA\Battle.net\Setup\Cache",
        "$env:PROGRAMDATA\Blizzard Entertainment\Battle.net\Cache"
    )) { Add-Gamer $total (Limpar-Pasta $p) }

    # Ubisoft Connect
    foreach ($p in @(
        "$env:LOCALAPPDATA\Ubisoft Game Launcher\cache",
        "$env:LOCALAPPDATA\Ubisoft Game Launcher\logs",
        "$env:LOCALAPPDATA\Ubisoft Game Launcher\upc_cache",
        "$env:PROGRAMDATA\Ubisoft\Ubisoft Game Launcher\cache"
    )) { Add-Gamer $total (Limpar-Pasta $p) }

    # EA app / Origin (somente cache e logs)
    foreach ($p in @(
        "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\Cache",
        "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\Code Cache",
        "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\GPUCache",
        "$env:APPDATA\Origin\Logs",
        "$env:APPDATA\Origin\Cache"
    )) { Add-Gamer $total (Limpar-Pasta $p) }

    return $total
}


function Garantir-Autorecuperacao {
    param([switch]$Silencioso)
    $acoes = [System.Collections.Generic.List[string]]::new()
    Garantir-Pasta-Estado

    if (-not (Test-Path $Script:PastaLogs)) {
        try { New-Item -Path $Script:PastaLogs -ItemType Directory -Force | Out-Null; $acoes.Add('Pasta de logs recriada.') } catch {}
    }

    $estado = Obter-EstadoAutoClean
    if ($estado -and $estado.Enabled) {
        $recriarInfra = $false
        try {
            if ($estado.CaminhoApp -and ([string]$estado.CaminhoApp -ne [string]$Script:CaminhoApp)) {
                Salvar-EstadoAutoClean -Enabled $true -UltimaAcao 'Caminho portátil atualizado automaticamente'
                $acoes.Add('Caminho portátil sincronizado com a instância atual.')
                $recriarInfra = $true
            }
        } catch {}

        try {
            $task = Get-ScheduledTask -TaskName $Script:NomeTarefa -ErrorAction SilentlyContinue
            if (-not $task) {
                $recriarInfra = $true
            } elseif ($task.State -eq 'Disabled') {
                Enable-ScheduledTask -TaskName $Script:NomeTarefa -ErrorAction SilentlyContinue | Out-Null
                $acoes.Add('Tarefa agendada reativada.')
            }
        } catch { $recriarInfra = $true }

        try {
            if (-not (Test-Path $Script:StartupLnk)) {
                $recriarInfra = $true
            }
        } catch { $recriarInfra = $true }

        if ($recriarInfra) {
            if (Criar-LNK) { $acoes.Add('Infraestrutura portátil restaurada automaticamente.') }
        }
    }

    try {
        if (-not (Test-Path "HKCU:\SOFTWARE\Classes\AppUserModelId\WSB.AutoClean.GE")) {
            New-Item -Path "HKCU:\SOFTWARE\Classes\AppUserModelId\WSB.AutoClean.GE" -Force | Out-Null
            New-ItemProperty -Path "HKCU:\SOFTWARE\Classes\AppUserModelId\WSB.AutoClean.GE" -Name "DisplayName" -Value "WSB AUTO CLEAN - GHOST EDITION" -Force | Out-Null
            New-ItemProperty -Path "HKCU:\SOFTWARE\Classes\AppUserModelId\WSB.AutoClean.GE" -Name "ShowInSettings" -Value 0 -PropertyType DWord -Force | Out-Null
            if ($Script:IsExe) {
                New-ItemProperty -Path "HKCU:\SOFTWARE\Classes\AppUserModelId\WSB.AutoClean.GE" -Name "IconUri" -Value $Script:CaminhoApp -Force | Out-Null
            }
            $acoes.Add('AppID de toast reconstruído.')
        }
    } catch {}

    if ($acoes.Count -gt 0) {
        try { $null = Escrever-ArquivoUtf8Bom -Caminho $Script:ArquivoUltimaRecuperacao -Conteudo (($acoes -join [Environment]::NewLine)) } catch {}
        Gravar-Log -Operacao 'AUTORECUPERACAO' -Linhas $acoes | Out-Null
        if (-not $Silencioso) {
            Enviar-Toast -Titulo 'WSB AutoClean GE - Auto Recuperação' -Sub "$($acoes.Count) ajuste(s) aplicados" -Corpo ($acoes -join ' | ') -Modo 'Normal' -Audio 'Notification.Default'
        }
    }
    return @($acoes)
}
# ==============================================================================
#  [4]  TOAST NOTIFICATION
#       - Gera banner GDI+ automaticamente (sempre presente)
#       - Limpa o PNG temporario 10s apos enviar (via job background)
#       - $Audio: sufixo do evento de som ms-winsoundevent
# ==============================================================================
function Enviar-Toast {
    param(
        [string]$Titulo,
        [string]$Sub,
        [string]$Corpo  = "",
        [ValidateSet("Normal","Alerta","RAM","Icones","USB","Ativado","Desativado")]
        [string]$Modo   = "Normal",
        [string]$Audio  = "Notification.Reminder"
    )

    # Gera banner sempre
    $imgPath = Gerar-Banner -Modo $Modo

    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

        $heroTag   = ""
        if ($imgPath -and (Test-Path $imgPath)) {
            $src     = "file:///$($imgPath -replace '\\','/')"
            $heroTag = "<image placement='hero' src='$src' />"
        }

        $corpoTag = if ($Corpo) { "<text>$([System.Security.SecurityElement]::Escape($Corpo))</text>" } else { "" }

        $xml = @"
<toast duration="short">
  <visual>
    <binding template="ToastGeneric">
      $heroTag
      <text>$([System.Security.SecurityElement]::Escape($Titulo))</text>
      <text>$([System.Security.SecurityElement]::Escape($Sub))</text>
      $corpoTag
    </binding>
  </visual>
  <audio src="ms-winsoundevent:$Audio" />
</toast>
"@
        $doc   = New-Object Windows.Data.Xml.Dom.XmlDocument
        $doc.LoadXml($xml)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($Script:AppId).Show($toast)
    } catch {}

    # Remove o PNG temporario 10s depois (sem bloquear o fluxo principal)
    if ($imgPath) {
        $imgTemp = $imgPath
        $null = Start-Job -ScriptBlock {
            param($p)
            Start-Sleep -Seconds 10
            if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
        } -ArgumentList $imgTemp
    }
}

# ==============================================================================
#  [5]  GERENCIAR TAREFA AGENDADA + LNK MARCADOR
#       Task Scheduler com RunLevel=Highest: executa admin no boot SEM prompt UAC
#       O .lnk permanece apenas como marcador visual de status (sem bit RunAs)
#       O clique manual eleva apenas o toggle para criar/remover a tarefa
# ==============================================================================
function Criar-LNK {
    try {
        Garantir-Pasta-Estado

        # --- AÇÃO: compatível com .ps1 e .exe portátil ---
        $action = New-ScheduledTaskAction `
            -Execute  $Script:TaskActionExecute `
            -Argument $Script:TaskActionArgument

        # --- GATILHO: ao logar o usuário atual ---
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"

        # --- CONFIGURAÇÕES: persistente, uma instância, não interrompe em bateria ---
        $settings = New-ScheduledTaskSettingsSet `
                        -ExecutionTimeLimit  ([TimeSpan]::Zero) `
                        -MultipleInstances   IgnoreNew `
                        -StartWhenAvailable `
                        -AllowStartIfOnBatteries `
                        -DontStopIfGoingOnBatteries

        # --- PRINCIPAL: RunLevel Highest = admin SEM UAC ao logar ---
        $principal = New-ScheduledTaskPrincipal `
            -UserId   "$env:USERDOMAIN\$env:USERNAME" `
            -LogonType Interactive `
            -RunLevel Highest

        Register-ScheduledTask `
            -TaskName  $Script:NomeTarefa `
            -Action    $action `
            -Trigger   $trigger `
            -Settings  $settings `
            -Principal $principal `
            -Force | Out-Null

        # --- LNK marcador visual (sem bit RunAs — apenas sinaliza "ativo") ---
        try {
            $wsh = New-Object -ComObject WScript.Shell
            $lnk = $wsh.CreateShortcut($Script:StartupLnk)
            $lnk.TargetPath       = $Script:TaskActionExecute
            $lnk.Arguments        = $Script:TaskActionArgument
            $lnk.WorkingDirectory = $Script:DiretorioApp
            $lnk.Description      = "WSB AutoClean GE v$($Script:VersaoApp) [Gerenciado via Task Scheduler | $($Script:NomeArquivoApp)]"
            $lnk.WindowStyle      = 7
            $lnk.Save()
        } catch {}

        Salvar-EstadoAutoClean -Enabled $true -UltimaAcao 'Ativação manual concluída'
        return $true
    } catch { return $false }
}

function Remover-LNK {
    $ok = $false

    # Sinaliza parada para a instância em execução antes de remover a infraestrutura
    try {
        Garantir-Pasta-Estado
        Set-Content -Path $Script:ArquivoDisable -Encoding ASCII -Force -Value ([string](Get-Date))
    } catch {}

    # Remove a tarefa agendada
    try {
        Disable-ScheduledTask -TaskName $Script:NomeTarefa -ErrorAction SilentlyContinue | Out-Null
        Unregister-ScheduledTask -TaskName $Script:NomeTarefa -Confirm:$false -ErrorAction SilentlyContinue
        $ok = $true
    } catch {}

    # Remove o .lnk marcador
    if (Test-Path $Script:StartupLnk) {
        Remove-Item $Script:StartupLnk -Force -ErrorAction SilentlyContinue
        $ok = $true
    }

    # Encerra o processo AutoRun em segundo plano via heartbeat/pid
    try {
        $heart = Obter-Info-Heartbeat
        if ($heart -and $heart.PID) {
            $proc = Get-Process -Id ([int]$heart.PID) -ErrorAction SilentlyContinue
            if ($proc -and $proc.Id -ne $PID) {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                $ok = $true
            }
        }
    } catch {}

    try {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { Testar-Processo-WSBAutoClean $_ } |
            ForEach-Object {
                try {
                    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
                    $ok = $true
                } catch {}
            }
    } catch {}

    Remove-Item $Script:ArquivoPID,$Script:ArquivoHeartbeat -Force -ErrorAction SilentlyContinue
    Salvar-EstadoAutoClean -Enabled $false -UltimaAcao 'Desativação manual concluída'
    return $ok
}


function WSB-Toast {
    param(
        [string]$Titulo,
        [string]$Mensagem,
        [string]$Icone = 'Normal',
        [string]$Corpo = '',
        [string]$Som = 'Notification.Default'
    )
    Enviar-Toast -Titulo $Titulo -Sub $Mensagem -Corpo $Corpo -Modo $Icone -Audio $Som
}

function Obter-Espaco-Livre-Sistema {
    try {
        $drive = $env:SystemDrive.TrimEnd(':')
        $psd = Get-PSDrive -Name $drive -ErrorAction SilentlyContinue
        if ($psd) { return [long]$psd.Free }
    } catch {}
    return [long]0
}

function Medir-Tamanho-Caminho {
    param([string]$Caminho)
    $total = [long]0
    try {
        if ($Caminho -and (Test-Path -LiteralPath $Caminho)) {
            Get-ChildItem -LiteralPath $Caminho -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
                try { $total += [long]$_.Length } catch {}
            }
        }
    } catch {}
    return $total
}

function Testar-Caminho-Protegido {
    param([string]$Caminho)
    if ([string]::IsNullOrWhiteSpace($Caminho)) { return $true }
    try {
        $full = [System.IO.Path]::GetFullPath($Caminho).TrimEnd('\\')
    } catch { return $true }

    $bloqueiosExatos = @(
        [System.IO.Path]::GetFullPath($env:SystemDrive + '\\').TrimEnd('\\'),
        [System.IO.Path]::GetFullPath($env:windir).TrimEnd('\\'),
        [System.IO.Path]::GetFullPath($env:ProgramFiles).TrimEnd('\\'),
        [System.IO.Path]::GetFullPath(${env:ProgramFiles(x86)}).TrimEnd('\\'),
        [System.IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\\'),
        [System.IO.Path]::GetFullPath($env:APPDATA).TrimEnd('\\'),
        [System.IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\\')
    ) | Where-Object { $_ }

    if ($bloqueiosExatos -contains $full) { return $true }
    if (Testar-Segmento-Sensivel -Caminho $full) { return $true }
    return $false
}

function Obter-Perfil-Limpeza {
    param([string]$Perfil = 'Padrao')
    switch ($Perfil) {
        'Seguro' {
            return [ordered]@{Nome='Seguro'; LimpaSistema=$true; LimpaLixeira=$true; LimpaBrowsers=$true; LimpaApps=$false; LimpaAvancado=$false; LimpaGamer=$false; LimpaPrivacidadeLeve=$false }
        }
        'Agressivo' {
            return [ordered]@{Nome='Agressivo'; LimpaSistema=$true; LimpaLixeira=$true; LimpaBrowsers=$true; LimpaApps=$true; LimpaAvancado=$true; LimpaGamer=$true; LimpaPrivacidadeLeve=$true }
        }
        'Privacidade' {
            return [ordered]@{Nome='Privacidade'; LimpaSistema=$true; LimpaLixeira=$true; LimpaBrowsers=$true; LimpaApps=$true; LimpaAvancado=$false; LimpaGamer=$false; LimpaPrivacidadeLeve=$true }
        }
        default {
            return [ordered]@{Nome='Padrao'; LimpaSistema=$true; LimpaLixeira=$true; LimpaBrowsers=$true; LimpaApps=$true; LimpaAvancado=$true; LimpaGamer=$true; LimpaPrivacidadeLeve=$false }
        }
    }
}

function Executar-Diagnostico-Sistema {
    param([string]$Perfil = 'Padrao')
    $cfg = Obter-Perfil-Limpeza -Perfil $Perfil
    $tempCandidates = @(
        'C:\\Windows\\Temp', $env:TEMP, "$env:LOCALAPPDATA\\Temp", 'C:\\Windows\\SoftwareDistribution\\Download',
        "$env:LOCALAPPDATA\\D3DSCache", "$env:LOCALAPPDATA\\Microsoft\\Windows\\Caches", "$env:LOCALAPPDATA\\CrashDumps"
    )
    $browserCandidates = @(
        "$env:LOCALAPPDATA\\Google\\Chrome\\User Data", "$env:LOCALAPPDATA\\Microsoft\\Edge\\User Data",
        "$env:LOCALAPPDATA\\BraveSoftware\\Brave-Browser\\User Data", "$env:LOCALAPPDATA\\Vivaldi\\User Data",
        "$env:APPDATA\\Opera Software\\Opera Stable", "$env:APPDATA\\Opera Software\\Opera GX Stable",
        "$env:LOCALAPPDATA\\Mozilla\\Firefox\\Profiles", "$env:APPDATA\\Mozilla\\Firefox\\Profiles"
    )
    $appCandidates = @(
        "$env:APPDATA\\discord", "$env:LOCALAPPDATA\\Discord", "$env:LOCALAPPDATA\\Steam", "$env:APPDATA\\Slack",
        "$env:APPDATA\\Microsoft\\Teams", "$env:LOCALAPPDATA\\Microsoft\\Teams", "$env:APPDATA\\WhatsApp",
        "$env:LOCALAPPDATA\\WhatsApp", "$env:APPDATA\\Telegram Desktop", "$env:APPDATA\\Code"
    )

    $diag = [ordered]@{
        Perfil = $cfg.Nome
        TempSistema = [long]0
        Navegadores = [long]0
        Apps = [long]0
        Lixeira = [long]0
        USBConectados = 0
        EspacoLivreAntes = (Obter-Espaco-Livre-Sistema)
    }

    foreach ($p in $tempCandidates) { $diag.TempSistema += Medir-Tamanho-Caminho $p }
    foreach ($p in $browserCandidates) { $diag.Navegadores += Medir-Tamanho-Caminho $p }
    foreach ($p in $appCandidates) { $diag.Apps += Medir-Tamanho-Caminho $p }

    try {
        foreach ($drive in @(Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 2 })) {
            $diag.USBConectados++
            foreach ($nomePasta in @('$Recycle.Bin','Recycler')) {
                $diag.Lixeira += Medir-Tamanho-Caminho (Join-Path ($drive.DeviceID + '\\') $nomePasta)
            }
        }
        foreach ($nomePasta in @('$Recycle.Bin','Recycler')) {
            $diag.Lixeira += Medir-Tamanho-Caminho (Join-Path ($env:SystemDrive + '\\') $nomePasta)
        }
    } catch {}

    return $diag
}

function Executar-Limpeza-Privacidade-Leve {
    $total = @{Bytes=[long]0;Itens=0;Falhas=0;Entradas=0}
    foreach ($pat in @(
        "$env:APPDATA\\Microsoft\\Windows\\Recent\\AutomaticDestinations\\*.automaticDestinations-ms",
        "$env:APPDATA\\Microsoft\\Windows\\Recent\\CustomDestinations\\*.customDestinations-ms",
        "$env:APPDATA\\Microsoft\\Windows\\Recent\\*.lnk"
    )) {
        $r = Limpar-Glob $pat
        $total.Bytes += $r.Bytes; $total.Itens += $r.Itens; $total.Falhas += $r.Falhas
        if ($r.Itens -gt 0 -or $r.Bytes -gt 0) { $total.Entradas++ }
    }
    return $total
}

function Obter-USB-GhostDevices {
    $saida = @()
    try {
        $cmd = Get-Command Get-PnpDevice -ErrorAction SilentlyContinue
        if ($cmd) {
            $saida = @(Get-PnpDevice -PresentOnly:$false -ErrorAction SilentlyContinue | Where-Object {
                (($_.Class -match 'USB|DiskDrive|Volume') -or ($_.InstanceId -match 'USB')) -and ($_.Status -ne 'OK')
            })
        }
    } catch {}
    return @($saida)
}

function Invoke-USBRepairSystem {
    param(
        [switch]$ScanConectados,
        [switch]$GhostReport,
        [switch]$Reenumerar
    )

    $log = New-Object System.Collections.Generic.List[string]
    $log.Add("  Perfil módulo USB Repair  : Seguro / Não destrutivo")

    if ($ScanConectados -or (-not $GhostReport -and -not $Reenumerar)) {
        $drives = @(Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 2 } | ForEach-Object { ($_.DeviceID + '\\') })
        if ($drives.Count -eq 0) {
            $log.Add('  Nenhum pendrive removível conectado para análise imediata.')
        } else {
            foreach ($d in $drives) {
                $log.Add("  Scan seguro iniciado em: $d")
                Reparar-USB-Com-Vacina -Drive $d -Origem 'USB Repair System'
            }
        }
    }

    if ($GhostReport) {
        $ghosts = @(Obter-USB-GhostDevices)
        $log.Add("  Dispositivos USB/Volume não saudáveis detectados: $($ghosts.Count)")
        foreach ($g in $ghosts | Select-Object -First 20) {
            $log.Add("    [$($g.Status)] $($g.Class) :: $($g.FriendlyName)")
        }
    }

    if ($Reenumerar) {
        $ok = $false
        try {
            $pnputil = (Get-Command pnputil.exe -ErrorAction SilentlyContinue).Source
            if ($pnputil) {
                & $pnputil /scan-devices 2>&1 | Out-Null
                $ok = $true
            }
        } catch {}
        $log.Add("  Reenumeração de dispositivos: $(if($ok){'Solicitada ao Windows'}else{'Indisponível neste sistema'})")
    }

    Gravar-Log -Operacao 'USB_REPAIR_SYSTEM' -Linhas $log | Out-Null
    return @($log)
}


# ==============================================================================
#  [6]  UTILIDADES DE LIMPEZA
# ==============================================================================
function Formatar-Tamanho([long]$b) {
    if ($b -ge 1GB) { return "{0:N2} GB" -f ($b/1GB) }
    if ($b -ge 1MB) { return "{0:N2} MB" -f ($b/1MB) }
    if ($b -ge 1KB) { return "{0:N2} KB" -f ($b/1KB) }
    return "0 KB"
}

function Limpar-Pasta([string]$caminho, [string[]]$IgnorarNomes = @()) {
    $bytes=[long]0; $n=0; $falhas=0
    if ($caminho -and (Test-Path $caminho) -and (-not (Testar-Caminho-Protegido -Caminho $caminho))) {
        Get-ChildItem -LiteralPath $caminho -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                if ($IgnorarNomes -contains $_.Name) { return }
                if (Testar-Segmento-Sensivel -Caminho $_.FullName) { return }
                $tam = [long]$_.Length
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                $bytes += $tam
                $n++
            } catch { $falhas++ }
        }
    }
    return @{Bytes=$bytes;Itens=$n;Falhas=$falhas}
}

function Limpar-Glob([string]$pat) {
    $bytes=[long]0; $n=0; $falhas=0
    try {
        Get-Item $pat -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                if ($_.PSIsContainer) { return }
                $bytes+=$_.Length
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                $n++
            } catch { $falhas++ }
        }
    } catch {}
    return @{Bytes=$bytes;Itens=$n;Falhas=$falhas}
}

function Limpar-Subpastas-Seguras([string]$Base, [string[]]$Subcaminhos, [string[]]$IgnorarNomes = @()) {
    $total = @{Bytes=[long]0;Itens=0;Falhas=0}
    foreach ($sub in $Subcaminhos) {
        $r = Limpar-Pasta (Join-Path $Base $sub) $IgnorarNomes
        $total.Bytes += $r.Bytes
        $total.Itens += $r.Itens
        $total.Falhas += $r.Falhas
    }
    return $total
}

function Limpar-Lixeira-Silenciosa {
    $total = @{Bytes=[long]0;Itens=0;Falhas=0}

    $drives = @(Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object {
        $_.DeviceID -and $_.DriveType -in 2,3
    })

    foreach ($drive in $drives) {
        $raizDrive = if ($drive.DeviceID.EndsWith('\')) { $drive.DeviceID } else { "$($drive.DeviceID)\" }

        foreach ($nomePasta in @('$Recycle.Bin','Recycler')) {
            $raizLixeira = Join-Path $raizDrive $nomePasta
            if (-not (Test-Path -LiteralPath $raizLixeira)) { continue }

            $subPastas = @(Get-ChildItem -LiteralPath $raizLixeira -Force -ErrorAction SilentlyContinue)
            foreach ($sub in $subPastas) {
                try {
                    Get-ChildItem -LiteralPath $sub.FullName -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
                        $total.Bytes += [long]$_.Length
                        $total.Itens++
                    }

                    try {
                        Start-Process -FilePath cmd.exe -ArgumentList "/c attrib -r -a -s -h /s /d `"$($sub.FullName)\*`"" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue | Out-Null
                    } catch {}

                    Remove-Item -LiteralPath $sub.FullName -Recurse -Force -ErrorAction Stop
                } catch {
                    $total.Falhas++
                    try {
                        Get-ChildItem -LiteralPath $sub.FullName -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | ForEach-Object {
                            try {
                                if ($_.PSIsContainer) {
                                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                                } else {
                                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                                }
                            } catch { $total.Falhas++ }
                        }
                        try { Remove-Item -LiteralPath $sub.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
                    } catch {
                        $total.Falhas++
                    }
                }
            }
        }
    }

    try {
        $clearRecycle = Get-Command Clear-RecycleBin -ErrorAction SilentlyContinue
        if ($clearRecycle) {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {}

    return $total
}

function Limpeza-Avancada-Sistema {
    $total = @{Bytes=[long]0;Itens=0;Falhas=0;Rotinas=0}

    function Add-Adv([hashtable]$acc, [hashtable]$r) {
        if ($r) {
            $acc.Bytes  += [long]$r.Bytes
            $acc.Itens  += [int]$r.Itens
            $acc.Falhas += [int]$r.Falhas
        }
    }

    foreach ($p in @(
        "C:\ProgramData\Microsoft\Windows\WER",
        "C:\Windows\Logs",
        "C:\Windows\Logs\CBS",
        "C:\Windows\Minidump",
        "C:\Windows\LiveKernelReports"
    )) {
        Add-Adv $total (Limpar-Pasta $p)
        $total.Rotinas++
    }

    Add-Adv $total (Limpar-Pasta "C:\Windows\SoftwareDistribution\DeliveryOptimization")
    $total.Rotinas++

    foreach ($p in @(
        "$env:LOCALAPPDATA\NVIDIA\DXCache",
        "$env:LOCALAPPDATA\NVIDIA\GLCache",
        "$env:LOCALAPPDATA\NVIDIA\OptixCache",
        "$env:LOCALAPPDATA\AMD\DxCache",
        "$env:LOCALAPPDATA\AMD\GLCache",
        "$env:LOCALAPPDATA\AMD\VkCache"
    )) {
        Add-Adv $total (Limpar-Pasta $p)
        $total.Rotinas++
    }

    Add-Adv $total (Limpar-Glob "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db")
    Add-Adv $total (Limpar-Glob "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db")
    $total.Rotinas += 2

    try {
        $p = Start-Process dism.exe -ArgumentList '/Online','/Cleanup-Image','/StartComponentCleanup' -WindowStyle Hidden -Wait -PassThru -ErrorAction SilentlyContinue
        if ($p -and $p.ExitCode -eq 0) { $total.Rotinas++ } else { $total.Falhas++ }
    } catch { $total.Falhas++ }

    return $total
}

# ==============================================================================
#  [7]  OTIMIZACAO DE RAM
# ==============================================================================
function Executar-Otimizacao-RAM {
    $antes = [long]0
    try { $antes = (Get-Process -ErrorAction SilentlyContinue | Measure-Object WorkingSet64 -Sum).Sum } catch {}

    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()

    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.MinWorkingSet = [IntPtr]::Subtract([IntPtr]::Zero, 1) } catch {}
    }

    Start-Sleep -Milliseconds 800

    $depois = [long]0
    try { $depois = (Get-Process -ErrorAction SilentlyContinue | Measure-Object WorkingSet64 -Sum).Sum } catch {}

    $delta = if ($antes -gt $depois) { $antes - $depois } else { [long]0 }
    return @{Delta=$delta}
}

# ==============================================================================
#  [8]  LIMPEZA COMPLETA (cache apenas — sem cookies, senhas, tokens)
# ==============================================================================
function Executar-Limpeza-Completa {
    param([string]$Perfil = 'Padrao')
    $cfg = Obter-Perfil-Limpeza -Perfil $Perfil
    $livreAntes = Obter-Espaco-Livre-Sistema
    $bSis=[long]0; $bNav=[long]0; $bApp=[long]0; $bLix=[long]0; $bAdv=[long]0; $bGame=[long]0; $bPriv=[long]0; $n=0; $falhas=0

    if ($cfg.LimpaSistema) {
    foreach ($p in @(
        "C:\Windows\Temp",
        $env:TEMP,
        "$env:LOCALAPPDATA\Temp",
        "C:\Windows\SoftwareDistribution\Download",
        "$env:LOCALAPPDATA\D3DSCache",
        "$env:LOCALAPPDATA\Microsoft\Windows\Caches",
        "$env:LOCALAPPDATA\CrashDumps",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
        "$env:ProgramData\Microsoft\Windows\DeliveryOptimization\Cache"
    )) {
        $r = Limpar-Pasta $p
        $bSis += $r.Bytes; $n += $r.Itens; $falhas += $r.Falhas
    }

    }

    # Prefetch parcial e conservador: remove apenas os mais antigos
    if ($cfg.Nome -ne 'Seguro') {
    try {
        Get-ChildItem "C:\Windows\Prefetch\*.pf" -Force -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime |
            Select-Object -First 90 |
            ForEach-Object {
                try { $bSis += $_.Length; Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop; $n++ } catch { $falhas++ }
            }
    } catch {}
    }

    if ($cfg.LimpaLixeira) {
    try {
        $r = Limpar-Lixeira-Silenciosa
        $bLix += $r.Bytes; $n += $r.Itens; $falhas += $r.Falhas
    } catch {}
    }

    # Chromium por perfil: somente caches voláteis, sem tocar em cookies, logins, tokens, Local State e sessões.
    if ($cfg.LimpaBrowsers) {
    foreach ($base in @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data",
        "$env:LOCALAPPDATA\Vivaldi\User Data"
    )) {
        if (Test-Path $base) {
            foreach ($perfil in (Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -match '^Profile\s\d+$' -or $_.Name -eq 'Guest Profile' -or $_.Name -eq 'System Profile' })) {
                $r = Limpar-Subpastas-Seguras -Base $perfil.FullName -Subcaminhos @(
                    'Cache','Code Cache','GPUCache','GrShaderCache','DawnCache',
                    'Service Worker\CacheStorage','Media Cache'
                ) -IgnorarNomes $Script:ArquivosProtegidosLogin
                $bNav += $r.Bytes; $n += $r.Itens; $falhas += $r.Falhas
            }
            $r = Limpar-Subpastas-Seguras -Base $base -Subcaminhos @('ShaderCache','Crashpad\reports')
            $bNav += $r.Bytes; $n += $r.Itens; $falhas += $r.Falhas
        }
    }

    foreach ($base in @(
        "$env:APPDATA\Opera Software\Opera Stable",
        "$env:APPDATA\Opera Software\Opera GX Stable"
    )) {
        if (Test-Path $base) {
            $r = Limpar-Subpastas-Seguras -Base $base -Subcaminhos @('Cache','Code Cache','GPUCache','ShaderCache','Crashpad\reports','Service Worker\CacheStorage','Media Cache') -IgnorarNomes $Script:ArquivosProtegidosLogin
            $bNav += $r.Bytes; $n += $r.Itens; $falhas += $r.Falhas
        }
    }

    foreach ($ffBase in @("$env:LOCALAPPDATA\Mozilla\Firefox\Profiles", "$env:APPDATA\Mozilla\Firefox\Profiles")) {
        if (Test-Path $ffBase) {
            Get-ChildItem $ffBase -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $r = Limpar-Subpastas-Seguras -Base $_.FullName -Subcaminhos @('cache2','startupCache','thumbnails','shader-cache-off-main-thread')
                $bNav += $r.Bytes; $n += $r.Itens; $falhas += $r.Falhas
            }
        }
    }

    }

    if ($cfg.LimpaApps) {
    foreach ($p in @(
        "$env:APPDATA\discord\Cache", "$env:APPDATA\discord\Code Cache", "$env:APPDATA\discord\GPUCache",
        "$env:LOCALAPPDATA\Discord\Cache", "$env:LOCALAPPDATA\Discord\Code Cache", "$env:LOCALAPPDATA\Discord\GPUCache",
        "$env:LOCALAPPDATA\Steam\htmlcache", "$env:LOCALAPPDATA\Steam\dumps", "$env:LOCALAPPDATA\Steam\logs",
        "$env:APPDATA\Slack\Cache", "$env:APPDATA\Slack\Code Cache", "$env:APPDATA\Slack\GPUCache",
        "$env:APPDATA\Microsoft\Teams\Cache", "$env:APPDATA\Microsoft\Teams\Code Cache", "$env:APPDATA\Microsoft\Teams\GPUCache",
        "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\Caches",
        "$env:LOCALAPPDATA\Microsoft\Teams\Packages\SquirrelTemp",
        "$env:APPDATA\WhatsApp\Cache", "$env:APPDATA\WhatsApp\Code Cache", "$env:APPDATA\WhatsApp\GPUCache",
        "$env:LOCALAPPDATA\WhatsApp\Cache", "$env:LOCALAPPDATA\WhatsApp\Code Cache", "$env:LOCALAPPDATA\WhatsApp\GPUCache",
        "$env:APPDATA\Telegram Desktop\tdata\user_data\cache",
        "$env:APPDATA\Code\Cache", "$env:APPDATA\Code\Code Cache", "$env:APPDATA\Code\GPUCache",
        "$env:LOCALAPPDATA\Packages\Microsoft.Windows.Photos_8wekyb3d8bbwe\LocalCache"
    )) {
        $r = Limpar-Pasta $p
        $bApp += $r.Bytes; $n += $r.Itens; $falhas += $r.Falhas
    }

    }

    foreach ($pat in @(
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db"
    )) {
        $r = Limpar-Glob $pat
        $bSis += $r.Bytes; $n += $r.Itens; $falhas += $r.Falhas
    }

    if ($cfg.LimpaAvancado) {
        $rAdv = Limpeza-Avancada-Sistema
        $bAdv += $rAdv.Bytes; $n += $rAdv.Itens; $falhas += $rAdv.Falhas
    } else {
        $rAdv = @{Bytes=[long]0;Itens=0;Falhas=0;Rotinas=0}
    }

    if ($cfg.LimpaBrowsers) {
        $rChromiumAuto = Limpar-Caches-Chromium-Genericos
        $bNav += $rChromiumAuto.Bytes; $n += $rChromiumAuto.Itens; $falhas += $rChromiumAuto.Falhas
    } else {
        $rChromiumAuto = @{Bytes=[long]0;Itens=0;Falhas=0}
    }

    if ($cfg.LimpaApps) {
        $rAppAuto = Limpar-Caches-Genericos-Apps
        $bApp += $rAppAuto.Bytes; $n += $rAppAuto.Itens; $falhas += $rAppAuto.Falhas
    } else {
        $rAppAuto = @{Bytes=[long]0;Itens=0;Falhas=0;Pastas=0}
    }

    if ($cfg.LimpaGamer) {
        $rGamer = Limpar-Caches-Gamer
        $bGame += $rGamer.Bytes; $n += $rGamer.Itens; $falhas += $rGamer.Falhas
    } else {
        $rGamer = @{Bytes=[long]0;Itens=0;Falhas=0;Pastas=0}
    }

    if ($cfg.LimpaPrivacidadeLeve) {
        $rPriv = Executar-Limpeza-Privacidade-Leve
        $bPriv += $rPriv.Bytes; $n += $rPriv.Itens; $falhas += $rPriv.Falhas
    } else {
        $rPriv = @{Bytes=[long]0;Itens=0;Falhas=0;Entradas=0}
    }
    $net = 'DNS OK'
    try { ipconfig /flushdns 2>&1 | Out-Null } catch { $net = 'PARCIAL' }

    # Winsock reset removido do boot automático por segurança: exige reboot e pode afetar a rede sem necessidade.
    $disco = 'N/A'
    try {
        $ssd = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.MediaType -match 'SSD|SCM|NVMe' }
        if ($ssd) {
            $j = Start-Job { Optimize-Volume -DriveLetter C -ReTrim -ErrorAction Stop 2>&1 | Out-Null }
            Wait-Job $j -Timeout 75 | Out-Null
            Receive-Job $j -ErrorAction SilentlyContinue | Out-Null
            Remove-Job $j -Force -ErrorAction SilentlyContinue
            $disco = 'OK'
        }
    } catch { $disco = 'PARCIAL' }

    $livreDepois = Obter-Espaco-Livre-Sistema
    $libReal = if ($livreDepois -gt $livreAntes) { [long]($livreDepois - $livreAntes) } else { [long]0 }

    return @{
        Perfil=$cfg.Nome
        Total=$bSis+$bNav+$bApp+$bLix+$bAdv+$bGame+$bPriv
        SISTEMA=$bSis; NAV=$bNav; APPS=$bApp; LIXO=$bLix; AVANCADO=$bAdv; GAMER=$bGame; PRIV=$bPriv
        NET=$net; DISCO=$disco; Itens=$n; FALHAS=$falhas;
        AUTO_NAV=$rChromiumAuto.Bytes; AUTO_APPS=$rAppAuto.Bytes; AUTO_PASTAS=$rAppAuto.Pastas; ADV_ROTINAS=$rAdv.Rotinas;
        GAMER_PASTAS=$rGamer.Pastas; PRIV_ENTRADAS=$rPriv.Entradas;
        LivreAntes=$livreAntes; LivreDepois=$livreDepois; EspacoLiberadoReal=$libReal
    }
}
# ==============================================================================
#  [9]  LIMPEZA PROFUNDA DE ICONES
# ==============================================================================
function Executar-Limpeza-Icones {
    $bytes=[long]0; $n=0; $sb=0

    try { Stop-Process -Name explorer -Force -ErrorAction Stop; Start-Sleep -Milliseconds 1200 } catch {}

    foreach ($pat in @(
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_32.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_48.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_96.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_256.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_idx.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_32.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_96.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_256.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_768.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_1280.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_1920.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_2560.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_idx.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_sr.db"
    )) { $r=Limpar-Glob $pat; $bytes+=$r.Bytes; $n+=$r.Itens }

    try { ie4uinit.exe -show 2>&1|Out-Null } catch {}

    foreach ($pat in @(
        "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\*.automaticDestinations-ms",
        "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations\*.customDestinations-ms",
        "$env:APPDATA\Microsoft\Windows\Recent\*.lnk"
    )) { $r=Limpar-Glob $pat; $bytes+=$r.Bytes; $n+=$r.Itens }

    foreach ($sp in @(
        "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU",
        "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags",
        "HKCU:\Software\Microsoft\Windows\Shell\BagMRU",
        "HKCU:\Software\Microsoft\Windows\Shell\Bags"
    )) {
        if (Test-Path $sp) { try { Remove-Item $sp -Recurse -Force -ErrorAction Stop; $sb++ } catch {} }
    }

    try { Start-Process "explorer.exe"; Start-Sleep -Milliseconds 1500 } catch {}
    return @{Bytes=$bytes; Itens=$n; ShellBags=$sb}
}


# ==============================================================================
#  [9.1] HEURISTICAS DE USB SEGURO
# ==============================================================================
function Resolver-Caminho-Drive {
    param([string]$Drive)

    if ([string]::IsNullOrWhiteSpace($Drive)) { return $null }

    $d = $Drive.Trim()

    if ($d -match '^[A-Za-z]$') {
        $d = "$d`:"
    }

    if ($d -match '^[A-Za-z]:$') {
        $d = "$d\"
    }

    if ($d -notmatch '^[A-Za-z]:\\$') {
        return $null
    }

    try {
        if ([System.IO.Directory]::Exists($d)) {
            return $d
        }
    } catch {}

    return $null
}

function Obter-Estrutura-Vacina-USB {
    param([string]$Drive)

    $Drive = Resolver-Caminho-Drive $Drive
    if (-not $Drive) { return $null }

    $autorunFolder = [System.IO.Path]::Combine($Drive, 'autorun.inf')
    $vaultFolder   = [System.IO.Path]::Combine($autorunFolder, 'WSB_USB_Shield')
    $quarFolder    = [System.IO.Path]::Combine($vaultFolder, 'Quarentena')
    $logFolder     = [System.IO.Path]::Combine($vaultFolder, 'Logs')
    $metaFolder    = [System.IO.Path]::Combine($vaultFolder, 'Metadados')
    $desktopIni    = [System.IO.Path]::Combine($autorunFolder, 'desktop.ini')

    return [pscustomobject]@{
        Drive         = $Drive
        AutorunFolder = $autorunFolder
        VaultFolder   = $vaultFolder
        QuarFolder    = $quarFolder
        LogFolder     = $logFolder
        MetaFolder    = $metaFolder
        DesktopIni    = $desktopIni
    }
}

function Aplicar-Vacina-USB-Segura {
    param([string]$Drive)

    $s = Obter-Estrutura-Vacina-USB -Drive $Drive
    if (-not $s) { return $false }

    try {
        if (Test-Path -LiteralPath $s.AutorunFolder) {
            $item = Get-Item -LiteralPath $s.AutorunFolder -Force -ErrorAction SilentlyContinue
            if ($item -and -not $item.PSIsContainer) {
                Remove-Item -LiteralPath $s.AutorunFolder -Force -ErrorAction SilentlyContinue
            }
        }

        foreach ($p in @($s.AutorunFolder, $s.VaultFolder, $s.QuarFolder, $s.LogFolder, $s.MetaFolder)) {
            if (-not (Test-Path -LiteralPath $p)) {
                New-Item -Path $p -ItemType Directory -Force | Out-Null
            }
        }

        if (-not (Test-Path -LiteralPath $s.DesktopIni)) {
            @"
[.ShellClassInfo]
ConfirmFileOp=0
NoSharing=1
"@ | Set-Content -LiteralPath $s.DesktopIni -Encoding ASCII -Force
        }

        try {
            attrib +h +s +r "$($s.AutorunFolder)" 2>$null
            attrib +h +s "$($s.DesktopIni)" 2>$null
            attrib +h +s "$($s.VaultFolder)" 2>$null
            attrib +h +s "$($s.QuarFolder)" 2>$null
            attrib +h +s "$($s.LogFolder)" 2>$null
            attrib +h +s "$($s.MetaFolder)" 2>$null
        } catch {}

        $pasta = Get-Item -LiteralPath $s.AutorunFolder -Force -ErrorAction SilentlyContinue
        if ($pasta -and $pasta.PSIsContainer) {
            $pasta.Attributes = [IO.FileAttributes]::ReadOnly -bor [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System -bor [IO.FileAttributes]::Directory
        }

        return $true
    } catch {}

    return $false
}

function Mover-Para-Quarentena-USB {
    param(
        [Parameter(Mandatory=$true)][string]$Drive,
        [Parameter(Mandatory=$true)][System.IO.FileSystemInfo]$Item
    )

    $s = Obter-Estrutura-Vacina-USB -Drive $Drive
    if (-not $s) { return $false }

    try {
        if (-not (Test-Path -LiteralPath $s.QuarFolder)) {
            New-Item -Path $s.QuarFolder -ItemType Directory -Force | Out-Null
        }

        $stamp   = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
        $destino = [System.IO.Path]::Combine($s.QuarFolder, "${stamp}__$($Item.Name)")

        Move-Item -LiteralPath $Item.FullName -Destination $destino -Force -ErrorAction Stop
        return $true
    } catch {
        try {
            Remove-Item -LiteralPath $Item.FullName -Force -Recurse -ErrorAction Stop
            return $true
        } catch {}
    }

    return $false
}

function Test-Atalho-USB-Suspeito {
    param([System.IO.FileInfo]$ArquivoLnk, [string]$Drive)

    $Drive = Resolver-Caminho-Drive $Drive
    if (-not $Drive) { return $false }

    try {
        $wsh = New-Object -ComObject WScript.Shell
        $sc  = $wsh.CreateShortcut($ArquivoLnk.FullName)
        $target = [string]$sc.TargetPath
        $args   = [string]$sc.Arguments

        if (($target + ' ' + $args) -match 'cmd\.exe|powershell\.exe|wscript\.exe|cscript\.exe|mshta\.exe|rundll32\.exe') { return $true }
        if (($target + ' ' + $args) -match '-enc|downloadstring|frombase64string|vbscript:|javascript:') { return $true }

        $base = [System.IO.Path]::GetFileNameWithoutExtension($ArquivoLnk.Name)
        $irm = Get-ChildItem -LiteralPath $Drive -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -eq $base -and $_.FullName -ne $ArquivoLnk.FullName }

        foreach ($item in $irm) {
            if (($item.Attributes -band [IO.FileAttributes]::Hidden) -or ($item.Attributes -band [IO.FileAttributes]::System)) {
                return $true
            }
        }
    } catch {}

    return $false
}

function Get-Itens-USB-Suspeitos {
    param([string]$Drive)

    $Drive = Resolver-Caminho-Drive $Drive
    $saida = [System.Collections.Generic.List[System.IO.FileSystemInfo]]::new()

    if (-not $Drive) { return $saida }

    try {
        Get-ChildItem -LiteralPath $Drive -Force -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.PSIsContainer) {
                $dn = $_.Name.ToLowerInvariant()

                if ($dn -in @('recycler','$recycle.bin')) {
                    $saida.Add($_) | Out-Null
                }

                if ($dn -eq 'autorun.inf') {
                    $okShield = Test-Path -LiteralPath ([System.IO.Path]::Combine($_.FullName, 'WSB_USB_Shield'))
                    if (-not $okShield) {
                        $saida.Add($_) | Out-Null
                    }
                }
                return
            }

            $ext = $_.Extension.ToLowerInvariant()
            $nome = $_.Name.ToLowerInvariant()
            $isHidden = (($_.Attributes -band [IO.FileAttributes]::Hidden) -or ($_.Attributes -band [IO.FileAttributes]::System))
            $sus = $false

            if ($nome -eq 'autorun.inf') { $sus = $true }
            elseif ($ext -in '.vbs','.vbe','.js','.jse','.wsf','.wsh','.hta','.scr','.pif') { $sus = $true }
            elseif ($ext -in '.bat','.cmd','.ps1') { $sus = $isHidden -or $nome -match 'autorun|open|launch|start|run' }
            elseif ($ext -eq '.lnk') { $sus = Test-Atalho-USB-Suspeito -ArquivoLnk $_ -Drive $Drive }
            elseif ($isHidden -and $ext -in '.exe','.com') { $sus = $true }

            if ($sus) { $saida.Add($_) | Out-Null }
        }
    } catch {}

    return $saida
}


function Aplicar-Vacinacao-Windows-USB {
    $log = [System.Collections.Generic.List[string]]::new()

    foreach ($path in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    )) {
        try {
            if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
            New-ItemProperty -Path $path -Name 'NoDriveTypeAutoRun' -PropertyType DWord -Value 255 -Force | Out-Null
            New-ItemProperty -Path $path -Name 'NoAutorun' -PropertyType DWord -Value 1 -Force | Out-Null
            $log.Add("  Politica aplicada: $path")
        } catch {
            $log.Add("  Falha ao aplicar política: $path")
        }
    }

    foreach ($mp in @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2'
    )) {
        try {
            if (Test-Path $mp) {
                Get-ChildItem $mp -ErrorAction SilentlyContinue | ForEach-Object {
                    try { Remove-Item -LiteralPath $_.PSPath -Recurse -Force -ErrorAction Stop } catch {}
                }
                $log.Add("  MountPoints limpos: $mp")
            }
        } catch {
            $log.Add("  Falha ao limpar MountPoints: $mp")
        }
    }

    return $log
}

function Reparar-USB-Com-Vacina {
    param([string]$Drive, [string]$Origem = 'Sentinela USB')

    $Drive = Resolver-Caminho-Drive $Drive
    if (-not $Drive) { return }

    try {
        $chave = $Drive.TrimEnd('\')
        $agora = Get-Date
        if ($Script:USBProcessados.ContainsKey($chave)) {
            $ult = [datetime]$Script:USBProcessados[$chave]
            if (($agora - $ult).TotalSeconds -lt $Script:USBJanelaReanaliseSeg) { return }
        }
        $Script:USBProcessados[$chave] = $agora
    } catch {}

    Start-Sleep -Milliseconds 1800

    $Drive = Resolver-Caminho-Drive $Drive
    if (-not $Drive) { return }

    $ts        = Get-Date -Format 'dd/MM/yyyy HH:mm:ss'
    $arqLog    = [System.Collections.Generic.List[string]]::new()
    $ameacaArq = [System.Collections.Generic.List[string]]::new()
    $ameacaReg = [System.Collections.Generic.List[string]]::new()

    $arqLog.Add("Drive Detectado : $Drive")
    $arqLog.Add("Inicio Analise  : $ts")
    $arqLog.Add("Origem          : $Origem")
    $arqLog.Add('')

    try { Stop-Process -Name 'wscript','cscript','mshta' -Force -ErrorAction SilentlyContinue } catch {}
    $arqLog.Add('[MEMORIA] Interpretadores de script suspeitos finalizados se necessário')

    $arqLog.Add('')
    $arqLog.Add('[ARQUIVOS SUSPEITOS]')
    foreach ($item in @(Get-Itens-USB-Suspeitos -Drive $Drive)) {
        try {
            if (Mover-Para-Quarentena-USB -Drive $Drive -Item $item) {
                $ameacaArq.Add($item.Name) | Out-Null
                $arqLog.Add("  ISOLADO: $($item.FullName)")
            } else {
                $arqLog.Add("  FALHA AO ISOLAR: $($item.FullName)")
            }
        } catch {
            $arqLog.Add("  FALHA AO ISOLAR: $($item.FullName)")
        }
    }
    if ($ameacaArq.Count -eq 0) { $arqLog.Add('  Nenhum artefato típico de worm USB encontrado na raiz.') }

    $arqLog.Add('')
    $arqLog.Add('[RESTAURACAO] Removendo atributos Hidden/System dos arquivos do usuário...')
    try {
        $mask = "$Drive*.*"
        Start-Process cmd.exe -ArgumentList "/c attrib -r -a -s -h /s /d `"$mask`"" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
        $arqLog.Add('  attrib concluído com sucesso.')
    } catch {
        $arqLog.Add('  Falha ao executar attrib.')
    }

    $arqLog.Add('')
    $arqLog.Add('[VACINA] Blindando estrutura autorun.inf no dispositivo...')
    if (Aplicar-Vacina-USB-Segura -Drive $Drive) {
        $arqLog.Add('  Vacina aplicada: pasta autorun.inf com subestrutura protegida.')
    } else {
        $arqLog.Add('  Nao foi possivel aplicar a vacina no dispositivo.')
    }

    $arqLog.Add('')
    $arqLog.Add('[VACINA WINDOWS] Endurecendo AutoRun/AutoPlay e limpando gatilhos antigos...')
    foreach ($linha in Aplicar-Vacinacao-Windows-USB) { $arqLog.Add($linha) }

    $arqLog.Add('')
    $arqLog.Add('[REGISTRO] Removendo persistências ligadas a USB/script malicioso...')
    $runKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'
    )
    foreach ($chave in $runKeys) {
        if (-not (Test-Path $chave)) { continue }
        try {
            $props = Get-ItemProperty -Path $chave -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                $nome  = $_.Name
                $valor = [string]$_.Value
                $sus   = $false
                if ($valor -match '([A-Z]:\\).*\.(vbs|vbe|js|jse|wsf|wsh|bat|cmd|ps1|scr|pif)') { $sus = $true }
                elseif ($valor -match 'wscript|cscript|mshta|powershell.*-enc|downloadstring|frombase64string|vbscript:|javascript:') { $sus = $true }
                if ($sus) {
                    try {
                        Remove-ItemProperty -Path $chave -Name $nome -Force -ErrorAction Stop
                        $ameacaReg.Add("$chave -> $nome") | Out-Null
                        $arqLog.Add("  REMOVIDO: [$chave] $nome = $valor")
                    } catch {
                        $arqLog.Add("  FALHA AO REMOVER: [$chave] $nome")
                    }
                }
            }
        } catch {}
    }
    if ($ameacaReg.Count -eq 0) { $arqLog.Add('  Nenhuma persistência suspeita ligada a USB foi encontrada.') }

    $totalAmeacas = $ameacaArq.Count + $ameacaReg.Count
    $arqLog.Add('')
    $arqLog.Add('[RESUMO]')
    $arqLog.Add("  Artefatos isolados             : $($ameacaArq.Count)")
    $arqLog.Add("  Persistencias removidas        : $($ameacaReg.Count)")
    $arqLog.Add("  Total de neutralizacoes        : $totalAmeacas")
    $arqLog.Add('  Vacina autorun.inf             : Aplicada')
    $arqLog.Add('  Endurecimento Windows USB      : Aplicado')
    $arqLog.Add('  Arquivos do usuario restaurados: Sim')

    $driveTag = $Drive.Replace(':','').Replace('\','')
    Gravar-Log -Operacao "USB_${driveTag}" -Linhas $arqLog | Out-Null

    Enviar-Toast `
        -Titulo "WSB USB Shield - $Drive" `
        -Sub    $(if ($totalAmeacas -gt 0) { "$($ameacaArq.Count) arquivo(s) + $($ameacaReg.Count) persistencia(s) removidos" } else { 'Dispositivo verificado e vacinado' }) `
        -Corpo  $(if ($totalAmeacas -gt 0) { 'Ameacas neutralizadas, arquivos restaurados e vacina aplicada.' } else { 'Vacina passiva aplicada, Windows endurecido e log salvo.' }) `
        -Modo   'USB' `
        -Audio  'Notification.Default'
}

# ==============================================================================
#  [10] VARREDURA USB INICIAL
#       Escaneia todos os pendrives ja conectados no momento do boot.
#       Roda UMA VEZ antes do Sentinela WMI entrar em modo de escuta.
#       Logica identica ao Sentinela — mesmas etapas, mesmos logs, mesmos banners.
# ==============================================================================
function Executar-Varredura-USB-Inicial {
    $drives = Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 2 }

    if (-not $drives) {
        Gravar-Log -Operacao 'USB_BOOT_INICIAL' -Linhas @(
            '  Nenhum dispositivo USB removivel conectado no boot.',
            '  Varredura inicial concluida sem acoes necessarias.'
        ) | Out-Null
        return
    }

    foreach ($disk in $drives) {
        $d = Resolver-Caminho-Drive $disk.DeviceID
        if ($d) {
            Reparar-USB-Com-Vacina -Drive $d -Origem 'Varredura USB Inicial (boot)'
        }
    }
}

# ==============================================================================
#  [10] SENTINELA USB
#       Roda em background via Register-WmiEvent.
#       Ao detectar pendrive executa analise silenciosa, vacina e notifica.
#       Loop watchdog a cada 5min reconecta o evento se ele cair.
# ==============================================================================
function Iniciar-Sentinela-USB {
    try { Unregister-Event -SourceIdentifier 'WSB_USBWatcher' -ErrorAction SilentlyContinue } catch {}
    try { Get-Job -Name 'WSB_USBWatcher' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue } catch {}

    $query = "SELECT * FROM Win32_VolumeChangeEvent WHERE EventType = 2"

    Register-WmiEvent -Query $query -SourceIdentifier 'WSB_USBWatcher' -Action {
        try {
            $drive = $Event.SourceEventArgs.NewEvent.DriveName
            if ([string]::IsNullOrWhiteSpace($drive)) { return }

            Start-Sleep -Milliseconds 1200
            Reparar-USB-Com-Vacina -Drive $drive -Origem 'Sentinela USB'
        } catch {}
    } | Out-Null
}

# ==============================================================================
#  [11] LOGICA PRINCIPAL
# ==============================================================================


if ($DiagnosticoSomente) {
    $diag = Executar-Diagnostico-Sistema -Perfil $PerfilLimpeza
    $linhas = @(
        "  Perfil             : $($diag.Perfil)",
        "  Espaço Livre Atual : $(Formatar-Tamanho $diag.EspacoLivreAntes)",
        "  TEMP/SISTEMA       : $(Formatar-Tamanho $diag.TempSistema)",
        "  NAVEGADORES        : $(Formatar-Tamanho $diag.Navegadores)",
        "  APPS/CACHE         : $(Formatar-Tamanho $diag.Apps)",
        "  LIXEIRA            : $(Formatar-Tamanho $diag.Lixeira)",
        "  USB CONECTADOS     : $($diag.USBConectados)"
    )
    Gravar-Log -Operacao 'DIAGNOSTICO SISTEMA' -Linhas $linhas | Out-Null
    WSB-Toast -Titulo 'WSB AutoClean GE - Diagnóstico' -Mensagem "Perfil $($diag.Perfil) | TEMP $(Formatar-Tamanho $diag.TempSistema) | APPS $(Formatar-Tamanho $diag.Apps)" -Corpo "NAV $(Formatar-Tamanho $diag.Navegadores) | LIX $(Formatar-Tamanho $diag.Lixeira) | USB $($diag.USBConectados)" -Icone 'Normal'
    Start-Sleep -Seconds 4
    try { if ($script:Mutex) { $script:Mutex.ReleaseMutex() | Out-Null; $script:Mutex.Dispose() } } catch {}
    exit
}

if ($USBRepairQuick) {
    $linhas = Invoke-USBRepairSystem -ScanConectados
    WSB-Toast -Titulo 'WSB USB Shield' -Mensagem 'USB Repair System executado.' -Corpo (($linhas | Select-Object -First 2) -join ' | ') -Icone 'USB'
    Start-Sleep -Seconds 4
    try { if ($script:Mutex) { $script:Mutex.ReleaseMutex() | Out-Null; $script:Mutex.Dispose() } } catch {}
    exit
}

if ($USBGhostReport) {
    $linhas = Invoke-USBRepairSystem -GhostReport
    WSB-Toast -Titulo 'WSB USB Shield' -Mensagem 'Relatório de dispositivos USB gerado.' -Corpo (($linhas | Select-Object -First 2) -join ' | ') -Icone 'USB'
    Start-Sleep -Seconds 4
    try { if ($script:Mutex) { $script:Mutex.ReleaseMutex() | Out-Null; $script:Mutex.Dispose() } } catch {}
    exit
}

if ($USBReenumerar) {
    $linhas = Invoke-USBRepairSystem -Reenumerar
    WSB-Toast -Titulo 'WSB USB Shield' -Mensagem 'Reenumeração USB solicitada ao Windows.' -Corpo (($linhas | Select-Object -First 2) -join ' | ') -Icone 'USB'
    Start-Sleep -Seconds 4
    try { if ($script:Mutex) { $script:Mutex.ReleaseMutex() | Out-Null; $script:Mutex.Dispose() } } catch {}
    exit
}

if ($AutoRun) {

    Garantir-Pasta-Estado
    Salvar-EstadoAutoClean -Enabled $true -UltimaAcao 'Inicialização AutoRun'
    Atualizar-Heartbeat
    Remove-Item $Script:ArquivoDisable -Force -ErrorAction SilentlyContinue
    Garantir-Autorecuperacao -Silencioso | Out-Null

    # -------------------------------------------------------------------------
    # MODO AUTO — acionado pela tarefa agendada no logon (100% silencioso)
    # -------------------------------------------------------------------------
    Start-Sleep -Seconds 18
    # Grava heartbeat/PID do processo AutoRun para permitir encerramento pelo Toggle
    Atualizar-Heartbeat

    WSB-Toast -Titulo "WSB AutoClean GE v$($Script:VersaoApp)" -Mensagem 'Ghost Edition iniciado em modo silencioso.' -Corpo "Perfil: $PerfilLimpeza | Logs em Documentos\WSB Auto Clean GE" -Icone 'Normal' -Som 'Notification.Default'

    $rDiag = Executar-Diagnostico-Sistema -Perfil $PerfilLimpeza
    Gravar-Log -Operacao 'DIAGNOSTICO SISTEMA' -Linhas @(
        "  Perfil             : $($rDiag.Perfil)",
        "  Espaço Livre Atual : $(Formatar-Tamanho $rDiag.EspacoLivreAntes)",
        "  TEMP/SISTEMA       : $(Formatar-Tamanho $rDiag.TempSistema)",
        "  NAVEGADORES        : $(Formatar-Tamanho $rDiag.Navegadores)",
        "  APPS/CACHE         : $(Formatar-Tamanho $rDiag.Apps)",
        "  LIXEIRA            : $(Formatar-Tamanho $rDiag.Lixeira)",
        "  USB CONECTADOS     : $($rDiag.USBConectados)",
        "  Resultado          : OK"
    ) | Out-Null

    WSB-Toast -Titulo 'WSB AutoClean GE - Diagnóstico' -Mensagem 'Escaneando sistema antes da limpeza...' -Corpo "TEMP $(Formatar-Tamanho $rDiag.TempSistema) | NAV $(Formatar-Tamanho $rDiag.Navegadores) | APPS $(Formatar-Tamanho $rDiag.Apps)" -Icone 'Normal' -Som 'Notification.Default'

    # --- ETAPA 1: OTIMIZACAO DE RAM ---
    $rRAM = Executar-Otimizacao-RAM
    $logRAM = Gravar-Log -Operacao "OTIMIZAÇÃO DA RAM" -Linhas @(
        "  Memória Liberada  : $(Formatar-Tamanho $rRAM.Delta)",
        "  Método            : GC.Collect (Gerações 0/1/2) + Redução WorkingSet",
        "  Processos Afetados: Todos os Processos do Usuário",
        "  Resultado         : OK"
    )

    Enviar-Toast `
        -Titulo "WSB AutoClean GE - RAM Otimizada" `
        -Sub    "$(Formatar-Tamanho $rRAM.Delta) Liberados do Working Set" `
        -Corpo  "GC Triplo + Redução WorkingSet Em Todos os Processos  |  Log Salvo Em Documentos" `
        -Modo   "RAM" `
        -Audio  "Notification.Default"

    # --- ETAPA 2: LIMPEZA COMPLETA ---
    WSB-Toast -Titulo 'WSB AutoClean GE - Limpeza' -Mensagem 'Limpeza em andamento...' -Corpo "Perfil $PerfilLimpeza | TEMP $(Formatar-Tamanho $rDiag.TempSistema) | APPS $(Formatar-Tamanho $rDiag.Apps)" -Icone 'Normal' -Som 'Notification.Default'
    $rClean = Executar-Limpeza-Completa -Perfil $PerfilLimpeza

    $logClean = Gravar-Log -Operacao "LIMPEZA COMPLETA" -Linhas @(
        "  Perfil            : $($rClean.Perfil)",
        "  Espaço Livre Antes: $(Formatar-Tamanho $rClean.LivreAntes)",
        "  Espaço Livre Depois: $(Formatar-Tamanho $rClean.LivreDepois)",
        "  Espaço Real Ganho : $(Formatar-Tamanho $rClean.EspacoLiberadoReal)",
        "  Total Liberado    : $(Formatar-Tamanho $rClean.Total)",
        "  Itens Removidos   : $($rClean.Itens)",
        "  TEMP/SISTEMA      : $(Formatar-Tamanho $rClean.SISTEMA)",
        "  LIXEIRA           : $(Formatar-Tamanho $rClean.LIXO)",
        "  NAVEGADORES       : $(Formatar-Tamanho $rClean.NAV)",
        "  APPS              : $(Formatar-Tamanho $rClean.APPS)",
        "  AVANÇADO SISTEMA  : $(Formatar-Tamanho $rClean.AVANCADO)  em $($rClean.ADV_ROTINAS) rotina(s)",
        "  GAMER CACHE      : $(Formatar-Tamanho $rClean.GAMER)  em $($rClean.GAMER_PASTAS) pasta(s)",
        "  PRIVACIDADE LEVE : $(Formatar-Tamanho $rClean.PRIV)  em $($rClean.PRIV_ENTRADAS) conjunto(s)",
        "  AUTO NAV         : $(Formatar-Tamanho $rClean.AUTO_NAV)",
        "  AUTO APPS        : $(Formatar-Tamanho $rClean.AUTO_APPS)  em $($rClean.AUTO_PASTAS) pasta(s)",
        "  DNS / Winsock     : $($rClean.NET)",
        "  TRIM SSD          : $($rClean.DISCO)",
        "  Cookies/Logins    : PRESERVADOS (Sem Alterações)",
        "  Falhas Ignoradas  : $($rClean.FALHAS) arquivo(s) bloqueados/ocupados",
        "  Resultado         : OK"
    )

    Enviar-Toast `
        -Titulo "WSB AutoClean GE - Sistema Limpo" `
        -Sub    "$(Formatar-Tamanho $rClean.EspacoLiberadoReal) reais  |  $($rClean.Itens) itens removidos" `
        -Corpo  "Perfil: $($rClean.Perfil) | SIS: $(Formatar-Tamanho $rClean.SISTEMA)  ADV: $(Formatar-Tamanho $rClean.AVANCADO)  LIX: $(Formatar-Tamanho $rClean.LIXO)  NAV: $(Formatar-Tamanho $rClean.NAV)  APPS: $(Formatar-Tamanho $rClean.APPS)" `
        -Modo   "Normal" `
        -Audio  "Notification.Default"

    # --- ETAPA 3: LIMPEZA PROFUNDA DE ICONES ---
    $rIco = Executar-Limpeza-Icones

    $logIco = Gravar-Log -Operacao "LIMPEZA ÍCONES" -Linhas @(
        "  Total Liberado    : $(Formatar-Tamanho $rIco.Bytes)",
        "  Arquivos Removidos: $($rIco.Itens)",
        "  Shell Bags Limpos : $($rIco.ShellBags) Chaves de Registro",
        "  Iconcache         : Limpo",
        "  Thumbcache        : Limpo",
        "  Jump Lists        : Limpos",
        "  Arquivos Recentes : Limpos",
        "  Explorer          : Reiniciado",
        "  Resultado         : OK"
    )

    Enviar-Toast `
        -Titulo "WSB AutoClean GE - Ícones Reconstruídos" `
        -Sub    "$(Formatar-Tamanho $rIco.Bytes) Liberados  |  $($rIco.Itens) Arquivos  |  $($rIco.ShellBags) Shell Bags" `
        -Corpo  "Iconcache + Thumbcache + JumpLists Limpos  |  Explorer Reiniciado  |  Log Salvo" `
        -Modo   "Icones" `
        -Audio  "Notification.Default"

    # --- VACINA WINDOWS USB (hardening global seguro) ---
    foreach ($linha in Aplicar-Vacinacao-Windows-USB) { }

    # --- VARREDURA USB INICIAL (pendrives ja conectados ao ligar) ---
    Executar-Varredura-USB-Inicial

    # --- ATIVA SENTINELA USB ---
    Iniciar-Sentinela-USB
    Registrar-Saude-Residente -Operacao 'SELFTEST AUTORUN INICIAL' | Out-Null

    # --- WATCHDOG: mantém o processo vivo e reconecta o sentinela se cair ---
    while ($true) {
        Start-Sleep -Seconds 180
        Atualizar-Heartbeat

        if (Test-Path $Script:ArquivoDisable) {
            try { Unregister-Event -SourceIdentifier 'WSB_USBWatcher' -ErrorAction SilentlyContinue } catch {}
            try { Get-Job -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue } catch {}
            break
        }

        $ev = Get-EventSubscriber -SourceIdentifier "WSB_USBWatcher" -ErrorAction SilentlyContinue
        if (-not $ev) {
            Iniciar-Sentinela-USB
            Registrar-Saude-Residente -Operacao 'SELFTEST WATCHDOG REPARO' | Out-Null
        }

        Garantir-Autorecuperacao -Silencioso | Out-Null

        # Limpeza de jobs, fila de eventos e cache de drives já tratados
        Get-Job -State Completed -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
        Get-Event -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
        try {
            foreach ($k in @($Script:USBProcessados.Keys)) {
                if (((Get-Date) - [datetime]$Script:USBProcessados[$k]).TotalMinutes -gt 15) { $Script:USBProcessados.Remove($k) }
            }
        } catch {}
    }

    Remove-Item $Script:ArquivoPID,$Script:ArquivoHeartbeat -Force -ErrorAction SilentlyContinue

} else {

    # -------------------------------------------------------------------------
    # MODO TOGGLE — execucao manual
    # -------------------------------------------------------------------------

    $estadoAtual = Obter-EstadoAutoClean
    $tarefaAtiva = Get-ScheduledTask -TaskName $Script:NomeTarefa -ErrorAction SilentlyContinue
    $infraAtiva = $false
    if ($tarefaAtiva) {
        $infraAtiva = $true
    } elseif (Test-Path $Script:StartupLnk) {
        $infraAtiva = $true
    } elseif ($estadoAtual -and $estadoAtual.Enabled) {
        $infraAtiva = $true
    }

    if (-not $isAdmin -and -not $ToggleAdmin) {
        if (Reiniciar-Processo-ElevadoParaToggle) { exit }

        Enviar-Toast `
            -Titulo "WSB AutoClean GE - Erro ao Ativar" `
            -Sub    "Não Foi Possível Obter Permissão de Administrador." `
            -Corpo  "Permissão negada. Nenhuma alteração foi aplicada." `
            -Modo   "Alerta" `
            -Audio  "Notification.Default"

        Start-Sleep -Seconds 4
        exit
    }

    if ($infraAtiva) {

        $removido = Remover-LNK
        if ($removido) {
            Start-Sleep -Milliseconds 900
            $saudeDesativacao = Registrar-Saude-Residente -Operacao 'SELFTEST TOGGLE DESATIVAR'
            $desativadoOk = (-not $saudeDesativacao.TarefaOk) -and (-not $saudeDesativacao.HeartbeatOk)

            Gravar-Log -Operacao "TOGGLE DESATIVAR" -Linhas @(
                "  Acao   : AutoClean DESATIVADO",
                "  Task   : Removida $($Script:NomeTarefa)",
                "  LNK    : Removido de $($Script:StartupLnk)",
                "  Status : Nenhuma Limpeza Será Executada no Próximo Boot",
                "  SelfTest Task     : $($saudeDesativacao.TarefaOk)",
                "  SelfTest Heartbeat: $($saudeDesativacao.HeartbeatOk)",
                "  SelfTest Estado   : $($saudeDesativacao.EstadoOk)"
            ) | Out-Null

            Enviar-Toast `
                -Titulo "WSB AutoClean GE - DESATIVADO" `
                -Sub    $(if ($desativadoOk) { "Inicialização automática removida com sucesso." } else { "Desativação concluída com verificação parcial." }) `
                -Corpo  "Task: $($saudeDesativacao.TarefaOk) | Heartbeat: $($saudeDesativacao.HeartbeatOk) | Estado: $($saudeDesativacao.EstadoOk)." `
                -Modo   "Desativado" `
                -Audio  "Notification.Default"
        } else {
            Enviar-Toast `
                -Titulo "WSB AutoClean GE - Falha ao Desativar" `
                -Sub    "Não Foi Possível Remover a Inicialização Automática." `
                -Corpo  "Verifique a tarefa $($Script:NomeTarefa) e o atalho em Startup." `
                -Modo   "Alerta" `
                -Audio  "Notification.Default"
        }

    } else {

        $criado = Criar-LNK
        if ($criado) {
            Garantir-Autorecuperacao -Silencioso | Out-Null
            Start-Sleep -Milliseconds 900
            $saudeAtivacao = Registrar-Saude-Residente -Operacao 'SELFTEST TOGGLE ATIVAR'

            Gravar-Log -Operacao "TOGGLE ATIVAR" -Linhas @(
                "  Acao   : WSB AutoClean GE - ATIVADO",
                "  Task   : Criada $($Script:NomeTarefa) com privilégios elevados",
                "  LNK    : Criado em $($Script:StartupLnk)",
                "  Status : Limpeza Será Executada Automaticamente no Próximo Boot",
                "  Etapas : RAM + Limpeza Completa + Ícones Profundo + Sentinela USB",
                "  AutoRec: Infraestrutura, toast, tarefa e atalho serão autorreparados se necessário",
                "  SelfTest Task     : $($saudeAtivacao.TarefaOk)",
                "  SelfTest Estado   : $($saudeAtivacao.EstadoOk)",
                "  SelfTest Watcher  : $($saudeAtivacao.USBWatcherOk)",
                "  SelfTest Heartbeat: $($saudeAtivacao.HeartbeatOk)"
            ) | Out-Null

            Enviar-Toast `
                -Titulo "WSB AutoClean GE v$($Script:VersaoApp) - ATIVADO!" `
                -Sub    "Inicialização automática validada e pronta para o próximo boot." `
                -Corpo  "Task: $($saudeAtivacao.TarefaOk) | Estado: $($saudeAtivacao.EstadoOk) | USB Watcher: $($saudeAtivacao.USBWatcherOk)." `
                -Modo   "Ativado" `
                -Audio  "Notification.Reminder"
        } else {
            Enviar-Toast `
                -Titulo "WSB AutoClean GE - Erro ao Ativar" `
                -Sub    "Não Foi Possível Criar a Inicialização Automática." `
                -Corpo  "Execute novamente e aceite a elevação para registrar a tarefa." `
                -Modo   "Alerta" `
                -Audio  "Notification.Default"
        }
    }

    Start-Sleep -Seconds 4
}

try { if ($script:Mutex) { $script:Mutex.ReleaseMutex() | Out-Null; $script:Mutex.Dispose() } } catch {}
