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

# ─── سطر بيانات الصفحة: نسخة الإضافة المرقَّعة ────────────────────────────
# تفصيل الرقعات في plugins/content-meta/PATCHES.md. والنسخة هنا **مطابقة بايتًا
# ببايت** لنظيرتها في D:\quartz-site، فالعطب واحد والحزمة واحدة. وأثره في هذا
# الموقع صفحةٌ واحدة (الفهرس العلنيّ) لا أكثر، إذ المتنُ مشفَّر فلا نصّ يُقاس
# منه وقتُ قراءة — ويبقى الإصلاح لازمًا فيها، ولئلّا يختلف الموقعان.
Test-Rule -Name "إضافة content-meta تشير إلى النسخة المحلّية" -File "package.json" `
    -Pattern '"@quartz-community/content-meta":\s*"file:\./plugins/content-meta"' `
    -Why "بالعودة إلى نسخة npm يعود التداخل: «٠٧ أغسطس ٢٠٢٦دقيقتان للقراءة»"

Test-Rule -Name "رقعة الأرقام اللاتينية في التاريخ" -File "plugins/content-meta/dist/index.js" `
    -Pattern '\-u\-nu\-latn' `
    -Why "بدونها يخرج التاريخ بأرقام هندية، ووقتُ القراءة بلاتينية حيث يكون رقمًا"

Test-Rule -Name "رقعة الفاصل النصّيّ" -File "plugins/content-meta/dist/index.js" `
    -Pattern 'segments\.flatMap' `
    -Why "بدونها يعود الفاصل عنصرًا وهميًّا (::after) لا يُنسخ مع النصّ ولا يُقرأ آليًّا"

Test-Rule -Name "رقعة عزل الاتّجاه" -File "plugins/content-meta/dist/index.js" `
    -Pattern 'unicode-bidi: isolate' `
    -Why "بدونها تتشابك صناديق التاريخ ووقت القراءة، ولا يمنع ذلك فاصلٌ ولا هامش"

