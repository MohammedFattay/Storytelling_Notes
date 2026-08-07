#!/usr/bin/env python3
"""بوّابة ما بعد البناء: تُثبت أنّ الناتج لا يحمل نصًّا صريحًا ولا صورةً مكشوفة.

وعلّة وجودها أنّ الإخلال في هذا الموقع **صامت**. فلو خلا ملفٌّ من ترويسة، أو
بقيت صورة على حالها، أو أعادت نسخةٌ جديدة من إضافة التشفير ترتيب مراحلها —
لبني الموقع بنجاح، ونُشر، ولم يشتكِ شيء. فيُقاس الناتج نفسه لا الإعداد:

  ١. **الطعم (Canary):** تُنتزع من متن كل ملاحظة تُشفَّر جملٌ نثرية مميّزة، ثم
     يُفحش بها ناتج البناء كلّه — html وjson وjs. فظهور واحدة منها معناه أنّ
     الصفحة نُشرت صريحة أو أنّ فهرس البحث حمل نصّها.
  ٢. **عدد الصفحات المشفَّرة** يطابق عدد الملاحظات التي حُقنت لها كلمة مرور.
  ٣. **لا ملفّ صورة** في الناتج يحمل اسم مرفق من مرفقات القاعدة.

والعناوين مستثناة من الطعم عمدًا: هي في الشجر والبحث ظاهرةٌ بالقصد، وإنما
المحجوب متنُ الصفحة.
"""

import argparse
import json
import re
import sys
from html import unescape
from pathlib import Path

FRONTMATTER = re.compile(r"\A---\r?\n(.*?)\r?\n---\r?\n", re.DOTALL)
HEADING = re.compile(r"^(#{2,6})\s+(.*)$")
# بادئات البنية تُقشَر ولا تُسقِط السطر: فصفحاتٌ كاملة في هذه القاعدة جداولُ
# وقوائم لا نثر (المعجم · أوراق العمل · المخططات)، ولو أُسقطت لخرجت بلا طعم
# فلم يُتحقّق من حجبها — وهو ما وقع في البناء الأول.
LEADING_MARKUP = re.compile(r"^\s*(?:[-*+]\s+|\d+[.)]\s+|>\s*(?:\[![a-z]+\][-+]?)?\s*|\|)")
INLINE_MARKUP = re.compile(r"\[\[[^\]]*\]\]|!\[[^\]]*\]|\[[^\]]*\]\([^)]*\)|<[^>]+>|\*\*|__|`|\*|_|~~")
TEXT_SUFFIXES = {".html", ".json", ".js", ".xml", ".txt", ".css"}
IMAGE_SUFFIXES = {".jpeg", ".jpg", ".png", ".gif", ".webp", ".svg", ".avif"}

CANARIES_PER_NOTE = 4
MIN_PROSE_LENGTH = 40
MIN_HEADING_LENGTH = 20


def strip_markup(line: str) -> str:
    plain = LEADING_MARKUP.sub("", line)
    plain = plain.replace("|", " · ")          # خلايا الجدول تصير نصًّا متّصلًا
    plain = INLINE_MARKUP.sub("", plain)
    return re.sub(r"\s+", " ", plain).strip(" ·—–-").strip()


