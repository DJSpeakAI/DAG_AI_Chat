// ============================================================
// KnowledgeStoreUtil.ets — Knowledge bank persistence utilities (0.146)
// ============================================================
// Persistence and manipulation helpers for the knowledge bank:
//   - connectKnowledgeBank(): PersistenceV2 connect with preset card
//   - addKnowledgeCard(): insert a card at the head
//   - pickRandomKnowledgeCards(): pick n random cards for the AI-bubble review area
//   - removeKnowledgeCard(): delete a card by id (knowledge bank page delete)
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

// Insert a card at the head so the newest entry shows first.
// Unlike the word bank there is no duplicate check — cards are user
// authored via the editor and may legitimately share a title.
export function addKnowledgeCard(store: KnowledgeBankStore, card: KnowledgeCard): void {
  store.cards = [card, ...store.cards];
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

// Remove a card by its unique id. Cards may share titles (user authored
// via the editor), so id is the only safe key for deletion.
export function removeKnowledgeCard(store: KnowledgeBankStore, cardId: string): void {
  store.cards = store.cards.filter((c: KnowledgeCard) => c.id !== cardId);
}
