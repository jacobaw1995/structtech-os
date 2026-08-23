
-- ============================================================
-- StructTech Audit Leads Table
-- Sales machine lead capture from Revenue Leak Scan funnel
-- ============================================================

CREATE TABLE IF NOT EXISTS audit_leads (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at   TIMESTAMPTZ DEFAULT now(),
  name         TEXT,
  email        TEXT NOT NULL,
  company      TEXT,
  trade        TEXT,
  score        INT,
  risk_level   TEXT,
  monthly_leak INT,
  crew_size    INT,
  top_leaks    TEXT[],
  answers      JSONB,
  source       TEXT DEFAULT 'audit.structtek.com',
  contacted    BOOLEAN DEFAULT false,
  notes        TEXT
);

ALTER TABLE audit_leads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow anon insert" ON audit_leads
  FOR INSERT TO anon WITH CHECK (true);

CREATE POLICY "Allow authenticated read" ON audit_leads
  FOR SELECT TO authenticated USING (true);

CREATE INDEX idx_audit_leads_created ON audit_leads (created_at DESC);
CREATE INDEX idx_audit_leads_risk    ON audit_leads (risk_level);
CREATE INDEX idx_audit_leads_email   ON audit_leads (email);
