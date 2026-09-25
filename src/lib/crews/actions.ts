"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { classifyCrewError, type CrewHint } from "@/lib/crews/crew-states";

// THE OFFICE SIDE OF THE CREW SCREEN. Track U, U-W1.23, 2026-09-19.
//
// House rules: server actions redirect(), never return data (rule 6); every
// mutation goes through a security-definer RPC (rule 3); getSession() before
// any DB call (rule 1).
//
// EVERY REFUSAL TRAVELS AS A CODE, NEVER AS TEXT (controller ruling
// 2026-09-15). `?e=<hint>` is looked up in CREW_HINT_COPY; an unknown value
// renders nothing. Track S's own hints come back on error.hint, so nothing here
// pattern-matches a message, and nothing here writes a second copy of a refusal
// S has already worded.

function str(formData: FormData, key: string): string {
  const v = formData.get(key);
  return typeof v === "string" ? v : "";
}

function required(formData: FormData, key: string): string {
  const v = str(formData, key);
  if (!v) throw new Error(`missing required field: ${key}`);
  return v;
}

/** "" means "not given". Distinct from a field the caller left out entirely. */
function optional(formData: FormData, key: string): string | null {
  const v = str(formData, key).trim();
  return v.length > 0 ? v : null;
}

function crewsHref(orgId: string, hint?: CrewHint, anchor?: string) {
  const qs = hint ? `?e=${hint}` : "";
  return `/w/${orgId}/coordination/crews${qs}${anchor ? `#${anchor}` : ""}`;
}

async function client() {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");
  return supabase;
}

/** Every action below ends the same way, so the ending is written once. */
function finish(orgId: string, error: { code?: string; hint?: string | null } | null, anchor?: string): never {
  if (error) redirect(crewsHref(orgId, classifyCrewError(error), anchor));
  revalidatePath(`/w/${orgId}/coordination/crews`);
  redirect(crewsHref(orgId, undefined, anchor));
}

// ── PEOPLE ────────────────────────────────────────────────────────────────────

export async function createCrewPerson(formData: FormData) {
  const orgId = required(formData, "orgId");
  const supabase = await client();
  const { error } = await supabase.rpc("create_crew_person", {
    p_org_id: orgId,
    p_full_name: str(formData, "full_name"),
    // OMITTED, NOT NULLED. Every optional argument on these RPCs is
    // `DEFAULT NULL` (read from pg_get_function_arguments 2026-09-19), so
    // leaving a key out sends exactly the NULL that "not given" means — and
    // the generated types say `undefined` for precisely that reason.
    p_phone: optional(formData, "phone") ?? undefined,
    p_preferred_language: optional(formData, "preferred_language") ?? undefined,
    p_skills: splitSkills(str(formData, "skills")) ?? undefined,
    p_has_vehicle: triState(str(formData, "has_vehicle")) ?? undefined,
    p_vehicle_note: optional(formData, "vehicle_note") ?? undefined,
    // A login is attached by EDITING the person, never at create:
    // crew_check_login refuses a login that is not yet a member of the
    // workspace, and the office adds the person before the invite is accepted.
  });
  finish(orgId, error, "people");
}

/**
 * ONLY WHAT CHANGED IS SENT. update_crew_person's contract is "key PRESENT =
 * set (JSON null clears); key ABSENT = leave", so a form that resends every
 * field WRITES every field — and CLAUDE.md rule 15's September amendment is
 * exactly that: a resubmitted value is not a deliberate write. Each input
 * carries a `<name>_was` hidden field holding what was on screen, and a key
 * enters the patch only when the two differ.
 *
 * An empty patch never reaches the database. MEASURED, because the obvious
 * assumption was wrong: `{}` is NOT refused with 'nothing to change' — that
 * raise fires only on a NULL or non-object patch, and `{}` is an object, so it
 * falls through to an UPDATE that sets every column to itself. Harmless, and
 * still not worth a round trip for somebody who pressed Save on a form they
 * did not edit.
 */
export async function updateCrewPerson(formData: FormData) {
  const orgId = required(formData, "orgId");
  const patch: Record<string, unknown> = {};

  const changed = (key: string) => str(formData, key) !== str(formData, `${key}_was`);

  if (changed("full_name")) patch.full_name = str(formData, "full_name");
  if (changed("phone")) patch.phone = optional(formData, "phone");
  if (changed("preferred_language")) patch.preferred_language = optional(formData, "preferred_language");
  if (changed("skills")) patch.skills = splitSkills(str(formData, "skills"));
  if (changed("has_vehicle")) patch.has_vehicle = triState(str(formData, "has_vehicle"));
  if (changed("vehicle_note")) patch.vehicle_note = optional(formData, "vehicle_note");

  if (Object.keys(patch).length === 0) {
    redirect(crewsHref(orgId, undefined, `person-${required(formData, "personId")}`));
  }

  const supabase = await client();
  const { error } = await supabase.rpc("update_crew_person", {
    p_person_id: required(formData, "personId"),
    p_patch: patch as never,
  });
  finish(orgId, error, `person-${str(formData, "personId")}`);
}

export async function setCrewPersonArchived(formData: FormData) {
  const orgId = required(formData, "orgId");
  const supabase = await client();
  const { error } = await supabase.rpc("set_crew_person_archived", {
    p_person_id: required(formData, "personId"),
    p_archived: str(formData, "archived") === "true",
  });
  finish(orgId, error, "people");
}

export async function deleteCrewPerson(formData: FormData) {
  const orgId = required(formData, "orgId");
  const supabase = await client();
  const { error } = await supabase.rpc("delete_crew_person", {
    p_person_id: required(formData, "personId"),
  });
  finish(orgId, error, "people");
}

