# supabase/

새 프로젝트(`pczprqckynukavpeylbq`)의 DB 구조는 **여기 파일이 기준**입니다. main 에 병합되면 Supabase GitHub 연동(Deploy to production)이 `migrations/` 의 새 파일만 순서대로 적용합니다.

```
migrations/   DB 변경. 파일 이름 = <14자리 시각>_<이름>.sql   ← 연동이 읽는 곳
functions/    엣지 함수 소스 (ai-helper) — 자동 배포 대상 아님
policies/     참고용 SQL (anon-guard) — 자동 적용 대상 아님
config.toml   최소 설정 (project_id 만)
```

## 지킬 것

- **이미 병합된 migrations 파일은 고치지 않습니다.** 바꾸려면 새 파일을 더합니다 (연동은 적용한 파일 이름을 기억합니다).
- 파일은 **여러 번 돌려도 안전하게** (`if not exists` · `drop … if exists` · `on conflict`) 씁니다.
- **사용자 데이터 행을 넣거나 지우거나 바꾸는 SQL 은 넣지 않습니다.** 건강 데이터 위치는 동의·법적 검토 사항입니다 (CLAUDE.md §2·§3).
- Auth 설정 · 비밀값 · 엣지 함수 배포는 이 폴더로 안 됩니다 — 대시보드에서 손으로 합니다.
- 열쇠·연결 문자열은 파일에 적지 않습니다.

## 연동을 켜는 곳 (대표님)

pczprq… 대시보드 → Project Settings → Integrations → GitHub → 저장소 `hyunjeongshin83/MediNote` · 브랜치 `main` · 작업 폴더 `.`(저장소 루트) → **Deploy to production** 켜기.
Pro 요금제의 Branching(PR 별 미리보기)은 켜지 않습니다 — 켜면 요금이 붙습니다.
