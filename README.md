# <img width="35" height="35" alt="뮤넥팅 로고" src="https://github.com/user-attachments/assets/ecdc3c6c-5b7e-4ebe-b087-91c51c6b538b" /> Munecting

<img width="1000" alt="1" src="https://github.com/user-attachments/assets/1c548d7b-6042-4e4d-af61-d3ee09d462fc" />



> Munecting은 Apple Music, Spotify, YouTube Music 사용자가 플랫폼을 바꾸지 않고 플레이리스트를 주고받을 수 있도록 만든 iOS 앱입니다.
> 
> 외부 음악 앱에서 공유한 플레이리스트를 하나의 공통 모델로 정리하고, 
> 받은 사람은 자신이 사용하는 음악 플랫폼에서 곡을 열거나 새로운 플레이리스트로 만들 수 있습니다.

## 주요 기능

### 음악 플랫폼 연결

- Apple Music의 보관함 플레이리스트 조회 및 생성
- Spotify OAuth 로그인, 플레이리스트 조회 및 생성
- YouTube OAuth 로그인, 재생목록 조회 및 생성
- 서로 다른 플랫폼의 곡 정보를 `SharedPlaylist`와 `MusicTrack` 공통 모델로 변환
- 곡별 앨범 아트 표시 및 선택한 플랫폼에서 재생

### 믹스 관리

- 홈에서 친구에게 받은 믹스 확인 및 삭제
- 내 믹스에서 플레이리스트 가져오기, 수정, 삭제 및 공유
- 공유 멘트, 믹스 제목, 커스텀 색상과 아이콘 저장
- SwiftData 기반 로컬 영속 저장

### 음악 공유

- Share Extension으로 외부 음악 앱의 공유 링크 가져오기
- App Group으로 Share Extension과 본 앱 사이의 데이터 전달
- AirDrop을 포함한 iOS 공유 시트로 믹스 전송
- Munecting 딥링크를 통한 수신 데이터 복원

## 사용자 흐름

1. **가져오기** — 내 믹스에서 사용하는 음악 플랫폼을 선택하고 플레이리스트를 가져옵니다.
2. **다듬기** — 믹스 제목, 공유 멘트, 이미지 스타일을 수정합니다.
3. **보내기** — iOS 공유 시트를 통해 친구에게 믹스를 전달합니다.
4. **받기** — 받은 믹스는 홈에 저장되고 수록곡 목록을 확인할 수 있습니다.
5. **이어 듣기** — 원하는 음악 플랫폼을 선택해 곡을 재생하거나 플레이리스트를 생성합니다.

<img width="1000" alt="2" src="https://github.com/user-attachments/assets/7851c722-6846-4f29-93e7-5a9b13586370" />

## 기술 스택

| 영역 | 기술 |
| --- | --- |
| UI | SwiftUI, Observation |
| 로컬 저장 | SwiftData |
| Apple Music | MusicKit |
| Spotify | Spotify iOS SDK, Spotify Web API, OAuth 2.0 PKCE |
| YouTube Music | YouTube Data API, OAuth 2.0 PKCE |
| 앱 간 공유 | Share Extension, App Group, Uniform Type Identifiers |
| 사용자 간 공유 | ShareLink, AirDrop, Custom URL Scheme |
| 동시성 | Swift Concurrency |


<img width="1000" alt="3" src="https://github.com/user-attachments/assets/42e0d7ff-a9a6-487e-baf5-bf7ced617b0b" />


## 구조

```text
Munecting/
├── App/                    # 앱 시작점, 전역 상태, 화면 연결
├── Domain/
│   ├── Models/             # 플랫폼에 독립적인 음악 모델
│   └── Repositories/       # 저장소 및 플랫폼 인터페이스
├── Data/
│   ├── Persistence/        # SwiftData 구현
│   ├── MusicKit/           # Apple Music 연동
│   ├── Spotify/            # Spotify 연동
│   ├── YouTube/            # YouTube Music 연동
│   └── Services/           # 공유, 재생, 앱 설정
├── Features/               # 홈, 내 믹스, 상세, 가져오기 화면
└── DesignSystem/           # 테마와 공통 컴포넌트

MunectingShareExtension/    # 외부 앱 공유 링크 수신
```

플랫폼별 API 코드는 각각의 서비스로 분리하고, 화면에서는 공통 도메인 모델만 사용합니다. 새로운 음악 플랫폼을 추가할 때 기존 화면과 저장 구조의 변경을 최소화하는 것이 핵심 설계 방향입니다.

## 실행 환경

- Xcode 26 이상
- iOS 26 이상
- Apple Developer 계정
- Apple Music 구독 및 MusicKit 권한
- Spotify Developer 앱
- Google Cloud 프로젝트와 YouTube Data API

## 시작하기

1. 저장소를 복제하고 `Munecting.xcodeproj`를 엽니다.
2. 앱과 Share Extension Target의 Team 및 Bundle Identifier를 자신의 값으로 설정합니다.
3. 두 Target에 동일한 App Group을 등록합니다.
4. Apple Developer에서 MusicKit Capability를 활성화합니다.
5. Spotify Dashboard에 앱의 Redirect URI를 등록하고 Client ID를 설정합니다.
6. Google Cloud Console에서 iOS OAuth Client와 YouTube Data API를 설정합니다.
7. 실제 기기를 선택해 빌드합니다.

> OAuth Client ID는 앱을 식별하는 공개 값이지만, Client Secret이나 액세스 토큰은 저장소에 커밋하지 마세요.

## 브랜치 및 커밋 규칙

```text
feat/#1-loginUI
refactor/#53-LoginViewRefactor

[feat/#1] 로그인 화면 구현
[docs/#2] README 작성
```

주요 라벨은 `🥸feat`, `🛠️fix`, `📄docs`, `⚙️setting`, `🤴🏻refactor`, `🤡style`을 사용합니다.

## 현재 상태

핵심 프로토타입과 플랫폼별 연결 흐름을 구현한 단계입니다. 실제 배포 전에는 다음 항목을 추가로 점검해야 합니다.

- Spotify 앱의 Development Mode 해제 및 배포 심사
- Google OAuth 동의 화면의 Production 전환
- Apple Music 권한과 App Group의 배포용 Provisioning Profile 확인
- 플랫폼 간 곡 매칭 정확도와 실패 처리 개선
- 실기기 기반 Share Extension 및 AirDrop 회귀 테스트

## License

별도의 라이선스가 명시되기 전까지 모든 권리는 프로젝트 소유자에게 있습니다.
