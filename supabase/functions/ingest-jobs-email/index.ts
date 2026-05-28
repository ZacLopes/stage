// Edge Function: ingest-jobs-email
//
// Recebe webhook do Resend Inbound (emails encaminhados pra um endereço tipo
// `vagas@inbound.stagevagas.app`) e ingere a vaga no banco.
//
// Caso de uso primário: usuário fundador encaminha emails da Polifinance
// (newsletter diária de vagas de finanças). Cada email tem 1 vaga renderizada
// como imagem (PNG/JPG) — não dá pra parsear texto, precisa GPT-4o vision.
//
// Fluxo:
//   1. Resend POSTa metadata (email_id, from, subject, attachments[])
//   2. Verifica svix-signature pra rejeitar webhooks forjados
//   3. Confere se o sender está na allowlist (POLIFINANCE_ALLOWED_SENDERS)
//   4. Busca attachments via Resend API → pega 1ª imagem
//   5. Baixa imagem via download_url pre-signed → base64
//   6. GPT-4o vision extrai JSON estruturado da vaga
//   7. Upsert company (slug='polifinance:<empresa-slug>') + job
//   8. Salva application_method='email' + application_email + subject
//
// Acesso:
//   --no-verify-jwt no deploy. Auth via Svix HMAC do Resend.
//
// Variáveis (supabase secrets):
//   RESEND_API_KEY                  (já existe, usada pelo daily-report)
//   RESEND_INBOUND_WEBHOOK_SECRET   (whsec_... do Resend Dashboard)
//   OPENAI_API_KEY                  (já existe)
//   POLIFINANCE_ALLOWED_SENDERS     (regex JS, default: "polifinance")
//   SUPABASE_URL                    (auto)
//   SUPABASE_SERVICE_ROLE_KEY       (auto)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  corsHeaders,
  getOrCreateCompany,
  inferArea,
  inferJobType,
  jsonResponse,
  normalizeForDedup,
  parseLocation,
} from "../_shared/jobs.ts";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const RESEND_INBOUND_WEBHOOK_SECRET = Deno.env.get("RESEND_INBOUND_WEBHOOK_SECRET") ?? "";
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ALLOWED_SENDERS_RE = new RegExp(
  Deno.env.get("POLIFINANCE_ALLOWED_SENDERS") ?? "polifinance",
  "i",
);

const SOURCE = "polifinance";

// ── Tipos do webhook do Resend ───────────────────────────────────────────────

interface ResendAttachmentMeta {
  id: string;
  filename: string;
  content_type: string;
  content_disposition?: string;
  content_id?: string;
}

interface ResendWebhookPayload {
  type: string; // "email.received"
  created_at: string;
  data: {
    email_id: string;
    created_at: string;
    from: string;
    to: string[];
    subject: string;
    attachments?: ResendAttachmentMeta[];
  };
}

interface ResendAttachmentFull extends ResendAttachmentMeta {
  download_url: string;
  expires_at?: string;
}

// ── Tipo da extração da vaga ─────────────────────────────────────────────────

interface ExtractedJob {
  title: string;
  company_name: string;
  company_description?: string | null;
  location?: string | null;
  work_model?: "presencial" | "hibrido" | "remoto" | null;
  description: string;          // texto plano, com seções (Responsabilidades, Pré-requisitos, etc)
  description_html?: string | null; // HTML pra renderização rica (opcional)
  requirements?: string[] | null;
  benefits?: string[] | null;
  application_email: string;
  application_subject?: string | null;
  deadline?: string | null;     // ISO date YYYY-MM-DD
  area_hint?: string | null;
  seniority_hint?: string | null;
}

// ── Svix signature verification ──────────────────────────────────────────────