// ── TIME OFF ──────────────────────────────────────────────────────────────────
// SCOPE §2.8 — recording time off marks a STATE. It removes nobody from a crew,
// refuses no assignment, and hides no control anywhere on this screen.

export async function addUnavailability(formData: FormData) {
  const orgId = required(formData, "orgId");
  const supabase = await client();
  const { error } = await supabase.rpc("add_crew_person_unavailability", {
    p_person_id: required(formData, "personId"),
    p_starts_on: str(formData, "starts_on"),
    p_ends_on: str(formData, "ends_on"),
    p_reason: optional(formData, "reason") ?? undefined,
  });
  finish(orgId, error, `person-${str(formData, "personId")}`);
}

export async function deleteUnavailability(formData: FormData) {
  const orgId = required(formData, "orgId");
  const supabase = await client();
  const { error } = await supabase.rpc("delete_crew_person_unavailability", {
    p_unavailability_id: required(formData, "unavailabilityId"),
  });
  finish(orgId, error, `person-${str(formData, "personId")}`);
}

// ── CREWS ─────────────────────────────────────────────────────────────────────

export async function createCrew(formData: FormData) {
  const orgId = required(formData, "orgId");
  const supabase = await client();
  const { error } = await supabase.rpc("create_crew", {
    p_org_id: orgId,
    p_name: str(formData, "name"),
  });
  finish(orgId, error, "crews");
}

export async function renameCrew(formData: FormData) {
  const orgId = required(formData, "orgId");
  const crewId = required(formData, "crewId");
  // RULE 10 in the surface: a name that did not change is not a rename.
  if (str(formData, "name") === str(formData, "name_was")) {
    redirect(crewsHref(orgId, undefined, `crew-${crewId}`));
  }
  const supabase = await client();
  const { error } = await supabase.rpc("rename_crew", { p_crew_id: crewId, p_name: str(formData, "name") });
  finish(orgId, error, `crew-${crewId}`);
}

export async function setCrewArchived(formData: FormData) {
  const orgId = required(formData, "orgId");
  const supabase = await client();
  const { error } = await supabase.rpc("set_crew_archived", {
    p_crew_id: required(formData, "crewId"),
    p_archived: str(formData, "archived") === "true",
  });
  finish(orgId, error, "crews");
}

export async function deleteCrew(formData: FormData) {
  const orgId = required(formData, "orgId");
  const supabase = await client();
  const { error } = await supabase.rpc("delete_crew", { p_crew_id: required(formData, "crewId") });
  finish(orgId, error, "crews");
}

export async function addCrewMember(formData: FormData) {
  const orgId = required(formData, "orgId");
  const crewId = required(formData, "crewId");
  // U-W1.32 — an unchosen person is a sentence, not a thrown 500. required()
  // would throw here, and a crash is not an answer to "you did not pick anyone".
  if (!optional(formData, "personId")) redirect(crewsHref(orgId, "person_required", `crew-${crewId}`));
  const supabase = await client();
  const { error } = await supabase.rpc("add_crew_member", {
    p_crew_id: crewId,
    p_person_id: required(formData, "personId"),
    p_is_lead: str(formData, "is_lead") === "true",
  });
  finish(orgId, error, `crew-${crewId}`);
}

export async function removeCrewMember(formData: FormData) {
  const orgId = required(formData, "orgId");
  const crewId = required(formData, "crewId");
  const supabase = await client();
  const { error } = await supabase.rpc("remove_crew_member", {
    p_crew_id: crewId,
    p_person_id: required(formData, "personId"),
  });
  finish(orgId, error, `crew-${crewId}`);
}

// ── ASSIGNMENT ────────────────────────────────────────────────────────────────

/**
 * assign_crew_to_work_order returns the resulting STATES (members,
 * vehicle_state, availability_state, unavailable_members) and refuses on none
 * of them. Nothing is read from that return here: the page re-reads
 * crew_assignment_states after the redirect and shows the same states in place,
 * which is where they stay visible rather than flashing past once.
 */
export async function assignCrewToWorkOrder(formData: FormData) {
  const orgId = required(formData, "orgId");
  const crewId = required(formData, "crewId");
  // U-W1.32 — see addCrewMember.
  if (!optional(formData, "workOrderId")) redirect(crewsHref(orgId, "work_order_required", `crew-${crewId}`));
  const supabase = await client();
  const { error } = await supabase.rpc("assign_crew_to_work_order", {
    p_work_order_id: required(formData, "workOrderId"),
    p_crew_id: crewId,
    p_task: optional(formData, "task") ?? undefined,
  });
  finish(orgId, error, `crew-${crewId}`);
}

export async function unassignCrewFromWorkOrder(formData: FormData) {
  const orgId = required(formData, "orgId");
  const crewId = str(formData, "crewId");
  const supabase = await client();
  const { error } = await supabase.rpc("unassign_crew_from_work_order", {
    p_assignment_id: required(formData, "assignmentId"),
  });
  finish(orgId, error, crewId ? `crew-${crewId}` : "crews");
}

// ── SHAPES THE RPCs EXPECT ────────────────────────────────────────────────────

/** Comma-separated in the box, text[] in the column. Empty means "clear it". */
function splitSkills(raw: string): string[] | null {
  const parts = raw
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  return parts.length > 0 ? parts : null;
}

/** has_vehicle is three-valued: "" is NOT RECORDED, and that is not "no". */
function triState(raw: string): boolean | null {
  if (raw === "true") return true;
  if (raw === "false") return false;
  return null;
}
