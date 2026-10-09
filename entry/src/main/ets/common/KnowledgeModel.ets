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

import { Type, AppStorageV2, PersistenceV2 } from '@kit.ArkUI'; // @Type decorator: required by PersistenceV2 nested class arrays; ★ 0.200.0 AppStorageV2（CardImportStore）；★ 0.202.0 PersistenceV2（AttentionStore）

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
  @Trace tags: string = '';        // ★ 0.202.0：标签（逗号/顿号/空格分隔原样存储；'' = 无标签）——注意力加权数据底座
  @Trace images: string = '';      // ★ 0.202.1：多图（JSON string[]；'' = 无图。imageUri 保留兼容——getCardImages 统一读取）
  @Trace folderId: string = '';    // ★ 0.207.0：所属文件夹（'' = 根目录）——anything 导入体系（对标 Anki 牌组）
  @Trace titleImages: string = ''; // ★ 0.210.0：标题图（JSON string[]；'' = 无。Anki「图对图」场景——题面插图，复习双面模式随正面显示）

  // All params have defaults so the class satisfies TypeConstructor<T> (new (): T),
  // which @Type requires for PersistenceV2 nested-class re-creation from disk.
  // ★ 0.188.0: 4 memory fields appended at the tail — legacy 5-arg call sites unchanged.
  // ★ 0.202.0: tags appended at the tail — legacy 9-arg call sites unchanged.
  // ★ 0.202.1: images appended at the tail — legacy 10-arg call sites unchanged.
  // ★ 0.207.0: folderId appended at the tail — legacy 11-arg call sites unchanged（Schema 铁律：只尾部追加）.
  // ★ 0.210.0: titleImages appended at the tail — legacy 12-arg call sites unchanged（Schema 铁律：只尾部追加）.
  constructor(id: string = '', title: string = '', definition: string = '', imageUri: string = '', createdAt: number = 0,
    strength: number = 0, reviewCount: number = 0, lastReviewAt: number = 0, nextReviewAt: number = 0,
    tags: string = '', images: string = '', folderId: string = '', titleImages: string = '') {
    this.id = id;
    this.title = title;
    this.definition = definition;
    this.imageUri = imageUri;
    this.createdAt = createdAt;
    this.strength = strength;
    this.reviewCount = reviewCount;
    this.lastReviewAt = lastReviewAt;
    this.nextReviewAt = nextReviewAt;
    this.tags = tags;
    this.images = images;
    this.folderId = folderId;
    this.titleImages = titleImages;
  }
}

/** ★ 0.207.0：知识库文件夹（对标 Anki 牌组层级；parentId='' = 根） */
@ObservedV2
export class KFolder {
  @Trace id: string = '';
  @Trace name: string = '';
  @Trace parentId: string = '';   // '' = 根目录
  @Trace createdAt: number = 0;

  constructor(id: string = '', name: string = '', parentId: string = '', createdAt: number = 0) {
    this.id = id;
    this.name = name;
    this.parentId = parentId;
    this.createdAt = createdAt;
  }
}

/** ★ 0.202.1：取卡片全部图片（images JSON 优先，空则回落旧 imageUri 单图——两代字段兼容读取） */
export function getCardImages(c: KnowledgeCard): string[] {
  if (c.images.trim().length > 0) {
    try {
      const arr = JSON.parse(c.images) as string[];
      if (Array.isArray(arr) && arr.length > 0) {
        return arr;
      }
    } catch (e) {
      // 损坏数据回落旧字段
    }
  }
  return c.imageUri.length > 0 ? [c.imageUri] : [];
}

/** ★ 0.210.0：取卡片标题图（JSON string[]；'' / 损坏 → []——标题图为全新字段无旧回落） */
export function getTitleImages(c: KnowledgeCard): string[] {
  if (c.titleImages.trim().length > 0) {
    try {
      const arr = JSON.parse(c.titleImages) as string[];
      if (Array.isArray(arr) && arr.length > 0) {
        return arr;
      }
    } catch (e) {
      // 损坏数据按无图处理
    }
  }
  return [];
}

/** ★ 0.202.0：标签字符串 → 数组（中英文逗号/顿号/空格混合分隔；空项滤除） */
export function parseTags(tags: string): string[] {
  return tags.split(/[,，、\s]+/).filter((t: string) => t.length > 0);
}

// PersistenceV2 top-level container. PersistenceV2 requires the persisted
// root to be a class object, and nested custom-class array properties MUST
// be decorated with @Type so items are re-created as KnowledgeCard
// instances when restored from disk.
@ObservedV2
export class KnowledgeBankStore {
  @Type(KnowledgeCard) @Trace cards: KnowledgeCard[] = [];
  @Type(KFolder) @Trace folders: KFolder[] = []; // ★ 0.207.0：文件夹层级（anything 导入体系）
}