/**
 * Verifica assinatura Svix do webhook do Resend.
 *
 * Algoritmo (https://docs.svix.com/receiving/verifying-payloads/how-manual):
 *   signedContent = `${svix-id}.${svix-timestamp}.${rawBody}`
 *   expected = base64(HMAC-SHA256(secret_bytes, signedContent))
 *   svix-signature header = "v1,<sig1> v1,<sig2> ..." (compara contra qualquer)
 *
 * O secret vem como "whsec_<base64>". Os bytes do HMAC são o base64 decodificado.
 */
async function verifySvixSignature(
  rawBody: string,
  headers: Headers,
  secret: string,
): Promise<boolean> {
  const svixId = headers.get("svix-id");
  const svixTimestamp = headers.get("svix-timestamp");
  const svixSignature = headers.get("svix-signature");
  if (!svixId || !svixTimestamp || !svixSignature) return false;

  // Tolerância de timestamp: 5min (proteção contra replay)
  const tsSeconds = Number(svixTimestamp);
  if (!Number.isFinite(tsSeconds)) return false;
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSeconds - tsSeconds) > 300) return false;

  const secretB64 = secret.startsWith("whsec_") ? secret.slice(6) : secret;
  const secretBytes = base64Decode(secretB64);

  const key = await crypto.subtle.importKey(
    "raw",
    secretBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signedContent = `${svixId}.${svixTimestamp}.${rawBody}`;
  const sigBuf = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(signedContent),
  );
  const expectedB64 = base64Encode(new Uint8Array(sigBuf));

  // svix-signature pode ter múltiplas assinaturas separadas por espaço,
  // cada uma no formato "v1,<base64sig>".
  const candidates = svixSignature.split(" ").map((s) => {
    const [version, sig] = s.split(",");
    return version === "v1" ? sig : null;
  }).filter((s): s is string => s !== null);

  return candidates.some((sig) => constantTimeEqual(sig, expectedB64));
}