def canaries(text: str, title: str) -> list[str]:
    """نصٌّ من المتن يجب ألّا يظهر في الناتج: نثرٌ وخلايا جداول وعناوينُ أقسام.

    والعناوين داخلة في الطعم بعد تعطيل الفهرس الجانبي (table-of-contents): فهو
    كان يرصفها **خارج** المتن فلا يبلغها التشفير. أمّا عنوان الصفحة نفسه فمستثنى،
    لأنّه في الشجر والبحث ظاهرٌ بالقصد.
    """
    match = FRONTMATTER.match(text)
    body = text[match.end():] if match else text

    candidates: list[str] = []
    in_fence = False
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_fence = not in_fence
            continue
        if in_fence or not stripped:
            continue
        if set(stripped) <= set("|-: "):        # سطر الفصل في الجداول
            continue

        heading = HEADING.match(stripped)
        if heading:
            plain = strip_markup(heading.group(2))
            if len(plain) >= MIN_HEADING_LENGTH and plain not in title and title not in plain:
                candidates.append(plain)
            continue
        if stripped.startswith("#"):            # عنوان المستوى الأول ≈ العنوان
            continue

        plain = strip_markup(stripped)
        if len(plain) >= MIN_PROSE_LENGTH:
            candidates.append(plain[:70])

    if len(candidates) <= CANARIES_PER_NOTE:
        return candidates
    step = len(candidates) // CANARIES_PER_NOTE
    return [candidates[i * step] for i in range(CANARIES_PER_NOTE)]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--content", required=True, type=Path)
    parser.add_argument("--public", required=True, type=Path)
    parser.add_argument("--attachments", required=True, type=Path, nargs="+")
    parser.add_argument("--exclude", default=["index.md"], nargs="*",
                        help="ملفّات علنية بالقصد — لا يُفحش بها")
    args = parser.parse_args()

    failures: list[str] = []
    excluded = {p.replace("\\", "/") for p in (args.exclude or [])}

    # ── الطعم ────────────────────────────────────────────────────────
    # نصّ الصفحات العلنية يُجمع أوّلًا ليُطرح من الطعم: فما ورد في صفحة الهبوط
    # ظهورُه في الناتج مقصود لا تسريب. ولولا هذا الطرح لأعلن الفحص «تسريبًا» عن
    # جملةٍ كتبتُها أنا في الهبوط تشبه جملةً في الفهرس — وقد وقع فعلًا.
    public_text = ""
    for name in sorted(excluded):
        candidate = args.content / name
        if candidate.exists():
            public_text += candidate.read_text(encoding="utf-8-sig") + "\n"

    expected_encrypted = 0
    canary_map: dict[str, str] = {}
    for note in sorted(args.content.rglob("*.md")):
        relative = note.relative_to(args.content).as_posix()
        if relative in excluded:
            continue
        expected_encrypted += 1
        text = note.read_text(encoding="utf-8-sig")
        header = FRONTMATTER.match(text)
        title_match = re.search(r"(?m)^title:\s*(.+)$", header.group(1)) if header else None
        title = title_match.group(1).strip().strip("\"'") if title_match else ""

        found = [phrase for phrase in canaries(text, title) if phrase not in public_text]
        if not found:
            failures.append(f"لم يُنتزع طعمٌ من {relative} — فلا يُتحقّق من حجبها")
        for phrase in found:
            canary_map.setdefault(phrase, relative)

    if not canary_map:
        failures.append("لا طعم على الإطلاق — الفحص بلا معنى، فيُعدّ ساقطًا")

    encrypted_pages = 0
    leaks: list[tuple[str, str, str]] = []
    for built in sorted(args.public.rglob("*")):
        if not built.is_file() or built.suffix.lower() not in TEXT_SUFFIXES:
            continue
        try:
            blob = built.read_text(encoding="utf-8", errors="ignore")
        except OSError as error:
            failures.append(f"تعذّرت قراءة {built}: {error}")
            continue
        if built.suffix.lower() == ".html" and "data-encrypted" in blob:
            encrypted_pages += 1
        # يُفَكّ ترميز الكيانات قبل الفحش: الناتج يكتب `&amp;` و`&quot;` حيث
        # يكتب المصدر `&` و`"`، فيفوت الطعمُ الذي فيه أحدهما ويُعلن الحجب تامًّا.
        blob = unescape(blob)
        for phrase, source in canary_map.items():
            if phrase in blob:
                leaks.append((built.relative_to(args.public).as_posix(), source, phrase))

    if leaks:
        failures.append(f"نصٌّ صريح في الناتج — {len(leaks)} موضعًا:")
        for where, source, phrase in leaks[:8]:
            failures.append(f"    {where}  ←  {source}   «{phrase[:40]}…»")

    if encrypted_pages != expected_encrypted:
        failures.append(
            f"صفحاتٌ مشفَّرة في الناتج: {encrypted_pages}، والمتوقّع {expected_encrypted}. "
            "والفرق صفحةٌ نُشرت صريحة أو لم تُبنَ أصلًا"
        )

    # ── الصور ────────────────────────────────────────────────────────
    attachment_names = {
        item.name.lower()
        for folder in args.attachments if folder.exists()
        for item in folder.rglob("*")
        if item.is_file() and item.suffix.lower() in IMAGE_SUFFIXES
    }
    exposed = [
        built.relative_to(args.public).as_posix()
        for built in args.public.rglob("*")
        if built.is_file() and built.name.lower() in attachment_names
    ]
    if exposed:
        failures.append(
            f"ملفّات صور مكشوفة في الناتج ({len(exposed)}): " + ", ".join(sorted(exposed)[:6]) +
            "\n    وهذه تُجلب برابطها المباشر بلا كلمة مرور"
        )

    # ── فهرس البحث المشفَّر ──────────────────────────────────────────
    shadow = args.public / "static" / "encryptedContentIndex.json"
    if not shadow.exists():
        failures.append("فهرس البحث المشفَّر غائب (static/encryptedContentIndex.json)")
    else:
        try:
            payload = json.loads(shadow.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            failures.append(f"فهرس البحث المشفَّر غير سليم: {error}")
        else:
            entries = payload.get("entries", payload) if isinstance(payload, dict) else payload
            print(f"  فهرس البحث المشفَّر: {len(entries)} مدخلًا")

    print(f"  طعمٌ مفحوصٌ به: {len(canary_map)} جملة من {expected_encrypted} صفحة")
    print(f"  صفحات مشفَّرة في الناتج: {encrypted_pages}")

    if failures:
        print("\n[ساقط] " + "\n[ساقط] ".join(failures), file=sys.stderr)
        return 1
    print("[تمّ] لا نصّ صريح ولا صورة مكشوفة في الناتج")
    return 0


if __name__ == "__main__":
    sys.exit(main())
