// Browser-only (uses Image and canvas). Called from PhotoPicker.
//
// U-W1.16 — A PHOTO LARGER THAN 1 MiB WAS SAVED CORRUPT, SILENTLY. Measured
// 2026-09-15 on the dev server AND on a production build: a data URL sent
// through a server action arrives cut to exactly 1,048,576 characters, and the
// action reports success. check_ins.photos stores the data URL itself, so a
// normal 2-5 MB phone photo would be written as a broken image with no error
// anywhere — found on the one screen a crew uses to prove the work was done.
//
// So the photo is made to fit BEFORE it is sent: scaled to at most 1600px on
// its long side and re-encoded as JPEG, stepping quality down until the data
// URL is under the ceiling. If it still does not fit, the caller is told in
// words and nothing is sent. Photos at volume belong in R2 (a later item);
// this stops the corruption until then.
export const PHOTO_DATA_URL_CEILING = 1_000_000; // characters, under the measured 1,048,576

export type PreparedPhoto = { ok: true; dataUrl: string } | { ok: false; reason: string };

export async function preparePhoto(file: File): Promise<PreparedPhoto> {
  const url = URL.createObjectURL(file);
  try {
    const img = await new Promise<HTMLImageElement>((resolve, reject) => {
      const i = new Image();
      i.onload = () => resolve(i);
      i.onerror = () => reject(new Error("unreadable"));
      i.src = url;
    });
    for (const longSide of [1600, 1200, 900]) {
      const scale = Math.min(1, longSide / Math.max(img.naturalWidth, img.naturalHeight));
      const canvas = document.createElement("canvas");
      canvas.width = Math.max(1, Math.round(img.naturalWidth * scale));
      canvas.height = Math.max(1, Math.round(img.naturalHeight * scale));
      const ctx = canvas.getContext("2d");
      if (!ctx) return { ok: false, reason: "This phone could not prepare the photo. Nothing was saved." };
      ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
      for (const quality of [0.82, 0.7, 0.55]) {
        const dataUrl = canvas.toDataURL("image/jpeg", quality);
        if (dataUrl.length <= PHOTO_DATA_URL_CEILING) return { ok: true, dataUrl };
      }
    }
    return { ok: false, reason: "That photo is too large to save even after shrinking it. Nothing was saved." };
  } catch {
    return { ok: false, reason: "Could not read that photo. Nothing was saved — try again." };
  } finally {
    URL.revokeObjectURL(url);
  }
}
