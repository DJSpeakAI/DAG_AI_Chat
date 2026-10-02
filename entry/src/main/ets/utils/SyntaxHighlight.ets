// ★ 0.149：代码块语法高亮（MVP 简易正则分词）
// 约束（需求既定）：不引入第三方库、不做完整词法语法解析；嵌套场景（如字符串内出现注释符号）
// 着色错位视为可接受，后续迭代再优化；关键字表手动维护，新增语言须手动追加关键字数组。

// 高亮 token 种类：0=普通文本 1=关键字 2=字符串 3=注释 4=数字
export class CodeToken {
  text: string;
  kind: number;
  constructor(text: string, kind: number) {
    this.text = text;
    this.kind = kind;
  }
}

// 性能兜底：超长代码 / 超多 token 直接放弃高亮整体单色渲染
//（流式期间 content 每帧变化都会重算分词，上限防止超长代码拖垮 UI）
const MAX_CODE_LEN = 30000;
const MAX_TOKENS = 6000;

// 语言别名归一：返回 'ts' | 'python' | 'java' | 'json'；不认识返回 ''（plaintext 不高亮）
export function normalizeLang(lang: string): string {
  const l = lang.toLowerCase().trim();
  if (l === 'ts' || l === 'typescript' || l === 'arkts') {
    return 'ts';
  }
  if (l === 'py' || l === 'python') {
    return 'python';
  }
  if (l === 'java') {
    return 'java';
  }
  if (l === 'json') {
    return 'json';
  }
  return '';
}

// ---- 各语言关键字表（手动维护，需求约束） ----
const TS_KEYWORDS = 'export|import|from|const|let|var|function|return|if|else|for|while|do|switch|case|break|continue|new|class|extends|implements|interface|type|enum|this|super|static|public|private|protected|readonly|async|await|try|catch|finally|throw|typeof|instanceof|in|of|as|void|null|undefined|true|false|number|string|boolean|object|any|unknown|never|struct|declare|namespace|is|keyof|infer|satisfies|abstract|yield';
const PY_KEYWORDS = 'def|class|return|if|elif|else|for|while|break|continue|import|from|as|pass|raise|try|except|finally|with|lambda|global|nonlocal|yield|assert|del|in|is|not|and|or|None|True|False|async|await|self|match|case';
const JAVA_KEYWORDS = 'public|private|protected|class|interface|extends|implements|static|final|void|int|long|double|float|boolean|char|byte|short|new|return|if|else|for|while|do|switch|case|break|continue|try|catch|finally|throw|throws|this|super|import|package|abstract|synchronized|volatile|transient|native|enum|instanceof|true|false|null|var|record|default|assert|yield|sealed|permits|strictfp';
const JSON_KEYWORDS = 'true|false|null';

// ---- 各语言正则片段（注释 | 字符串 | 关键字 | 数字，alternation 顺序即优先级） ----
// 注释：TS/Java 行注释 + 块注释；Python # 行注释；JSON 无注释（占位符永不匹配）
const TS_COMMENT = "//[^\\n]*|/\\*[\\s\\S]*?\\*/";
const PY_COMMENT = "#[^\\n]*";
const NO_MATCH = "[^\\s\\S]"; // 永不匹配的字符类占位（JSON 无注释）
// 字符串：单双引号（不跨行）+ TS 模板串 / Python 三引号（可跨行）；JSON 仅双引号
const TS_STRING = "'(?:[^'\\\\\\n]|\\\\.)*'|\"(?:[^\"\\\\\\n]|\\\\.)*\"|`(?:[^`\\\\]|\\\\[\\s\\S])*?`";
const PY_STRING = "'''[\\s\\S]*?'''|\"\"\"[\\s\\S]*?\"\"\"|'(?:[^'\\\\\\n]|\\\\.)*'|\"(?:[^\"\\\\\\n]|\\\\.)*\"";
const JAVA_STRING = "'(?:[^'\\\\\\n]|\\\\.)*'|\"(?:[^\"\\\\\\n]|\\\\.)*\"";
const JSON_STRING = "\"(?:[^\"\\\\\\n]|\\\\.)*\"";
// 数字：JSON 支持负数与科学计数法
const NUM = "\\b\\d+(?:\\.\\d+)?\\b";
const JSON_NUM = "-?\\b\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b";

// 组合正则缓存（语言 → 已编译正则；全局复用，避免流式期间反复编译正则）
const regexCache: Map<string, RegExp> = new Map();

function buildLangRegex(lang: string): RegExp {
  const cached = regexCache.get(lang);
  if (cached !== undefined) {
    return cached;
  }
  let comment = '';
  let str = '';
  let kw = '';
  let num = NUM;
  if (lang === 'ts') {
    comment = TS_COMMENT;
    str = TS_STRING;
    kw = TS_KEYWORDS;
  } else if (lang === 'python') {
    comment = PY_COMMENT;
    str = PY_STRING;
    kw = PY_KEYWORDS;
  } else if (lang === 'java') {
    comment = TS_COMMENT; // Java 行/块注释与 TS 同形
    str = JAVA_STRING;
    kw = JAVA_KEYWORDS;
  } else {
    // json
    comment = NO_MATCH;
    str = JSON_STRING;
    kw = JSON_KEYWORDS;
    num = JSON_NUM;
  }
  const pattern = `(${comment})|(${str})|(\\b(?:${kw})\\b)|(${num})`;
  const re = new RegExp(pattern, 'g');
  regexCache.set(lang, re);
  return re;
}

// 主入口：代码 → 着色 token 序列（单遍正则扫描）。
// 返回 null = 放弃高亮（语言不支持 / 代码为空 / 超长 / 超 token 上限），调用方整体单色渲染。
// token 顺序拼接与原文本完全一致——保证 Text 划词/全选/复制偏移与 content 不错位。
export function tokenizeCode(code: string, lang: string): CodeToken[] | null {
  const norm = normalizeLang(lang);
  if (norm === '' || code.length === 0 || code.length > MAX_CODE_LEN) {
    return null;
  }
  const re = buildLangRegex(norm);
  re.lastIndex = 0; // 全局正则复用，重置扫描位置
  const tokens: CodeToken[] = [];
  let last = 0;
  let m: RegExpExecArray | null = re.exec(code);
  while (m !== null) {
    if (m.index > last) {
      tokens.push(new CodeToken(code.substring(last, m.index), 0));
    }
    let kind = 0;
    if (m[1] !== undefined) {
      kind = 3; // 注释
    } else if (m[2] !== undefined) {
      kind = 2; // 字符串
    } else if (m[3] !== undefined) {
      kind = 1; // 关键字
    } else {
      kind = 4; // 数字
    }
    tokens.push(new CodeToken(m[0], kind));
    last = m.index + m[0].length;
    if (tokens.length > MAX_TOKENS) {
      return null; // 超 token 上限：放弃高亮（性能兜底）
    }
    m = re.exec(code);
  }
  if (last < code.length) {
    tokens.push(new CodeToken(code.substring(last), 0));
  }
  return tokens;
}
