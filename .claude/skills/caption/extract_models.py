"""MakerWorld에서 저장한 HTML 파일에서 모델 정보와 대표 이미지를 뽑아 JSON으로 출력합니다.

사용법:
    python3 -I extract_models.py --img-dir <이미지 저장 폴더> a.html b.html ...

출력 (표준 출력, JSON 배열):
    [{"file", "name", "designer", "url", "rating", "ratings", "likes",
      "print_hours", "images": [이미지 경로...]}, ...]
정보를 찾지 못한 파일은 {"file", "error"}로 표시됩니다.
"""

import argparse
import base64
import html
import json
import os
import re
import sys
from urllib.parse import urlsplit, urlunsplit

META_RE = re.compile(r"<script[^>]*>\s*(\{.*?\})\s*</script>", re.S)
TITLE_RE = re.compile(r"<title>(.*?)</title>", re.S)
IMG_RE = re.compile(r'<img[^>]*src="data:image/(\w+);base64,([^"]+)"')
TITLE_SUFFIX = " - Free 3D Print Model - MakerWorld"


def clean_url(url):
    # ?from=search 같은 쿼리와 #profileId 같은 조각을 뗀다
    parts = urlsplit(url)
    return urlunsplit((parts.scheme, parts.netloc, parts.path, "", ""))


def find_meta(text):
    for m in META_RE.finditer(text):
        try:
            data = json.loads(m.group(1))
        except ValueError:
            continue
        if isinstance(data, dict) and "name" in data and "by" in data:
            return data
    return None


def extract(path, img_dir, max_images):
    with open(path, encoding="utf-8", errors="ignore") as f:
        text = f.read()

    meta = find_meta(text)
    if meta is None:
        title = TITLE_RE.search(text)
        if not title:
            return {"file": path, "error": "모델 정보를 찾지 못했습니다"}
        name = html.unescape(title.group(1).strip()).removesuffix(TITLE_SUFFIX)
        return {"file": path, "name": name, "error": "디자이너 정보를 찾지 못했습니다"}

    stem = re.sub(r"[^\w-]+", "_", meta["name"]).strip("_")[:40] or "model"
    images = []
    for i, m in enumerate(IMG_RE.finditer(text)):
        if i >= max_images:
            break
        out = os.path.join(img_dir, f"{stem}_{i}.{m.group(1)}")
        with open(out, "wb") as f:
            f.write(base64.b64decode(m.group(2)))
        images.append(out)

    return {
        "file": path,
        "name": meta["name"],
        "designer": meta["by"],
        "url": clean_url(meta.get("url", "")),
        "rating": meta.get("rating"),
        "ratings": meta.get("ratings"),
        "likes": meta.get("likes"),
        "print_hours": meta.get("hours"),
        "images": images,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("files", nargs="+", help="MakerWorld에서 저장한 HTML 파일")
    parser.add_argument("--img-dir", required=True, help="대표 이미지를 저장할 폴더")
    parser.add_argument("--images", type=int, default=2, help="모델마다 저장할 이미지 수 (기본 2)")
    args = parser.parse_args()

    os.makedirs(args.img_dir, exist_ok=True)
    results = [extract(p, args.img_dir, args.images) for p in args.files]
    json.dump(results, sys.stdout, ensure_ascii=False, indent=2)
    print()


if __name__ == "__main__":
    main()
