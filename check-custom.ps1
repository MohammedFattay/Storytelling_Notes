<#
    check-custom.ps1 — يتحقّق أنّ تخصيصات هذا المستودع ما تزال قائمة.

    علّته: هذا المستودع فرعٌ من Quartz، وكلّ سحبٍ من upstream قد يعيد ملفًّا إلى
    أصله فيُلغي تخصيصًا صامتًا — يبني الموقع بنجاح، ويخرج مكسورًا. فالتوثيق في
    README يقول ماذا غُيِّر، وهذا السكربت يقول ما إذا كان التغيير ما يزال قائمًا.

    شغّله: بعد كل `git merge upstream/v5`، وقبل كلّ دفع.
        .\check-custom.ps1
    ويخرج بالرمز 1 إن سقط شيء، فيصلح للاستعمال في سيور العمل.
#>
param([switch]$Quiet)

$ErrorActionPreference = "Stop"
$Root  = $PSScriptRoot
$Fails = New-Object System.Collections.ArrayList
$Pass  = 0

function Test-Rule {
    param(
        [Parameter(Mandatory)][string]$Name,     # ما يُفحص
        [Parameter(Mandatory)][string]$File,     # الملف، بمسار نسبيّ
        [Parameter(Mandatory)][string]$Pattern,  # النمط
        [Parameter(Mandatory)][string]$Why,      # ماذا ينكسر إن ضاع
        [switch]$Literal,                        # النمط نصّ حرفيّ لا تعبير نمطيّ
        [switch]$Absent                          # النمط يجب ألّا يوجد
    )
    $path = Join-Path $Root $File
    if (-not (Test-Path $path)) {
        [void]$Fails.Add([pscustomobject]@{ Name = $Name; File = $File; Why = "الملف نفسه مفقود" })
        return
    }
    $text = Get-Content $path -Raw -Encoding UTF8
    $rx   = if ($Literal) { [regex]::Escape($Pattern) } else { $Pattern }
    $hit  = $text -match $rx
    $ok   = if ($Absent) { -not $hit } else { $hit }

    if ($ok) {
        $script:Pass++
        if (-not $Quiet) { Write-Host ("  ✓ " + $Name) -ForegroundColor DarkGray }
    } else {
        [void]$Fails.Add([pscustomobject]@{ Name = $Name; File = $File; Why = $Why })
    }
}

Write-Host "`n=== فحص تخصيصات المستودع ===" -ForegroundColor Cyan

