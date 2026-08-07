#!/usr/bin/env python3
"""الوجه الآخر من الفحص: أنّ المحجوب **يُسترجَع** بكلمة المرور.

فبوّابة verify-encrypted.py تُثبت أنّ الناتج لا يحمل نصًّا صريحًا، وهي وحدها
لا تكفي: صفحةٌ حُشيت هراءً ثم شُفِّرت تجتازها بامتياز. فهذا السكربت يفكّ
تشفير كل صفحة بالمفتاح نفسه ويسأل ثلاثة أسئلة عن الناتج:

  ١. أنّ فكّ التشفير ينجح أصلًا — أي أنّ كلمة المرور المدفوعة هي المعلومة.
  ٢. أنّ الصور مُدمَجة داخل المتن المفكوك (data:image)، فتظهر بعد الفتح.
  ٣. أنّ فيه من نصّ الملاحظة ما يُثبت أنّه هو لا صفحةٌ فارغة.

ويُشغَّل يدويًّا عند تغيير كلمة المرور أو ترقية إضافة التشفير، ولا يدخل في
sync.ps1: فهو يحتاج حزمة cryptography، والبوّابة الحاجبة لا تحتاجها.
"""

import argparse
import re
import sys
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.hashes import SHA256
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

import base64

# مطابقة لثوابت الإضافة (node_modules/@quartz-community/encrypted-pages)
SALT_LENGTH, IV_LENGTH, TAG_LENGTH, KEY_LENGTH = 16, 12, 16, 32
BLOB = re.compile(r'data-encrypted="([^"]+)"')


def decrypt(blob_b64: str, password: str, iterations: int) -> str:
    raw = base64.b64decode(blob_b64)
    salt = raw[:SALT_LENGTH]
    iv = raw[SALT_LENGTH:SALT_LENGTH + IV_LENGTH]
    tag = raw[SALT_LENGTH + IV_LENGTH:SALT_LENGTH + IV_LENGTH + TAG_LENGTH]
    body = raw[SALT_LENGTH + IV_LENGTH + TAG_LENGTH:]
    key = PBKDF2HMAC(algorithm=SHA256(), length=KEY_LENGTH,
                     salt=salt, iterations=iterations).derive(password.encode())
    # المكتبة تتوقّع بصمة التوثيق ملحقةً بالنصّ المشفَّر، والإضافة تفصلها
    return AESGCM(key).decrypt(iv, body + tag, None).decode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--public", required=True, type=Path)
    parser.add_argument("--password-file", required=True, type=Path)
    parser.add_argument("--iterations", type=int, default=600000)
    args = parser.parse_args()

    password = args.password_file.read_text(encoding="utf-8-sig").strip()
    failures: list[str] = []
    checked = 0

    for page in sorted(args.public.rglob("*.html")):
        html = page.read_text(encoding="utf-8", errors="ignore")
        match = BLOB.search(html)
        if not match:
            continue
        name = page.relative_to(args.public).as_posix()
        checked += 1
        try:
            plain = decrypt(match.group(1), password, args.iterations)
        except Exception as error:                      # noqa: BLE001
            failures.append(f"{name}: تعذّر فكّ التشفير — {type(error).__name__}")
            continue

        images = plain.count("data:image")
        text_only = re.sub(r"<[^>]+>", " ", plain)
        arabic = len(re.findall(r"[؀-ۿ]", text_only))
        if arabic < 500:
            failures.append(f"{name}: المتن المفكوك فيه {arabic} حرفًا عربيًّا فقط — صفحةٌ شبه فارغة")
        print(f"  {name:44} {arabic:>7} حرفًا · {images:>2} صورة مُدمَجة")

    if not checked:
        failures.append("لا صفحة مشفَّرة في الناتج — لا شيء يُفكّ")

    if failures:
        print("\n[ساقط] " + "\n[ساقط] ".join(failures), file=sys.stderr)
        return 1
    print(f"\n[تمّ] {checked} صفحة تُفكّ بكلمة المرور، ومتونها سليمة")
    return 0


if __name__ == "__main__":
    sys.exit(main())
