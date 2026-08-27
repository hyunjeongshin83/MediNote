// MediNote AI 도우미 프록시
//
// 이전에는 앱이 브라우저에서 api.anthropic.com 을 직접 부르면서 사용자 각자에게
// Anthropic API 키(sk-ant-…)를 물어봤다. 어르신 사용자가 그 키를 가지고 있을 리
// 없으니 도우미는 사실상 아무에게도 작동하지 않았다. 키를 여기(서버)로 옮긴다.
//
// 필요한 시크릿: ANTHROPIC_API_KEY
// 선택 시크릿:  AI_DAILY_LIMIT (기본 30), AI_EFFORT (기본 medium)

import Anthropic from "npm:@anthropic-ai/sdk@0.72.0";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = "claude-fable-5";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json; charset=utf-8" },
  });

/** 앱이 보내온 사용자 데이터를 근거 블록으로 만든다. 없으면 빈 문자열. */
function contextBlock(ctx: Record<string, unknown> | undefined): string {
  if (!ctx) return "";
  const parts: string[] = [];
  const push = (label: string, v: unknown) => {
    if (v == null) return;
    const s = typeof v === "string" ? v.trim() : JSON.stringify(v);
    if (s && s !== "{}" && s !== "[]") parts.push(`${label}: ${s}`);
  };
  push("나이대·성별 등 프로필", ctx.profile);
  push("복용 중인 약", ctx.meds);
  push("최근 기록한 증상", ctx.symptoms);
  push("지난 예방접종", ctx.vaccinations);
  if (!parts.length) return "";
  return (
    "\n\n<사용자_기록>\n" + parts.join("\n") +
    "\n</사용자_기록>\n" +
    "위 기록은 사용자가 앱에 남긴 것이다. 답변에 관련될 때만 자연스럽게 반영하고, " +
    "기록에 없는 것을 있는 것처럼 말하지 않는다."
  );
}

