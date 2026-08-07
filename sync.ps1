<#
    sync.ps1 — مزامنة قاعدة «فن السرد القصصي» من الفولت إلى موقعها المشفَّر

    الاستعمال:
      .\sync.ps1                     نسخ المحتوى وتحضيره فقط
      .\sync.ps1 -Serve              نسخ ثم معاينة محلية على http://localhost:8080
      .\sync.ps1 -Push               نسخ ثم بناء ثم نشر — الموقع والفولت معًا
      .\sync.ps1 -Push -SiteOnly     الموقع وحده، للإصلاحات الخاصّة بالنشر

    المستودعات:
      D:\Obsidian_Vault        →  obsidian-vault      (خاص · الفولت كاملًا)
      D:\quartz-storytelling   →  Storytelling_Notes  (عام  · الإعداد وحده)
      فرع gh-pages فيه         →  الناتج المشفَّر، وهو ما يخدمه GitHub Pages

    ══ وفيم يفارق هذا السكربت نظيره في D:\quartz-site؟ ══════════════════
    مادّة هذه القاعدة شرحٌ موسَّع لمنتج تجاري مدفوع (Storyteller Tactics —
    Pip Decks): فيها نصّ البطاقات وصورها السبعون. فالنشر هنا **منشور غير
    علنيّ**: يُقرأ بكلمة مرور. وثلاثة أشياء تجتمع ليصحّ ذلك، وسقوط واحدٍ
    منها يُبطل الثلاثة:

      ١. إضافة encrypted-pages تشفّر متن كل صفحة بـAES-256-GCM عند البناء.
      ٢. content/ لا تُثبَّت (‎.gitignore‎)، وإلا قُرئ النصّ الخام في المستودع
         العام بجوار الناتج المشفَّر — فلا معنى للتشفير.
      ٣. الصور تُدمج data: URI في المتن (tools/prepare-content.py)، وإلا
         نُسخت ملفّاتها إلى public/ وجُلبت برابطها المباشر.

    ولأنّ content/ غير مثبَّتة، لا يستطيع GitHub أن يبني — فالبناء محليّ،
    والمدفوع هو الناتج وحده إلى فرع gh-pages. (‎.github/NO-CI.md‎)

    وبوّابةٌ رابعة تقيس الناتج نفسه بعد البناء: tools/verify-encrypted.py
    تنتزع من كل ملاحظة جملًا مميّزة وتفحش بها ناتج البناء كلّه. فإن ظهرت
    واحدة، أُوقف النشر — لأنّ الوقوف هنا مجّاني، وما بلغ المستودع العام
    يبقى في تاريخه ولو حُذف بعد دقيقة. (CLAUDE.md 16/هـ)
#>
param(
    [switch]$Serve,
    [switch]$Push,
    [switch]$SiteOnly,
    [string]$Message = "sync: تحديث المحتوى من الفولت"
)

$ErrorActionPreference = "Stop"

$Vault    = "D:\Obsidian_Vault"
$Source   = Join-Path $Vault "Storytelling"
$Attach   = Join-Path $Source "attachments"
$Site     = "D:\quartz-storytelling"
$Content  = Join-Path $Site "content"
$Extra    = Join-Path $Site "site-files"
$Public   = Join-Path $Site "public"
$Tools    = Join-Path $Site "tools"
$Secret   = Join-Path $Site ".secrets\page-password.txt"
$Audit    = Join-Path $Vault ".claude\skills\vault-audit\scripts\audit.py"

# شجرة عملٍ لفرع gh-pages، وموضعها خارج مجلد الموقع عمدًا: لو كانت داخله
# لطالتها المطابقة والتنسيق وفحوص الإعداد، وهي ليست من الإعداد.
$PagesTree = "D:\quartz-storytelling-pages"

if (-not (Test-Path -LiteralPath $Source)) { throw "مجلد المصدر غير موجود: $Source" }

# ── 1. مطابقة content/ بمجلد المصدر ───────────────────────────────
# المرفقات مستثناة: تُقرأ في الخطوة 3 وتُدمج في المتن، ولا يُنسخ منها ملفّ.
# والقوالب مستثناة أيضًا: Quartz يتجاهلها بـignorePatterns فلا تُنشر، لكنها
# تحمل صورًا نائبة (`card-slug.jpeg`) لا وجود لها — فتُسقط بوّابة الإدماج
# نشرًا سليمًا. فإخراجها من المصدر أصحّ من إعفائها في البوّابة.
Write-Host "→ نسخ المحتوى من الفولت..." -ForegroundColor Cyan
robocopy $Source $Content /MIR /XD $Attach /XF "_*Template*" /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "فشل robocopy برمز $LASTEXITCODE" }
$global:LASTEXITCODE = 0

