-- 익명 로그인(anonymous sign-in)을 켜기 「직전」에 적용합니다 — #55 MN-55-2 · MN-55-3.
-- 익명 사용자도 authenticated 역할이라, 「로그인한 사람 = 팀원」 가정 위에 있는 표는
-- is_anonymous = false 를 요구하는 RESTRICTIVE 정책으로 먼저 막아야 합니다.
-- (2026-10-01 pg_policies 기준: meetings · meeting_sessions · meeting_records · meeting_connections 가
--  authenticated 에게 전부 열려 있고, hub_state 의 medit:% 키를 authenticated 가 읽고 고칠 수 있음)
-- 적용 전까지는 파일일 뿐입니다. 적용은 대표님이 MN-55-3 을 정한 뒤 Supabase MCP apply_migration 으로.

create policy "meetings_no_anon" on public.meetings
  as restrictive for all to authenticated
  using  ((select (auth.jwt()->>'is_anonymous')::boolean) is false)
  with check ((select (auth.jwt()->>'is_anonymous')::boolean) is false);

create policy "meeting_sessions_no_anon" on public.meeting_sessions
  as restrictive for all to authenticated
  using  ((select (auth.jwt()->>'is_anonymous')::boolean) is false)
  with check ((select (auth.jwt()->>'is_anonymous')::boolean) is false);

create policy "meeting_records_no_anon" on public.meeting_records
  as restrictive for all to authenticated
  using  ((select (auth.jwt()->>'is_anonymous')::boolean) is false)
  with check ((select (auth.jwt()->>'is_anonymous')::boolean) is false);

create policy "meeting_connections_no_anon" on public.meeting_connections
  as restrictive for all to authenticated
  using  ((select (auth.jwt()->>'is_anonymous')::boolean) is false)
  with check ((select (auth.jwt()->>'is_anonymous')::boolean) is false);

-- hub_state: 자기 키(medinote:% 등 user_id = auth.uid())는 익명도 됩니다. 팀 키(medit:%)만 막습니다.
create policy "hub_state_medit_no_anon" on public.hub_state
  as restrictive for all to authenticated
  using  (key not like 'medit:%' or (select (auth.jwt()->>'is_anonymous')::boolean) is false)
  with check (key not like 'medit:%' or (select (auth.jwt()->>'is_anonymous')::boolean) is false);
