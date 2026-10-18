-- =====================================================================
-- MediNote 테이블 구조 복사본  (2026-10-17 · 대표님 요청)  — 이 파일은 supabase/migrations/ 로 옮겨 GitHub 연동이 자동 적용합니다 (supabase/README.md)
--
-- 원본  : xaclqvveppvccdpebzsz (CampusTownHub 와 같이 쓰던 프로젝트)  — 이 파일은 거기서 「읽기만」 해서 만들었습니다.
-- 대상  : pczprqckynukavpeylbq (새 프로젝트)
-- 방침  : 옮기기가 아니라 「복사」. 원본은 그대로 두고 양쪽을 함께 유지합니다. 원본에서는 아무것도 지우거나 바꾸지 않았습니다.
--
-- 들어 있는 것   테이블 13개 · 열거형 4개 · 인덱스 · 행 수준 보안(RLS) 정책 · 함수 · 트리거 · 건강 파일 버킷 · metric_defs 기준값 11행
-- 들어 있지 않은 것 (의도적)
--   · 사용자 데이터 행 전부 — health_profiles · hub_state · measurements · profiles 등.
--     건강 데이터를 어느 서버에 두느냐는 동의·법적 검토가 걸립니다 (CLAUDE.md §2·§3). 대표님이 정하신 뒤 따로 옮깁니다.
--   · CampusTownHub 쪽: meetings · meeting_* · tv_demo · hub_snapshots · registry · register() · touch_updated_at ·
--     hub_state 의 medit:% 정책 · hub_state_guard 트리거 · documents 버킷
--   · 엣지 함수(ai-helper)와 그 비밀값 — 파일이 아니라 따로 배포합니다 (아래 「이 파일 뒤에 할 일」)
--
-- 실행 방법: 새 프로젝트 대시보드 → SQL Editor → 이 파일 전체를 붙여 넣고 한 번 실행. 두 번 실행해도 되도록 썼습니다.
-- =====================================================================

-- ---------- 열거형 ----------
do $$ begin
  create type public.observation_status as enum ('registered','preliminary','final','amended','corrected','cancelled','entered-in-error','unknown');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.recording_modality as enum ('sensed','actively_recorded','self_reported','unknown');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.source_channel as enum ('manual','device_ble','platform_sync','public_api','clinician','derived');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.source_grade as enum ('medical_device','clinical_record','wellness','self_reported','unknown');
exception when duplicate_object then null; end $$;

-- ---------- 테이블 ----------
create table if not exists public.metric_defs (
  metric text not null primary key,
  display_ko text not null,
  loinc_code text,
  ucum_unit text not null,
  icon text,
  hard_min double precision,
  hard_max double precision,
  soft_min double precision,
  soft_max double precision
);

create table if not exists public.profiles (
  id uuid not null primary key references auth.users(id) on delete cascade,
  email text,
  name text,
  created_at timestamptz default now()
);

create table if not exists public.health_profiles (
  id uuid not null primary key references auth.users(id) on delete cascade,
  name text,
  birth date,
  sex text,
  blood_type text,
  height_cm numeric,
  weight_kg numeric,
  conditions text,
  allergies text,
  meds text,
  emergency_contact text,
  note text,
  updated_at timestamptz default now(),
  waist_cm numeric,
  smoking text,
  drinking text,
  activity text,
  family_history text,
  past_history text,
  surgery_history text,
  vaccinations text,
  doctor text,
  pharmacy text
);

create table if not exists public.hub_state (
  key text not null primary key,
  value jsonb,
  updated_at timestamptz default now(),
  user_id uuid default auth.uid() references auth.users(id) on delete cascade,
  is_public boolean not null default false
);

create table if not exists public.measurements (
  id uuid not null primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  metric text not null references public.metric_defs(metric),
  value_num double precision,
  value_text text,
  unit text not null,
  effective_time timestamptz not null,
  note text,
  channel public.source_channel not null default 'manual',
  grade public.source_grade not null default 'self_reported',
  modality public.recording_modality not null default 'self_reported',
  status public.observation_status not null default 'final',
  performer_type text not null default 'patient',
  device_name text,
  device_firmware text,
  device_maker text,
  raw_hex text,
  source_ref text,
  client_ts timestamptz,
  received_at timestamptz not null default now(),
  plausibility text[] not null default '{}'::text[],
  created_at timestamptz not null default now(),
  effective_end timestamptz,
  zone_offset_min smallint,
  clock_source text
);

