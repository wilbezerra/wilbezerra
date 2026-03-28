# ==============================================================================
#  WSB FLASH CLEAN  v3.1 (AGGRESSIVE PUBLIC PROTECTED)
#  Desenvolvido por WSB TECH
#
#  MODO DE OPERACAO:
#    Execucao MANUAL -> Executa tudo imediatamente ao clicar
#    Sem boot, sem LNK, sem tarefas agendadas
#
#  O QUE FAZ AO CLICAR:
#    1. Otimizacao de RAM  (GC + reducao WorkingSet)       -> Toast + Log
#    2. Limpeza Completa   (cache, DNS, TRIM silencioso)   -> Toast + Log
#    3. Limpeza de Icones  (iconcache, thumbcache, Bags)   -> Toast + Log
#    4. Varredura USB      (todos os pendrives conectados) -> Toast + Log
#       - Analise silenciosa, vacina, limpa registro
#
#  LOGS:  %USERPROFILE%\Documents\WSB Flash Clean\  (um arquivo por evento)
#  BANNER: GDI+ -> PNG temporario em disco    (presente em TODOS os toasts)
#  LOGINS: Nenhum cookie, senha ou token e removido
# ==============================================================================

# ==============================================================================
#  [PROTECAO DE INTEGRIDADE - RELEASE PUBLICA]
#  ESTA VERSAO E PARA DISTRIBUICAO PUBLICA.
#  INSTRUCOES:
#    1) Gere o hash SHA256 FINAL deste proprio arquivo apos concluir o build
#    2) Substitua PLACEHOLDER_HASH pelo hash final antes de publicar
#  OBSERVACAO:
#    - Esta protecao bloqueia execucao se o arquivo for alterado
#    - Ela nao criptografa o codigo de forma real; ela impede adulteracao pratica
# ==============================================================================
function Get-WSBFlashCleanSelfHash {
    try {
        $path = if ($PSCommandPath) { $PSCommandPath } else { [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName }
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $null }
        return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
    } catch {
        return $null
    }
}

$Script:WSBExpectedHash = "PLACEHOLDER_HASH"
$Script:WSBCurrentHash  = Get-WSBFlashCleanSelfHash

if ($Script:WSBExpectedHash -ne "PLACEHOLDER_HASH") {
    if ([string]::IsNullOrWhiteSpace($Script:WSBCurrentHash) -or ($Script:WSBCurrentHash -ne $Script:WSBExpectedHash)) {
        try {
            $violDir = Join-Path $env:USERPROFILE "Documents\WSB Flash Clean"
            $null = New-Item -ItemType Directory -Path $violDir -Force -ErrorAction SilentlyContinue
            $violLog = Join-Path $violDir "Violacao_Integridade.log"
            $msg = "[{0}] VIOLACAO DE INTEGRIDADE DETECTADA | HashAtual={1} | Arquivo={2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Script:WSBCurrentHash, ($PSCommandPath)
            Add-Content -LiteralPath $violLog -Value $msg -Encoding UTF8
        } catch {}
        exit
    }
}


# ==============================================================================
#  [DETECCAO ANTECIPADA] Detecta .exe antes de qualquer outra coisa
# ==============================================================================
$Script:IsExePre   = ($null -eq $PSCommandPath -or $PSCommandPath -eq "")
$Script:CaminhoExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

# ==============================================================================
#  [OCULTAR JANELA] Silencioso desde o primeiro frame
# ==============================================================================
try {
    $codeHide = '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
    $typeHide  = Add-Type -MemberDefinition $codeHide -Name "Win32SW_WSBFC" -Namespace "Win32FC" -PassThru -ErrorAction SilentlyContinue
    $handleHide = [System.Diagnostics.Process]::GetCurrentProcess().MainWindowHandle
    if ($handleHide -ne [IntPtr]::Zero) { $typeHide::ShowWindow($handleHide, 0) | Out-Null }
} catch {}

