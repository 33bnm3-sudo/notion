# 영상 다운로더 (YouTube / Instagram)

유튜브, 인스타그램 등에서 마음에 드는 영상을 개인 소장용으로 다운로드하는 간단한 도구입니다.
내부적으로 [yt-dlp](https://github.com/yt-dlp/yt-dlp)를 사용하며, 그 외 yt-dlp가 지원하는
다양한 사이트(트위터/X, 틱톡, 페이스북 등)에서도 동작합니다.

## 사용법 (Windows)

1. [Python](https://www.python.org/downloads/)이 설치되어 있어야 합니다 (설치 시 "Add to PATH" 체크).
2. `실행.bat` 파일을 더블클릭합니다.
3. 필요한 패키지가 자동으로 설치된 후, 다운로드할 영상의 URL을 입력하라는 안내가 나옵니다.
4. URL을 붙여넣고 Enter를 누르면 다운로드가 시작됩니다.
5. 오디오(음원)만 필요하다면 `y`를 입력하세요.
6. 다운로드가 끝나면 같은 폴더의 `downloads` 폴더에 저장됩니다.

## 수동 실행 (Windows / macOS / Linux 공통)

```bash
pip install -r requirements.txt
python download_video.py
```

## 참고 사항

- 병합된 최고 화질 영상을 만들려면 [ffmpeg](https://ffmpeg.org/download.html)가 설치되어 있으면 좋습니다
  (없어도 대체 포맷으로 다운로드는 가능합니다).
- 인스타그램의 비공개 게시물/스토리는 로그인 정보가 필요할 수 있습니다. 필요 시
  `download_video.py`의 `ydl_opts`에 `cookiesfrombrowser` 옵션을 추가해 브라우저 쿠키를
  활용할 수 있습니다 (yt-dlp 문서 참고).
- 저작권이 있는 콘텐츠는 개인 소장 용도로만 사용하고, 재배포나 상업적 이용은 각 플랫폼의
  이용약관 및 저작권법을 반드시 확인 후 진행하세요.