const SYSTEM_BASE =
  "당신은 한국의 예방접종·복약 안내 도우미입니다. 숙명여대 약학대학 방준석 교수님 연구실이 감수합니다.\n" +
  "\n" +
  "지켜야 할 것:\n" +
  "- 진단하거나 처방하지 않습니다. 정보 제공까지만 하고, 최종 판단은 의사·약사와 상담하도록 안내합니다.\n" +
  "- 질병관리청(KDCA)·예방접종도우미·식약처 등 공신력 있는 출처를 웹검색으로 확인해 답합니다.\n" +
  "- 확실하지 않으면 확실하지 않다고 말합니다. 지어내지 않습니다.\n" +
  "- 응급 징후(호흡곤란, 얼굴·입 부위 붓기, 의식 저하, 심한 어지러움, 반복 구토)가 보이면 " +
  "먼저 119 또는 1339로 연락하도록 안내합니다.\n" +
  "\n" +
  "말투: 어르신이 읽기 쉬운 담백한 존댓말. 짧은 문단과 항목으로 나눕니다. " +
  "전문용어는 쉬운 말로 풀어 씁니다. 답변 끝에 근거 출처를 한 줄로 적습니다.";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, error: "POST 로 호출해 주세요." }, 405);

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    return json({
      ok: false,
      error: "not_configured",
      message: "도우미가 아직 연결되지 않았습니다. 운영자가 ANTHROPIC_API_KEY 를 등록하면 바로 작동합니다.",
    }, 503);
  }

  // verify_jwt 가 켜져 있어 여기까지 온 요청은 서명이 검증된 상태다. 사용자만 꺼낸다.
  const authHeader = req.headers.get("Authorization") ?? "";
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const token = authHeader.replace(/^Bearer\s+/i, "");
  const { data: userData } = await supabase.auth.getUser(token);
  const user = userData?.user;
  if (!user) {
    return json({ ok: false, error: "login_required", message: "도우미는 로그인 후 이용하실 수 있어요." }, 401);
  }

  // 한 사람이 하루에 쓸 수 있는 횟수 — 우리 키로 나가므로 상한이 필요하다.
  const limit = Number(Deno.env.get("AI_DAILY_LIMIT") ?? "30");
  const { data: allowed, error: capErr } = await supabase.rpc("ai_usage_take", {
    p_user: user.id,
    p_limit: limit,
  });
  if (capErr) return json({ ok: false, error: "usage_check_failed", message: capErr.message }, 500);
  if (allowed !== true) {
    return json({
      ok: false,
      error: "daily_limit",
      message: `오늘 도우미 이용 횟수(${limit}회)를 모두 쓰셨어요. 내일 다시 이용해 주세요.`,
    }, 429);
  }

  let body: {
    messages?: Array<{ role: "user" | "assistant"; content: string }>;
    context?: Record<string, unknown>;
    system?: string;
    max_tokens?: number;
    web_search?: boolean;
  };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "bad_json" }, 400);
  }

  const messages = (body.messages ?? []).filter(
    (m) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string" && m.content.trim(),
  );
  if (!messages.length) return json({ ok: false, error: "empty_messages" }, 400);

  const system = (body.system ? String(body.system) : SYSTEM_BASE) + contextBlock(body.context);
  const maxTokens = Math.min(Math.max(Number(body.max_tokens ?? 4000), 256), 16000);
  const effort = (Deno.env.get("AI_EFFORT") ?? "medium") as "low" | "medium" | "high" | "xhigh" | "max";
  const wantSearch = body.web_search !== false;

  const client = new Anthropic({ apiKey });

  // Fable 5 는 사고가 항상 켜져 있어 thinking 을 넘기지 않는다(넘기면 400).
  // temperature 도 받지 않는다. 깊이는 output_config.effort 로만 조절한다.
  const build = (searchType: "web_search_20260209" | "web_search_20250305") => ({
    model: MODEL,
    max_tokens: maxTokens,
    system,
    messages,
    output_config: { effort },
    // 정책상 거절되면 같은 호출 안에서 대체 모델이 이어받는다.
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    ...(wantSearch ? { tools: [{ type: searchType, name: "web_search" }] } : {}),
  });

  let response;
  try {
    response = await client.beta.messages.create(build("web_search_20260209") as never);
  } catch (e) {
    const msg = String((e as Error)?.message ?? e);
    // 새 웹검색 도구를 이 모델이 아직 안 받으면 기본 변형으로 한 번만 다시 시도한다.
    if (wantSearch && /web_search_20260209|tool.*type/i.test(msg)) {
      try {
        response = await client.beta.messages.create(build("web_search_20250305") as never);
      } catch (e2) {
        return json({ ok: false, error: "upstream", message: String((e2 as Error)?.message ?? e2) }, 502);
      }
    } else {
      return json({ ok: false, error: "upstream", message: msg }, 502);
    }
  }

  if (response.stop_reason === "refusal") {
    return json({
      ok: false,
      error: "refusal",
      message: "이 질문에는 답변을 드리기 어렵습니다. 의사·약사와 상담해 주세요.",
    }, 200);
  }

  const text = (response.content ?? [])
    .filter((b: { type: string }) => b.type === "text")
    .map((b: { text: string }) => b.text)
    .join("\n")
    .trim();

  const sources = (response.content ?? [])
    .filter((b: { type: string }) => b.type === "web_search_tool_result")
    .flatMap((b: { content?: unknown }) => (Array.isArray(b.content) ? b.content : []))
    .map((r: { title?: string; url?: string }) => ({ title: r?.title, url: r?.url }))
    .filter((s: { url?: string }) => !!s.url)
    .slice(0, 6);

  const usage = response.usage ?? {};
  await supabase.rpc("ai_usage_record", {
    p_user: user.id,
    p_in: (usage.input_tokens ?? 0) + (usage.cache_read_input_tokens ?? 0),
    p_out: usage.output_tokens ?? 0,
  }).catch(() => {});

  return json({ ok: true, text, sources, model: response.model, served_by: response.model });
});