create table if not exists public.prescriptions (
  id text not null primary key,
  data jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  user_id uuid references auth.users(id) on delete set null
);

create table if not exists public.push_subscriptions (
  endpoint text not null primary key,
  sub jsonb,
  uid text,
  created_at timestamptz default now()
);

create table if not exists public.health_files (
  id uuid not null primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null default 'doc',
  title text,
  path text not null,
  mime text,
  size bigint,
  created_at timestamptz default now()
);

create table if not exists public.checkups (
  id uuid not null primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  exam_date date, org text, height_cm numeric, weight_kg numeric, bmi numeric, waist_cm numeric,
  sbp integer, dbp integer, vision_l numeric, vision_r numeric, hearing text, glucose numeric,
  total_chol numeric, hdl numeric, ldl numeric, tg numeric, hb numeric, ast numeric, alt numeric, ggt numeric,
  creatinine numeric, egfr numeric, urine_protein text, chest_xray text, result text, note text,
  created_at timestamptz default now()
);

create table if not exists public.encounters (
  id uuid not null primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  visit_date date, org text, department text, diagnosis text, doctor text, notes text,
  source text default 'manual',
  created_at timestamptz default now()
);

create table if not exists public.medications (
  id uuid not null primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  start_date date, end_date date, drug_name text, dose text, frequency text, days integer, prescriber text,
  source text default 'manual',
  created_at timestamptz default now()
);

create table if not exists public.lifelogs (
  id uuid not null primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  log_date date, steps integer, sleep_min integer, heart_rate integer, sbp integer, dbp integer, weight_kg numeric,
  source text default 'device',
  created_at timestamptz default now(),
  sleep_start timestamptz, sleep_end timestamptz, zone_offset_min smallint
);

create table if not exists public.ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null default ((now() at time zone 'utc')::date),
  calls integer not null default 0,
  in_tokens bigint not null default 0,
  out_tokens bigint not null default 0,
  self_calls integer not null default 0,
  primary key (user_id, day)
);

-- ---------- 인덱스 ----------
create index if not exists checkups_user_idx on public.checkups (user_id, exam_date desc);
create index if not exists encounters_user_idx on public.encounters (user_id, visit_date desc);
create index if not exists health_files_user_idx on public.health_files (user_id, created_at desc);
create index if not exists lifelogs_user_idx on public.lifelogs (user_id, log_date desc);
create unique index if not exists measurements_dedup_idx on public.measurements (user_id, metric, effective_time, value_num) where (status <> 'entered-in-error'::public.observation_status);
create index if not exists measurements_user_metric_time_idx on public.measurements (user_id, metric, effective_time desc);
create index if not exists medications_user_idx on public.medications (user_id, start_date desc);

-- ---------- 기준값 (개인정보 없음) ----------
insert into public.metric_defs (metric, display_ko, loinc_code, ucum_unit, icon, hard_min, hard_max, soft_min, soft_max) values
 ('body_fat','체지방률','41982-0','%','FAT',1,70,null,null),
 ('body_temperature','체온','8310-5','Cel','TEMP',25,45,35,39),
 ('dbp','이완기 혈압','8462-4','mm[Hg]','BP',20,200,50,120),
 ('device_battery','기기 배터리',null,'%','BAT',0,100,null,null),
 ('glucose','혈당','2339-0','mg/dL','GLU',10,900,70,250),
 ('heart_rate','심박수','8867-4','/min','HR',20,300,40,150),
 ('pulse_rate','맥박수','8889-8','/min','PR',20,300,40,150),
 ('respiratory_rate','호흡수','9279-1','/min','RR',4,80,10,24),
 ('sbp','수축기 혈압','8480-6','mm[Hg]','BP',40,300,80,180),
 ('spo2','산소포화도','2708-6','%','SPO2',50,100,90,100),
 ('weight','체중','29463-7','kg','WT',1,400,null,null)