// Result shape of an AI card draft (returned by ApiClient.queryKnowledge).
// The AI output is a DRAFT only — the user edits it in the card editor
// before anything is saved to the bank.
export interface KnowledgeQueryResult {
  title: string;
  definition: string;
  tags?: string[]; // ★ 0.202.1：AI 建议标签（2~4 个学科/主题词——编辑弹窗勾选采纳；旧模型未返回时缺失）
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
  @Trace imageUrisJson: string = '[]'; // ★ 0.202.2：卡片图组（JSON string[]——多图全链路；'[]' = 无图）
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

// ============================================================
// ★ 0.202.0：注意力标签（艾宾浩斯 2.0 第二支柱——「注意力在哪，记忆曲线就变在哪」）
// ============================================================
// 机制：用户在 ChatPage 发消息 → 本地子串匹配（卡标题/标签 ∈ 消息文本）→ 命中卡的
// 全部标签热度 +1 → 复习队列排序时命中标签的卡段内提权（S<30 天才提——很熟的卡不打扰）。
// 纯本地毫秒级（AI 还在流式输出时权重已算完）；热度按天指数衰减（×0.5/天），
// 注意力转移后旧标签自然冷却。单 JSON 字符串字段存储（PersistenceV2 避坑先例）。
const DAY_MS_ATT = 24 * 60 * 60 * 1000;
const ATTENTION_HALF_LIFE_DAYS = 1; // 热度半衰期：1 天（注意力时效短——昨天关心的话题今天未必）
const ATTENTION_TAG_MIN_LEN = 2;    // 参与匹配的最短词长（防单字误命中）

@ObservedV2
export class AttentionStore {
  @Trace heatJson: string = '{}'; // {"标签": 热度}——浮点热度
  @Trace updatedAt: number = 0;   // 上次写入时间（衰减基准）
}

export function connectAttention(): AttentionStore {
  return PersistenceV2.connect(AttentionStore, 'attention-v1', () => new AttentionStore()) as AttentionStore;
}

/** 解析热度表（含按天衰减的当前值） */
export function getTagHeat(store: AttentionStore): Map<string, number> {
  const result = new Map<string, number>();
  let raw: Record<string, number> = {};
  try {
    raw = JSON.parse(store.heatJson) as Record<string, number>;
  } catch (e) {
    return result; // 损坏数据按空处理
  }
  const decay = Math.pow(0.5, (Date.now() - store.updatedAt) / DAY_MS_ATT / ATTENTION_HALF_LIFE_DAYS);
  Object.keys(raw).forEach((k: string) => {
    const v = raw[k] * decay;
    if (v > 0.05) {
      result.set(k, v); // 衰减到 0.05 以下视为冷却清除
    }
  });
  return result;
}

/** 消息 → 标签热度更新：卡标题或任一标签是消息子串 → 该卡全部标签 +1（写入前先衰减旧值） */
export function updateAttention(store: AttentionStore, cards: KnowledgeCard[], message: string): void {
  const text = message.trim();
  if (text.length < ATTENTION_TAG_MIN_LEN) {
    return;
  }
  // 先取衰减后的当前热度作为基数
  const heat = getTagHeat(store);
  let hit = false;
  for (let i = 0; i < cards.length; i++) {
    const c = cards[i];
    const titleHit = c.title.length >= ATTENTION_TAG_MIN_LEN && text.includes(c.title);
    const tags = parseTags(c.tags);
    let tagHit = false;
    for (let j = 0; j < tags.length; j++) {
      if (tags[j].length >= ATTENTION_TAG_MIN_LEN && text.includes(tags[j])) {
        tagHit = true;
        break;
      }
    }
    if (titleHit || tagHit) {
      hit = true;
      // 命中卡的「全部」标签加权（问"幺半群"→ 抽象代数整个标签域被点亮——用户核心场景）
      for (let j = 0; j < tags.length; j++) {
        heat.set(tags[j], (heat.get(tags[j]) ?? 0) + 1);
      }
      if (tags.length === 0 && titleHit) {
        // 无标签卡：用标题自身当标签（保证标题命中也能积累可检索的注意力）
        heat.set(c.title, (heat.get(c.title) ?? 0) + 1);
      }
    }
  }
  if (!hit) {
    return;
  }
  // 序列化回写（ArkTS 严格模式：程序化构建 Record）
  const out: Record<string, number> = {};
  heat.forEach((v: number, k: string) => {
    out[k] = Math.round(v * 100) / 100;
  });
  store.heatJson = JSON.stringify(out);
  store.updatedAt = Date.now();
}

/** 卡片是否被当前注意力命中（复习队列提权判定：命中任一热标签 且 S<30 天——很熟的卡不打扰） */
export function isAttentionHot(c: KnowledgeCard, heat: Map<string, number>): boolean {
  if (c.strength >= 30) {
    return false; // 用户拍板："一个月后很熟的群公理不用提"
  }
  const tags = parseTags(c.tags);
  for (let i = 0; i < tags.length; i++) {
    if ((heat.get(tags[i]) ?? 0) > 0.05) {
      return true;
    }
  }
  return false;
}
