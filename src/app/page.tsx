export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-6 bg-bg px-6">
      <div className="flex flex-col items-center gap-3 text-center">
        <span className="rounded-full bg-accent-soft px-3 py-1 font-mono text-xs uppercase tracking-wide text-accent-strong">
          Week 1 · Foundation scaffold
        </span>
        <h1 className="text-3xl font-semibold text-text">StructTech OS</h1>
        <p className="max-w-md text-sm text-muted">
          Multi-tenant shell — auth, org switching, and entitlement-driven
          nav land next.
        </p>
      </div>

      <div className="flex flex-wrap items-center justify-center gap-3 rounded-lg border border-border bg-surface p-4">
        <div className="rounded-md bg-surface2 px-3 py-2 text-sm text-text">
          surface2
        </div>
        <div className="rounded-md bg-accent px-3 py-2 text-sm text-white">
          accent
        </div>
        <button className="rounded-md bg-accent-strong px-3 py-2 text-sm font-medium text-white">
          accent-strong button
        </button>
        <div className="rounded-md bg-warn-soft px-3 py-2 font-mono text-sm text-text">
          $12,400.00
        </div>
      </div>
    </main>
  );
}
