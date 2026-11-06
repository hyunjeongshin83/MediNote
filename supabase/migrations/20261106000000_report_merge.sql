-- MN-172-2 · kv_put — 증상 기록을 서버에서 합쳐 저장 (대표님 결정 2026-11-06 · 채팅: 가)
-- 「기록하기」는 목록 전체를 한 값으로 덮어써서, 두 기기가 서로의 기록을 모른 채 저장하면 먼저 저장한 쪽 기록이 서버에서 사라졌습니다 (#172).
-- 이 파일은 kv_put 함수 하나만 바꿉니다 — 사용자 데이터 행을 넣거나 지우거나 바꾸지 않습니다. 저장 키·값 모양({records:[…]})·크기 상한(256KB)·
-- 비로그인 g_ 행 상한(MN-148-1)은 그대로이고, medinote:report:* 키의 records 배열만 기존 값과 합집합(키: ts|date|symptom)으로 합쳐 최신순으로 저장합니다.
-- 합친 값이 256KB 를 넘으면 false — 앱은 이미 「기기에 저장했어요」로 다룹니다. 기존 값이 없거나 records 가 배열이 아니면 전과 같이 들어온 값을 그대로 씁니다.
-- 여러 번 돌려도 안전합니다 (create or replace). 실행 권한은 그대로입니다 (anon · authenticated).

create or replace function public.kv_put(p_key text, p_value jsonb) returns boolean
 language plpgsql security definer set search_path to '' as $f$
declare
  u      uuid    := (select auth.uid());
  sz     integer;
  new_len bigint;
  old_len bigint;
  n      bigint;
  total  bigint;
  old_val jsonb;
begin
  if not public.kv_writable(p_key) then return false; end if;
  if p_value is null then return false; end if;

  -- 증상 기록(medinote:report:*)은 서버에서 합집합으로 합쳐 저장한다 (MN-172-2).
  -- 두 기기가 서로의 기록을 모른 채 저장해도 먼저 저장한 쪽 기록이 지워지지 않는다. 지우는 길이 없는 목록이라 합쳐도 되살아나는 기록이 없다.
  -- 같은 열쇠의 쓰기끼리는 차례로 처리한다 (트랜잭션이 끝나면 풀림). 같은 기록의 기준: ts|date|symptom (앱 loadRecords 와 같음).
  if p_key ~ '^medinote:report:' and jsonb_typeof(p_value -> 'records') = 'array' then
    perform pg_advisory_xact_lock(hashtext('medinote:kv_merge:' || p_key));
    select h.value into old_val from public.hub_state h where h.key = p_key;
    if old_val is not null and jsonb_typeof(old_val -> 'records') = 'array' then
      p_value := jsonb_set(p_value, '{records}', (
        select coalesce(jsonb_agg(m.r order by m.ts desc, m.n), '[]'::jsonb)
          from (
            select distinct on (coalesce(t.r ->> 'ts', '') || '|' || coalesce(t.r ->> 'date', '') || '|' || coalesce(t.r ->> 'symptom', ''))
                   t.r as r, coalesce(t.r ->> 'ts', '') as ts, t.n
              from jsonb_array_elements((p_value -> 'records') || (old_val -> 'records')) with ordinality as t(r, n)
             where jsonb_typeof(t.r) = 'object'
             order by coalesce(t.r ->> 'ts', '') || '|' || coalesce(t.r ->> 'date', '') || '|' || coalesce(t.r ->> 'symptom', ''), t.n
          ) m
      ));
    end if;
  end if;
  sz := pg_column_size(p_value);
  if sz > 262144 then return false; end if;  -- 256KB 상한 (전과 같음)

  if left(public.kv_scope(p_key), 2) = 'g_' then
    -- 동시에 여러 요청이 와도 상한을 함께 넘지 않도록 g_ 쓰기끼리만 차례로 (트랜잭션이 끝나면 풀림)
    perform pg_advisory_xact_lock(hashtext('medinote:kv_put:g_'));
    -- 크기는 들어온 값·저장된 값·합계 모두 kv_size 한 기준으로만 셉니다 (#166 Codex 두 번 — 위 kv_size 설명).
    new_len := public.kv_size(p_value);
    select public.kv_size(h.value) into old_len from public.hub_state h where h.key = p_key;
    if not found then
      select count(*) into n from public.hub_state h
       where h.key ~ '^medinote:(report|reports_sent):g_';
      if n >= 20000 then return false; end if;
    end if;
    if new_len > coalesce(old_len, 0) then
      select coalesce(sum(public.kv_size(h.value)), 0) into total from public.hub_state h
       where h.key ~ '^medinote:(report|reports_sent):g_';
      if total - coalesce(old_len, 0) + new_len > 104857600 then return false; end if;  -- 100MB
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
