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
import { KnowledgeCard, KnowledgeBankStore, KFolder } from '../common/KnowledgeModel';

// Dedicated PersistenceV2 key, isolated from bubble tree / word bank keys
const KNOWLEDGE_BANK_KEY = 'knowledge-bank';

// ★ 0.151: preset test cards — 10 AI-concept entries (user request, for
// testing the bank / review features). AI-drafted sample data, same
// nature as the 0.146 "DJ" preset. Fixed 'preset-*' ids make seeding
// idempotent and deletion-aware.
// ★ 0.202.2：编程主题测试数据（用户验收标签/多图用）——10 张卡、标签 0~9 个递增、部分 1~3 图（占位头像 PNG）
const PRESET_IMG_1: string = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAYAAADimHc4AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAUSSURBVHhe7dvZkhRFFMbxfiavvfYhxBV3BQH3DVxREdzFXRRRQXHfEJWXEPcdhmEWhmGJEC8cKfNkdmae7Do1U92dJ08ZfS7+MTeZffH7IiZiaqp732w7vwo9uqo6iHvsgtC30OMXpj1xUfUd7smLQ99DT12S9vSl1Q+4Z1aHfoS2XxZ79nLbT9BzV8Sev9L2M/TCVWkvXp30y0vXpL18bdor11W/4nasCf0Gvbo27bXrq99xO9eF/oBeX5+2a0P1J+6NG0KHoDdvrOIAil8cPw6g+CL4bgDFF8O3Ayi+HP6ht25CAyh+cfzDYQDFF8F3Ayi+GH4ygOKXxz+8+2Y3gOLL4NsBFF8O3w2g+GL4U7UBFL8o/tSeW9AAil8cPw6g+CL4bgDFF8O3Ayi+HP7U27eiARS/OP6RMIDii+BDPcWXw4fCAIpfHv/IO7e5ARRfBt8OoPhy+G4AxRfDn64NoPhF8af33o4G6DD+0l8nTafSzrSry/hxgI7h/2PBcQZzBHyqLuG7ATqED/Cc+Lgu4NsBuoDv4Uvh4yTxp9+9Aw1gwCcNHyeBfzQMYMBL42N4aXxfaXw3gAFX/FhJ/GQAxY+Vwj/63p1uAMWvVwLfDqD4zXHjuwEUf9k48WeSAZjwBwf4P+EvnTnNij/z/l39ATqIf+4559UaPNOm0T/ndIgL3w3AiI8HGBffN3h2uaj7Pup8LOLbAZjwwwBdwocoMB91vinqvo8670rxl/52ceDPfLCx6nHh+wGGxYcoMB91vinqvo8634QfBsiM7wZgwofn+bnxIeoOFXUXV7+D4Afw7QAM+LPJAJnx4z9S2uP7KDAfdb4p6r4vPdtHb8DHA+TEn/1wU38ABvxx/pNFgfmo801R933xnAFeAR/iwHcDdAwfosB81PmmqPs+d8bgtsCHOPDDALnxbTvWjITva0YbrubPMbAt8SEO/NmP7q56XPjJAAMo8hnUIfAhDnw3ABN+GIAEkMyADokPceDP1QbIiA/v7dAAkhnMEfAhDvy5j+9BA2TGhxelaASpDOSI+BAHfhyAAd9HY5TOIHYQ3w3AiN+NAQziGPgQF35tgNz4/l1NGqZEBrDD+HOf3BsH4MKXG8AAtsSvzp5tjBM/DMCJb9u5ro9SKgPbAp8Cx/1rzvg48O0AJfB9NFbuDG5mfF9u/PoAjPj+FXEaLVcGtwU+RKH7KHwoN/78p/ehAQrg+2i8cTOwjPi+nPhxgIL4tl0b+mi5MrAt8SEKHqLAB8uJ7wYQwMdfjqBBh8mgDoEPjYoP5cSvD1AY37+bT8O2yYCOiU8hL1dO/PnP7kcDCOHjL0fQyE0Z0CHxfQAPPynglcqJHwfoAD6OBscZyBHx4akm/KRw25QT3w3QMXzq/fxx8MNzfJ/5q5aCbVtOfDtA1/G5XhGncFcqN/785w+gASYIf+QBMuMfCwNMGL5/rkMhN8WB7waYUHz8YI0C93H82vH4yQCTip/72c4w+Mf2bXYDKL4Mvh1A8eXw3QCKL4a/UBtA8YviL3zxIBpA8YvjxwEUXwQf6im+HD7UU3w5/IX9D6EBFL84/vEwgOKL4LsBFF8MPxlA8cvjH//yYTeA4svg2wEUXw7fDaD4YviLtQEUvyj+4ldb0ACKXxw/DqD4IvhuAMUXw7cDKL4c/uLXj6ABFL84/okwgOKL4LsBFF8MPxlA8cvjnziw1Q2g+DL4dgDFl8N3Ayi+GP7JA1ur/wBpexfgkyeoHAAAAABJRU5ErkJggg==';
const PRESET_IMG_2: string = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAYAAADimHc4AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAVYSURBVHhe7dvZcxRVFMfx/E0+++yfI+6KC+64BkQkCSEJSUgIQXHfF8RdBBQQkB39G1xCaZXXe0/36T7dc2ame3LPPW3Nqa7vQ6pu5+Hzq8xDp2fi9qNTLrQFmnZbPp92dxTNuDuxYzPurmN7i+7Gvph195Duxb7c5+6rdf9Xc5Ue+Hq+0tZvFooexL7d7x4iPYx9t+geIW2Dlty275fco0XL7jHs+LJ7/PiBoiewH1bck6SnsBOr7ula208cdNtPlj1zcq3s1Jp79tShoudCP4bW3fPYT+vuhaLD7sXThx0MYPg6+DCA4evh5wMYvhb+JAxg+Gr4k6dfdROGr4c/eaYYwPA18HdkAxi+Fj4MYPh6+DvOvJYPYPgq+DthAMNXw4cBDF8Pf+dZMoDhp8d/6eyRbADD18GHAQxfD78cgMAbfjr8XTAAgTf8tPgwgOHr4e/6+fVyAMNPj/8yDmD4OvgwgOHr4ZcDGL4K/m4YwPDV8GEAw9fD333ujeoAhp8W/xU6QJfxf//7r5HrMn4xQNfwOchYdQkfBugSPgcm00Yn8HsG0MLnkaTacH+QNPH3nHuzHGAc8Wka+HvO5wNo4PNAkvHwtNT4MIDhV0uJ3zPAuONjqfCnzr9VDmD41VLgFwMYPp80Pgxg+AP6Z0MUf+oCGUAKP/0ADOQoeXw6gAT+9IW3swG6iH/rLbf1xJ2rVkP0cb+nfqanHB+TwocBJPFHHYBDw7jzWTkeibsfq58tquEXAxD4WPjlAAReGz/EgWHc+X4fO9z9GHeew8ck8GdgAAIfE38zTzU5MKz3vAfqE3c/1nOeQadJ4MMAUvijDsBh0arnPU6fuHtplfMMeD0J/Jlf3ikHiI0f/plSxWoeB4aV5zzMkLj7seIcg80lgb8XB5DA38x/sjgwLDvjURrE3Y/BGQa6XxL4MEDX8EMcGNYUP8Tdj3HIg5LALweIjI9xuE3j0NrgY9zv4YCHJYE/CwMI4Yc3FzjY0fMQMWJwh/WnTwIfBpDCjzuAh4hRDbZJAZ8OEBN/9uK75QCx8cN7Ozxm2zxEjAhq0xAfB4iNvw8HkMAPL0rxoG3yEDHKQdtE8UMS+DCAFD7GwzbJQ8TI47UtFX4+gBz+6AN4iBh5vLbV8WEAIfw5GEAQH9/V5JH75SFi5OHalhp/7uJ7bkIav90AHiJGHq5N/w64JPHnLhUDyOGHwguyPDjNY8SIAe4XheYu+pcggT+fDSCPj/HwIQ8Soxy2SRSauyh+MUJkfBggFT6+It4F/BDFrl8cfig2/vyl9/MBEuFj/0d8LCb+AgyQGB/fz9fCD1FwenHg9WLiwwAa+PTLESxq0zxI2wIiRcerDt2vmPgLl8kAGvj45QgWd1geo20BkKKHqw48rJj4+y9/kA2giU+/HMFCc3mItlHEUeCzbkbFhwG6gk+/HMGiYx6ibRQxPNWkPzfvJhQTvxyAwGvjc+/nbwYfn+Nj4cEaDzyoDB8HiIW/CAMQ+C7iS70izkNzyeEvXvEDjCN+8wFK/FBs/MUrH5YDjBM+Ptfh0TF5/CUcYBzx6YO1QfgSHzuIDwOMO37sZztt8Jeu4gCGr4K/DAMYvho+DGD4evjLVz+qDmD4afEPXCMDGH56/GIAw9fBhwEMXw8/G8Dw1fBXrn1cDmD46fFXrucDGL4OPgxg+Hr41QEMPzn+6vVP8gEMXwU/G8Dw1fBhAMPXw1+9QQYw/PT4B298mg1g+Dr4MIDh6+FnAxi+Gv5aNoDha+HDAIavh7/262f5AIavgn8IBjB8NXwYwPD18MkAhq+Bv54NYPha+DCA4evhr/921P0HgsaSxpZ3HpkAAAAASUVORK5CYII=';
const PRESET_IMG_3: string = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAYAAADimHc4AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAATESURBVHhe7dvZdhRVFMZxn8lrr30mJ1REBcUJBBEBhQQSSMKQRAVkcGRSngNEGZU4XJiy9j69u051f11d3Zx9drF6X/zvqnqt+n0rWaurq5554fCtgnqROhJ6SZq7Xbwc9cp81RbqaOhV6divxWtRry/U20otVr2xeKfq+J1iW9Sb1InQW9LSb8XbUduXq3ZQK6F3pJO/F+9G7TxV9R51OvS+dOZu8UHUh6v1Plqrt2v9Xq3dX1Z9TH0V2iN9fb/YG/XJ2fsFD+D4Nvg8gOPb4YcBHN8Mf58M4Pg2+DyA49vh7zsnAzi+Cf6nPIDjm+HzAI5vh18bwPHz4++XARzfBp8HcHw7/P3nowEcPz/+ZzKA49vg8wCOb4cfBnB8M/wDMoDj2+Af+KYcwPHt8KsBHN8E/yAP4Phm+DyA49vhH7zwoBrA8fPjH5IBHN8GnwdwfDv8oQEcPy/+5xejAbqM//jv/ybvn1CX8fsDdA0fgk5SDx/VJXweoEv4EHPSADqqC/hhgA7gQ8hpAtCojShL/C8uRQPMIn6cBX5/AAt8iDhtJWCbEHxcbnwewPHr5cSvD+D4/XLhH778sDeA4w+VAz8M4Pgj08bnARy/OU382gBa+EkHKEHahCCnTRP/yLe9AbqI/9yzzw+FsAcbBESfM3jMuLTweQBN/GkHQGgSQpcG4dD50uCxTWnhhwE6hk8hMAnBUwgOnS+h45vSwJ+TATTwn+SuJgKT2uJT6HwJHd+UBv7cd+UAWvh0Lx/hjgthxaXAp9A5TWngVwMo4E87AIXApDb4EjpfQsc3pYE/zwMo4T/JL1kITGqLT6HzJXR8Uxr4PEDX8NsMgIBQ6HwJHd+UBv7894+qAVLiyw/oEHlU5UXGIbRJ8CX0Oei4cWngH5UBNPDpqQUIjSovsE0IJlca+DyAFn7rAcqLaxNCyZkGfm2A1PitBigvrE0IJHca+Md+6A2ggU8PSkF0qbyoNiEMizTweQAtfMnxR+OHARTx4QDlBbUJQVj017/1AVLiL8gAWvjyjKbjY/yFH8sBtPH7A5QX1CYEod3mZjEyTfxqAEV8ih6ORdiDIRzNEHgc/QWENlXwF3mADPgSQpcQkGYIPC7Gl1Lj8wC58Cl6NLwL+BRClxA+lRp/8ac/qgFy4EtPI76UEv+4DJATX57Pt8KnEDw1Dp9Kic8DWODHL0cgIO2mxadS4tcGsMCXlyMQklaj4cfjUynxT1zpDWCJH78cgcA0GoZvh0+lxOcBuoIfvxyB0FJFdzWnxadS4ocBOoaPns9HkG2T+/gSfaudFp9Kib8kA3QZX+sR8S7g8wCziB8GwMhNpcZfuioDzBi+3NMZBG5KA3+ZB5hRfIm+2SJwSePfjuDzALOOn/reziT4y1f/rAZw/Pz4KzKA49vg8wCOb4e/cm1gAMfPi38yHsDx8+P3B3B8G3wewPHt8IcGcPy8+KeuRwM4fn78/gCOb4PPAzi+Hf7QAI6fF//0jcfVAI6fH78/gOPb4PMAjm+HXxvA8fPjn/m5N4Dj2+DzAI5vhx8GcHwz/NUyHsDxbfBXfykHcHw7/GoAxzfBX+MBHN8MnwdwfDv8tZsb1QCOnx9/XQZwfBt8HsDx7fDXb24U/wNeOakYMZ6aJwAAAABJRU5ErkJggg==';

