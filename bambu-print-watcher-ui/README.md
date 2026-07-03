# Bambu Print Watcher GUI

`bambu-print-watcher/watch.py`를 GUI로 감싼 런처입니다. `gemini-image-test-ui` 등 다른 도구와 같은 방식(PowerShell + WinForms)이지만, 감시기는 계속 켜져있는 백그라운드 프로그램이라 **로그를 이 창 안에 보여주는 대신, 별도의 콘솔 창을 새로 띄워서** 거기서 실시간 로그를 봅니다.

## 필요한 것

- Python ([python.org](https://python.org))
- `bambu-print-watcher` 폴더에서 `pip install -r requirements.txt` (paho-mqtt)

## 실행 방법

1. 이 리포를 본인 컴퓨터에 `git pull`
2. `bambu-print-watcher-ui` 폴더의 `run.bat` 더블클릭
3. Printer IP / Serial number / Access code 입력 (찾는 법은 `bambu-print-watcher/README.md` 참고)
4. **Start Watching** 클릭 → 새 콘솔 창이 뜨고 거기서 실시간 로그가 보임
5. 멈추고 싶으면 그 콘솔 창을 닫거나 Ctrl+C

입력한 값은 `%APPDATA%\BambuPrintWatcher\config.json`에 저장돼서 다음에 켤 때 그대로 불러옵니다.

## 검증 관련 참고

이 GUI 자체(PowerShell 부분)는 이 샌드박스에 PowerShell 실행 환경이 없어서 직접 띄워보는 검증은 못 했습니다. 코드는 이미 검증된 다른 테스트 도구들(`gemini-image-test-ui` 등)과 동일한 패턴으로 작성했습니다. 실제로 호출하는 `watch.py`는 별도로 단위 테스트까지 거친 상태입니다.
