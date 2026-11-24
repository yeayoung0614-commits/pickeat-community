# 픽잇 커뮤니티

식단관리하는 사람들이 익명으로 식단·제품 후기·고민을 나누는 커뮤니티 (14조).

- 정적 사이트: `index.html` + `config.js` (Supabase URL·publishable key) + `vendor/supabase.min.js`
- DB: `supabase/schema.sql`을 Supabase SQL Editor에서 한 번 실행
- 배포: Vercel에서 이 저장소를 Import → Framework Preset "Other" → Deploy

## 카카오 로그인 켜기
1. developers.kakao.com → 내 애플리케이션 → 애플리케이션 추가 (앱 이름 `픽잇`)
2. 플랫폼 → Web 사이트 도메인: `https://pickeat-community.vercel.app`
3. 카카오 로그인 → 활성화 ON, Redirect URI: `https://mpwyukmkibsbqofgwlda.supabase.co/auth/v1/callback`
4. 카카오 로그인 → 동의항목: 닉네임·프로필 사진을 '선택 동의' 이상으로 설정 (이메일은 비즈 앱이 아니면 건너뛰기)
5. REST API 키 복사, 보안 → Client Secret 생성 후 '사용함'
6. Supabase → Authentication → Sign In / Providers → Kakao: Enable, REST API Key, Client Secret 넣고 'Allow users without an email' 켜기 → Save
7. Supabase → Authentication → URL Configuration: Site URL `https://pickeat-community.vercel.app`, Redirect URLs에 `https://pickeat-community.vercel.app/**`
8. `config.js`의 `KAKAO_LOGIN`을 `true`로
