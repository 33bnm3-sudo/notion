# Windows 11 → Windows 10 우클릭 메뉴 복원 도구

Windows 11에서 새로 바뀐 "축약형" 우클릭(컨텍스트) 메뉴를 Windows 10 시절의 전체 메뉴로 되돌리는 도구입니다.

## 사용 방법 (택1)

### 방법 1: PowerShell 스크립트 (권장)

1. 이 폴더를 Windows 컴퓨터로 복사합니다.
2. PowerShell을 **관리자 권한 없이** 일반 사용자로 실행해도 됩니다 (HKCU만 건드림).
3. 다음 명령으로 실행 정책을 임시 허용합니다 (필요한 경우):
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```
4. Windows 10 스타일 메뉴로 변경:
   ```powershell
   .\Set-ClassicContextMenu.ps1 -Mode Classic
   ```
5. 다시 Windows 11 기본 메뉴로 되돌리고 싶으면:
   ```powershell
   .\Set-ClassicContextMenu.ps1 -Mode Windows11
   ```

스크립트가 실행되면 자동으로 탐색기(`explorer.exe`)를 재시작해서 바로 적용됩니다.

### 방법 2: .reg 파일 더블클릭

- `enable-classic-context-menu.reg` 더블클릭 → Windows 10 스타일 메뉴 적용
- `restore-windows11-context-menu.reg` 더블클릭 → Windows 11 기본 메뉴로 복원

`.reg` 파일 적용 후에는 작업 관리자에서 `탐색기(Windows Explorer)`를 재시작하거나 로그아웃 후 다시 로그인해야 변경 사항이 보입니다.

## 원리

Windows 11의 새 컨텍스트 메뉴는 레지스트리에 다음 CLSID가 등록되어 있는지 여부로 켜고 끌 수 있습니다.

```
HKEY_CURRENT_USER\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32
```

이 키의 기본값을 빈 문자열로 설정하면 탐색기가 예전(Windows 10) 방식의 풀 컨텍스트 메뉴를 사용하도록 강제합니다. 이 키를 삭제하면 원래의 Windows 11 메뉴로 돌아갑니다.

이 방법은 시스템 파일을 수정하지 않고, 현재 로그인한 사용자(HKCU)에만 영향을 주므로 안전하게 되돌릴 수 있습니다. Windows 업데이트로 인해 동작이 바뀔 수도 있습니다.