on conflict (metric) do nothing;

-- ---------- 함수 ----------
create or replace function public.kv_scope(p_key text) returns text
 language sql immutable set search_path to '' as $f$
  select substring(
    p_key from
    '^medinote:(?:report|reports_sent):(g_[0-9a-f]{32}|u_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$'
  );
$f$;

create or replace function public.kv_allowed(p_key text) returns boolean
 language sql stable set search_path to '' as $f$
  select case
    when public.kv_scope(p_key) is null            then false
    when left(public.kv_scope(p_key), 2) = 'g_'    then true
    else public.kv_scope(p_key) = 'u_' || coalesce((select auth.uid())::text, '')
  end;
$f$;

create or replace function public.kv_public(p_key text) returns boolean
 language sql immutable set search_path to '' as $f$
  select p_key in ('medinote:cards', 'medinote:rx', 'medit:rx');
$f$;

create or replace function public.kv_readable(p_key text) returns boolean
 language sql stable set search_path to '' as $f$
  select public.kv_public(p_key) or public.kv_allowed(p_key);
$f$;

create or replace function public.kv_writable(p_key text) returns boolean
 language sql stable set search_path to '' as $f$
  select public.kv_allowed(p_key);
$f$;

create or replace function public.kv_get(p_key text) returns jsonb
 language plpgsql stable security definer set search_path to '' as $f$
declare v jsonb;
begin
  if not public.kv_readable(p_key) then return null; end if;
  select value into v from public.hub_state where key = p_key;
  return v;
end $f$;

create or replace function public.kv_get_many(p_keys text[]) returns jsonb
 language plpgsql stable security definer set search_path to '' as $f$
declare out jsonb := '{}'::jsonb; k text; v jsonb;
begin
  if array_length(p_keys, 1) is null or array_length(p_keys, 1) > 20 then return out; end if;
  foreach k in array p_keys loop
    if public.kv_readable(k) then
      select value into v from public.hub_state where key = k;
      if v is not null then out := out || jsonb_build_object(k, v); end if;
    end if;
  end loop;
  return out;
end $f$;

create or replace function public.kv_put(p_key text, p_value jsonb) returns boolean
 language plpgsql security definer set search_path to '' as $f$
declare u uuid := (select auth.uid());
begin
  if not public.kv_writable(p_key) then return false; end if;
  if p_value is null or pg_column_size(p_value) > 262144 then return false; end if;  -- 256KB 상한
  insert into public.hub_state (key, value, updated_at, is_public, user_id)
  values (p_key, p_value, now(), false, u)
  on conflict (key) do update
    set value = excluded.value,
        updated_at = now(),
        user_id = coalesce(excluded.user_id, hub_state.user_id);
  return true;
end $f$;

create or replace function public.kv_put_cards(p_value jsonb) returns boolean
 language plpgsql security definer set search_path to '' as $f$
begin
  -- 원본에는 여기에 「로그인했는가」 검사(auth.uid() is null)가 있었습니다. 실행 권한을 service_role 에게만 주었으므로(아래 grant)
  -- 호출자는 서비스 키·SQL Editor 뿐이고 이들은 사용자 uid 가 없어 그 검사가 항상 false 를 돌려줬습니다 (Codex P2). 권한이 문이므로 검사는 뺍니다.
  if p_value is null or pg_column_size(p_value) > 262144 then return false; end if;
  if jsonb_typeof(p_value -> 'cards') is distinct from 'array' then return false; end if;
  insert into public.hub_state (key, value, updated_at, is_public)
  values ('medinote:cards', p_value, now(), true)
  on conflict (key) do update set value = excluded.value, updated_at = now();
  return true;
end $f$;

create or replace function public.get_prescription(p_id text) returns jsonb
 language plpgsql stable security definer set search_path to '' as $f$
