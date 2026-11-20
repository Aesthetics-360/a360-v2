/**
 * Library labels for the baked academy videos (IPI-1177, plan 25).
 *
 * The label overlay is keyed by stable YouTube id (never by title). It comes from the model-screened
 * YouTube library review: model screening, not human or medical validation. A video the review
 * excluded or quarantined stays reachable by its existing lesson link (slugs and timestamps are
 * unchanged) but is left out of browse, search, topic citations and the chat's retrieval.
 * A video the overlay does not name is left as it was.
 */

export interface AcademyLabels {
  /** active | excluded | quarantined */
  status: string;
  audience: string;
  clinicalTraining: boolean;
  injectionTraining: boolean;
  patientSafe: boolean;
  /** True when the video may appear in browse and search. */
  browsable: boolean;
}

/** Compact overlay row as stored in data/label-overlay.json. */
export interface OverlayRow {
  s: string;
  a: string;
  c: number;
  i: number;
  p: number;
  b: number;
}

export type Overlay = Record<string, OverlayRow>;

export function labelsFor(
  youtubeId: string | null,
  overlay: Overlay
): AcademyLabels | undefined {
  const row = youtubeId ? overlay[youtubeId] : undefined;
  if (!row) return undefined;
  return {
    status: row.s,
    audience: row.a,
    clinicalTraining: row.c === 1,
    injectionTraining: row.i === 1,
    patientSafe: row.p === 1,
    browsable: row.b === 1,
  };
}

/** Browsable unless the overlay explicitly says otherwise. */
export function isBrowsableVideo(video: {
  labels?: AcademyLabels;
}): boolean {
  return video.labels ? video.labels.browsable : true;
}
