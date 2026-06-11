import { useState } from 'react';
import { Search, Save, ShieldCheck } from 'lucide-react';
import { invokeAdmin } from '../../lib/api';
import { Badge, Button, Card, Field, Input } from '../../components/ui';

// Fase 1 T1.8 — busca de candidatos para a operação concierge de shortlists.
// Fluxo: filtros → busca (admin-candidates-search) → seleção → consent por
// candidato (admin-users update_consent, com nota de evidência) → salvar
// como lista (candidate_list_requests + items 'pending') → aprovação e
// export CSV consent-gated seguem no fluxo existente da página Listas.

interface Candidate {
  userId: string;
  name: string;
  email: string;
  course: string;
  semester: string;
  city: string | null;
  state: string | null;
  completeness: number;
  skills: string[];
  institutions: string[];
  consentStatus: 'not_asked' | 'granted' | 'denied' | 'revoked';
}

interface SearchResponse {
  total: number;
  offset: number;
  limit: number;
  candidates: Candidate[];
}

const consentTone: Record<Candidate['consentStatus'], 'green' | 'amber' | 'red' | 'slate'> = {
  granted: 'green',
  denied: 'red',
  revoked: 'red',
  not_asked: 'slate',
};

export function CandidatesSearchPage() {
  const [course, setCourse] = useState('');
  const [institutionText, setInstitutionText] = useState('');
  const [city, setCity] = useState('');
  const [skillsRaw, setSkillsRaw] = useState('');
  const [minCompleteness, setMinCompleteness] = useState('');
  const [activeDays, setActiveDays] = useState('');
  const [hasCv, setHasCv] = useState(false);

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<SearchResponse | null>(null);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [saving, setSaving] = useState(false);
  const [savedMsg, setSavedMsg] = useState<string | null>(null);

  async function runSearch(offset = 0) {
    setLoading(true);
    setError(null);
    setSavedMsg(null);
    try {
      const filters: Record<string, unknown> = {};
      if (course.trim()) filters.course = course.trim();
      if (institutionText.trim()) filters.institutionText = institutionText.trim();
      if (city.trim()) filters.city = city.trim();
      const skills = skillsRaw.split(',').map((s) => s.trim()).filter(Boolean);
      if (skills.length > 0) filters.skills = skills;
      const mc = Number.parseInt(minCompleteness, 10);
      if (Number.isFinite(mc) && mc > 0) filters.minCompleteness = mc;
      const ad = Number.parseInt(activeDays, 10);
      if (Number.isFinite(ad) && ad > 0) filters.activeWithinDays = ad;
      if (hasCv) filters.hasCv = true;

      const data = await invokeAdmin<SearchResponse>('admin-candidates-search', {
        action: 'search',
        filters,
        limit: 25,
        offset,
      });
      setResult(data);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }

  function toggle(userId: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      return next;
    });
  }

  async function markConsent(c: Candidate) {
    const reason = window.prompt(
      `Nota de evidência do consent de ${c.name || c.email}\n` +
        '(ex.: "confirmou por WhatsApp em 10/06"):',
    );
    if (!reason || !reason.trim()) return;
    try {
      await invokeAdmin('admin-users', {
        action: 'update_consent',
        id: c.userId,
        consent: {
          status: 'granted',
          reason: reason.trim(),
          grantedVia: 'whatsapp',
          scope: ['contact_info'],
        },
      });
      setResult((prev) =>
        prev
          ? {
              ...prev,
              candidates: prev.candidates.map((x) =>
                x.userId === c.userId ? { ...x, consentStatus: 'granted' } : x,
              ),
            }
          : prev,
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }

  async function saveList() {
    const title = window.prompt('Título da shortlist (ex.: "Estágio Financeiro — Cliente X"):');
    if (!title || !title.trim()) return;
    setSaving(true);
    setError(null);
    try {
      const data = await invokeAdmin<{ request: { id: string }; itemCount: number }>(
        'admin-candidates-search',
        { action: 'save_list', title: title.trim(), userIds: [...selected] },
      );
      setSavedMsg(
        `Lista criada com ${data.itemCount} candidato(s). ` +
          'Aprovação e export CSV (consent-gated) na aba Listas.',
      );
      setSelected(new Set());
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          <Field label="Curso">
            <Input value={course} onChange={(e) => setCourse(e.target.value)} placeholder="ADS, Direito..." />
          </Field>
          <Field label="Instituição">
            <Input value={institutionText} onChange={(e) => setInstitutionText(e.target.value)} placeholder="FATEC, USP..." />
          </Field>
          <Field label="Cidade">
            <Input value={city} onChange={(e) => setCity(e.target.value)} placeholder="São Paulo" />
          </Field>
          <Field label="Skills (vírgula = E)">
            <Input value={skillsRaw} onChange={(e) => setSkillsRaw(e.target.value)} placeholder="excel, sql" />
          </Field>
          <Field label="Completeness ≥">
            <Input value={minCompleteness} onChange={(e) => setMinCompleteness(e.target.value)} placeholder="40" />
          </Field>
          <Field label="Ativo nos últimos (dias)">
            <Input value={activeDays} onChange={(e) => setActiveDays(e.target.value)} placeholder="14" />
          </Field>
          <Field label="Tem CV/experiências">
            <label className="flex h-9 items-center gap-2 text-sm text-slate-600">
              <input type="checkbox" checked={hasCv} onChange={(e) => setHasCv(e.target.checked)} />
              somente com CV
            </label>
          </Field>
          <div className="flex items-end">
            <Button onClick={() => runSearch(0)} disabled={loading}>
              <Search className="mr-1 h-4 w-4" />
              {loading ? 'Buscando…' : 'Buscar'}
            </Button>
          </div>
        </div>
      </Card>

      {error && <Card className="border-red-200 bg-red-50 text-sm text-red-700">{error}</Card>}
      {savedMsg && <Card className="border-green-200 bg-green-50 text-sm text-green-700">{savedMsg}</Card>}

      {result && (
        <Card>
          <div className="mb-3 flex items-center justify-between">
            <div className="text-sm text-slate-600">
              {result.total} candidato(s) · mostrando {result.candidates.length} · {selected.size} selecionado(s)
            </div>
            <Button onClick={saveList} disabled={selected.size === 0 || saving} variant="secondary">
              <Save className="mr-1 h-4 w-4" />
              {saving ? 'Salvando…' : 'Salvar como lista'}
            </Button>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-left text-xs uppercase text-slate-400">
                  <th className="py-2 pr-2"></th>
                  <th className="py-2 pr-4">Candidato</th>
                  <th className="py-2 pr-4">Curso</th>
                  <th className="py-2 pr-4">Instituição</th>
                  <th className="py-2 pr-4">Cidade</th>
                  <th className="py-2 pr-4">Skills</th>
                  <th className="py-2 pr-4">Compl.</th>
                  <th className="py-2 pr-4">Consent</th>
                </tr>
              </thead>
              <tbody>
                {result.candidates.map((c) => (
                  <tr key={c.userId} className="border-b last:border-0">
                    <td className="py-2 pr-2">
                      <input
                        type="checkbox"
                        checked={selected.has(c.userId)}
                        onChange={() => toggle(c.userId)}
                      />
                    </td>
                    <td className="py-2 pr-4">
                      <div className="font-medium text-slate-800">{c.name || '—'}</div>
                      <div className="text-xs text-slate-400">{c.email}</div>
                    </td>
                    <td className="py-2 pr-4">{c.course || '—'}</td>
                    <td className="py-2 pr-4">{c.institutions.join(', ') || '—'}</td>
                    <td className="py-2 pr-4">{c.city || '—'}</td>
                    <td className="py-2 pr-4 text-xs">{c.skills.join(', ') || '—'}</td>
                    <td className="py-2 pr-4">{c.completeness}</td>
                    <td className="py-2 pr-4">
                      <div className="flex items-center gap-2">
                        <Badge tone={consentTone[c.consentStatus]}>{c.consentStatus}</Badge>
                        {c.consentStatus !== 'granted' && (
                          <button
                            type="button"
                            title="Registrar consent (com nota de evidência)"
                            onClick={() => markConsent(c)}
                            className="text-slate-400 hover:text-green-600"
                          >
                            <ShieldCheck className="h-4 w-4" />
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {result.total > result.offset + result.candidates.length && (
            <div className="mt-3">
              <Button variant="ghost" onClick={() => runSearch(result.offset + result.limit)} disabled={loading}>
                Próxima página
              </Button>
            </div>
          )}
        </Card>
      )}
    </div>
  );
}
