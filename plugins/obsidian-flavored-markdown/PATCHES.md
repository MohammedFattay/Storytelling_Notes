# نسخة مرقَّعة من `@quartz-community/obsidian-flavored-markdown@0.1.2`

هذا المجلد **نسخة حرفية** من الحزمة المنشورة على npm، عليها رقعة واحدة.
وتُستعمل عبر `"@quartz-community/obsidian-flavored-markdown": "file:./plugins/obsidian-flavored-markdown"`
في `package.json`، فيبقى اسم الحزمة ومسار استيرادها كما هما، ولا يتغيّر شيء في
`quartz.config.yaml`.

> **عند تحديث الحزمة يومًا:** انسخ `dist/` من النسخة الجديدة، ثم أعِد الرقعة
> أدناه بنصّها، ثم شغّل `.\check-custom.ps1` — ففيه فحصٌ لها.

## الرقعة — رصفُ mermaid يُعيده نداءٌ ثانٍ هراءً

**الملفّ:** `dist/index.js` (داخل نصّ سكربت رصف mermaid).

```diff
- "--codeFont"],L;async function M()
+ "--codeFont"],L,mermaidSourceCache=new WeakMap;async function M()
```

```diff
- let t=L.default,n=new WeakMap;for(let r of e)n.set(r,r.innerText);
+ let t=L.default,n=mermaidSourceCache;for(let r of e)if(!n.has(r))n.set(r,r.innerText);
```

**العلّة.** الدالّة تُنشئ `WeakMap` **داخل كلّ نداء**، فتخزّن فيها ما تجده في
العنصر لحظتَها لا تعريفَ المخطّط الأصلي:

```js
let n = new WeakMap;
for (let r of e) n.set(r, r.innerText);   // ← ما تجده، أيًّا كان
...
n.get(i) && (i.innerHTML = n.get(i));     // ← ثم تعيده محتوى العنصر
await t.run({ nodes: e });
```

فالنداء الأوّل يخزّن التعريف ويرصفه، والعنصر يصير `<svg>`. ثم يخزّن النداء
**الثاني** نصّ الـSVG المرصوف — أي التسميات وحدها بلا `flowchart` ولا أسهم —
ويعيده محتوى العنصر، ويعطيه mermaid. فيسقط بـ:

```
No diagram type detected matching given configuration for text: ألف
باء

جيم
```

وهو الصندوق الأحمر «Syntax error in text» في الصفحة.

**وقياسه لا تقديره:** `.claude/skills/vault-audit/scripts/mermaid-parse/double-run.html`
في الفولت يحاكي المنطق حرفيًّا وينادِيه مرّتين، فيُخرج الأولى `rendered`
والثانية `ERROR: No diagram type detected…`.

**ولماذا يظهر في هذا الموقع دون موقع إدارة المشاريع؟** لأنّ الدالّة مربوطة
بحدثَي `nav` و`render`، وفي الصفحة **المشفَّرة** منادِيان لا واحد: يفكّ سكربت
`encrypted-pages` التشفير ثم يبعث `render` بعد حقن المتن. فمتى كانت كلمة المرور
محفوظة في `sessionStorage` — أي في كل زيارة بعد الأولى — حُقن المتن في `nav`
فرصفت الدالّة المخطّطات، ثم أعاد `render` نداءها فأفسدت ما رصفت. وأمّا الصفحة
غير المشفَّرة فمنادٍ واحد، فلا يظهر العطب فيها أصلًا.

**والرقعة** ترفع الـ`WeakMap` إلى نطاق الوحدة وتمنع الكتابة فوق مدخلٍ قائم، فيبقى
التعريف الأصلي محفوظًا للعنصر ما دامت الصفحة. فيصير الرصف **عاطلًا عن الأثر**
(idempotent): النداء العاشر كالأوّل. وتُصلح معه علّةً ثانية من جنسها: تبديل
الثيم (`themechange`) ينادي المنطق نفسه، فكان يفسد المخطّطات كذلك.
