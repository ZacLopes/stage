export type AdminRole = 'owner' | 'analyst';

export interface AdminUser {
  email: string;
  role: AdminRole;
}

export interface ApiPage<T> {
  page: number;
  pageSize: number;
  total: number;
  [key: string]: T[] | number;
}

export interface EmployerClient {
  id: string;
  name: string;
  website?: string | null;
  contactName?: string | null;
  contactEmail?: string | null;
  status: 'prospect' | 'active' | 'paused' | 'archived';
  notes?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface AdminJob {
  id: string;
  title: string;
  company?: { name: string; logoUrl?: string | null } | null;
  area?: string | null;
  locationCity?: string | null;
  locationState?: string | null;
  workModel?: string | null;
  jobType?: string | null;
  isActive: boolean;
  source?: string | null;
  externalUrl?: string | null;
  applicationMethod?: string | null;
  publishedAt?: string | null;
  ageDays?: number | null;
  requirements: string[];
  description?: string | null;
  metrics: { likes: number; applies: number; avgScore: number };
}

export interface AdminCandidate {
  id: string;
  name: string;
  email: string;
  phone: string;
  city?: string | null;
  state?: string | null;
  headline?: string | null;
  completenessScore: number;
  dataSharingConsent: 'not_asked' | 'granted' | 'denied' | 'revoked';
  aiConsent: boolean;
  skills: string[];
  desiredTitles: string[];
  activity: { likes: number; rejects: number; applies: number };
  createdAt: string;
}

export interface CandidateListRequest {
  id: string;
  client_id?: string | null;
  source_job_id?: string | null;
  title: string;
  area?: string | null;
  status: 'draft' | 'ranking' | 'review' | 'exported' | 'archived';
  min_score: number;
  created_at: string;
  employer_clients?: { name: string } | null;
}

export interface CandidateListItem {
  id: string;
  userId: string;
  rank: number;
  score: number;
  status: 'pending' | 'approved' | 'rejected' | 'exported';
  exportable: boolean;
  notes?: string | null;
  outcome?: 'interviewing' | 'interviewed' | 'hired' | 'not_selected' | 'no_response' | null;
  outcomeNote?: string | null;
  scoreBreakdown: Array<{ label: string; points: number; detail: string }>;
  candidate: {
    name: string;
    email: string;
    city?: string | null;
    state?: string | null;
    headline?: string | null;
    skills: string[];
    desiredTitles: string[];
    consentStatus: string;
  } | null;
}