declare v jsonb;
begin
  if p_id is null or length(p_id) < 20 or length(p_id) > 128 then return null; end if;
  if p_id !~ '^[A-Za-z0-9_-]+$' then return null; end if;
  select data into v from public.prescriptions where id = p_id limit 1;
  return v;
end $f$;

create or replace function public.push_subscribe(p_endpoint text, p_sub jsonb) returns boolean
 language plpgsql security definer set search_path to '' as $f$
begin
  if p_endpoint is null or p_endpoint !~ '^https://' then return false; end if;
  if length(p_endpoint) < 24 or length(p_endpoint) > 2048 then return false; end if;
  if p_sub is null or pg_column_size(p_sub) > 8192 then return false; end if;

  insert into public.push_subscriptions (endpoint, sub, uid, created_at)
  values (p_endpoint, p_sub, (select auth.uid())::text, now())
  on conflict (endpoint) do update
    set sub = excluded.sub,
        uid = coalesce(excluded.uid, push_subscriptions.uid);
  return true;
end $f$;

create or replace function public.ai_usage_take(p_user uuid, p_limit integer) returns boolean
 language plpgsql security definer set search_path to '' as $f$
declare n integer;
begin
  if p_user is null then return false; end if;
  insert into public.ai_usage (user_id, day, calls)
  values (p_user, (now() at time zone 'utc')::date, 1)
  on conflict (user_id, day) do update set calls = public.ai_usage.calls + 1
  returning calls into n;
  return n <= greatest(p_limit, 1);
end $f$;

create or replace function public.ai_usage_record(p_user uuid, p_in bigint, p_out bigint) returns void
 language plpgsql security definer set search_path to '' as $f$
begin
  update public.ai_usage
     set in_tokens = in_tokens + coalesce(p_in, 0),
         out_tokens = out_tokens + coalesce(p_out, 0)
   where user_id = p_user and day = (now() at time zone 'utc')::date;
end $f$;

create or replace function public.ai_usage_self(p_user uuid) returns void
 language plpgsql security definer set search_path to '' as $f$
begin
  if p_user is null then return; end if;
  insert into public.ai_usage (user_id, day, self_calls)
  values (p_user, (now() at time zone 'utc')::date, 1)
  on conflict (user_id, day) do update set self_calls = public.ai_usage.self_calls + 1;
end $f$;

create or replace function public.handle_new_user() returns trigger
 language plpgsql security definer set search_path to 'public' as $f$
begin
  insert into public.profiles(id, email, name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)))
  on conflict (id) do nothing;
  return new;
end; $f$;

create or replace function public.measurements_guard() returns trigger
 language plpgsql security definer set search_path to '' as $f$
declare
  d public.metric_defs%rowtype;
  flags text[] := '{}';
begin
  select * into d from public.metric_defs where metric = new.metric;
  if found and new.value_num is not null then
    if d.hard_min is not null and new.value_num < d.hard_min then
      raise exception '%: 값 % 은(는) 물리적으로 불가능한 범위입니다', d.display_ko, new.value_num;
    end if;
    if d.hard_max is not null and new.value_num > d.hard_max then
      raise exception '%: 값 % 은(는) 물리적으로 불가능한 범위입니다', d.display_ko, new.value_num;
    end if;
    if (d.soft_min is not null and new.value_num < d.soft_min)
       or (d.soft_max is not null and new.value_num > d.soft_max) then
      flags := array_append(flags, 'out_of_usual_range');
    end if;
  end if;
  if new.effective_time > now() + interval '1 minute' then
    flags := array_append(flags, 'future_ts');
  end if;
  if new.client_ts is not null
     and abs(extract(epoch from (new.client_ts - now()))) > 600 then
    flags := array_append(flags, 'client_clock_skew');
  end if;
  new.plausibility := flags;
  new.received_at  := now();
  return new;
end $f$;

