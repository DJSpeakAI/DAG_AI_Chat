// ============================================================
// KnowledgeStoreUtil.ets — Knowledge bank persistence utilities (0.146 / 0.148)
// ============================================================
// Persistence and manipulation helpers for the knowledge bank:
//   - connectKnowledgeBank(): PersistenceV2 connect with 10 preset test
//     cards + one-shot seed merge for pre-existing devices (0.151)
//   - genCardId(): unique card id generator (0.148)
//   - addKnowledgeCard(): insert a card at the head; auto-fills id/createdAt (0.148)
//   - updateKnowledgeCard(): edit title/definition/imageUri by id (0.148; ★ 0.160 imageUri added)
//   - removeKnowledgeCard(): delete a card by id (knowledge bank page delete)
//   - removeCardsByIds(): batch delete for multi-select mode (0.148)
//   - pickRandomKnowledgeCards(): pick n random cards for the AI-bubble review area
//
// The knowledge bank is persisted under its OWN PersistenceV2 key
// ('knowledge-bank'), fully isolated from the bubble tree / word bank —
// the two banks are independent tables per the 0.146 spec.
// ============================================================

import { PersistenceV2 } from '@kit.ArkUI';
import { KnowledgeCard, KnowledgeBankStore } from '../common/KnowledgeModel';

// Dedicated PersistenceV2 key, isolated from bubble tree / word bank keys
const KNOWLEDGE_BANK_KEY = 'knowledge-bank';

// ★ 0.151: preset test cards — 10 AI-concept entries (user request, for
// testing the bank / review features). AI-drafted sample data, same
// nature as the 0.146 "DJ" preset. Fixed 'preset-*' ids make seeding
// idempotent and deletion-aware.
function buildPresetCards(): KnowledgeCard[] {
  const now = Date.now();
  return [
    new KnowledgeCard('preset-dj', 'DJ', '一个天才', '', now),
    new KnowledgeCard('preset-dag', 'DAG', '有向无环图（Directed Acyclic Graph）。由节点和有方向的边组成、不含环路的一种图结构。本应用用它组织气泡对话树：每个气泡是一个节点，回复关系是有向边。', '', now - 1000),
    new KnowledgeCard('preset-prompt', 'Prompt Engineering', '提示词工程。设计与优化输入提示（Prompt），引导大语言模型产出期望输出的技术；清晰的指令、示例与角色设定都能显著提升回答质量。', '', now - 2000),
    new KnowledgeCard('preset-token', 'Token', '词元。大语言模型处理文本的基本单位；一个英文单词约 1 个 token，一个汉字约 1~2 个 token。模型的上下文窗口与计费通常按 token 计数。', '', now - 3000),
    new KnowledgeCard('preset-context', 'Context Window', '上下文窗口。模型单次对话能处理的 token 总量上限；超出后最早的内容会被截断，模型便「忘记」先前说过的话。', '', now - 4000),
    new KnowledgeCard('preset-hallucination', 'Hallucination', '幻觉。大语言模型生成看似合理、实则错误或凭空虚构内容的现象；通过检索增强（RAG）与引用来源可缓解。', '', now - 5000),
    new KnowledgeCard('preset-finetuning', 'Fine-tuning', '微调。在预训练模型基础上，用领域数据继续训练，使模型适配特定任务或风格的技术。', '', now - 6000),
    new KnowledgeCard('preset-rag', 'RAG', '检索增强生成（Retrieval-Augmented Generation）。先从知识库检索相关资料，再让模型基于资料生成回答，可显著缓解幻觉、支持私有知识。', '', now - 7000),
    new KnowledgeCard('preset-multimodal', 'Multimodal', '多模态。模型同时理解与生成文本、图像、音频等多种形式数据的能力；本应用的图片消息即为一种多模态输入。', '', now - 8000),
    new KnowledgeCard('preset-agent', 'Agent', '智能体。能感知环境、自主规划并调用工具完成任务的 AI 系统；大语言模型常作为智能体的推理内核。', '', now - 9000)
  ];
}

// ★ 0.151: one-shot seed-merge marker. v1 = 0.146 "DJ" preset;
// v2 = the 10-card test set above. Persisted under its own key so each
// seed version merges missing presets EXACTLY ONCE — user-deleted cards
// stay deleted afterwards.
const KNOWLEDGE_SEED_VERSION = 2;
const KNOWLEDGE_SEED_KEY = 'knowledge-bank-seed';

// Ids already seeded by v1 (0.146): v2 seeding must NOT resurrect this
// when the user has deleted it on a v1 device.
const KNOWLEDGE_SEED_V1_IDS: string[] = ['preset-dj'];