# ─── الإعداد: العربية والنشر ───────────────────────────────────────────────
Test-Rule -Name "locale: ar-SA" -File "quartz.config.yaml" `
    -Pattern 'locale:\s*ar-SA' `
    -Why "بدونه يخرج <html lang=`"en`"> بلا dir=rtl، فتُقلب الصفحة كلّها"

Test-Rule -Name "analytics معطّلة" -File "quartz.config.yaml" `
    -Pattern 'analytics:\s*null' `
    -Why "تفعيلها يرسل بيانات الزوّار إلى طرف ثالث — قرار خصوصية لا إعداد"

Test-Rule -Name "خطوط عربية في إضافة quartz-fonts" -File "quartz.config.yaml" `
    -Pattern '(?s)quartz-fonts.{0,500}?header:\s*Tajawal' `
    -Why "الإضافة لا تقرأ theme.typography؛ وتركها فارغةً يُعيد خطوطًا بلا حروف عربية"

Test-Rule -Name "خطوط عربية في theme.typography" -File "quartz.config.yaml" `
    -Pattern '(?s)typography:.{0,300}?IBM Plex Sans Arabic' `
    -Why "الموضع الثاني للخطوط — يُضبط الاثنان معًا أو يظهر خطّان متنافسان"

Test-Rule -Name "استثناء ملفات القوالب" -File "quartz.config.yaml" `
    -Pattern '\*\*/_\*Template\*' -Literal:$false `
    -Why "بدونه تُنشر القوالب؛ وبنمط أوسع (**/_*) يسقط محتوى حقيقي يبدأ بشرطة سفلية"

Test-Rule -Name "ترتيب الشجر بالسلاج لا بالعنوان" -File "quartz.config.yaml" `
    -Pattern '(?s)explorer.{0,600}?sortFn:.{0,300}?slugSegment' `
    -Why "بدونه يعود الفرز إلى العنوان، فيسبق «الجزء السابع» «السادسَ» أبجديًّا"

Test-Rule -Name "إضافة excalidraw معطّلة" -File "quartz.config.yaml" `
    -Pattern '(?s)excalidraw.{0,200}?enabled:\s*false' `
    -Why "حزمتها غير منشورة على npm، فتفعيلها يُنذر في كلّ بناء بلا فائدة"

# ─── الأنماط: إصلاح Mermaid والعربية ──────────────────────────────────────
Test-Rule -Name "تثبيت --color-accent-1/2 (إصلاح Mermaid)" -File "quartz/styles/custom.scss" `
    -Pattern '--color-accent-1:\s*hsl\(\s*\d' `
    -Why "ثيم Quartz يعرّفهما بـ hsl(calc(…))، ومحلّل ألوان Mermaid يرفضها فتسقط المخططات كلّها"

Test-Rule -Name "عزل الاتجاه في الكود والمعادلات" -File "quartz/styles/custom.scss" `
    -Pattern 'unicode-bidi:\s*isolate' `
    -Why "بدونه تنقلب أسطر الكود والمعادلات داخل صفحة RTL"

# ─── التمثيل التفاعلي: نسخة الإضافة المرقَّعة ─────────────────────────────
# تفصيل الرقعات في plugins/graph/PATCHES.md
Test-Rule -Name "إضافة graph تشير إلى النسخة المحلّية" -File "package.json" `
    -Pattern '"@quartz-community/graph":\s*"file:\./plugins/graph"' `
    -Why "بالعودة إلى نسخة npm يعود العطل الأصلي: نقطة واحدة في كلّ صفحة عربية"

Test-Rule -Name "رقعة فكّ ترميز المسار" -File "plugins/graph/dist/index.js" `
    -Pattern 'decodeURIComponent' `
    -Why "بدونها لا يطابق سلاجُ الصفحة المرمَّز مفاتيحَ contentIndex العربية، فلا جيران"

Test-Rule -Name "رقعة لون الوصلات" -File "plugins/graph/dist/index.js" `
    -Pattern '--graph-link' `
    -Why "بدونها تُرسم الوصلات بلون خلفية الثيم (تباين 1.04:1) فلا تُرى واحدة منها"

Test-Rule -Name "رقعة حدّ العقد في المخطّط المحلّي" -File "plugins/graph/dist/index.js" `
    -Pattern 'ru\.size>90' `
    -Why "بدونها تخرج الصفحتان الفهرسيّتان (٦٦٨ و٤٥٠ جارًا) مستطيلًا أسود"

Test-Rule -Name "تعريف --graph-link" -File "quartz/styles/custom.scss" `
    -Pattern '--graph-link:\s*#' `
    -Why "الرقعة تقرؤه، فإن غاب عادت الوصلات إلى لون الخلفية"

# ─── سلسلة الأدوات ────────────────────────────────────────────────────────
Test-Rule -Name "moduleResolution: bundler" -File "tsconfig.json" `
    -Pattern '"moduleResolution":\s*"bundler"' `
    -Why "`"node`" (=node10) مهجورة وتتوقّف في TypeScript 7 — يعود تحذير الهجران"

Test-Rule -Name "تعيين micromorph في paths" -File "tsconfig.json" `
    -Pattern 'micromorph' `
    -Why "خريطة exports لا تعلن index.d.ts، فيفشل tsc بعد الترحيل إلى bundler"

