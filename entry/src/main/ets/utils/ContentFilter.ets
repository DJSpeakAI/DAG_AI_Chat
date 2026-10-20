// 0.250.0 敏感词本地预过滤（华为上架合规：应用侧内容自审兜底防线）
// 定位：主防线=平台侧（腾讯 TokenHub 输入/输出双向过滤+审计日志），本地只做输入侧兜底初筛
// 算法：DFA 前缀树（Trie）——文本沿树走而非逐词匹配，千级词库毫秒级
// 词库：SensitiveWords.ets（脚本生成禁手改；更新须重跑生成脚本）
// ★ 0.276.0 用户拍板放宽：输出侧本地扫描整体退役（2 字通用词误杀正常回复实锤——本地断流吞整条回复
//   的体验代价远高于兜底收益；输出安全全交平台侧双向过滤），本文件仅保留输入侧 checkInput

import { SENSITIVE_POLITICAL, SENSITIVE_PORN, SENSITIVE_WEAPONS } from './SensitiveWords';

export interface FilterHit {
  category: string;
  word: string;
}

class TrieNode {
  children: Map<string, TrieNode> = new Map();
  endCats: string = '';
}

function normalizeText(text: string): string {
  let out = '';
  for (let i = 0; i < text.length; i++) {
    let code = text.charCodeAt(i);
    // 去空白类字符（防"法 轮 功"式分隔绕过；含全角空格）
    if (code === 32 || code === 9 || code === 10 || code === 13 || code === 12288) {
      continue;
    }
    // 全角 ASCII（！~ 区）转半角
    if (code >= 0xFF01 && code <= 0xFF5E) {
      code = code - 0xFEE0;
    }
    out += String.fromCharCode(code);
  }
  return out.toLowerCase();
}

function addWord(root: TrieNode, word: string, cat: string): void {
  const norm = normalizeText(word);
  if (norm.length === 0) {
    return;
  }
  let node = root;
  for (let i = 0; i < norm.length; i++) {
    const ch = norm.charAt(i);
    let next = node.children.get(ch);
    if (next === undefined) {
      next = new TrieNode();
      node.children.set(ch, next);
    }
    node = next;
  }
  if (node.endCats.indexOf(cat) < 0) {
    node.endCats = node.endCats.length > 0 ? node.endCats + '|' + cat : cat;
  }
}

function matchTrie(normText: string, root: TrieNode): FilterHit | null {
  for (let start = 0; start < normText.length; start++) {
    let node = root.children.get(normText.charAt(start));
    if (node === undefined) {
      continue;
    }
    for (let end = start + 1; end <= normText.length; end++) {
      if (node.endCats.length > 0) {
        return { category: node.endCats, word: normText.substring(start, end) };
      }
      if (end === normText.length) {
        break;
      }
      const next = node.children.get(normText.charAt(end));
      if (next === undefined) {
        break;
      }
      node = next;
    }
  }
  return null;
}

function buildTrie(includeWeapons: boolean): TrieNode {
  const root = new TrieNode();
  for (const w of SENSITIVE_POLITICAL) {
    addWord(root, w, 'political');
  }
  for (const w of SENSITIVE_PORN) {
    addWord(root, w, 'porn');
  }
  if (includeWeapons) {
    for (const w of SENSITIVE_WEAPONS) {
      addWord(root, w, 'weapons');
    }
  }
  return root;
}

export class ContentFilter {
  private static inputTrie: TrieNode | null = null;

  // 输入侧：用户消息发送前兜底初筛（三表词库）；命中即本地拦截不出网
  static checkInput(text: string): FilterHit | null {
    if (ContentFilter.inputTrie === null) {
      ContentFilter.inputTrie = buildTrie(true);
    }
    return matchTrie(normalizeText(text), ContentFilter.inputTrie);
  }
}