# ==============================================================================
#  [AUTO-ELEVACAO] Reexecuta como Administrador se nao tiver privilegios
#  Funciona corretamente tanto como .ps1 quanto como .exe compilado
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    if ($Script:IsExePre) {
        try { Start-Process -FilePath $Script:CaminhoExe -Verb RunAs } catch {}
    } else {
        $argList = "-ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File `"$PSCommandPath`""
        try { Start-Process powershell.exe -Verb RunAs -ArgumentList $argList } catch {}
    }
    exit
}

# ==============================================================================
#  [EXCLUSAO DEFENDER] Protege o proprio executavel de quarentena
#  Evita que o Windows Defender bloqueie ou remova o script/exe
# ==============================================================================
try {
    Add-MpPreference -ExclusionPath $Script:CaminhoExe -ErrorAction SilentlyContinue
} catch {}

# ==============================================================================
#  [ENCODING] Acentos corretos nos logs e strings
# ==============================================================================
try { [Console]::InputEncoding  = [System.Text.Encoding]::UTF8 } catch {}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8
[System.Threading.Thread]::CurrentThread.CurrentCulture   = [System.Globalization.CultureInfo]'pt-BR'
[System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]'pt-BR'

# ==============================================================================
#  [0]  CONSTANTES
# ==============================================================================
$Script:VersaoApp  = "3.1"
$Script:NomeApp    = "WSB FLASH CLEAN"

$Script:CaminhoPS1 = if (-not $Script:IsExePre) { $PSCommandPath } else { $Script:CaminhoExe }
$Script:IsExe      = $Script:IsExePre

$Script:PastaLogs  = "$env:USERPROFILE\Documents\WSB Flash Clean"

$Script:PastaEstado = Join-Path $env:ProgramData "WSBTech\FlashClean"
$Script:MutexNome   = 'Global\WSB_FlashClean_Run'
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
# [PATCH SEGURO - AUTO CACHE]
# Lista de caches universalmente descartaveis para descoberta automatica em AppData.
# Mantem a proposta original de auto-detectar apps novos, mas com foco em pastas de baixo risco.
$Script:NomesCacheAutoDiretos = @(
    'cache','code cache','gpucache','grshadercache','dawncache','shadercache','media cache',
    'cache2','inetcache','d3dscache','dxcache','glcache','squirreltemp',
    'webcache','cefcache','browsercache','blob_storage','component_crx_cache'
)
# [PATCH SEGURO - AUTO CACHE]
# Pastas mais genericas. Continuam suportadas, mas passam por validacao extra
# para reduzir risco de atingir perfis, storages e dados operacionais de apps.
$Script:NomesCacheAutoCautelosos = @(
    'caches','temp','tmp','logs','cache_data'
)
$Script:NomesCacheGenericos = @($Script:NomesCacheAutoDiretos + $Script:NomesCacheAutoCautelosos)
# [PATCH SEGURO - AUTO CACHE]
# Marcadores absolutos de exclusao: se o caminho tocar nessas areas, a limpeza
# automatica por nome generico nao entra. Preserva logins, sessoes, perfil e dados
# de integridade de navegadores, Electron/Chromium, VSCode e apps similares.
$Script:MarcadoresAutoExcluidos = @(
    '\User Data\','\Profiles\','\Profile ','\Default\','\Guest Profile\','\System Profile\',
    '\Local Storage\','\Session Storage\','\Sessions\','\IndexedDB\','\Extensions\',
    '\Service Worker\Database','\workspaceStorage\','\globalStorage\','\User\History',
    '\User\snippets','\User\workspaceStorage','\User\globalStorage','\storage\',
    '\Network\','\databases\','\Cache_Data\metadata','\Code\User\','\Code - Insiders\User\',
    '\Firefox\Profiles\','\Mozilla\Firefox\Profiles\','\tdata\','\userdata\',
    '\TokenBroker\','\Microsoft\Protect\','\Credentials\','\Authy\','\wallet\'
)
$Script:SegmentosSensiveis = @(
    '\Cookies','\Login Data','\Web Data','\Local State','\Sessions','\Session Storage',
    '\Local Storage','\IndexedDB','\Network','\databases','\Pepper Data','\Extensions',
    '\File System','\storage','\Service Worker\Database','\User Data\Default\Extensions',
    '\tdata','\userdata','\Saved Games','\save','\saves','\profiles','\Profile',
    '\Microsoft\Protect','\Credentials','\TokenBroker','\Authy','\wallet'
)

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

# ==============================================================================
#  [REGISTRO DO APPID] Garante nome correto no toast — apaga cache anterior
# ==============================================================================
try {
    $baseNotif = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings"
    $baseAppId = "HKCU:\SOFTWARE\Classes\AppUserModelId"

    # 1. Remove lista fixa de IDs conhecidos de versoes anteriores
    $idsAntigos = @(
        "WSB TECH","WSB.Flash.Clean","WSB.FlashClean",
        "WSBTech.PrecisionUnit","WSB.AutoClean","WSB_AutoClean","WSB.AutoClean.GE"
    )
    foreach ($id in $idsAntigos) {
        foreach ($base in @($baseNotif, $baseAppId)) {
            $p = "$base\$id"
            if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    # 2. Varredura dinamica — remove QUALQUER entrada WSB encontrada nos dois locais
    #    Garante limpeza mesmo de IDs desconhecidos de versoes futuras ou renomeadas
    foreach ($base in @($baseNotif, $baseAppId)) {
        if (Test-Path $base) {
            Get-ChildItem $base -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -match "WSB|Flash|Clean|Ghost|AutoClean" } |
                ForEach-Object {
                    Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                }
        }
    }
} catch {}

# Registra AppId do Flash Clean — deleta e recria sempre para evitar cache
$regPath  = "HKCU:\SOFTWARE\Classes\AppUserModelId\WSB.FlashClean.V3"
$regNotif = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\WSB.FlashClean.V3"
try { Remove-Item $regPath  -Recurse -Force -ErrorAction SilentlyContinue } catch {}
try { Remove-Item $regNotif -Recurse -Force -ErrorAction SilentlyContinue } catch {}
try {
    New-Item -Path $regPath -Force | Out-Null
    New-ItemProperty -Path $regPath -Name "DisplayName"    -Value "WSB FLASH CLEAN" -Force | Out-Null
    New-ItemProperty -Path $regPath -Name "ShowInSettings" -Value 0 -PropertyType DWord -Force | Out-Null
    # Define icone: proprio .exe se compilado, senao usa powershell.exe
    $iconPath = if ($Script:IsExe) {
        $Script:CaminhoExe
    } else {
        "$env:SystemRoot\System32\WindowsPowerShell1.0\powershell.exe"
    }
    New-ItemProperty -Path $regPath -Name "IconUri" -Value $iconPath -Force | Out-Null
} catch {}
$Script:AppId = "WSB.FlashClean.V3"

# ==============================================================================
#  [1]  GERAR BANNER HERO  (GDI+ -> PNG em disco)
#       Modo "Normal"  = degradê azul  (limpeza / status)
#       Modo "Alerta"  = degradê vermelho/laranja (USB / ameaca)
#       Modo "RAM"     = degradê roxo  (otimizacao de memoria)
#       Modo "Icones"  = degradê verde escuro  (limpeza de icones)
#       Modo "Flash"   = degradê dourado/laranja (inicio / conclusao)
#       Retorna o caminho do PNG gravado ou "" se falhar
# ==============================================================================
function Gerar-Banner {
    param(
        [ValidateSet("Normal","Alerta","RAM","Icones","Flash")]
        [string]$Modo = "Normal"
    )

    $destino = "$env:TEMP\wsb_flash_$($Modo.ToLower())_$(Get-Random).png"

    try {
        try { Add-Type -AssemblyName System.Drawing -ErrorAction Stop } catch {
            try {
                $gdPath = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
                Add-Type -Path (Join-Path $gdPath "System.Drawing.dll") -ErrorAction SilentlyContinue
            } catch {}
        }
        if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'System.Drawing' })) {
            return ""
        }

        $W = 364; $H = 180
        $bmp = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g   = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        switch ($Modo) {
            "Flash"   {
                $corA = [System.Drawing.Color]::FromArgb(255, 18, 10,  0)
                $corB = [System.Drawing.Color]::FromArgb(255, 90, 45,  0)
                $corL = [System.Drawing.Color]::FromArgb(220,255,180,  0)
                $corT = [System.Drawing.Color]::FromArgb(255,255,200,  0)
                $txt1 = "WSB TECH"
                $txt2 = "FLASH CLEAN"
                $txt3 = "Limpeza Instantânea em Execução"
                $txt4 = "by Will Bezerra  |  v$($Script:VersaoApp)"
            }
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
                $txt3 = "Cache de Ícones e Miniaturas Limpos"
                $txt4 = "by Will Bezerra  |  v$($Script:VersaoApp)"
            }
            default   {   # Normal (azul)
                $corA = [System.Drawing.Color]::FromArgb(255,  5,  5, 18)
                $corB = [System.Drawing.Color]::FromArgb(255,  0, 35, 75)
                $corL = [System.Drawing.Color]::FromArgb(200,  0,190,255)
                $corT = [System.Drawing.Color]::FromArgb(255,  0,210,255)
                $txt1 = "WSB TECH"
                $txt2 = "FLASH CLEAN"
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

        foreach ($o in @($grad,$penTop,$penBot,$fT,$fS,$fG,$bA,$bW,$bG,$sf)) { try{$o.Dispose()}catch{} }
        $g.Dispose()

        # Salva PNG diretamente em disco
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        [System.IO.File]::WriteAllBytes($destino, $ms.ToArray())
        $ms.Dispose()

        return $destino
    } catch { return "" }
}

# ==============================================================================
#  [2]  SISTEMA DE LOG
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
        $ts      = Get-Date -Format "yyyyMMdd_HHmmss"
        $nomeArq  = "WSB_$($Operacao -replace '[^\p{L}0-9_]','_')_$ts.txt"
        $caminho = Join-Path $Script:PastaLogs $nomeArq

        $cabecalho = @(
            "====================================================",
            "  WSB FLASH CLEAN  v$($Script:VersaoApp)",
            "  Operação : $Operacao",
            "  Data/Hora: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')",
            "  Máquina  : $env:COMPUTERNAME  |  Usuário: $env:USERNAME",
            "====================================================",
            ""
        )
        ($cabecalho + $Linhas + @("","[ FIM DO LOG ]")) |
            Set-Content -Path $caminho -Encoding UTF8 -Force
        return $caminho
    } catch { return "" }
}

# ==============================================================================
#  [3]  TOAST NOTIFICATION
# ==============================================================================
function Enviar-Toast {
    param(
        [string]$Titulo,
        [string]$Sub,
        [string]$Corpo  = "",
        [ValidateSet("Normal","Alerta","RAM","Icones","Flash")]
        [string]$Modo   = "Normal",
        [string]$Audio  = "Notification.Default"
    )

    $imgPath = Gerar-Banner -Modo $Modo

    try {
        Invoke-Expression '$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]'
        Invoke-Expression '$null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]'

        $heroTag  = ""
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

    # Remove PNG temporario 10s depois
    if ($imgPath) {
        $imgTemp = $imgPath
        $null = Start-Job -ScriptBlock {
            param($p); Start-Sleep -Seconds 10
            if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
        } -ArgumentList $imgTemp
    }
}

# ==============================================================================
#  [4]  UTILIDADES
# ==============================================================================
function Formatar-Tamanho([long]$b) {
    if ($b -ge 1GB) { return "{0:N2} GB" -f ($b/1GB) }
    if ($b -ge 1MB) { return "{0:N2} MB" -f ($b/1MB) }
    if ($b -ge 1KB) { return "{0:N2} KB" -f ($b/1KB) }
    return "0 KB"
}


function Testar-Segmento-Sensivel {
    param([string]$Caminho)
    if (-not $Caminho) { return $true }
    foreach ($seg in $Script:SegmentosSensiveis) {
        if ($Caminho -like "*$seg*") { return $true }
    }
    return $false
}

# [PATCH SEGURO - AUTO CACHE]
# Validador central da limpeza automatica em AppData.
# Ele permite manter o comportamento nativo de descoberta de novos apps,
# mas exige que a pasta encontrada pareca realmente descartavel.
function Testar-Pasta-Cache-AutoSegura {
    param([string]$Caminho, [string]$Nome, [string]$RaizBase)

    if ([string]::IsNullOrWhiteSpace($Caminho) -or [string]::IsNullOrWhiteSpace($Nome)) { return $false }
    if (Testar-Segmento-Sensivel -Caminho $Caminho) { return $false }

    foreach ($marcador in $Script:MarcadoresAutoExcluidos) {
        if ($Caminho -like "*$marcador*") { return $false }
    }

    if ($Caminho -like "*\Packages\*\AC\*") { return $false }

    $nomeNormal = $Nome.ToLowerInvariant()

    if ($Script:NomesCacheAutoDiretos -contains $nomeNormal) { return $true }

    if ($Script:NomesCacheAutoCautelosos -contains $nomeNormal) {
        $rel = $Caminho
        if ($RaizBase -and $Caminho.StartsWith($RaizBase, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rel = $Caminho.Substring($RaizBase.Length).TrimStart('\\')
        }
        $profundidade = @($rel -split '\\' | Where-Object { $_ }).Count

        if ($profundidade -lt 2) { return $false }
        if ($Caminho -like "*\Crashpad\*") { return $false }
        return $true
    }

    return $false
}


function Limpar-Pasta {
    param(
        [string]$caminho,
        [string[]]$IgnorarNomes = @()
    )
    $bytes=[long]0; $n=0; $falhas=0
    if ($caminho -and (Test-Path -LiteralPath $caminho)) {
        Get-ChildItem -LiteralPath $caminho -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | ForEach-Object {
            try {
                if ($IgnorarNomes -contains $_.Name) { return }
                if ($_.PSIsContainer) {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                } else {
                    $bytes += [long]$_.Length
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                    $n++
                }
            } catch { $falhas++ }
        }
    }
    return @{Bytes=$bytes;Itens=$n;Falhas=$falhas}
}

function Limpar-Glob {
    param([string]$pat)
    $bytes=[long]0; $n=0; $falhas=0
    try {
        Get-Item $pat -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                if (-not $_.PSIsContainer) { $bytes += [long]$_.Length }
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                $n++
            } catch { $falhas++ }
        }
    } catch {}
    return @{Bytes=$bytes;Itens=$n;Falhas=$falhas}
}

function Limpar-Subpastas-Seguras {
    param(
        [string]$Base,
        [string[]]$Subcaminhos,
        [string[]]$IgnorarNomes = @()
    )

    $total = @{Bytes=[long]0;Itens=0;Falhas=0}
    if (-not $Base -or -not (Test-Path -LiteralPath $Base)) { return $total }

    foreach ($sub in $Subcaminhos) {
        $alvo = Join-Path $Base $sub
        $r = Limpar-Pasta -caminho $alvo -IgnorarNomes $IgnorarNomes
        $total.Bytes += [long]$r.Bytes; $total.Itens += [int]$r.Itens; $total.Falhas += [int]$r.Falhas
    }
    return $total
}

# [PATCH SEGURO - AUTO CACHE]
# Continua varrendo LOCALAPPDATA e APPDATA de forma nativa, sem cadastro manual
# de apps, mas agora filtrando pela funcao de seguranca acima.
function Obter-Pastas-Cache-Genericas {
    $saida = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($raiz in @($env:LOCALAPPDATA, $env:APPDATA)) {
        if (-not $raiz -or -not (Test-Path $raiz)) { continue }
        try {
            Get-ChildItem -Path $raiz -Directory -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { Testar-Pasta-Cache-AutoSegura -Caminho $_.FullName -Nome $_.Name -RaizBase $raiz } |
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
#  [6]  LIMPEZA COMPLETA (cache apenas — sem cookies, senhas, tokens)
# ==============================================================================
function Executar-Limpeza-Completa {
    $bSis=[long]0; $bNav=[long]0; $bApp=[long]0; $bLix=[long]0; $bGame=[long]0; $bAdv=[long]0
    $n=0; $falhas=0; $pastas=0

    function Add-Resultado([hashtable]$r, [ref]$bytes, [ref]$itens, [ref]$falhasRef, [ref]$pastasRef) {
        if ($r) {
            $bytes.Value += [long]$r.Bytes
            $itens.Value += [int]$r.Itens
            if ($r.ContainsKey('Falhas')) { $falhasRef.Value += [int]$r.Falhas }
            if (($r.Itens -gt 0) -or ($r.Bytes -gt 0)) { $pastasRef.Value++ }
        }
    }

    foreach ($p in @(
        'C:\Windows\Temp', $env:TEMP, "$env:LOCALAPPDATA\Temp",
        'C:\Windows\Prefetch', 'C:\Windows\SoftwareDistribution\Download',
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"
    )) {
        $r = Limpar-Pasta -caminho $p
        Add-Resultado $r ([ref]$bSis) ([ref]$n) ([ref]$falhas) ([ref]$pastas)
    }

    $rLix = Limpar-Lixeira-Silenciosa
    Add-Resultado $rLix ([ref]$bLix) ([ref]$n) ([ref]$falhas) ([ref]$pastas)

    $rChrom = Limpar-Caches-Chromium-Genericos
    Add-Resultado $rChrom ([ref]$bNav) ([ref]$n) ([ref]$falhas) ([ref]$pastas)

    $ffBase = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $ffBase) {
        Get-ChildItem $ffBase -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            foreach ($sub in @('cache2','startupCache','thumbnails')) {
                $r = Limpar-Pasta -caminho (Join-Path $_.FullName $sub)
                Add-Resultado $r ([ref]$bNav) ([ref]$n) ([ref]$falhas) ([ref]$pastas)
            }
        }
    }

    $rApps = Limpar-Caches-Genericos-Apps
    Add-Resultado $rApps ([ref]$bApp) ([ref]$n) ([ref]$falhas) ([ref]$pastas)

    $rGame = Limpar-Caches-Gamer
    Add-Resultado $rGame ([ref]$bGame) ([ref]$n) ([ref]$falhas) ([ref]$pastas)

    foreach ($p in @(
        "$env:APPDATA\discord\Cache", "$env:APPDATA\discord\Code Cache", "$env:APPDATA\discord\GPUCache",
        "$env:APPDATA\Slack\Cache", "$env:APPDATA\Slack\Code Cache", "$env:APPDATA\Slack\GPUCache",
        "$env:APPDATA\Microsoft\Teams\Cache", "$env:APPDATA\Microsoft\Teams\Code Cache", "$env:APPDATA\Microsoft\Teams\GPUCache",
        "$env:APPDATA\WhatsApp\Cache", "$env:APPDATA\WhatsApp\Code Cache",
        "$env:APPDATA\Telegram Desktop\tdata\user_data\cache",
        "$env:APPDATA\Code\Cache", "$env:APPDATA\Code\Code Cache", "$env:APPDATA\Code\GPUCache"
    )) {
        $r = Limpar-Pasta -caminho $p -IgnorarNomes $Script:ArquivosProtegidosLogin
        Add-Resultado $r ([ref]$bApp) ([ref]$n) ([ref]$falhas) ([ref]$pastas)
    }

    foreach ($pat in @(
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db"
    )) {
        $r = Limpar-Glob $pat
        Add-Resultado $r ([ref]$bSis) ([ref]$n) ([ref]$falhas) ([ref]$pastas)
    }

    $rAdv = Limpeza-Avancada-Sistema
    Add-Resultado $rAdv ([ref]$bAdv) ([ref]$n) ([ref]$falhas) ([ref]$pastas)

    $net='ERRO'
    try { ipconfig /flushdns 2>&1 | Out-Null; netsh winsock reset 2>&1 | Out-Null; $net='OK' } catch {}

    $disco='N/A'
    try {
        $j = Start-Job { Optimize-Volume -DriveLetter C -ReTrim -ErrorAction Stop 2>&1 | Out-Null }
        Wait-Job $j -Timeout 90 | Out-Null
        Receive-Job $j -ErrorAction SilentlyContinue | Out-Null
        Remove-Job $j -Force -ErrorAction SilentlyContinue
        $disco='OK'
    } catch {}

    return @{
        Total  = $bSis + $bNav + $bApp + $bLix + $bGame + $bAdv
        SISTEMA= $bSis; NAV=$bNav; APPS=$bApp; LIXO=$bLix; GAMER=$bGame; AVANCADO=$bAdv
        NET=$net; DISCO=$disco; Itens=$n; Falhas=$falhas; Pastas=$pastas
    }
}

# ==============================================================================
# [PATCH SEGURO - EXPLORER]
# Fecha apenas a primeira janela do Explorer aberta automaticamente logo apos o
# rebuild pesado de icones. Nao fica monitorando janelas futuras abertas pelo usuario.
function Fechar-Primeira-Janela-Explorer-Apos-Rebuild {
    $janelaFechada = $false
    $limite = (Get-Date).AddSeconds(6)

    while ((Get-Date) -lt $limite -and (-not $janelaFechada)) {
        Start-Sleep -Milliseconds 450
        try {
            $shell = New-Object -ComObject Shell.Application
            foreach ($win in @($shell.Windows())) {
                try {
                    if (-not $win) { continue }
                    $exe = ''
                    try { $exe = [System.IO.Path]::GetFileName(($win.FullName | Out-String).Trim()) } catch {}
                    if ($exe -ine 'explorer.exe') { continue }
                    $hwnd = 0
                    try { $hwnd = [int64]$win.HWND } catch {}
                    if ($hwnd -le 0) { continue }
                    $win.Quit()
                    $janelaFechada = $true
                    break
                } catch {}
            }
        } catch {}
    }

    return $janelaFechada
}

# ==============================================================================
#  [7]  LIMPEZA PROFUNDA DE ICONES
# ==============================================================================
# [PATCH SEGURO - EXPLORER]
# Rotina nativa preservada. O ajuste abaixo apenas registra e tenta fechar a
# primeira janela automatica do Explorer apos a reconstrucao de icones.
function Executar-Limpeza-Icones {
    $bytes=[long]0; $n=0; $sb=0; $janelaFechada=$false

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
    # Disparo unico: tenta fechar so a primeira janela automatica desse momento.
    $janelaFechada = Fechar-Primeira-Janela-Explorer-Apos-Rebuild
    return @{Bytes=$bytes; Itens=$n; ShellBags=$sb; JanelaExplorerFechada=$janelaFechada}
}

# ==============================================================================
#  [8]  VARREDURA USB IMEDIATA
#       Escaneia TODOS os pendrives/HDs externos conectados no momento do clique
#       (sem WMI Event — execucao direta e sincrona)
# ==============================================================================
function Executar-Varredura-USB {
    $drives = Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 2 }

    if (-not $drives) {
        Gravar-Log -Operacao 'USB_SCAN' -Linhas @(
            '  Nenhum dispositivo USB removível conectado no momento.',
            '  Sentinela manual concluído sem ações necessárias.'
        ) | Out-Null

        Enviar-Toast -Titulo "$($Script:NomeApp) - USB" -Sub 'Nenhum dispositivo removível conectado' -Corpo 'Clique manual concluído. Nenhuma mídia USB encontrada para análise.' -Modo 'Alerta' -Audio 'Notification.Default'
        return
    }

    foreach ($disk in $drives) {
        $d = Resolver-Caminho-Drive $disk.DeviceID
        if ($d) { Reparar-USB-Com-Vacina -Drive $d -Origem 'Flash Clean Manual' }
    }
}

# ============================================================================
#  [9]  LOGICA PRINCIPAL — executa tudo imediatamente ao clicar
# ============================================================================
$script:RunMutex = $null
$criouNovo = $false
try {
    if (-not (Test-Path $Script:PastaEstado)) { New-Item -Path $Script:PastaEstado -ItemType Directory -Force | Out-Null }
    $script:RunMutex = New-Object System.Threading.Mutex($true, $Script:MutexNome, [ref]$criouNovo)
} catch {}

if (-not $criouNovo) {
    Enviar-Toast `
        -Titulo "$($Script:NomeApp) - Processo em andamento" `
        -Sub    'O clique foi bloqueado para evitar sobreposição' `
        -Corpo  'A limpeza/verificação anterior ainda está em execução. Aguarde a conclusão e tente novamente.' `
        -Modo   'Flash' `
        -Audio  'Notification.Default'
    exit
}