Test-Rule -Name "تعيين remark-parse/lib في paths" -File "tsconfig.json" `
    -Pattern 'remark-parse/lib' `
    -Why "استيراد عميق غير معلَن في exports — يفشل tsc بدونه"

Test-Rule -Name "سكربت precheck" -File "package.json" `
    -Pattern '"precheck"' `
    -Why ".quartz/plugins وحدة مولَّدة ومستثناة من git، فيفشل الفحص في أيّ استنساخ جديد"

Test-Rule -Name "موافقات allowScripts" -File "package.json" `
    -Pattern '(?s)allowScripts.{0,200}?sharp' `
    -Why "npm 12 يحجب سكربتات التثبيت؛ وبدون الموافقة يفشل بناء sharp/esbuild في CI"

Test-Rule -Name "استثناء content من Prettier" -File ".prettierignore" `
    -Pattern '(?m)^content\s*$' `
    -Why "content/ نسخة مولَّدة من الفولت — تنسيقها يعارض المصدر وتمحوه أوّل مزامنة"

Test-Rule -Name "استثناء .quartz من Prettier" -File ".prettierignore" `
    -Pattern '(?m)^\.quartz\s*$' `
    -Why "مجلّد مولَّد — يُغرق فحص npm run check بشكاوى تنسيق لا تخصّنا"

# ─── سيور العمل: ألّا تعود سيور Quartz الخاصّة بمستودعه ───────────────────
$flows = @(Get-ChildItem (Join-Path $Root ".github/workflows") -Filter *.y*ml -ErrorAction SilentlyContinue |
           Select-Object -ExpandProperty Name | Sort-Object)
if ($flows.Count -eq 1 -and $flows[0] -eq "deploy.yaml") {
    $Pass++
    if (-not $Quiet) { Write-Host "  ✓ سير عمل واحد فقط (deploy.yaml)" -ForegroundColor DarkGray }
} else {
    [void]$Fails.Add([pscustomobject]@{
        Name = "سيور عمل زائدة: $($flows -join ', ')"
        File = ".github/workflows/"
        Why  = "سيور Quartz الخاصّة بمستودعه (ci · docker · preview) تعود بالدمج، فتستهلك دقائق Actions وتفشل عندنا"
    })
}

# ─── فحص ما بُني فعلًا، إن وُجد ───────────────────────────────────────────
$built = Join-Path $Root "public/index.html"
if (Test-Path $built) {
    $html = Get-Content $built -Raw -Encoding UTF8
    if ($html -match 'dir="rtl"') {
        $Pass++
        if (-not $Quiet) { Write-Host "  ✓ الناتج المبنيّ يحمل dir=rtl" -ForegroundColor DarkGray }
    } else {
        [void]$Fails.Add([pscustomobject]@{
            Name = "الناتج المبنيّ بلا dir=rtl"; File = "public/index.html"
            Why  = "الإعداد قد يكون سليمًا والناتج مكسورًا — هذا هو الفحص الوحيد على ما يراه الزائر"
        })
    }
} elseif (-not $Quiet) {
    Write-Host "  · public/ غير مبنيّ — تُخطّى فحوص الناتج" -ForegroundColor DarkGray
}

# ─── الخلاصة ──────────────────────────────────────────────────────────────
Write-Host ""
if ($Fails.Count -eq 0) {
    Write-Host "✓ $Pass تخصيصًا قائمًا، ولا سقوط." -ForegroundColor Green
    exit 0
}

Write-Host "✗ سقط $($Fails.Count) من $($Fails.Count + $Pass):" -ForegroundColor Red
foreach ($f in $Fails) {
    Write-Host ""
    Write-Host "  ✗ $($f.Name)" -ForegroundColor Red
    Write-Host "    الملف : $($f.File)" -ForegroundColor DarkGray
    Write-Host "    العلّة: $($f.Why)" -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "راجع «ما خُصِّص لهذا المستودع» في README.md لإعادة ما سقط." -ForegroundColor Yellow
exit 1