# ── 2. ملفات تخصّ الموقع لا الفولت ────────────────────────────────
# تُنسخ بعد المطابقة لأن /MIR كان سيحذفها. وفيها صفحة الهبوط العلنية.
if (Test-Path -LiteralPath $Extra) {
    Copy-Item -Path (Join-Path $Extra '*') -Destination $Content -Recurse -Force
}

# ── 3. التحضير: حقن كلمة المرور وإدماج الصور ──────────────────────
Write-Host "→ تحضير المحتوى (تشفير وإدماج الصور)..." -ForegroundColor Cyan
python (Join-Path $Tools "prepare-content.py") `
    --content $Content --attachments $Attach --password-file $Secret --public index.md
if ($LASTEXITCODE -ne 0) { throw "فشل تحضير المحتوى — لم يُبنَ شيء" }

$Count = (Get-ChildItem -LiteralPath $Content -Recurse -Filter *.md -File | Measure-Object).Count
Write-Host "✓ $Count ملاحظة في content/" -ForegroundColor Green

# ── 4. المعاينة أو النشر ──────────────────────────────────────────

function Publish-Repo {
    <#
        يثبّت ما لم يُثبَّت، ثم يدفع إن كان المستودع متقدّمًا على البعيد.

        والحكم لـ rev-list لا لـ status: قياس الحاجة إلى الدفع بوجود تغييرات
        غير مثبَّتة يترك التثبيتات القديمة غير مدفوعة إلى الأبد.
    #>
    param([string]$Name, [switch]$Fatal)

    git add -A
    if (git status --porcelain) { git commit -m $Message | Out-Null }

    $tracked = (git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $tracked) {
        throw "${Name}: الفرع بلا مرجع بعيد متتبَّع، فلا يُعرف كم تقدّم. أصلحه بـ: git branch --set-upstream-to=origin/main main"
    }

    $ahead = [int](git rev-list --count "$tracked..HEAD")
    if ($ahead -eq 0) {
        Write-Host "${Name}: لا شيء يُدفع" -ForegroundColor Yellow
        return
    }

    git push
    if ($LASTEXITCODE -ne 0) {
        if ($Fatal) { throw "فشل دفع $Name — أُوقف كل شيء قبل أن يتقدّم مستودع على الآخر" }
        Write-Host "✗ فشل دفع $Name" -ForegroundColor Red
        return
    }
    Write-Host "✓ دُفع $Name ($ahead تثبيتًا)" -ForegroundColor Green
}

function Publish-Pages {
    <#
        يدفع ناتج البناء وحده إلى فرع gh-pages عبر شجرة عملٍ منفصلة.

        وعلّة الشجرة المنفصلة أنّ public/ مُدرَجة في .gitignore على main —
        فلا تُثبَّت هناك أصلًا. والفرعان لا يتلاقيان: main يحمل الإعداد،
        وgh-pages يحمل الناتج المشفَّر، ولا تاريخ مشترك بينهما.
    #>
    param([string]$BuildDir, [string]$TreeDir)

    if (-not (Test-Path -LiteralPath (Join-Path $BuildDir "index.html"))) {
        throw "لا ناتج بناء في $BuildDir — أُوقف النشر"
    }

    if (-not (Test-Path -LiteralPath $TreeDir)) {
        git show-ref --verify --quiet refs/heads/gh-pages
        $hasLocal = ($LASTEXITCODE -eq 0)
        $global:LASTEXITCODE = 0

        if ($hasLocal) {
            git worktree add $TreeDir gh-pages
        } else {
            git ls-remote --exit-code --heads origin gh-pages 2>$null | Out-Null
            $hasRemote = ($LASTEXITCODE -eq 0)
            $global:LASTEXITCODE = 0
            if ($hasRemote) {
                git fetch origin gh-pages:gh-pages
                git worktree add $TreeDir gh-pages
            } else {
                Write-Host "  فرع gh-pages لا وجود له — يُنشأ فرعًا بلا أصل" -ForegroundColor DarkGray
                git worktree add --orphan -b gh-pages $TreeDir
            }
        }
        if ($LASTEXITCODE -ne 0) { throw "تعذّر تهيئة شجرة عمل gh-pages" }
    }

    # ‎/XF .git‎ لازم: في شجرة العمل يكون ‎.git‎ ملفًّا لا مجلدًا، و/MIR كان
    # سيحذفه بوصفه زائدًا عن المصدر — فتنقطع الشجرة عن مستودعها.
    robocopy $BuildDir $TreeDir /MIR /XF ".git" /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "فشل نسخ الناتج إلى شجرة gh-pages برمز $LASTEXITCODE" }
    $global:LASTEXITCODE = 0

    # يمنع Jekyll من التصرّف في الناتج — وهو يتجاهل كل ما يبدأ بشرطة سفلية.
    Set-Content -Path (Join-Path $TreeDir ".nojekyll") -Value "" -NoNewline -Encoding utf8

    Push-Location $TreeDir
    try {
        git add -A
        if (git status --porcelain) {
            git commit -m "$Message (ناتج مشفَّر)" | Out-Null
        } else {
            Write-Host "gh-pages: لا شيء يُدفع" -ForegroundColor Yellow
            return
        }
        git push -u origin gh-pages
        if ($LASTEXITCODE -ne 0) { throw "فشل دفع gh-pages" }
        Write-Host "✓ دُفع الناتج المشفَّر إلى gh-pages" -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

Set-Location $Site

# من هنا تُستدعى أوامر خارجية (npx و git و python)، وكلها تكتب إشعاراتها
# الاعتيادية إلى stderr. ومع ErrorActionPreference = Stop تعامل PowerShell ذلك
# فشلًا فتُجهض السكربت. فيُرخى الضبط، ويُعتمد على $LASTEXITCODE صراحةً.
$ErrorActionPreference = "Continue"

if ($Serve) {
    Write-Host "→ معاينة على http://localhost:8080 (Ctrl+C للإيقاف)" -ForegroundColor Cyan
    Write-Host "  الصفحات مشفَّرة هنا أيضًا — تُفتح بكلمة المرور نفسها" -ForegroundColor DarkGray
    npx quartz build --serve
    return
}

if ($Push) {
    # ── بوّابة الخصوصية ───────────────────────────────────────────
    Write-Host "→ فحص الخصوصية (مسارات بيئة التطوير)..." -ForegroundColor Cyan
    python $Audit --root $Content --only paths
    if ($LASTEXITCODE -ne 0) {
        throw "مسار بيئة تطوير في المحتوى — أُوقف النشر قبل أن يصير في تاريخ المستودع العام"
    }

    # ── بوّابة الترتيب ────────────────────────────────────────────
    # الوسيط الفارغ يُكتب `--glossary=` رمزًا واحدًا: فـPowerShell 5.1 يُسقط
    # `""` قبل أن يصل إلى العملية، فيقرأ argparse خيارًا بلا قيمة ويخرج بخطأ
    # استعمال — فتقرؤه البوّابة «ترتيبًا مكسورًا» وتوقف نشرًا سليمًا.
    Write-Host "→ فحص ترتيب الملفات..." -ForegroundColor Cyan
    python $Audit --root $Content --only ordering --glossary=
    if ($LASTEXITCODE -ne 0) {
        throw "ترتيب مكسور في المحتوى — أُوقف النشر قبل أن يُقرأ الفصل السابع قبل السادس"
    }

    # يُبنى قبل الدفع عمدًا: فشل البناء محليًّا أرخص من نشرة مكسورة
    Write-Host "→ بناء الموقع..." -ForegroundColor Cyan
    npx quartz build
    if ($LASTEXITCODE -ne 0) { throw "فشل البناء — لم يُدفع شيء" }

    Write-Host "→ فحص التخصيصات..." -ForegroundColor Cyan
    & (Join-Path $Site "check-custom.ps1") -Quiet
    if ($LASTEXITCODE -ne 0) { throw "سقط تخصيص — أُوقف النشر. شغّل .\check-custom.ps1 للتفصيل" }
    Write-Host "✓ التخصيصات قائمة" -ForegroundColor Green

    # ── بوّابة الحجب: تُقاس على الناتج لا على الإعداد ─────────────
    Write-Host "→ فحص الحجب (طعمٌ في الناتج المبنيّ)..." -ForegroundColor Cyan
    python (Join-Path $Tools "verify-encrypted.py") `
        --content $Content --public $Public --attachments $Attach --exclude index.md
    if ($LASTEXITCODE -ne 0) {
        throw "نصٌّ صريح أو صورة مكشوفة في الناتج — أُوقف النشر. وهذا ما لا يُصلحه حذفٌ بعد الدفع"
    }

    Publish-Pages -BuildDir $Public -TreeDir $PagesTree
    Set-Location $Site
    Publish-Repo -Name "إعداد الموقع" -Fatal
    Write-Host "  تُحدَّث النشرة على GitHub خلال دقيقة أو دقيقتين" -ForegroundColor DarkGray

    # ── 5. الفولت الخاص ───────────────────────────────────────────
    # الأصل أن يُدفع معه، فمصدر المحتوى هو الفولت لا content/.
    Set-Location $Vault
    if ($SiteOnly) {
        $pending = (git status --porcelain | Measure-Object).Count
        Set-Location $Site
        if ($pending -gt 0) {
            Write-Host "تنبيه: في الفولت الخاص $pending تغييرًا لم يُدفع (تخطّيته بـ -SiteOnly)." -ForegroundColor Yellow
        }
    } else {
        Publish-Repo -Name "الفولت الخاص"
        Set-Location $Site
    }
}