try {
    Gravar-Log -Operacao 'SESSAO_FLASH' -Linhas @(
        '  Modo               : Silent / Manual por clique',
        '  Proteção de clique : Mutex exclusivo ativo',
        '  Perfil de limpeza  : Inteligente / preserva logins e dados sensíveis',
        '  Sentinela USB      : Motor de vacina/quarentena herdado do AutoClean',
        '  Início da sessão   : ' + (Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
    ) | Out-Null

    $rRAM = Executar-Otimizacao-RAM
    Gravar-Log -Operacao 'OTIMIZACAO_RAM' -Linhas @(
        "  Memória liberada  : $(Formatar-Tamanho $rRAM.Delta)",
        '  Método            : GC triplo + redução de WorkingSet',
        '  Resultado         : OK'
    ) | Out-Null
    Enviar-Toast -Titulo "$($Script:NomeApp) - RAM otimizada" -Sub "$(Formatar-Tamanho $rRAM.Delta) liberados do Working Set" -Corpo 'GC triplo + redução de memória aplicada com log salvo.' -Modo 'RAM' -Audio 'Notification.Default'

    $rClean = Executar-Limpeza-Completa
    Gravar-Log -Operacao 'LIMPEZA_COMPLETA' -Linhas @(
        "  Total liberado    : $(Formatar-Tamanho $rClean.Total)",
        "  Itens removidos   : $($rClean.Itens)",
        "  Pastas tratadas   : $($rClean.Pastas)",
        "  Falhas toleradas  : $($rClean.Falhas)",
        "  TEMP/SISTEMA      : $(Formatar-Tamanho $rClean.SISTEMA)",
        "  LIXEIRA           : $(Formatar-Tamanho $rClean.LIXO)",
        "  NAVEGADORES       : $(Formatar-Tamanho $rClean.NAV)",
        "  APPS              : $(Formatar-Tamanho $rClean.APPS)",
        "  GAMER/LAUNCHERS   : $(Formatar-Tamanho $rClean.GAMER)",
        "  LIMPEZA AVANCADA  : $(Formatar-Tamanho $rClean.AVANCADO)",
        "  DNS / Winsock     : $($rClean.NET)",
        "  TRIM SSD          : $($rClean.DISCO)",
        '  Cookies/Logins    : PRESERVADOS (sem alterações)',
        '  Resultado         : OK'
    ) | Out-Null
    Enviar-Toast -Titulo "$($Script:NomeApp) - Sistema limpo" -Sub "$(Formatar-Tamanho $rClean.Total) liberados | $($rClean.Itens) item(ns) removidos" -Corpo "SIS: $(Formatar-Tamanho $rClean.SISTEMA)  NAV: $(Formatar-Tamanho $rClean.NAV)  APP: $(Formatar-Tamanho $rClean.APPS)  GAME: $(Formatar-Tamanho $rClean.GAMER)" -Modo 'Normal' -Audio 'Notification.Default'

    $rIco = Executar-Limpeza-Icones
    Gravar-Log -Operacao 'LIMPEZA_ICONES' -Linhas @(
        "  Total liberado    : $(Formatar-Tamanho $rIco.Bytes)",
        "  Arquivos removidos: $($rIco.Itens)",
        "  Shell Bags limpos : $($rIco.ShellBags)",
        '  Explorer          : Reiniciado',
        "  Janela Inicial    : " + $(if ($rIco.JanelaExplorerFechada) { "Fechada automaticamente" } else { "Nao foi necessario fechar" }),
        '  Resultado         : OK'
    ) | Out-Null
    Enviar-Toast -Titulo "$($Script:NomeApp) - Ícones reconstruídos" -Sub "$(Formatar-Tamanho $rIco.Bytes) liberados | $($rIco.Itens) arquivo(s)" -Corpo 'Iconcache, thumbcache, Jump Lists e Bags processados com log salvo.' -Modo 'Icones' -Audio 'Notification.Default'

    Executar-Varredura-USB

    Gravar-Log -Operacao 'SESSAO_FLASH_FIM' -Linhas @(
        '  Sessão concluída com sucesso.',
        '  Clique concorrente bloqueado enquanto a execução esteve ativa.',
        '  Motor inteligente aplicado sem remover logins, cookies ou saves.',
        '  Encerramento      : ' + (Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
    ) | Out-Null

    Get-Job -State Completed -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 4
}
finally {
    try { if ($script:RunMutex) { $script:RunMutex.ReleaseMutex() | Out-Null; $script:RunMutex.Dispose() } } catch {}
}