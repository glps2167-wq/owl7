# owlSeven (개인용 iPhone 앱)

화면을 꺼도, 다른 앱을 써도 백그라운드에서 계속 한국어로 받아쓰는 개인용 앱입니다.
음성 인식은 iPhone 안(iOS 26 SpeechAnalyzer)에서 처리되어 음성이 외부로 나가지 않습니다.

## 기능
- 녹음 시간 설정(30분~8시간, 제한 없음) 후 자동 정지
- 백그라운드·잠금 화면 상태에서도 받아쓰기 유지
- ★ 모르는 말 표시
- "Claude로 보내기": 용어 해설 요청문을 붙여 공유
- 기록 자동 저장: 파일 앱 > 나의 iPhone > owlSeven > 받아쓰기

## 요구 사항
- iOS 26 이상, iPhone 12 이후 모델
- 빌드: GitHub Actions (공개 저장소는 무료)
- 설치: Windows PC + Sideloadly + 무료 Apple ID (7일마다 재서명)

## 빌드 방법
1. 이 폴더 전체를 GitHub **공개(Public)** 저장소에 올립니다.
2. 저장소의 Actions 탭에서 "앱 빌드" 작업이 끝나면 `owlSeven-ipa` 결과물을 내려받습니다.
3. 압축을 풀면 `owlSeven.ipa`가 나옵니다.

## 설치 방법 (Windows)
1. Apple 웹사이트에서 iTunes와 iCloud를 설치합니다(Microsoft Store 버전 X).
2. sideloadly.io에서 Sideloadly를 설치합니다.
3. iPhone을 USB로 연결하고 "이 컴퓨터를 신뢰" 합니다.
4. Sideloadly에 `owlSeven.ipa`를 끌어 놓고 Apple ID를 입력한 뒤 Start.
5. iPhone 설정 > 개인정보 보호 및 보안 > 개발자 모드 켜기(재시동).
6. iPhone 설정 > 일반 > VPN 및 기기 관리 > 내 Apple ID > 신뢰.
7. 7일이 지나면 같은 방법으로 다시 설치합니다(기록은 유지됩니다).