-- ---------- 트리거 ----------
drop trigger if exists measurements_guard_trg on public.measurements;
create trigger measurements_guard_trg before insert on public.measurements
  for each row execute function public.measurements_guard();

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- 행 수준 보안 (모든 표 켬) ----------
alter table public.metric_defs enable row level security;
alter table public.profiles enable row level security;
alter table public.health_profiles enable row level security;
alter table public.hub_state enable row level security;
alter table public.measurements enable row level security;
alter table public.prescriptions enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.health_files enable row level security;
alter table public.checkups enable row level security;
alter table public.encounters enable row level security;
alter table public.medications enable row level security;
alter table public.lifelogs enable row level security;
alter table public.ai_usage enable row level security;   -- 정책 없음 = 클라이언트 접근 차단, 함수·서비스 키로만

-- ---------- 정책 ----------
drop policy if exists "metric_defs_read" on public.metric_defs;
create policy "metric_defs_read" on public.metric_defs as permissive for select to anon, authenticated using (true);

drop policy if exists "profiles self select" on public.profiles;
drop policy if exists "profiles self insert" on public.profiles;
drop policy if exists "profiles self update" on public.profiles;
create policy "profiles self select" on public.profiles for select to public using (auth.uid() = id);
create policy "profiles self insert" on public.profiles for insert to public with check (auth.uid() = id);
create policy "profiles self update" on public.profiles for update to public using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "hp self select" on public.health_profiles;
drop policy if exists "hp self upsert" on public.health_profiles;
drop policy if exists "hp self update" on public.health_profiles;
create policy "hp self select" on public.health_profiles for select to public using (auth.uid() = id);
create policy "hp self upsert" on public.health_profiles for insert to public with check (auth.uid() = id);
create policy "hp self update" on public.health_profiles for update to public using (auth.uid() = id) with check (auth.uid() = id);

