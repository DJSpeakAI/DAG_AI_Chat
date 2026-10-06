// ============================================================
// KnowledgeModel.ets — Knowledge bank data model (0.146 Knowledge Bank)
// ============================================================
// Data structures for the personal knowledge bank feature:
//   - KnowledgeCard: a single knowledge card (id / title / definition / imageUri / createdAt)
//   - KnowledgeBankStore: PersistenceV2 top-level container holding KnowledgeCard[]
//   - KnowledgeQueryResult: plain result shape returned by the AI card-draft API
//
// Tech stack: HarmonyOS ArkUI V2
//   - @ObservedV2 + @Trace: observable class properties
//   - @Type: required by PersistenceV2 for nested custom class arrays
//
// Documented deviations from the 0.146 spec (see change notes):
//   - reviewInfo (spaced-repetition scheduling) is NOT included: no such
//     engine exists yet (the 0.145 word bank has none either); the review
//     logic shared by both banks is the random-pick shown in the AI bubble
//     footer. The field can be added in a later iteration without breaking
//     persistence (PersistenceV2 restores missing properties from defaults).
//   - imageUri stores a base64 data URI (the project-wide pattern for image
//     messages, see ChatPage.selectImages) instead of a sandbox file path —
//     it survives restarts with zero file management; '' means no image and
//     the image area is simply not rendered.
//   - definition is stored as plain text; LaTeX source is preserved as-is
//     but not rendered (ArkUI Text has no LaTeX engine).
// ============================================================

import { Type, AppStorageV2 } from '@kit.ArkUI'; // @Type decorator: required by PersistenceV2 nested class arrays; ★ 0.200.0 AppStorageV2（CardImportStore）

// A single knowledge card stored in the knowledge bank
@ObservedV2
export class KnowledgeCard {
  @Trace id: string = '';          // unique card id
  @Trace title: string = '';       // card title (concept name)
  @Trace definition: string = '';  // card body definition (LaTeX source preserved as plain text)
  @Trace imageUri: string = '';    // base64 data URI; '' = no image (image area not rendered)
  @Trace createdAt: number = 0;    // creation timestamp (ms)
  // ★ 0.188.0: memory-algorithm state (same 4 fields as WordItem; hidden from users;
  // spec in docs/0.165+/0.187.0 记忆算法与复习系统.md)
  @Trace strength: number = 0;     // 记忆强度 S（天，浮点）；0 = 从未评分（新卡标记）
  @Trace reviewCount: number = 0;  // 展示复习次数（展示即复习——被动计数，评分不重复计）
  @Trace lastReviewAt: number = 0; // 上次展示复习时间戳（ms）
  @Trace nextReviewAt: number = 0; // 计划下次复习时间戳（ms）；0 = 新卡，视为已到期

  // All params have defaults so the class satisfies TypeConstructor<T> (new (): T),
  // which @Type requires for PersistenceV2 nested-class re-creation from disk.
  // ★ 0.188.0: 4 memory fields appended at the tail — legacy 5-arg call sites unchanged.
  constructor(id: string = '', title: string = '', definition: string = '', imageUri: string = '', createdAt: number = 0,
    strength: number = 0, reviewCount: number = 0, lastReviewAt: number = 0, nextReviewAt: number = 0) {
    this.id = id;
    this.title = title;
    this.definition = definition;
    this.imageUri = imageUri;
    this.createdAt = createdAt;
    this.strength = strength;
    this.reviewCount = reviewCount;
    this.lastReviewAt = lastReviewAt;
    this.nextReviewAt = nextReviewAt;
  }
}

// PersistenceV2 top-level container. PersistenceV2 requires the persisted
// root to be a class object, and nested custom-class array properties MUST
// be decorated with @Type so items are re-created as KnowledgeCard
// instances when restored from disk.
@ObservedV2
export class KnowledgeBankStore {
  @Type(KnowledgeCard) @Trace cards: KnowledgeCard[] = [];
}

// Result shape of an AI card draft (returned by ApiClient.queryKnowledge).
// The AI output is a DRAFT only — the user edits it in the card editor
// before anything is saved to the bank.
export interface KnowledgeQueryResult {
  title: string;
  definition: string;
}

// ============================================================
// ★ 0.200.0：知识卡片导入气泡对话——跨页共享 store + 导航辅助
// ============================================================
// 生命周期：入口（知识库列表/编辑弹窗/复习页）写入 → 画布选择模式消费（action 保留）
//           → ChatPage.onShown 落地消费后清空 action。
// 模式同 AnnotationResultStore（AppStorageV2 内存态不落盘；action 空 = 无导入进行中）。
@ObservedV2
export class CardImportStore {
  @Trace action: string = '';      // '' 无 / 'import' 导入对话 / 'branch' 创建子气泡
  @Trace title: string = '';       // 卡片标题
  @Trace definition: string = '';  // 卡片定义
  @Trace imageUri: string = '';    // 卡片图（base64 data URI；'' = 无图）
}

export function connectCardImport(): CardImportStore {
  return AppStorageV2.connect(CardImportStore, 'card-import', () => new CardImportStore()) as CardImportStore;
}

/** 回画布四态导航（★ 0.200.0，逻辑同 Index.sideBarNav('canvas')——知识库/复习页发起导入后回画布：
 *  ①画布已在栈顶不动 ②画布在栈中连续 pop 到顶 ③不在栈中 replacePath 顶页直换 ④空栈 pushPath） */
export function navBackToCanvas(pathStack: NavPathStack): void {
  const names = pathStack.getAllPathName();
  const idx = names.indexOf('BBTreeCanvas');
  if (idx >= 0 && idx === names.length - 1) {
    return; // 已在画布
  }
  if (idx >= 0) {
    const pops = names.length - 1 - idx;
    for (let i = 0; i < pops; i++) {
      pathStack.pop(); // 连续 pop 到画布为顶
    }
  } else if (names.length > 0) {
    pathStack.replacePath({ name: 'BBTreeCanvas' }); // 画布不在栈：顶页替换
  } else {
    pathStack.pushPath({ name: 'BBTreeCanvas' }); // 空栈（首页）：进画布
  }
}