Test-Rule -Name "لا margin-right في سطر البيانات" -File "plugins/content-meta/dist/index.js" `
    -Pattern 'margin-right' `
    -Absent `
    -Why "الهامش على الجهة المادّية يذهب في RTL إلى حافة الصفحة لا بين العنصرين"

# وهذا الفحص على **الناتج** لا على الإعداد، فقد تبقى الرقعة في المصدر ولا تبلغ
# البناء. والفهرس العلنيّ هو الصفحة الوحيدة التي يظهر فيها السطر هنا.
Test-Rule -Name "الناتج المبنيّ: تاريخٌ لاتينيّ ثمّ فاصل" -File "public/index.html" `
    -Pattern 'class="content-meta"><time[^>]*>[0-9]{2} \S+ [0-9]{4}</time>، <span>' `
    -Why "فحصٌ على الناتج لا على الإعداد: يكشف رقعةً قائمةً في المصدر ولم تبلغ البناء"

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

# ─── سيور العمل: لا سير عمل واحد في هذا المستودع ─────────────────────────
# ويفارق هذا نظيره في موقع إدارة المشاريع: هناك يُطلب سير عمل واحد (deploy.yaml)
# يبني من content/ المثبَّتة. وهنا content/ غير مثبَّتة، فالسير الذي يبني ينتج
# موقعًا فارغًا **ثم يحلّ به محلّ النشرة السليمة** — فشلٌ صامت: البناء ينجح
# والموقع يخلو. فالمطلوب هنا صفر. (‎.github/NO-CI.md‎)
$flows = @(Get-ChildItem (Join-Path $Root ".github/workflows") -Filter *.y*ml -ErrorAction SilentlyContinue |
           Select-Object -ExpandProperty Name | Sort-Object)
if ($flows.Count -eq 0) {
    $Pass++
    if (-not $Quiet) { Write-Host "  ✓ لا سير عمل يبني (البناء محليّ)" -ForegroundColor DarkGray }
} else {
    [void]$Fails.Add([pscustomobject]@{
        Name = "سيور عمل عادت: $($flows -join ', ')"
        File = ".github/workflows/"
        Why  = "لا content/ في هذا المستودع، فالسير الذي يبني يُنتج موقعًا فارغًا ويحلّ به محلّ النشرة المشفَّرة"
    })
}

# ─── وثلاثة تخصيصات هي محور هذا الموقع: حجب المادّة ──────────────────────
Test-Rule -Name "المحتوى خارج المستودع" -File "sync.ps1" `
    -Pattern '(?m)^\$Content\s*=\s*"D:\\quartz-storytelling-content"' `
    -Why "لو عاد إلى content/ داخل المستودع لثبّته git سهوًا، فقُرئ النصّ الخام بلا كلمة مرور"

Test-Rule -Name "البناء يشير إلى المحتوى الخارجي" -File "sync.ps1" `
    -Pattern 'quartz build -d \$Content' `
    -Why "بلا ‎-d‎ يبني Quartz من content/ الفارغ فيُخرج موقعًا بلا صفحات، وينجح"

Test-Rule -Name "لا حرس .gitignore على content" -File ".gitignore" `
    -Pattern '(?m)^content/\s*$' -Absent `
    -Why "Quartz يحترم .gitignore عند جمع ملفّاته، فإدراج content/ يُخفيه عن البناء نفسه — مقيسٌ لا مُفترَض"

Test-Rule -Name "إضافة التشفير مفعَّلة" -File "quartz.config.yaml" `
    -Pattern '(?s)encrypted-pages"\s*\n\s*enabled:\s*true' `
    -Why "بها وحدها يُشفَّر متن الصفحات — وتعطيلها ينشر المادّة صريحة"

Test-Rule -Name "الفهرس الجانبي معطَّل" -File "quartz.config.yaml" `
    -Pattern '(?s)table-of-contents"\s*\n\s*enabled:\s*false' `
    -Why "يُرصَف خارج المتن فلا يبلغه التشفير، فينشر عناوين التكتيكات صريحةً"

# ─── رقعة رصف mermaid: نداءٌ ثانٍ كان يُعيده هراءً ───────────────────────
Test-Rule -Name "إضافة ofm تشير إلى النسخة المحلّية" -File "package.json" `
    -Pattern '"@quartz-community/obsidian-flavored-markdown":\s*"file:\./plugins/obsidian-flavored-markdown"' `
    -Why "بلا ذلك تُستعمل نسخة npm بلا رقعة، فتُعيد الصفحةُ المشفَّرة مخطّطاتها «Syntax error in text»"

Test-Rule -Name "رقعة تخزين تعريف mermaid" `
    -File "plugins/obsidian-flavored-markdown/dist/index.js" `
    -Pattern 'n=mermaidSourceCache;for\(let r of e\)if\(!n\.has\(r\)\)' `
    -Why "بها وحدها يصير الرصف عاطلًا عن الأثر — وعلّتها في PATCHES.md هناك"

# ─── ما يعلو على طبقات الثيم ──────────────────────────────────────────────
# تُعلن حزمة الثيم: @layer quartz-base, obsidian-theme, quartz-themes-base, …
# فتنسيق Quartz في أدنى الطبقات وطبقاتُ الثيم بعده، والمتأخّرة تكسب مهما كانت
# الأخرى أخصّ. فلا تنفع هنا حيلة ‎:root:root:root‎؛ والمخرج أنّ custom.scss
# يُبنى **بلا طبقة**، وغير المصنَّف يكسب الطبقات كلَّها.
Test-Rule -Name "استعادة تنسيق لوحة البحث" -File "quartz/styles/custom.scss" `
    -Pattern '(?s)>\s*\.search-layout\s*\{[^}]{0,120}background:\s*var\(--light\)' `
    -Why "بدونها يُصفِّر الثيم خلفية اللوحة وحدودها وحشو البطاقات، فتخرج النتائج نصًّا عاريًا فوق صفحة مضبَّبة"

Test-Rule -Name "حشو بطاقات النتائج وفاصلها" -File "quartz/styles/custom.scss" `
    -Pattern '(?s)\.result-card\s*\{[^}]{0,200}padding:\s*1em' `
    -Why "بدونه تتلاصق عناوين النتائج بلا حشو ولا خطّ فاصل"

Test-Rule -Name "محاذاة البطاقة start لا left" -File "quartz/styles/custom.scss" `
    -Pattern 'text-align:\s*start' `
    -Why "Quartz يضع left وهو خطأ في صفحة عربية؛ وسقوط هذا يعيد النتائج إلى محاذاة يسارية"