function buildPresetCards(): KnowledgeCard[] {
  const now = Date.now();
  return [
    new KnowledgeCard('preset-dj', '算法复杂度', '衡量算法效率的标尺：大 O 表示法描述运行时间/空间随输入规模的增长趋势。常数 O(1)、对数 O(log n)、线性 O(n) 层层递增，优化就是把复杂度阶级往下压。', '', now, 0, 0, 0, 0, ''),
    new KnowledgeCard('preset-dag', '数据结构', '数据的组织与存储方式：数组连续随机访问快、链表插删灵活、哈希表以空间换时间、树结构分层检索。选对结构，算法问题就解决了一半。', '', now - 1000, 0, 0, 0, 0, '数据结构'),
    new KnowledgeCard('preset-prompt', '设计模式', '可复用的面向对象设计方案：单例控全局唯一、工厂封装创建、观察者解耦通知、策略替换算���族。是前人踩坑沉淀的套路，不是死记硬背的教条。', '', now - 2000, 0, 0, 0, 0, '设计模式,面向对象', JSON.stringify([PRESET_IMG_1])),
    new KnowledgeCard('preset-token', 'HTTP 协议', 'Web 世界的传输语言：请求/响应模型、GET 与 POST 语义、状态码 200/404/500 各自报信、无状态靠 Cookie/Token 补记忆。前端后端的一切对话都建立在它之上。', '', now - 3000, 0, 0, 0, 0, '网络,HTTP,前后端'),
    new KnowledgeCard('preset-context', '数据库索引', '以额外存储换查询速度的数据结构：B+ 树是最常见实现，像书的目录一样让查找免于全表扫描。索引不是越多越好——写操作要维护索引，滥用反而拖慢入库。', '', now - 4000, 0, 0, 0, 0, '数据库,SQL,性能优化,后端', JSON.stringify([PRESET_IMG_1, PRESET_IMG_2])),
    new KnowledgeCard('preset-hallucination', '正则表达式', '文本模式的描述语言：\d 匹配数字、+ 表示重复、() 捕获分组、^$ 锚定首尾。爬虫提取、表单校验、日志分析的背后都是它，写对一次处处复用。', '', now - 5000, 0, 0, 0, 0, '正则,文本处理,工具,编程基础,字符串'),
    new KnowledgeCard('preset-finetuning', '并发编程', '多任务同时执行的协调艺术：线程/协程是执行单元，锁防止数据竞争，死锁是互相等待的僵局，原子操作与消息队列是解法。用对并发模型，吞吐量翻倍。', '', now - 6000, 0, 0, 0, 0, '并发,多线程,锁,内存模型,后端,性能优化'),
    new KnowledgeCard('preset-rag', 'Git 版本控制', '代码的时间机器：commit 是快照、branch 是平行宇宙、merge 汇流合流、rebase 重写历史。分布式设计让每个克隆都是完整仓库，协作与回滚皆从容。', '', now - 7000, 0, 0, 0, 0, 'Git,版本控制,协作,命令行,工具,工程实践,DevOps', JSON.stringify([PRESET_IMG_1, PRESET_IMG_2, PRESET_IMG_3])),
    new KnowledgeCard('preset-multimodal', '递归', '函数调用自身的分治智慧：基准情形终止展开、递归情形缩小问题规模，像俄罗斯套娃层层打开。栈是它的天然载体，栈溢出是它的悬崖边界。', '', now - 8000, 0, 0, 0, 0, '算法,递归,编程基础,思维模型,栈,函数,入门,计算机科学'),
    new KnowledgeCard('preset-agent', 'SOLID 原则', '面向对象设计的五条军规：单一职责、开闭、里氏替换、接口隔离、依赖倒置。目标是高内聚低耦合——需求变化时只改一处而非牵一发动全身。', '', now - 9000, 0, 0, 0, 0, 'SOLID,设计原则,面向对象,架构,代码质量,可维护性,设计模式,工程实践,编程进阶')
  ];
}

