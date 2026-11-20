/**
 * Check the library-label overlay on the baked academy data (IPI-1177).
 * Run from the repo root:  npx tsx scripts/check-academy-labels.ts
 * Exits non-zero on the first failed expectation. Counts only.
 */
import fs from "fs";
import path from "path";
import {
  getAllTopicEntries,
  getBrowsableIllustrations,
  getFeaturedLessons,
  getFullIndex,
  getIndex,
  getModuleVideos,
  getTopicVideos,
  getVideoSummary,
  getVideos,
} from "../lib/academy/server";
import { searchCorpus } from "../lib/academy/search";

let failed = 0;
function expect(name: string, ok: boolean, detail = "") {
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? "  " + detail : ""}`);
  if (!ok) failed++;
}

const overlay = JSON.parse(
  fs.readFileSync(path.join(process.cwd(), "lib/academy/data/label-overlay.json"), "utf8")
) as Record<string, { s: string; b: number; c: number; i: number }>;

const full = getFullIndex().videos;
const browse = getVideos();
const hidden = full.filter((v) => v.labels && !v.labels.browsable);
const hiddenSlugs = new Set(hidden.map((v) => v.slug));
const labelled = full.filter((v) => v.labels);

expect("overlay rows", Object.keys(overlay).length === 407, String(Object.keys(overlay).length));
expect("baked videos unchanged in the full index", full.length === 408, String(full.length));
expect("labelled by YouTube id", labelled.length === 407, String(labelled.length));
expect(
  "active and browsable",
  labelled.filter((v) => v.labels!.status === "active" && v.labels!.browsable).length === 332
);
expect("excluded hidden", hidden.filter((v) => v.labels!.status === "excluded").length === 46);
expect("quarantined hidden", hidden.filter((v) => v.labels!.status === "quarantined").length === 29);
expect(
  "clinical-training matched (264, of which 261 active)",
  labelled.filter((v) => v.labels!.clinicalTraining).length === 264 &&
    labelled.filter((v) => v.labels!.status === "active" && v.labels!.clinicalTraining).length === 261
);
expect(
  "injection-training active",
  labelled.filter((v) => v.labels!.status === "active" && v.labels!.injectionTraining).length === 154
);
expect("browse index drops hidden", browse.length === 408 - hidden.length, String(browse.length));
expect("no hidden slug in browse", browse.every((v) => !hiddenSlugs.has(v.slug)));
expect("getIndex videos equal browse", getIndex().videos.length === browse.length);

const modules = getFullIndex().modules;
let leaked = 0;
for (const m of modules) {
  for (const v of getModuleVideos(m.id)) if (hiddenSlugs.has(v.slug)) leaked++;
}
for (const t of getFullIndex().topics) {
  for (const v of getTopicVideos(t.id)) if (hiddenSlugs.has(v.slug)) leaked++;
}
for (const v of getFeaturedLessons(50)) if (hiddenSlugs.has(v.slug)) leaked++;
expect("no hidden video in module, topic or featured lists", leaked === 0, String(leaked));

let cited = 0;
for (const e of getAllTopicEntries()) for (const c of e.citations) if (hiddenSlugs.has(c.videoSlug)) cited++;
expect("no hidden video in topic citations", cited === 0, String(cited));

let found = 0;
for (const q of ["botulinum", "filler", "cannula", "anatomy", "complication", "lip", "glabella", "dilution"]) {
  for (const s of searchCorpus(q, 200).segments) if (hiddenSlugs.has(s.slug)) found++;
}
expect("no hidden video in search hits", found === 0, String(found));
expect(
  "no hidden video in the illustration gallery",
  getBrowsableIllustrations().every((v) => !v.slug || !hiddenSlugs.has(v.slug))
);
expect(
  "direct lesson links still resolve for hidden videos",
  hidden.every((v) => getVideoSummary(v.slug)?.slug === v.slug)
);
const unlabelled = full.filter((v) => !v.labels);
expect(
  "unmatched videos stay browsable",
  unlabelled.every((v) => browse.some((b) => b.slug === v.slug)),
  `${unlabelled.length} unlabelled`
);

console.log(failed === 0 ? "ALL PASS" : `${failed} FAILED`);
process.exit(failed === 0 ? 0 : 1);
