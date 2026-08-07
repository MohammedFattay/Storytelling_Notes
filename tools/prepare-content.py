#!/usr/bin/env python3
"""تحضير content/ للبناء المشفَّر — يُشغَّل من sync.ps1 بعد المطابقة وقبل البناء.

يعمل عملين لا ثالث لهما، وكلٌّ منهما يسدّ ثقبًا لا تسدّه إضافة التشفير وحدها:

  ١. حقن `password:` في ترويسة كل ملاحظة. فإضافة encrypted-pages لا تشفّر إلا
     ما وجدت له كلمة مرور في ترويسته، وما خلا منها يُنشر نصًّا صريحًا. وموضع
     الحقن content/ المولَّدة لا الفولت: فالفولت مصدر الحقيقة ولا تُدسّ فيه
     أسرار (CLAUDE.md 15/هـ).

  ٢. إدماج الصور بصيغة `data:` URI داخل متن الصفحة. وعلّته أنّ الصورة ملفٌّ
     ساكن لا نصُّ صفحة: فلو بقيت `![[card-x.jpeg]]` لنُسخ الملفّ إلى public/
     ولجُلب برابطه المباشر — مشفَّرةً كانت الصفحة أو لم تكن. وبإدماجه تصير
     بايتاته جزءًا من الحمولة المشفَّرة، ولا يُكتب في public/ ملفّ صورة واحد.

ويخرج بالرمز 1 عند أي إخلال، فيُجهض sync.ps1 النشر قبل أن يقع.
"""

import argparse
import base64
import mimetypes
import re
import sys
from pathlib import Path

EMBED = re.compile(r"!\[\[([^\]\|#]+?)(?:\|([^\]]*))?\]\]")
FRONTMATTER = re.compile(r"\A---\r?\n(.*?)\r?\n---\r?\n", re.DOTALL)
PASSWORD_LINE = re.compile(r"(?m)^password:.*$")

IMAGE_SUFFIXES = {".jpeg", ".jpg", ".png", ".gif", ".webp", ".svg", ".avif"}


def die(message: str) -> None:
    print(f"[خطأ] {message}", file=sys.stderr)
    sys.exit(1)


def load_password(path: Path) -> str:
    if not path.exists():
        die(
            f"ملف كلمة المرور غير موجود: {path}\n"
            "       أنشئه بسطر واحد فيه الكلمة، ولا يُثبَّت (مُدرَج في .gitignore):\n"
            f'       Set-Content -Path "{path}" -Value "كلمتك" -Encoding utf8 -NoNewline'
        )
    password = path.read_text(encoding="utf-8-sig").strip()
    if not password:
        die(f"ملف كلمة المرور فارغ: {path}")
    if '"' in password or "\n" in password:
        die("كلمة المرور لا تحمل علامة تنصيص مزدوجة ولا سطرًا جديدًا — تُكسر ترويسة YAML")
    return password


def index_attachments(folders: list[Path]) -> dict[str, Path]:
    """فهرس بالاسم لا بالمسار: الروابط في هذا الفولت بالاسم المجرّد وحده."""
    index: dict[str, Path] = {}
    for folder in folders:
        if not folder.exists():
            continue
        for item in folder.rglob("*"):
            if item.is_file() and item.suffix.lower() in IMAGE_SUFFIXES:
                index.setdefault(item.name, item)
                index.setdefault(item.stem, item)
    return index


def data_uri(path: Path) -> str:
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    payload = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime};base64,{payload}"


def inject_password(text: str, password: str, note: Path) -> str:
    match = FRONTMATTER.match(text)
    if not match:
        die(f"لا ترويسة في {note.name} — فلا موضع لحقن كلمة المرور، ولا تُشفَّر الصفحة")
    body = match.group(1)
    line = f'password: "{password}"'
    body = PASSWORD_LINE.sub(line, body) if PASSWORD_LINE.search(body) else f"{body}\n{line}"
    return f"---\n{body}\n---\n" + text[match.end():]


def inline_images(text: str, note: Path, index: dict[str, Path], stats: dict) -> str:
    missing: list[str] = []

    def replace(match: re.Match) -> str:
        target = match.group(1).strip()
        if Path(target).suffix.lower() not in IMAGE_SUFFIXES:
            return match.group(0)  # إدماج ملاحظة لا صورة — يُترك لـQuartz
        found = index.get(target) or index.get(Path(target).name)
        if found is None:
            missing.append(target)
            return match.group(0)
        alt = (match.group(2) or Path(target).stem).replace('"', "'")
        stats["inlined"] += 1
        stats["bytes"] += found.stat().st_size
        return f'<img src="{data_uri(found)}" alt="{alt}" loading="lazy" />'

    result = EMBED.sub(replace, text)
    if missing:
        die(
            f"صور مُشار إليها في {note.name} ولا وجود لها: {', '.join(sorted(set(missing)))}\n"
            "       ولو مضى النشر لظهرت الصفحة ناقصةً بعد فكّ التشفير"
        )
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--content", required=True, type=Path, help="مجلد content/ المولَّد")
    parser.add_argument("--attachments", required=True, type=Path, nargs="+",
                        help="مجلدات المرفقات في الفولت (تُقرأ ولا تُنسخ)")
    parser.add_argument("--password-file", required=True, type=Path)
    parser.add_argument("--public", default=["index.md"], nargs="*",
                        help="ملفّات تبقى علنية بلا تشفير — مسارات نسبية من content/")
    args = parser.parse_args()

    if not args.content.is_dir():
        die(f"مجلد المحتوى غير موجود: {args.content}")

    password = load_password(args.password_file)
    index = index_attachments(args.attachments)
    if not index:
        die("لم يُوجد أي مرفق في المجلدات المذكورة — تحقّق من مسار --attachments")

    public = {p.replace("\\", "/") for p in (args.public or [])}
    stats = {"inlined": 0, "bytes": 0}
    encrypted = kept_public = 0

    for note in sorted(args.content.rglob("*.md")):
        relative = note.relative_to(args.content).as_posix()
        # utf-8-sig لا utf-8: بعض ملفّات الفولت تحمل BOM، وبقاؤه يجعل الترويسة
        # لا تُطابَق (فلا تُحقن كلمة المرور) والصفحة تُنشر صريحة. وقد وقع فعلًا
        # في «01 - Concept.md». والكتابة بلا BOM توحيدًا لما في content/.
        text = note.read_text(encoding="utf-8-sig")
        original = text

        text = inline_images(text, note, index, stats)

        if relative in public:
            kept_public += 1
        else:
            text = inject_password(text, password, note)
            encrypted += 1

        if text != original:
            note.write_text(text, encoding="utf-8", newline="\n")

    leftover = [
        p.relative_to(args.content).as_posix()
        for p in args.content.rglob("*")
        if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES
    ]
    if leftover:
        die(
            "ملفّات صور باقية في content/ بعد الإدماج: " + ", ".join(sorted(leftover)[:10]) +
            "\n       وهذه تُنسخ إلى public/ وتُجلب برابطها المباشر بلا كلمة مرور"
        )

    megabytes = stats["bytes"] / (1024 * 1024)
    print(f"[تمّ] {encrypted} صفحة تُشفَّر · {kept_public} علنية · "
          f"{stats['inlined']} صورة أُدمجت ({megabytes:.1f} م.ب)")


if __name__ == "__main__":
    main()
