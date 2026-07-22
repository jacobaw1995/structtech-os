import { redirect } from "next/navigation";

// Chunk 5 cutover: the document moved to the canonical /estimating/[id]
// route (no more /document suffix carrying rebuild scaffolding forever).
// This stub only exists so any stale bookmark/link from Chunks 2-4 still
// lands somewhere real instead of 404ing.
export default function EstimateDocumentRedirect({
  params,
}: {
  params: { orgId: string; estimateId: string };
}) {
  redirect(`/w/${params.orgId}/estimating/${params.estimateId}`);
}
