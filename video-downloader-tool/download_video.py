"""
YouTube / Instagram 영상 다운로더

개인 소장 목적으로 유튜브, 인스타그램 등에서 영상을 다운로드합니다.
내부적으로 yt-dlp 라이브러리를 사용합니다.

주의: 저작권이 있는 콘텐츠를 무단으로 재배포하거나 상업적으로 이용하지 마세요.
      각 플랫폼의 이용약관과 저작권법을 준수하는 범위 내에서 사용하세요.
"""

import os
import sys

try:
    import yt_dlp
except ImportError:
    print("yt-dlp가 설치되어 있지 않습니다. 먼저 requirements.txt를 설치해주세요.")
    print("  pip install -r requirements.txt")
    sys.exit(1)


DOWNLOAD_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "downloads")


def download(url: str, audio_only: bool = False) -> None:
    os.makedirs(DOWNLOAD_DIR, exist_ok=True)

    outtmpl = os.path.join(DOWNLOAD_DIR, "%(title)s.%(ext)s")

    if audio_only:
        ydl_opts = {
            "outtmpl": outtmpl,
            "format": "bestaudio/best",
            "postprocessors": [
                {
                    "key": "FFmpegExtractAudio",
                    "preferredcodec": "mp3",
                    "preferredquality": "192",
                }
            ],
        }
    else:
        ydl_opts = {
            "outtmpl": outtmpl,
            "format": "bestvideo+bestaudio/best",
            "merge_output_format": "mp4",
        }

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        ydl.download([url])


def main() -> None:
    print("=== YouTube / Instagram 영상 다운로더 ===")
    url = input("다운로드할 영상 URL을 입력하세요: ").strip()

    if not url:
        print("URL이 입력되지 않았습니다.")
        return

    choice = input("오디오만 다운로드하시겠습니까? (y/N): ").strip().lower()
    audio_only = choice == "y"

    print("다운로드를 시작합니다...")
    try:
        download(url, audio_only=audio_only)
        print(f"다운로드 완료! 저장 위치: {DOWNLOAD_DIR}")
    except Exception as e:
        print(f"다운로드 중 오류가 발생했습니다: {e}")


if __name__ == "__main__":
    main()
