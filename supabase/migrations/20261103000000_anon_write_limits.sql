-- =====================================================================
-- 비로그인 쓰기 입구의 상한 · 안내카드 갱신 권한  (2026-11-03 · 대표님 결정)
--
--   MN-117-2   kv_put_cards 는 service_role 만 (로그인한 일반 계정은 못 부름)
--   MN-148-1   kv_put — 비로그인(g_) 키의 개수·합계 크기 상한
--   MN-148-1 · MN-51-6   push_subscribe — 로그인한 사용자만 · 알려진 푸시 서비스 주소만
--
-- 여러 번 돌려도 안전합니다 (create or replace · revoke/grant 는 되풀이해도 같음).
-- 사용자 데이터 행은 넣지도 지우지도 바꾸지도 않습니다. 이미 있는 행(uid 없는 구독 등)은 그대로 둡니다.
-- create or replace 는 함수의 기존 실행 권한을 그대로 둡니다 — kv_put · push_subscribe 는 지금처럼 anon·authenticated 가 부릅니다.
-- =====================================================================

-- ---------- MN-117-2 · kv_put_cards ----------
-- 첫 파일(20261017000000)에서 이미 service_role 에게만 주었습니다. 원본 프로젝트처럼 authenticated 에게 열린 적이 있어도 닫히도록 한 번 더 적습니다.
-- 이 파일은 앱이 쓰는 프로젝트(pczprq…)에만 적용됩니다. 옛 프로젝트(xaclq…)는 SQL Editor 에서 같은 두 줄을 손으로 돌려야 합니다.
revoke execute on function public.kv_put_cards(jsonb) from public, anon, authenticated;
grant execute on function public.kv_put_cards(jsonb) to service_role;

-- ---------- MN-148-1 · kv_put ----------
-- 비로그인 키(medinote:report:g_… · medinote:reports_sent:g_…)는 형식만 맞으면 누구나 새로 만들 수 있어, 공개 열쇠만으로 DB 를 채울 수 있었습니다.
--   · 새 g_ 키는 g_ 행이 20,000 개 이상이면 만들지 않습니다 (이미 있는 키를 덮어쓰는 것은 그대로).
--   · g_ 행의 값 합계가 100MB 를 넘게 되는 쓰기는 받지 않습니다 (크기가 줄거나 같은 덮어쓰기는 그대로).
--   · 행 하나의 상한은 256KB 그대로 둡니다. 64KB 로 낮추자는 안이 있었지만, 앱의 증상 기록은 건수 상한 없이 쌓이므로(MediNote_app.html save)
--     오래 쓴 사람은 64KB 를 넘을 수 있습니다. 넘으면 클라우드 저장이 계속 실패합니다. 개수·합계 상한만으로 「DB 를 채우는 길」은 닫힙니다.
-- 세는 기준은 user_id 가 아니라 키 모양입니다 — 로그인한 계정도 g_ 키를 쓸 수 있고(kv_allowed), 그때는 user_id 가 채워지기 때문입니다.
-- 로그인 키(u_)는 본인 uid 와 맞아야 해 계정마다 두 행뿐이라 그대로 둡니다.
-- 상한에 걸리면 false — 앱은 이미 「기기에 저장했어요(클라우드는 다음에 동기화)」로 다룹니다.
create or replace function public.kv_put(p_key text, p_value jsonb) returns boolean
 language plpgsql security definer set search_path to '' as $f$
declare
  u      uuid    := (select auth.uid());
  sz     integer;
  new_len integer;
  old_len integer;
  n      bigint;
  total  bigint;
begin
  if not public.kv_writable(p_key) then return false; end if;
  if p_value is null then return false; end if;
  sz := pg_column_size(p_value);
  if sz > 262144 then return false; end if;  -- 256KB 상한 (전과 같음)

  if left(public.kv_scope(p_key), 2) = 'g_' then
    -- 동시에 여러 요청이 와도 상한을 함께 넘지 않도록 g_ 쓰기끼리만 차례로 (트랜잭션이 끝나면 풀림)
    perform pg_advisory_xact_lock(hashtext('medinote:kv_put:g_'));
    -- 늘어난 양은 압축 전 글자 길이끼리 견줍니다. 저장된 값은 TOAST 로 압축돼 pg_column_size 가 작게 나오므로,
    -- 들어온 값(압축 전)과 그대로 견주면 같은 기록을 덮어써도 「늘었다」로 잡힙니다 (#166 Codex).
    new_len := octet_length(p_value::text);
    select octet_length(h.value::text) into old_len from public.hub_state h where h.key = p_key;
    if not found then
      select count(*) into n from public.hub_state h
       where h.key ~ '^medinote:(report|reports_sent):g_';
      if n >= 20000 then return false; end if;
    end if;
    if new_len > coalesce(old_len, 0) then
      -- 합계는 실제로 차지하는 크기(압축 후)로 셉니다. 여기에 압축 전 증가분을 더하므로 상한 쪽으로 넉넉하게 막습니다.
      select coalesce(sum(pg_column_size(h.value)), 0) into total from public.hub_state h
       where h.key ~ '^medinote:(report|reports_sent):g_';
      if total + (new_len - coalesce(old_len, 0)) > 104857600 then return false; end if;  -- 100MB
    end if;
  end if;

  insert into public.hub_state (key, value, updated_at, is_public, user_id)
  values (p_key, p_value, now(), false, u)
  on conflict (key) do update
    set value = excluded.value,
        updated_at = now(),
        user_id = coalesce(excluded.user_id, hub_state.user_id);
  return true;
end $f$;

-- ---------- MN-51-6 · MN-148-1 · push_subscribe ----------
-- 로그인하지 않으면 false (uid 없는 구독은 보내는 쪽이 일정을 알 수 없어 쓸 수 없는 행이었습니다).
-- 주소는 브라우저 푸시 서비스로 시작할 때만 받습니다 — Chrome·Edge(Chromium)·삼성 인터넷 = FCM · Firefox = Mozilla · Safari = Apple · 옛 Edge = WNS.
-- 로그인한 사용자의 동작은 전과 같습니다 (길이·크기 검사 · 같은 주소는 덮어씀).
create or replace function public.push_subscribe(p_endpoint text, p_sub jsonb) returns boolean
 language plpgsql security definer set search_path to '' as $f$
declare u text := (select auth.uid())::text;
begin
  if u is null then return false; end if;
  if p_endpoint is null or length(p_endpoint) < 24 or length(p_endpoint) > 2048 then return false; end if;
  if p_endpoint !~ '^https://(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|web\.push\.apple\.com|[a-z0-9-]+\.notify\.windows\.com)/' then
    return false;
  end if;
  if p_sub is null or pg_column_size(p_sub) > 8192 then return false; end if;

  insert into public.push_subscriptions (endpoint, sub, uid, created_at)
  values (p_endpoint, p_sub, u, now())
  on conflict (endpoint) do update
    set sub = excluded.sub,
        uid = coalesce(excluded.uid, push_subscriptions.uid);
  return true;
end $f$;