function base64Decode(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function base64Encode(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// ── Resend API ───────────────────────────────────────────────────────────────

async function listAttachments(emailId: string): Promise<ResendAttachmentFull[]> {
  const res = await fetch(
    `https://api.resend.com/emails/receiving/${emailId}/attachments`,
    { headers: { Authorization: `Bearer ${RESEND_API_KEY}` } },
  );
  if (!res.ok) {
    throw new Error(`Resend list attachments failed: ${res.status} ${await res.text()}`);
  }
  const json = await res.json();
  // Resend retorna { data: [...] } ou só array — defensivo nos dois casos.
  const items = Array.isArray(json) ? json : (json.data ?? json.attachments ?? []);
  return items as ResendAttachmentFull[];
}

async function downloadAsBase64(url: string): Promise<string> {
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Download attachment failed: ${res.status}`);
  }
  const buf = new Uint8Array(await res.arrayBuffer());
  // Chunked encoding pra evitar stack overflow em strings grandes
  let bin = "";
  const CHUNK = 0x8000;
  for (let i = 0; i < buf.length; i += CHUNK) {
    bin += String.fromCharCode.apply(null, Array.from(buf.subarray(i, i + CHUNK)));
  }
  return btoa(bin);
}

// ── OpenAI Vision ────────────────────────────────────────────────────────────

const EXTRACTION_PROMPT = `Você está extraindo dados de uma vaga de emprego brasileira que veio como imagem em uma newsletter de finanças.

Retorne APENAS JSON válido (sem markdown, sem texto antes/depois), no formato:

{
  "title": "Cargo exato como aparece no topo",
  "company_name": "Nome da empresa que está contratando",
  "company_description": "Descrição 'Sobre a empresa' se houver, senão null",
  "location": "Endereço/cidade/estado como aparece, ex: 'São Paulo - SP' ou 'Vila Olímpia, São Paulo - SP'",
  "work_model": "presencial" | "hibrido" | "remoto" | null,
  "description": "Texto plano completo da vaga incluindo seções (Responsabilidades, Pré-requisitos, Diferenciais) com quebras de linha entre seções. Cada bullet em linha separada começando com '• '.",
  "description_html": "Mesmo conteúdo em HTML simples: <h3>Responsabilidades</h3><ul><li>...</li></ul><h3>Pré-requisitos</h3>... etc. Use h3/ul/li/p/strong apenas.",
  "requirements": ["bullet 1", "bullet 2", ...] (lista dos pré-requisitos atomizados, máx 15),
  "benefits": [] (lista de benefícios se mencionados, senão []),
  "application_email": "email pra enviar CV (extrair de 'Enviar CV para:' ou similar)",
  "application_subject": "Assunto sugerido do email, copiando exatamente como aparece (mantenha '[SEU NOME]' literal se aparecer)",
  "deadline": "YYYY-MM-DD ou null (extrair de 'Data limite' ou similar)",
  "area_hint": "uma das: Tecnologia, Finanças, Marketing, Vendas, Recursos Humanos, Operações, Produto, Engenharia, Administrativo, Jurídico, Saúde, Geral",
  "seniority_hint": "estagio" | "trainee" | "clt_junior" | "temporario" | null
}

REGRAS:
- NUNCA invente dados. Se não encontrar um campo, use null (ou [] pra arrays).
- application_email é OBRIGATÓRIO — se a vaga não tem email de candidatura, retorne string vazia "" pra esse campo (vou rejeitar a vaga depois).
- Mantenha pontuação e maiúsculas como na imagem.
- Não traduza nada.`;

async function extractFromImage(
  imageBase64: string,
  contentType: string,
): Promise<ExtractedJob> {
  const dataUrl = `data:${contentType};base64,${imageBase64}`;

  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o",
      temperature: 0.1,
      max_tokens: 2000,
      response_format: { type: "json_object" },
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: EXTRACTION_PROMPT },
            { type: "image_url", image_url: { url: dataUrl, detail: "high" } },
          ],
        },
      ],
    }),
  });

  if (!res.ok) {
    throw new Error(`OpenAI vision failed: ${res.status} ${await res.text()}`);
  }
  const json = await res.json();
  const content = json.choices?.[0]?.message?.content;
  if (!content) throw new Error("OpenAI returned empty content");

  let parsed: ExtractedJob;
  try {
    parsed = JSON.parse(content);
  } catch (e) {
    throw new Error(`OpenAI returned invalid JSON: ${e}\n\nContent: ${content}`);
  }
  return parsed;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function isImage(contentType: string): boolean {
  return contentType.toLowerCase().startsWith("image/");
}

function slugify(s: string): string {
  return normalizeForDedup(s).replace(/\s+/g, "-").slice(0, 80);
}

// ── Handler ──────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const rawBody = await req.text();

  // 1. Verifica assinatura Svix (rejeita se falhar e secret estiver configurado)
  if (RESEND_INBOUND_WEBHOOK_SECRET) {
    const ok = await verifySvixSignature(rawBody, req.headers, RESEND_INBOUND_WEBHOOK_SECRET);
    if (!ok) {
      return jsonResponse({ error: "invalid_signature" }, 401);
    }
  } else {
    console.warn("RESEND_INBOUND_WEBHOOK_SECRET not set — skipping signature verification");
  }

  // 2. Parseia payload
  let payload: ResendWebhookPayload;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  if (payload.type !== "email.received") {
    return jsonResponse({ skipped: "non_received_event", type: payload.type });
  }

  // 3. Valida sender
  const from = payload.data.from ?? "";
  if (!ALLOWED_SENDERS_RE.test(from)) {
    console.log(`Rejected sender: ${from}`);
    return jsonResponse({ skipped: "sender_not_allowed", from });
  }

  // 4. Pega 1ª imagem dos anexos. Polifinance manda 1 imagem; outras fontes
  //    podem ter múltiplas — pegamos a maior heurística futura, MVP usa a 1ª.
  let attachments: ResendAttachmentFull[];
  try {
    attachments = await listAttachments(payload.data.email_id);
  } catch (e) {
    console.error("List attachments failed:", e);
    return jsonResponse({ error: "list_attachments_failed", message: String(e) }, 502);
  }

  const imageAtt = attachments.find((a) => isImage(a.content_type));
  if (!imageAtt) {
    return jsonResponse({
      skipped: "no_image_attachment",
      attachments_count: attachments.length,
    });
  }

  // 5. Baixa imagem
  let imageBase64: string;
  try {
    imageBase64 = await downloadAsBase64(imageAtt.download_url);
  } catch (e) {
    console.error("Download attachment failed:", e);
    return jsonResponse({ error: "download_failed", message: String(e) }, 502);
  }

  // 6. Extrai vaga via GPT-4o vision
  let extracted: ExtractedJob;
  try {
    extracted = await extractFromImage(imageBase64, imageAtt.content_type);
  } catch (e) {
    console.error("Extraction failed:", e);
    return jsonResponse({ error: "extraction_failed", message: String(e) }, 500);
  }

  // 7. Sanidade — vaga sem email de candidatura é descartada
  const email = extracted.application_email?.trim();
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return jsonResponse({
      skipped: "no_application_email",
      extracted_title: extracted.title,
    });
  }
  if (!extracted.title?.trim() || !extracted.company_name?.trim()) {
    return jsonResponse({ skipped: "missing_required_fields" });
  }

  // 8. Upsert no banco
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const companySlug = `${SOURCE}:${slugify(extracted.company_name)}`;
  const companyId = await getOrCreateCompany(
    supabase,
    companySlug,
    extracted.company_name,
    SOURCE,
    {
      description: extracted.company_description ?? null,
    },
  );
  if (!companyId) {
    return jsonResponse({ error: "company_upsert_failed" }, 500);
  }

  const { city, state } = parseLocation(extracted.location ?? "");
  const area = extracted.area_hint?.trim() ||
    inferArea(extracted.title, extracted.description);
  const jobType = extracted.seniority_hint?.trim() ||
    inferJobType(extracted.title);
  const workModel = extracted.work_model ?? "presencial";

  const externalId = payload.data.email_id; // único por email recebido
  const now = new Date().toISOString();

  const jobPayload = {
    source: SOURCE,
    external_id: externalId,
    company_id: companyId,
    title: extracted.title.trim(),
    description: extracted.description ?? "",
    description_html: extracted.description_html ?? null,
    requirements: extracted.requirements ?? [],
    benefits: extracted.benefits ?? [],
    location_city: city,
    location_state: state,
    work_model: workModel,
    job_type: jobType,
    area,
    published_at: payload.data.created_at ?? now,
    deadline: extracted.deadline ?? null,
    last_seen_at: now,
    is_active: true,
    // Email-based application (campos novos)
    application_method: "email",
    application_email: email,
    application_subject: extracted.application_subject ?? null,
    external_url: null, // explicitamente NULL — UI usa application_email
    raw_payload: {
      resend_email_id: payload.data.email_id,
      resend_subject: payload.data.subject,
      resend_from: from,
      attachment_filename: imageAtt.filename,
      extracted_at: now,
    },
  };

  const { data: jobData, error: jobErr } = await supabase
    .from("jobs")
    .upsert(jobPayload, { onConflict: "source,external_id" })
    .select("id")
    .single();

  if (jobErr) {
    console.error("Job upsert failed:", jobErr);
    return jsonResponse({ error: "job_upsert_failed", message: jobErr.message }, 500);
  }

  // Log estruturado pro `supabase functions logs ingest-jobs-email --tail`.
  // ai_generation_logs exige user_id NOT NULL, então não cabe aqui (vagas
  // ingeridas via email não pertencem a um usuário específico).
  console.log(JSON.stringify({
    event: "job_ingested",
    source: SOURCE,
    job_id: jobData.id,
    company: extracted.company_name,
    title: extracted.title,
    email_id: payload.data.email_id,
  }));

  return jsonResponse({
    ok: true,
    job_id: jobData.id,
    company: extracted.company_name,
    title: extracted.title,
    application_email: email,
  });
});
