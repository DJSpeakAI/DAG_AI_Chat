// ============================================================
// KnowledgeStoreUtil.ets — Knowledge bank persistence utilities (0.146 / 0.148)
// ============================================================
// Persistence and manipulation helpers for the knowledge bank:
//   - connectKnowledgeBank(): PersistenceV2 connect with preset card
//   - genCardId(): unique card id generator (0.148)
//   - addKnowledgeCard(): insert a card at the head; auto-fills id/createdAt (0.148)
//   - updateKnowledgeCard(): edit title/definition by id (0.148; imageUri untouched)
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

// Connect (or create) the knowledge bank persistence instance.
// Factory presets ONE sample card on FIRST launch only (user-specified
// default): title "DJ", definition "一个天才". Once persisted, later
// launches restore from disk and the factory never runs again.
export function connectKnowledgeBank(): KnowledgeBankStore {
  return PersistenceV2.connect(KnowledgeBankStore, KNOWLEDGE_BANK_KEY, () => {
    const store = new KnowledgeBankStore();
    store.cards = [
      new KnowledgeCard('preset-dj', 'DJ', '一个天才', '', Date.now())
    ];
    return store;
  }) as KnowledgeBankStore;
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

// ★ 0.148: edit a card's title/definition by id (imageUri is NOT part of
// the bank-page editor and stays untouched). Cards may share titles, so
// no duplicate check here either.
export function updateKnowledgeCard(store: KnowledgeBankStore, cardId: string,
  title: string, definition: string): void {
  for (let i = 0; i < store.cards.length; i++) {
    if (store.cards[i].id === cardId) {
      store.cards[i].title = title.trim();
      store.cards[i].definition = definition.trim();
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