// PersistenceV2 wrapper for the seed marker (persisted root must be a class).
@ObservedV2
class KnowledgeSeedMarker {
  @Trace version: number = 0;
}

// Connect (or create) the knowledge bank persistence instance.
// Factory presets the 10 test cards on FIRST launch only; once persisted,
// later launches restore from disk and the factory never runs again.
// ★ 0.151: devices that already hold v1 data get the v2 additions merged
// in by seedPresetCards() below — the factory alone cannot reach them.
export function connectKnowledgeBank(): KnowledgeBankStore {
  const store = PersistenceV2.connect(KnowledgeBankStore, KNOWLEDGE_BANK_KEY, () => {
    const s = new KnowledgeBankStore();
    s.cards = buildPresetCards();
    return s;
  }) as KnowledgeBankStore;
  seedPresetCards(store);
  return store;
}

// ★ 0.151: one-shot seed merge for devices with pre-existing persisted data
// (the connect factory only runs when the key has never been persisted).
// Missing v2 cards (by fixed 'preset-*' id, v1 ids excluded) are inserted
// once; the marker version is persisted right after, so user-deleted cards
// never come back on later launches. Merged cards get fresh descending
// timestamps so the whole test set shows at the top of the bank page.
function seedPresetCards(store: KnowledgeBankStore): void {
  const marker = PersistenceV2.connect(KnowledgeSeedMarker, KNOWLEDGE_SEED_KEY, () => new KnowledgeSeedMarker()) as KnowledgeSeedMarker;
  if (marker.version >= KNOWLEDGE_SEED_VERSION) {
    return; // v2 already merged — deleted cards stay deleted
  }
  const existing: Set<string> = new Set<string>();
  store.cards.forEach((c: KnowledgeCard) => {
    existing.add(c.id);
  });
  const missing = buildPresetCards().filter((c: KnowledgeCard) =>
    !existing.has(c.id) && !KNOWLEDGE_SEED_V1_IDS.includes(c.id));
  if (missing.length > 0) {
    const now = Date.now();
    for (let i = 0; i < missing.length; i++) {
      missing[i].createdAt = now - i * 1000;
    }
    store.cards = [...missing, ...store.cards];
  }
  marker.version = KNOWLEDGE_SEED_VERSION;
}

// ★ 0.148: unique card id generator — timestamp(base36) + random suffix
export function genCardId(): string {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

// Insert a card at the head so the newest entry shows first.
// Unlike the word bank there is no duplicate check — cards are user
// authored via the editor and may legitimately share a title.
// ★ 0.148: auto-fills id/createdAt when absent — the bank-page add editor
// creates a card without them; ChatPage's call site passes both already.
export function addKnowledgeCard(store: KnowledgeBankStore, card: KnowledgeCard): void {
  if (card.id.length === 0) {
    card.id = genCardId();
  }
  if (card.createdAt === 0) {
    card.createdAt = Date.now();
  }
  store.cards = [card, ...store.cards];
}

// ★ 0.148: edit a card's title/definition by id. ★ 0.160: imageUri is now
// part of the bank-page editor (add / remove image) and is saved alongside.
// Cards may share titles, so no duplicate check here either.
export function updateKnowledgeCard(store: KnowledgeBankStore, cardId: string,
  title: string, definition: string, imageUri: string): void {
  for (let i = 0; i < store.cards.length; i++) {
    if (store.cards[i].id === cardId) {
      store.cards[i].title = title.trim();
      store.cards[i].definition = definition.trim();
      store.cards[i].imageUri = imageUri;
      return;
    }
  }
}

// Remove a card by its unique id. Cards may share titles (user authored
// via the editor), so id is the only safe key for deletion.
export function removeKnowledgeCard(store: KnowledgeBankStore, cardId: string): void {
  store.cards = store.cards.filter((c: KnowledgeCard) => c.id !== cardId);
}

// ★ 0.148: batch delete for the multi-select mode.
export function removeCardsByIds(store: KnowledgeBankStore, cardIds: string[]): void {
  store.cards = store.cards.filter((c: KnowledgeCard) => !cardIds.includes(c.id));
}

// Pick up to `count` random cards (Fisher-Yates shuffle on a copy).
// Returns fewer items when the bank has fewer cards; empty bank returns [].
export function pickRandomKnowledgeCards(store: KnowledgeBankStore, count: number): KnowledgeCard[] {
  const pool: KnowledgeCard[] = [...store.cards];
  for (let i = pool.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const tmp = pool[i];
    pool[i] = pool[j];
    pool[j] = tmp;
  }
  return pool.slice(0, count);
}