const KNOWLEDGE_SEED_VERSION = 3; // ★ 0.202.2：v3 = 编程主题测试数据（更新同 id 卡内容，保留记忆字段）
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
  normalizeCardMemoryFields(store); // ★ 0.188.0：存量卡片补齐记忆字段（防 undefined/NaN 进算法）
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
    return; // already merged — deleted cards stay deleted
  }
  const presets = buildPresetCards();
  // ★ 0.202.2 v3：同 id 已存在的卡 → 内容更新为新测试数据（记忆字段保留——用户的复习进度不丢）
  const presetMap = new Map<string, KnowledgeCard>();
  presets.forEach((p: KnowledgeCard) => {
    presetMap.set(p.id, p);
  });
  for (let i = 0; i < store.cards.length; i++) {
    const fresh = presetMap.get(store.cards[i].id);
    if (fresh !== undefined) {
      store.cards[i].title = fresh.title;
      store.cards[i].definition = fresh.definition;
      store.cards[i].tags = fresh.tags;
      store.cards[i].imageUri = fresh.imageUri;
      store.cards[i].images = fresh.images;
    }
  }
  const existing: Set<string> = new Set<string>();
  store.cards.forEach((c: KnowledgeCard) => {
    existing.add(c.id);
  });
  const missing = presets.filter((c: KnowledgeCard) =>
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

// ★ 0.188.0: back-fill memory fields on legacy cards (same pattern as
// WordStoreUtil.normalizeMemoryFields). Cards persisted before 0.188 lack
// the 4 new fields — normalize to numeric defaults so the memory algorithm
// never sees NaN/undefined.
function normalizeCardMemoryFields(store: KnowledgeBankStore): void {
  for (let i = 0; i < store.cards.length; i++) {
    const c = store.cards[i];
    if (typeof c.strength !== 'number' || !isFinite(c.strength)) {
      c.strength = 0;
    }
    if (typeof c.reviewCount !== 'number' || !isFinite(c.reviewCount)) {
      c.reviewCount = 0;
    }
    if (typeof c.lastReviewAt !== 'number' || !isFinite(c.lastReviewAt)) {
      c.lastReviewAt = 0;
    }
    if (typeof c.tags !== 'string') {
      c.tags = ''; // ★ 0.202.0：存量卡补 tags 兜底（PersistenceV2 旧快照新增字段缺失防 undefined）
    }
    if (typeof c.nextReviewAt !== 'number' || !isFinite(c.nextReviewAt)) {
      c.nextReviewAt = 0;
    }
    if (typeof c.folderId !== 'string') {
      c.folderId = ''; // ★ 0.207.0：存量卡补 folderId 兜底（旧快照缺失 → 根目录）
    }
  }
  if (!(store.folders instanceof Array)) {
    store.folders = []; // ★ 0.207.0：旧快照无 folders 字段兜底
  }
}

// ============================================================
// ★ 0.207.0：文件夹 CRUD + 卡片移动/复制（anything 导入体系）
// ============================================================

function genFolderId(): string {
  return 'f' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

/** 新建文件夹（同名允许——id 唯一即可；返回新文件夹 id） */
export function addFolder(store: KnowledgeBankStore, name: string, parentId: string): string {
  const nm = name.trim();
  if (nm.length === 0) {
    return '';
  }
  const f = new KFolder(genFolderId(), nm, parentId, Date.now());
  store.folders = [...store.folders, f];
  return f.id;
}

/** 重命名文件夹 */
export function renameFolder(store: KnowledgeBankStore, folderId: string, name: string): void {
  const nm = name.trim();
  if (nm.length === 0) {
    return;
  }
  for (let i = 0; i < store.folders.length; i++) {
    if (store.folders[i].id === folderId) {
      store.folders[i].name = nm;
      return;
    }
  }
}

/**
 * 删除文件夹——卡片与子文件夹一律**上移到被删文件夹的父级**（绝不删卡，数据安全红线）。
 */
export function deleteFolder(store: KnowledgeBankStore, folderId: string): void {
  const target = store.folders.find((f: KFolder): boolean => f.id === folderId);
  if (target === undefined) {
    return;
  }
  const upParent = target.parentId;
  for (let i = 0; i < store.cards.length; i++) {
    if (store.cards[i].folderId === folderId) {
      store.cards[i].folderId = upParent;
    }
  }
  const newFolders: KFolder[] = [];
  for (let i = 0; i < store.folders.length; i++) {
    if (store.folders[i].id === folderId) {
      continue;
    }
    if (store.folders[i].parentId === folderId) {
      store.folders[i].parentId = upParent;
    }
    newFolders.push(store.folders[i]);
  }
  store.folders = newFolders;
}

/** 移动卡片（批量）到目标文件夹（folderId='' 即根目录） */
export function moveCards(store: KnowledgeBankStore, cardIds: string[], folderId: string): void {
  for (let i = 0; i < store.cards.length; i++) {
    if (cardIds.includes(store.cards[i].id)) {
      store.cards[i].folderId = folderId;
    }
  }
}

/**
 * 复制卡片（批量）到目标文件夹——新 id / 新 createdAt，记忆字段清零（新卡从零开始，
 * 复制的是内容不是进度）；返回新增张数。
 */
export function copyCards(store: KnowledgeBankStore, cardIds: string[], folderId: string): number {
  let n = 0;
  const now = Date.now();
  const copies: KnowledgeCard[] = [];
  for (let i = 0; i < store.cards.length; i++) {
    const src = store.cards[i];
    if (!cardIds.includes(src.id)) {
      continue;
    }
    const cp = new KnowledgeCard(genCardId(), src.title, src.definition, src.imageUri, now + n,
      0, 0, 0, 0, src.tags, src.images, folderId);
    copies.push(cp);
    n++;
  }
  if (copies.length > 0) {
    store.cards = [...copies, ...store.cards];
  }
  return n;
}

/** 取文件夹名链（根→…→当前）——面包屑/导出路径用 */
export function folderChain(store: KnowledgeBankStore, folderId: string): KFolder[] {
  const chain: KFolder[] = [];
  let cur = store.folders.find((f: KFolder): boolean => f.id === folderId);
  // 深度上限 32 防环（数据异常时不死循环）
  let guard = 0;
  while (cur !== undefined && guard < 32) {
    chain.unshift(cur);
    const pid: string = cur.parentId;
    cur = pid.length === 0 ? undefined : store.folders.find((f: KFolder): boolean => f.id === pid);
    guard++;
  }
  return chain;
}

/**
 * 逐级找/建文件夹路径（导入用）——names 形如 ['英语','词根']（Anki deck "A::B::C" 拆解后），
 * 已有同名子文件夹则复用（幂等——重复导入不产生重复文件夹）；返回最深层 folderId。
 */
export function ensureFolderPath(store: KnowledgeBankStore, names: string[], parentId: string): string {
  let pid = parentId;
  for (let i = 0; i < names.length; i++) {
    const nm = names[i].trim();
    if (nm.length === 0) {
      continue;
    }
    const exist = store.folders.find((f: KFolder): boolean => f.parentId === pid && f.name === nm);
    if (exist !== undefined) {
      pid = exist.id;
    } else {
      pid = addFolder(store, nm, pid);
    }
  }
  return pid;
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
// ★ 0.202.0: tags saved alongside (attention-weighting data base).
// Cards may share titles, so no duplicate check here either.
export function updateKnowledgeCard(store: KnowledgeBankStore, cardId: string,
  title: string, definition: string, imageUri: string, tags: string = '', images: string = '', titleImages: string = ''): void {
  for (let i = 0; i < store.cards.length; i++) {
    if (store.cards[i].id === cardId) {
      store.cards[i].title = title.trim();
      store.cards[i].definition = definition.trim();
      store.cards[i].imageUri = imageUri;
      store.cards[i].tags = tags.trim();
      store.cards[i].images = images; // ★ 0.202.1：多图（编辑保存时清空 imageUri 旧字段——getCardImages 统一读 images）
      store.cards[i].titleImages = titleImages; // ★ 0.210.0：标题图（尾部默认参——旧调用点不传=清空，语义与 images 同）
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

// ★ 0.188.0: pickRandomKnowledgeCards REMOVED — review selection now goes
// through MemoryAlgorithm.pickReviewCards (forgetting-curve driven, replaces random).