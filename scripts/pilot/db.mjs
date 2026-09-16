// Read-only database access for the pilot scripts.  Track X, X-W1.18, 2026-09-16.
// The connection string comes from SUPABASE_DB_URL (environment or .env.local) and is
// handed to psql through PG* environment variables, never argv, so it does not show
// in a process list and is never printed. Every statement runs inside BEGIN READ ONLY
// and is rolled back.
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

function fromEnvFile(name) {
  try {
    for (const line of readFileSync('.env.local', 'utf8').split('\n')) {
      const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
      if (m && m[1] === name) return m[2].replace(/^["']|["']$/g, '');
    }
  } catch { /* no file */ }
  return undefined;
}

export function dbAvailable() {
  return Boolean(process.env.SUPABASE_DB_URL || fromEnvFile('SUPABASE_DB_URL'));
}

function pgEnv() {
  const u = new URL(process.env.SUPABASE_DB_URL || fromEnvFile('SUPABASE_DB_URL'));
  return {
    ...process.env,
    PGHOST: u.hostname, PGPORT: u.port || '5432', PGUSER: decodeURIComponent(u.username),
    PGPASSWORD: decodeURIComponent(u.password), PGDATABASE: u.pathname.slice(1) || 'postgres',
    PGSSLMODE: 'require', PGCONNECT_TIMEOUT: '15',
  };
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Run one read-only query and return its single text value.
 * `asUser` (a uuid) runs it as role `authenticated` with that user's JWT claims, so
 * the answer is what RLS lets THAT person see — the property, not a role name.
 */
export function q(sql, { asUser } = {}) {
  if (asUser && !UUID.test(asUser)) throw new Error('asUser must be a uuid');
  const as = asUser
    ? `set local role authenticated; set local request.jwt.claims = '{"sub":"${asUser}","role":"authenticated"}';`
    : '';
  const out = execFileSync('psql', ['-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1', '-c',
    `begin read only; ${as} ${sql}; rollback;`], { env: pgEnv(), encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  return out.trim();
}