-- hub_state: 원본의 medit:% (CampusTownHub 팀 키) 정책은 뺐습니다.
-- 주의: 앱의 MediNoteSaveRx(MediNote_app.boot.js · 병원·약국 연동이 부르는 입구, 저장소 안에서는 아무도 부르지 않음)는 hub_state 에 medit:rx 를 직접 씁니다.
--       아래 허용 목록은 이 키를 허용하지 않으므로 복사본에서는 그 저장이 거부됩니다. 의도입니다 — kv_public 이 medit:rx 를 「누구나 읽기」로 두고 있어,
--       가입한 누구나 먼저 만든 처방이 모든 이용자에게 돌려질 수 있기 때문입니다 (이슈 #22 MN-22-4). 연동이 필요해지면 서비스 키로 쓰게 하거나 키 설계를 먼저 정합니다.
-- 직접 쓰기(insert · update)는 「본인 보고서 키」(medinote:report:u_<내 uid> · medinote:reports_sent:u_<내 uid>)만 허용합니다 — kv_scope 가 그 모양을 가립니다.
-- 원본은 medinote:% 로 시작하기만 하면 되어, 공개로 읽히는 키(medinote:cards · medinote:rx)를 가입한 누구나 먼저 만들어 모든 이용자에게 돌려줄 수 있었습니다
-- (Codex P1 · 2026-10-17). 키 이름을 하나씩 빼는 대신 허용 목록으로 뒤집었습니다. 앱은 hub_state 에 직접 쓰지 않고 kv_put 함수로만 씁니다.
drop policy if exists "hub_read_own" on public.hub_state;
drop policy if exists "hub_read_public" on public.hub_state;
drop policy if exists "hub_update_own" on public.hub_state;
drop policy if exists "hub_write_own" on public.hub_state;
drop policy if exists "hub_no_self_publish" on public.hub_state;
create policy "hub_read_own" on public.hub_state as permissive for select to authenticated using ((select auth.uid()) = user_id);
create policy "hub_read_public" on public.hub_state as permissive for select to anon, authenticated using (is_public = true);
create policy "hub_update_own" on public.hub_state as permissive for update to authenticated
  using (((select auth.uid()) = user_id) and (public.kv_scope(key) = 'u_' || (select auth.uid())::text))
  with check (((select auth.uid()) = user_id) and (public.kv_scope(key) = 'u_' || (select auth.uid())::text) and (is_public = false));
create policy "hub_write_own" on public.hub_state as permissive for insert to authenticated
  with check (((select auth.uid()) = user_id) and (public.kv_scope(key) = 'u_' || (select auth.uid())::text));
create policy "hub_no_self_publish" on public.hub_state as restrictive for insert to authenticated with check (is_public = false);

drop policy if exists "m_select_own" on public.measurements;
drop policy if exists "m_insert_own" on public.measurements;
drop policy if exists "m_own_rows_only" on public.measurements;
drop policy if exists "m_no_forged_provenance" on public.measurements;
create policy "m_select_own" on public.measurements as permissive for select to authenticated using ((select auth.uid()) = user_id);
create policy "m_insert_own" on public.measurements as permissive for insert to authenticated
  with check (((select auth.uid()) = user_id) and (effective_time <= (now() + interval '00:05:00')) and (effective_time >= (now() - interval '10 years')));
create policy "m_own_rows_only" on public.measurements as restrictive for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "m_no_forged_provenance" on public.measurements as restrictive for insert to authenticated
  with check ((channel = any (array['manual'::public.source_channel, 'device_ble'::public.source_channel]))
          and (grade = any (array['self_reported'::public.source_grade, 'wellness'::public.source_grade]))
          and (performer_type = 'patient') and (status = 'final'::public.observation_status));

drop policy if exists "rx_own" on public.prescriptions;
drop policy if exists "rx_insert_own" on public.prescriptions;
drop policy if exists "rx_update_own" on public.prescriptions;
create policy "rx_own" on public.prescriptions as permissive for select to authenticated using ((select auth.uid()) = user_id);
create policy "rx_insert_own" on public.prescriptions as permissive for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "rx_update_own" on public.prescriptions as permissive for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
-- push_subscriptions: 정책 없음 — push_subscribe() 함수로만 들어옵니다 (원본과 같음)

drop policy if exists "hf self select" on public.health_files;
drop policy if exists "hf self insert" on public.health_files;
drop policy if exists "hf self delete" on public.health_files;
create policy "hf self select" on public.health_files for select to public using (auth.uid() = user_id);
create policy "hf self insert" on public.health_files for insert to public with check (auth.uid() = user_id);
create policy "hf self delete" on public.health_files for delete to public using (auth.uid() = user_id);

drop policy if exists "ck self select" on public.checkups;
drop policy if exists "ck self insert" on public.checkups;
drop policy if exists "ck self update" on public.checkups;
drop policy if exists "ck self delete" on public.checkups;
create policy "ck self select" on public.checkups for select to public using (auth.uid() = user_id);
create policy "ck self insert" on public.checkups for insert to public with check (auth.uid() = user_id);
create policy "ck self update" on public.checkups for update to public using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "ck self delete" on public.checkups for delete to public using (auth.uid() = user_id);

drop policy if exists "en self select" on public.encounters;
drop policy if exists "en self insert" on public.encounters;
drop policy if exists "en self update" on public.encounters;
drop policy if exists "en self delete" on public.encounters;
create policy "en self select" on public.encounters for select to public using (auth.uid() = user_id);
create policy "en self insert" on public.encounters for insert to public with check (auth.uid() = user_id);
create policy "en self update" on public.encounters for update to public using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "en self delete" on public.encounters for delete to public using (auth.uid() = user_id);

drop policy if exists "md self select" on public.medications;
drop policy if exists "md self insert" on public.medications;
drop policy if exists "md self update" on public.medications;
drop policy if exists "md self delete" on public.medications;
create policy "md self select" on public.medications for select to public using (auth.uid() = user_id);
create policy "md self insert" on public.medications for insert to public with check (auth.uid() = user_id);
create policy "md self update" on public.medications for update to public using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "md self delete" on public.medications for delete to public using (auth.uid() = user_id);

drop policy if exists "ll self select" on public.lifelogs;
drop policy if exists "ll self insert" on public.lifelogs;
drop policy if exists "ll self update" on public.lifelogs;
drop policy if exists "ll self delete" on public.lifelogs;
create policy "ll self select" on public.lifelogs for select to public using (auth.uid() = user_id);
create policy "ll self insert" on public.lifelogs for insert to public with check (auth.uid() = user_id);
create policy "ll self update" on public.lifelogs for update to public using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "ll self delete" on public.lifelogs for delete to public using (auth.uid() = user_id);

-- ---------- 권한 (원본에서 읽은 그대로) ----------
-- 함수: 기본으로는 누구나 실행할 수 있으므로 먼저 걷고, 원본처럼 필요한 역할에만 줍니다.
revoke all on function public.ai_usage_take(uuid, integer), public.ai_usage_record(uuid, bigint, bigint), public.ai_usage_self(uuid),
  public.handle_new_user(), public.measurements_guard(), public.get_prescription(text), public.kv_put_cards(jsonb),
  public.kv_get(text), public.kv_get_many(text[]), public.kv_put(text, jsonb), public.push_subscribe(text, jsonb)
  from public, anon, authenticated;
grant execute on function public.ai_usage_take(uuid, integer), public.ai_usage_record(uuid, bigint, bigint), public.ai_usage_self(uuid),
  public.handle_new_user(), public.measurements_guard() to service_role;
-- get_prescription 은 원본과 같이 anon 에게는 주지 않습니다(authenticated 만). 그래서 로그인하지 않은 사람이 ?rx=<처방ID> 링크를 열면 이 함수가 거부되고
-- 앱은 조용히 내장 데모 처방으로 물러납니다(MediNote_app.boot.js loadRx) — 원본도 같은 상태입니다 (Codex P1 · 이슈 #117 MN-117-4 · 결정 대기).
-- 처방 내용은 건강 정보라 익명에게 여는 것은 이 복사본에서 임의로 정하지 않습니다.
grant execute on function public.get_prescription(text) to authenticated, service_role;
-- kv_put_cards 는 원본과 달리 service_role 에게만 줍니다 (Codex P1 · 2026-10-17).
-- 원본은 authenticated 에게도 열려 있어, 이메일로 가입만 한 누구나 모든 이용자에게 공개되는 안내카드(medinote:cards)를 덮어쓸 수 있습니다.
-- 함수 안의 검사는 「로그인했는가」뿐이라 관리자 확인이 아닙니다. 카드는 SQL Editor 또는 서비스 키로만 채웁니다.
-- (seed_cards.html 의 「로그인한 계정으로 갱신」은 이 복사본에서는 동작하지 않습니다 — 관리자 확인 방식을 정한 뒤에.)
grant execute on function public.kv_put_cards(jsonb) to service_role;
grant execute on function public.kv_get(text), public.kv_get_many(text[]), public.kv_put(text, jsonb), public.push_subscribe(text, jsonb)
  to anon, authenticated, service_role;

-- 표: 열 단위 권한까지 원본과 같게 (서버가 채우는 열은 클라이언트가 못 쓰게)
revoke all on public.metric_defs, public.profiles, public.health_profiles, public.hub_state, public.measurements, public.prescriptions,
  public.push_subscriptions, public.health_files, public.checkups, public.encounters, public.medications, public.lifelogs, public.ai_usage
  from anon, authenticated;
grant select on public.metric_defs to anon, authenticated;
grant select, insert, update on public.profiles, public.health_profiles, public.health_files, public.checkups, public.encounters,
  public.medications, public.lifelogs to anon;
grant select, insert, update, delete on public.profiles, public.health_profiles, public.health_files, public.checkups, public.encounters,
  public.medications, public.lifelogs to authenticated;
grant select on public.hub_state to anon;
grant select on public.hub_state to authenticated;
grant insert (is_public, key, updated_at, user_id, value), update (is_public, key, updated_at, user_id, value) on public.hub_state to authenticated;
grant select on public.measurements to authenticated;
-- 앱(toRows)이 보내는 열을 모두 허용합니다. 원본 프로젝트의 권한은 이 중 5개(effective_end · zone_offset_min · clock_source · status · performer_type)가
-- 빠져 있어, MN-18-3 뒤의 앱이 보내는 「읽은 값 클라우드에 저장」은 거기서 거부됩니다 (2026-10-17 확인 · Codex 가 이 PR 에서 짚음).
-- status · performer_type 은 위의 m_no_forged_provenance 정책이 'final' · 'patient' 가 아니면 막으므로 열어도 위조할 수 없습니다.
-- 서버가 채우는 received_at · plausibility · created_at · id 와 source_ref 는 계속 클라이언트가 못 씁니다.
grant insert (channel, client_ts, clock_source, device_firmware, device_maker, device_name, effective_end, effective_time, grade, metric, modality, note,
              performer_type, raw_hex, status, unit, user_id, value_num, value_text, zone_offset_min)
  on public.measurements to authenticated;
grant select on public.prescriptions to authenticated;
grant insert (created_at, data, id, updated_at, user_id), update (created_at, data, id, updated_at, user_id) on public.prescriptions to authenticated;
grant insert (created_at, endpoint, sub, uid), update (created_at, sub, uid) on public.push_subscriptions to anon, authenticated;
-- ai_usage: 클라이언트 권한 없음(위 revoke 로 끝). 서비스 키·함수만.

-- ---------- 건강 파일 버킷 (비공개 · 25MB) ----------
insert into storage.buckets (id, name, public, file_size_limit)
values ('health', 'health', false, 26214400)
on conflict (id) do nothing;

drop policy if exists "health own read" on storage.objects;
drop policy if exists "health own insert" on storage.objects;
drop policy if exists "health own update" on storage.objects;
drop policy if exists "health own delete" on storage.objects;
create policy "health own read"   on storage.objects for select to public using (bucket_id = 'health' and (storage.foldername(name))[1] = (auth.uid())::text);
create policy "health own insert" on storage.objects for insert to public with check (bucket_id = 'health' and (storage.foldername(name))[1] = (auth.uid())::text);
create policy "health own update" on storage.objects for update to public using (bucket_id = 'health' and (storage.foldername(name))[1] = (auth.uid())::text);
create policy "health own delete" on storage.objects for delete to public using (bucket_id = 'health' and (storage.foldername(name))[1] = (auth.uid())::text);

-- =====================================================================
-- 이 파일 뒤에 할 일 (SQL 로는 안 되는 것)
--  1. Authentication → URL Configuration
--       Site URL         https://hyunjeongshin83.github.io/MediNote/MediNote_app.html
--       Redirect URLs    같은 주소 (앱 셸·미리보기 주소가 따로 있으면 그것도)
--  2. Authentication → Providers → Google: 새 프로젝트의 콜백 주소(https://pczprqckynukavpeylbq.supabase.co/auth/v1/callback)를
--     구글 콘솔 「승인된 리디렉션 URI」에 추가하고 클라이언트 ID·시크릿을 넣기 (시크릿은 여기·이슈·카톡에 적지 않습니다)
--  3. 엣지 함수 ai-helper 배포 (supabase/functions/ai-helper) + 비밀값(ANTHROPIC 열쇠) 새 프로젝트에 따로 등록
--  4. 앱을 새 쪽으로 돌리기 (이 순간부터 새 쪽을 씁니다. 그 전까지는 원본을 씁니다) — 웹과 앱이 따로 움직입니다
--       a. medinote.config.js 의 REF · KEY 두 줄 → 새 프로젝트 것 (웹앱)
--       b. python3 tools/build-packaged-app.py 로 안드로이드·iOS 용 화면 세 벌을 다시 만들기 — 빌드 도구가 medinote.config.js 를 화면 안에
--          그대로 박아 넣으므로(MediNote_apps_0706/*/index.html 의 REF · KEY), 이걸 안 하면 앱은 계속 원본을 씁니다 (Codex P1)
--       c. APK · iOS 앱을 다시 빌드해 배포하고 이용자가 업데이트 — 업데이트 전의 앱은 계속 원본에 로그인·저장합니다.
--          그래서 원본은 앱이 모두 넘어올 때까지 살려 둡니다 (양쪽 유지). 웹과 앱이 한동안 다른 쪽을 쓰는 기간이 생기는 점도 감안
--  5. 사용자 데이터를 옮길지는 대표님 결정 (건강 데이터 저장 위치 · 동의 · 방침 문구)
-- =====================================================================
