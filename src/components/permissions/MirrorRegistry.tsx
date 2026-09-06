import { MIRRORS, MIRROR_COUNT, oldestMirrorDerivation } from "@/lib/permissions/model";

/**
 * The mirror count, rendered where the mirrored values are rendered.
 *
 * Everything on the permissions page is either observed live (org_members,
 * through RLS) or copied from a database object the application is not
 * permitted to read. This says how many of the second kind there are, what each
 * one copies, and the command that re-derives it — so a reader can decide how
 * much to trust the page rather than having to assume.
 *
 * It is NOT a staleness indicator, and it says so on screen. Nothing in the
 * browser can check these against the database; the whole reason they are
 * copies is that the reads are refused. Presenting a date as if it were a
 * health check would be exactly the failure this page keeps pointing at
 * elsewhere — a name standing in for a control.
 */
export function MirrorRegistryPanel() {
  return (
    <section className="rounded-lg border border-border bg-surface">
      <div className="border-b border-border px-4 py-3">
        <h2 className="text-sm font-semibold text-text">
          {MIRROR_COUNT} values on this page are copies of the live schema
        </h2>
        <p className="mt-1 text-xs leading-relaxed text-muted">
          Last derived {oldestMirrorDerivation()}. Nothing here checks itself:
          the application is not permitted to read any of the four sources, which
          is why they are copies. Re-derive by running the command against the
          database — <strong className="text-text">re-derive, do not hand-edit</strong>.
          On 2026-09-06 mirror C was found wrong within a day of being written,
          by running its command rather than by reading it.
        </p>
      </div>
      <ul>
        {MIRRORS.map((m) => (
          <li key={m.id} className="border-b border-border px-4 py-3 last:border-0">
            <div className="flex flex-wrap items-baseline gap-x-2">
              <span className="rounded bg-surface2 px-1.5 py-0.5 text-[11px] font-semibold text-text">
                {m.id}
              </span>
              <code className="text-sm font-medium text-text">{m.constant}</code>
              <span className="text-xs text-muted">mirrors {m.mirrors}</span>
            </div>
            <p className="mt-1 text-xs leading-relaxed text-muted">
              Not readable at runtime: {m.unreachableBecause}
            </p>
            {/* Selectable, wrapping, and mono — this is meant to be copied into
                a SQL editor, so it must survive being dragged over with a
                cursor rather than being pretty. */}
            <pre className="mt-1.5 overflow-x-auto whitespace-pre-wrap break-words rounded bg-surface2 px-2 py-1.5 font-mono text-[11px] leading-relaxed text-text">
              {m.rederive}
            </pre>
          </li>
        ))}
      </ul>
    </section>
  );
}
