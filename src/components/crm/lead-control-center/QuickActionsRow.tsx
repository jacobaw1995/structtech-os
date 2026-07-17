import Link from "next/link";

// Call/Text are native tel:/sms: links (SCOPE §13 — Twilio/Gmail
// integration is later). Schedule jumps to the New Lead tab where "Site
// visit scheduled" lives (appointments/Stage 6 isn't built yet — this is
// the fastest path to that field today, not a placeholder). Log Activity
// anchor-scrolls to the notes section (desktop right panel / mobile
// in-flow section share the same #lead-notes id).
export function QuickActionsRow({ orgId, dealId, phone }: { orgId: string; dealId: string; phone: string | null }) {
  const base = `/w/${orgId}/crm?deal=${dealId}`;
  return (
    <div className="grid grid-cols-2 gap-2 sm:grid-cols-2">
      <QuickAction href={phone ? `tel:${phone}` : undefined} label="Call" icon={<PhoneIcon />} />
      <QuickAction href={phone ? `sms:${phone}` : undefined} label="Text" icon={<TextIcon />} />
      <QuickAction href={`${base}&stage=new_lead`} label="Schedule" icon={<CalendarIcon />} />
      <QuickAction href={`${base}#lead-notes`} label="Log Activity" icon={<LogIcon />} />
    </div>
  );
}

function QuickAction({ href, label, icon }: { href?: string; label: string; icon: React.ReactNode }) {
  if (!href) {
    return (
      <div className="flex min-h-14 flex-col items-center justify-center gap-1 rounded-lg border border-border bg-bg px-2 py-3 text-xs font-medium text-muted opacity-50 sm:min-h-0">
        {icon}
        {label}
      </div>
    );
  }
  return (
    <Link
      href={href}
      className="flex min-h-14 flex-col items-center justify-center gap-1 rounded-lg border border-border bg-bg px-2 py-3 text-xs font-medium text-text hover:border-accent hover:text-accent-strong sm:min-h-0"
    >
      {icon}
      {label}
    </Link>
  );
}

function PhoneIcon() {
  return (
    <svg viewBox="0 0 20 20" fill="none" className="h-5 w-5">
      <path
        d="M5 3h2.5l1 4-2 1.5a10 10 0 004.5 4.5l1.5-2 4 1V15a1.5 1.5 0 01-1.5 1.5A12.5 12.5 0 013.5 4.5 1.5 1.5 0 015 3z"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
function TextIcon() {
  return (
    <svg viewBox="0 0 20 20" fill="none" className="h-5 w-5">
      <path d="M3 4h14v9H8l-4 3v-3H3V4z" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
function CalendarIcon() {
  return (
    <svg viewBox="0 0 20 20" fill="none" className="h-5 w-5">
      <rect x="3" y="4" width="14" height="13" rx="1.5" stroke="currentColor" strokeWidth="1.4" />
      <path d="M3 8h14M7 2.5v3M13 2.5v3" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
    </svg>
  );
}
function LogIcon() {
  return (
    <svg viewBox="0 0 20 20" fill="none" className="h-5 w-5">
      <rect x="3" y="3" width="14" height="14" rx="2" stroke="currentColor" strokeWidth="1.4" />
      <path d="M6.5 8.5l2 2 4-4.5" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
