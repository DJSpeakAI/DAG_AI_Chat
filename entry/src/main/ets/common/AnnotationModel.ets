// ============================================================
// AnnotationModel.ets — Screen annotation data stores (0.152 Screen Annotate)
// ============================================================
// Data stores for the built-in screen annotation feature:
//   - AnnotationDraftStore: the captured screenshot (base64 data URI) passed
//     from ChatPage to AnnotationPage via AppStorageV2 (in-memory, no disk)
//   - AnnotationResultStore: the annotated composite image + the user's
//     chosen action, passed back from AnnotationPage to ChatPage; consumed
//     in NavDestination.onShown when the annotation page pops back
//   - AnnotationPrefStore: one-time usage notice flag (PersistenceV2, own
//     fresh key — per the 0.143 lesson, never add fields to a class whose
//     disk snapshot predates them)
//
// Image strategy: the screenshot and the annotated export are base64 data
// URIs throughout (same pattern as album images in ChatPage.selectImages and
// KnowledgeCard.imageUri). No temp cache files are created, nothing is ever
// written to the system gallery, and images live and die with the message /
// card they belong to — cleaner than a temp-dir + 24h-cleanup scheme and
// immune to the system clearing cacheDir.
//
// Tech stack: HarmonyOS ArkUI V2
//   - @ObservedV2 + @Trace: observable class properties
// ============================================================

import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';

// The captured screenshot handed to the annotation page.
// Written by ChatPage right before pushPath('AnnotationPage');
// read once by AnnotationPage in aboutToAppear.
@ObservedV2
export class AnnotationDraftStore {
  @Trace imageUri: string = ''; // base64 data URI; '' = no pending screenshot
}

// ★ 0.152: connect the in-memory draft store (AppStorageV2 — ephemeral by
// design; a screenshot must never survive a restart as a "pending" draft)
export function connectAnnotationDraft(): AnnotationDraftStore {
  return AppStorageV2.connect(AnnotationDraftStore, 'annotation-draft', () => new AnnotationDraftStore()) as AnnotationDraftStore;
}

// The annotation result handed back to ChatPage.
// action: '' = nothing pending (the guard for onShown fires on every show);
//         'import'   = append image to the current conversation's pendingImages
//         'branch'   = create a child bubble carrying the image
//         'knowledge' = open the knowledge card editor with an AI draft
//                      extracted from the annotated image
// ★ 0.184.0 note: the user's supplementary requirement typed on the
//   annotation page (e.g. "title should be X, definition should focus on Y").
//   For 'knowledge' it steers the AI card draft (image + note sent together);
//   for 'import'/'branch' it is pre-filled into the chat input box.
@ObservedV2
export class AnnotationResultStore {
  @Trace action: string = '';
  @Trace imageUri: string = ''; // annotated composite (base64 data URI)
  @Trace note: string = '';     // ★ 0.184.0：补充要求（'' = 未填写）
}

// ★ 0.152: connect the in-memory result store (consumed immediately in
// ChatPage.onShown, then cleared — no persistence needed)
export function connectAnnotationResult(): AnnotationResultStore {
  return AppStorageV2.connect(AnnotationResultStore, 'annotation-result', () => new AnnotationResultStore()) as AnnotationResultStore;
}

// One-time usage notice flag ("used for screen-annotate questions, never
// records the screen in the background"). PersistenceV2 with a brand-new key
// so the flag survives restarts (the notice is shown once per install, not
// once per session).
@ObservedV2
export class AnnotationPrefStore {
  @Trace notifyShown: boolean = false; // true = notice already acknowledged
}

// ★ 0.152: connect the preference store (PersistenceV2, fresh key
// 'annotation-pref-v1' — 0.143 lesson: fresh keys have no legacy snapshot)
export function connectAnnotationPref(): AnnotationPrefStore {
  return PersistenceV2.connect(AnnotationPrefStore, 'annotation-pref-v1', () => new AnnotationPrefStore()) as AnnotationPrefStore;
}