Test-Rule -Name "إظهار أثر وضع القراءة" -File "quartz/styles/custom.scss" `
    -Pattern '(?s):root\[reader-mode="on"\]\s*\{[^}]{0,400}opacity:\s*0' `
    -Why "بدونها تُعيد قاعدةُ الثيم الشريطين كلّما كانت الفأرة خارج المتن — والزرّ في الشريط، فلا يُرى للضغط أثر"

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

    # رقعة mermaid في الناتج لا في المصدر وحده. ويُفحَص المعنى لا الاسم: فـQuartz
    # يعيد تصغير السكربت فيسمّي `mermaidSourceCache` حرفًا واحدًا (`x` في أوّل
    # بناء). والمطلوب أن يكون بعد `code.mermaid` استعمالٌ لـ`.has(` — أي أنّ
    # المخزَن لا يُكتب فوقه. وبلا هذا يُصلَح المصدر ويبقى الزائر على العطب.
    $bundle = Get-ChildItem (Join-Path $Root "public/static") -Filter *.js -Recurse -ErrorAction SilentlyContinue |
              Where-Object { (Get-Content $_.FullName -Raw -Encoding UTF8) -match 'code\.mermaid' } |
              Select-Object -First 1
    if (-not $bundle) {
        if (-not $Quiet) { Write-Host "  · لا سكربت mermaid في الناتج — يُخطّى" -ForegroundColor DarkGray }
    } else {
        $js = Get-Content $bundle.FullName -Raw -Encoding UTF8
        $i  = $js.IndexOf('code.mermaid')
        $window = $js.Substring($i, [Math]::Min(420, $js.Length - $i))
        if ($window -match '\.has\(') {
            $Pass++
            if (-not $Quiet) { Write-Host "  ✓ رقعة mermaid قائمة في الناتج المبنيّ" -ForegroundColor DarkGray }
        } else {
            [void]$Fails.Add([pscustomobject]@{
                Name = "الناتج المبنيّ بلا رقعة mermaid"; File = $bundle.Name
                Why  = "النداء الثاني سيخزّن نصّ الـSVG المرصوف ويعطيه mermaid — «Syntax error in text» ومصدرُ المخطّط سليم"
            })
        }
    }
    # وهذا أهمّ فحوص الناتج في هذا الباب: أن تكون قواعدنا **خارج** كتلة
    # @layer. فالقاعدة الصحيحة داخل طبقة تُهزَم بلا ضجيج — تبني بنجاح وتخرج
    # مكسورة. واسم الملفّ فيه بصمة تتغيّر بكلّ بناء، فيُبحث بنمط لا باسم.
    $idx = Get-ChildItem -LiteralPath (Join-Path $Root "public") -Filter "index-*.css" -File |
           Select-Object -First 1
    if ($idx) {
        $css = Get-Content $idx.FullName -Raw -Encoding UTF8
        # نهاية كتلة @layer quartz-base: تُحسب بموازنة الأقواس
        $start = $css.IndexOf("{", $css.IndexOf("@layer"))
        $depth = 0; $end = -1
        for ($j = $start; $j -lt $css.Length; $j++) {
            if ($css[$j] -eq "{") { $depth++ }
            elseif ($css[$j] -eq "}") { $depth--; if ($depth -eq 0) { $end = $j; break } }
        }
        foreach ($probe in @(
            @{ Key = "reader-mode=on"; Name = "قواعد وضع القراءة بلا طبقة" },
            @{ Key = "search-layout{background"; Name = "قواعد لوحة البحث بلا طبقة" }
        )) {
            $at = $css.IndexOf($probe.Key)
            if ($at -ge 0 -and ($end -lt 0 -or $at -gt $end)) {
                $Pass++
                if (-not $Quiet) { Write-Host ("  ✓ " + $probe.Name) -ForegroundColor DarkGray }
            } else {
                [void]$Fails.Add([pscustomobject]@{
                    Name = $probe.Name; File = "public/" + $idx.Name
                    Why  = if ($at -lt 0) { "القاعدة غائبة عن الناتج أصلًا" }
                           else { "القاعدة داخل @layer، فتهزمها طبقات الثيم بلا ضجيج" }
                })
            }
        }
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
