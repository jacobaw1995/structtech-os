// Client-safe: no server-only imports. Date-only arithmetic done in UTC
// (not local time) so day-diffing two "YYYY-MM-DD" strings can't be thrown
// off by DST — same class of bug formatDateOnly (coordination/stage.ts)
// exists to avoid for display, this is the arithmetic equivalent.

function toUTCDays(dateStr: string): number {
  const [year, month, day] = dateStr.split("-").map(Number);
  return Date.UTC(year, month - 1, day) / 86_400_000;
}

export type ScheduleBlockStatus = {
  state: "active" | "upcoming";
  label: string;
};

export function scheduleBlockStatus(
  startDate: string,
  endDate: string,
  todayIso: string
): ScheduleBlockStatus {
  const start = toUTCDays(startDate);
  const end = toUTCDays(endDate);
  const today = toUTCDays(todayIso);

  if (today >= start && today <= end) {
    const day = today - start + 1;
    const total = end - start + 1;
    return { state: "active", label: total > 1 ? `Day ${day} of ${total}` : "Today" };
  }

  const daysUntil = start - today;
  return {
    state: "upcoming",
    label: daysUntil === 1 ? "Starts tomorrow" : `Starts in ${daysUntil} days`,
  };
}
