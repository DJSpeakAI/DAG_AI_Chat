// WebFetchUtil.ets — ★ 0.286.0 AI 读网页一期（纯客户端抓取，用户拍板架构 A）
// 定位：用户消息含 http/https 链接时，app 从设备直接抓取网页正文（去标签抽纯文本），
//   以 system 消息一次性拼进本次 AI 请求（复刻 0.235.0 划词引用注入模式——
//   气泡原文/持久化/Schema/后续轮次零改动）；失败不阻断发送。
// 合规：网址与网页内容不上传开发者服务器（隐私政策第 2 条已披露）；
//   网页正文过 ContentFilter 输入侧兜底——命中即丢弃该网页块（不拦用户消息本身）。
// 限制（一期接受）：JS 重渲染页/反爬站抓不到 → 上层 toast 明示，不硬撑；
//   每 条消息最多 2 个 URL、每页正文截断 6000 字符（防 token 爆炸多扣 SP）。

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ContentFilter } from './ContentFilter';

// 单条消息最多抓取的 URL 数（去重后）
export const WEB_MAX_URLS: number = 2;
// 单页正文截断上限（字符）
export const WEB_MAX_CONTENT_CHARS: number = 6000;
// ★ 0.286.1 壳判定线：静态抽取正文低于此字数 = 疑似前端渲染壳（SPA 文档站），触发 Web 组件渲染重取
export const WEB_RENDER_TRIGGER_CHARS: number = 300;

// 抓取结果条目（一条 URL 一个）
export interface WebFetchItem {
  url: string;
  ok: boolean;
  content: string; // ok=true 为「标题+正文」块；ok=false 为中文失败原因
}

// 全链结果摘要（上层 toast 用）
export interface WebFetchSummary {
  block: string;     // 拼好的 system 注入块（空串=无需注入）
  okCount: number;
  failCount: number;
}

// 从消息文本提取 http/https 链接（去重保序，截断到上限）
export function detectWebUrls(text: string): string[] {
  const out: string[] = [];
  const seen: Set<string> = new Set();
  // 链接合法结尾字符集：排除中文标点/右括号/引号等常见「跟在链接后的字符」
  const pattern = /https?:\/\/[A-Za-z0-9\-._~:\/?#\[\]@!$&'()*+,;=%]+/g;
  const matches = text.match(pattern);
  if (matches === null || matches === undefined) {
    return out;
  }
  for (let i = 0; i < matches.length; i++) {
    // 尾部清理：右括号/分号/句点等成对收尾字符回退（(url) / url。 / url, 场景）
    let u = matches[i];
    while (u.length > 0 && (u.endsWith(')') || u.endsWith(';') || u.endsWith('.') || u.endsWith(','))) {
      u = u.substring(0, u.length - 1);
    }
    if (u.length > 0 && !seen.has(u) && seen.size < WEB_MAX_URLS) {
      seen.add(u);
      out.push(u);
    }
  }
  return out;
}

// 剥离成对块（含标签体整体删除，不区分大小写）——script/style/nav 等结构块
function stripBlockTags(html: string, tag: string): string {
  const re = new RegExp(`<${tag}(\\s[^>]*)?>[\\s\\S]*?</${tag}>`, 'gi');
  return html.replace(re, ' ');
}

// 块级标签转换行（保文字分行，防全部糊成一行）
function blockTagsToNewline(html: string): string {
  return html.replace(/<\/(p|div|br|li|tr|h[1-6]|section|article|blockquote|pre|table|ul|ol)>/gi, '\n')
    .replace(/<br\s*\/?>/gi, '\n');
}

// 解码常见 HTML 实体（含数字形式常见两枚）
function decodeEntities(text: string): string {
  return text
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, '\'')
    .replace(/&apos;/g, '\'')
    .replace(/&nbsp;/g, ' ')
    .replace(/&#8212;/g, '—');
}

// 压缩空白：多空格归一、3+ 连续换行压成 2、去行首尾空格
function squeezeWhitespace(text: string): string {
  const lines = text.split('\n');
  const kept: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i].replace(/[ \t\u3000]+/g, ' ').trim();
    if (t.length > 0) {
      kept.push(t);
    }
  }
  return kept.join('\n');
}

export interface ReadablePage {
  title: string;
  text: string;
}

// HTML → 纯文本正文（纯函数，ohosTest 断言同源）
export function extractReadableText(html: string): ReadablePage {
  // 1. 标题先行提取（后面块剥离不影响）
  let title = '';
  const titleMatch = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  if (titleMatch !== null && titleMatch !== undefined && titleMatch.length >= 2) {
    title = squeezeWhitespace(decodeEntities(titleMatch[1])).substring(0, 120);
  }
  // 2. 结构块整体删除
  let body = html;
  body = stripBlockTags(body, 'script');
  body = stripBlockTags(body, 'style');
  body = stripBlockTags(body, 'noscript');
  body = stripBlockTags(body, 'svg');
  body = stripBlockTags(body, 'nav');
  body = stripBlockTags(body, 'header');
  body = stripBlockTags(body, 'footer');
  body = stripBlockTags(body, 'aside');
  body = stripBlockTags(body, 'form');
  body = stripBlockTags(body, 'iframe');
  // 3. HTML 注释删除
  body = body.replace(/<!--[\s\S]*?-->/g, ' ');
  // 4. 块级标签转换行（先于去标签，保分行）
  body = blockTagsToNewline(body);
  // 5. 剩余标签全删
  body = body.replace(/<[^>]+>/g, ' ');
  // 6. 实体解码 + 空白压缩
  body = squeezeWhitespace(decodeEntities(body));
  // 7. 截断（尾部标注）
  if (body.length > WEB_MAX_CONTENT_CHARS) {
    body = `${body.substring(0, WEB_MAX_CONTENT_CHARS)}\n（网页内容过长，已截断）`;
  }
  return { title: title, text: body };
}

// 抓取单页静态 HTML → 抽正文（GET + UA 伪装 + 超时；2xx 且文本类才收；错误全中文）
export function fetchWebPageReadable(url: string): Promise<ReadablePage> {
  return new Promise<ReadablePage>((resolve, reject) => {
    const req = http.createHttp();
    const finish = (val: ReadablePage | Error): void => {
      req.destroy();
      if (val instanceof Error) {
        reject(val);
      } else {
        resolve(val);
      }
    };
    req.request(url, {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8'
      },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 8000,
      readTimeout: 12000,
      usingCache: false
    }).then((resp: http.HttpResponse) => {
      const code = resp.responseCode;
      if (code < 200 || code >= 300) {
        finish(new Error(`网页无法访问（HTTP ${code}）`));
        return;
      }
      const html = typeof resp.result === 'string' ? resp.result : '';
      // 启发式校验（header 为 Object 索引访问触发 arkts-no-any-unknown，弃 Content-Type 精确校验）：
      // 2xx 且含 HTML 标签痕迹或足量可读文本才收；图片/压缩包等二进制下载直接拒
      if (html.trim().length === 0) {
        finish(new Error('网页内容为空（可能需要浏览器渲染）'));
        return;
      }
      if (html.indexOf('<') < 0 && html.trim().length < 200) {
        finish(new Error('该链接不是网页（不支持读取）'));
        return;
      }
      const page = extractReadableText(html);
      finish(page);
    }).catch((err: BusinessError) => {
      const msg = `${err.message}`;
      if (msg.indexOf('timeout') >= 0 || msg.indexOf('2300028') >= 0 || err.code === 2300028) {
        finish(new Error('网页读取超时'));
      } else if (err.code === 2300006 || err.code === 2300007 || err.code === 2300025) {
        finish(new Error('无法连接该网站（网络或网址问题）'));
      } else {
        finish(new Error(`网页读取失败（${msg.substring(0, 40)}）`));
      }
    });
  });
}

// ReadablePage → 注入块用文本（标题行 + 正文行）
export function formatReadablePage(page: ReadablePage): string {
  const head = page.title.length > 0 ? `标题：${page.title}\n` : '';
  return `${head}正文：\n${page.text}`;
}

// 任意纯文本 → 压空白 + 截断 6000（Web 组件渲染结果复用同一闸）
export function clampWebText(raw: string): string {
  let text = raw.replace(/\r/g, '');
  text = squeezeWhitespace(text);
  if (text.length > WEB_MAX_CONTENT_CHARS) {
    text = `${text.substring(0, WEB_MAX_CONTENT_CHARS)}\n（网页内容过长，已截断）`;
  }
  return text;
}

// 拼 system 注入块（成功正文 + 失败原因均列出——模型不瞎编；敏感词块标注跳过）
export function buildWebContextBlock(items: WebFetchItem[]): string {
  if (items.length === 0) {
    return '';
  }
  const parts: string[] = [];
  parts.push('【用户消息包含以下网页链接，应用已尝试自动抓取正文，请结合抓到的内容回答；抓取失败的链接不要凭空编造内容】');
  for (let i = 0; i < items.length; i++) {
    const it = items[i];
    parts.push(`—— 网页 ${i + 1}（${it.url}）——`);
    if (it.ok) {
      parts.push(it.content);
    } else {
      parts.push(`（抓取失败：${it.content}）`);
    }
  }
  parts.push('【网页内容结束】');
  return parts.join('\n');
}

// ★ 0.292.0：单 URL 两级瀑布抓取（0.286.1 fetchWebContextForMessage 循环体原样抽出共用——
//   消息预抓与 FC 工具 open_url 两入口同链路）；ok=false 时 content=中文失败原因
export async function fetchSingleUrlReadable(url: string,
  webRenderer?: (url: string) => Promise<string>): Promise<WebFetchItem> {
  const item: WebFetchItem = { url: url, ok: false, content: '' };
  // ★ 0.286.1 两级瀑布：静态抓（快 1~2s）→ 正文 < 300 字判定壳 → Web 组件渲染重取（真渲染）
  let fetchedText = '';
  try {
    const page = await fetchWebPageReadable(url);
    if (page.text.length >= WEB_RENDER_TRIGGER_CHARS || webRenderer === undefined) {
      // 正文足量（普通网页快通道）或无渲染器（保持旧链路行为）——静态结果直接用
      fetchedText = formatReadablePage(page);
    } else {
      // 壳（SPA/文档站静态 HTML 只有框架）→ Web 组件渲染取 innerText
      try {
        const rendered = await webRenderer(url);
        if (rendered.trim().length >= WEB_RENDER_TRIGGER_CHARS) {
          fetchedText = clampWebText(rendered);
        } else if (page.text.trim().length > 0) {
          // 渲染了但仍短：静态短正文兜底（有总比没有好）
          fetchedText = `${formatReadablePage(page)}\n（网页可能未完全加载，内容不完整）`;
        } else {
          item.ok = false;
          item.content = '网页需要浏览器渲染，渲染后仍未取得有效正文';
        }
      } catch (we) {
        // 渲染失败：静态短正文兜底，否则报失败
        if (page.text.trim().length > 0) {
          fetchedText = `${formatReadablePage(page)}\n（网页可能未完全加载，内容不完整）`;
        } else {
          item.ok = false;
          item.content = we instanceof Error ? we.message : '网页渲染读取失败';
        }
      }
    }
  } catch (e) {
    // 静态抓本身失败（超时/HTTP 错）→ 有渲染器再试渲染通道
    if (webRenderer !== undefined) {
      try {
        const rendered = await webRenderer(url);
        if (rendered.trim().length > 0) {
          fetchedText = clampWebText(rendered);
        } else {
          item.ok = false;
          item.content = '网页内容为空';
        }
      } catch (we2) {
        item.ok = false;
        item.content = e instanceof Error ? e.message : '网页读取失败';
      }
    } else {
      item.ok = false;
      item.content = e instanceof Error ? e.message : '网页读取失败';
    }
  }
  if (fetchedText.length > 0) {
    const hit = ContentFilter.checkInput(fetchedText);
    if (hit !== null) {
      item.ok = false;
      item.content = '内容未通过本地安全检查，已跳过';
    } else {
      item.ok = true;
      item.content = fetchedText;
    }
  }
  return item;
}

// 全链入口：检测 → 两级瀑布抓取（静态/壳→Web 渲染）→ 敏感词过滤 → 拼块（单页失败静默记录，不阻断）
// ★ 0.286.1 webRenderer：壳页/静态失败页的渲染通道（ChatPage 隐形 Web 组件取 innerText），
//   可缺省——不传时行为与 0.286.0 纯静态链一致（ohosTest/独立调用方兼容）
// ★ 0.292.0：抓取体抽出 fetchSingleUrlReadable（本函数只保留检测/汇总编排，行为零变化）
export async function fetchWebContextForMessage(text: string,
  webRenderer?: (url: string) => Promise<string>): Promise<WebFetchSummary> {
  const urls = detectWebUrls(text);
  const summary: WebFetchSummary = { block: '', okCount: 0, failCount: 0 };
  if (urls.length === 0) {
    return summary;
  }
  const items: WebFetchItem[] = [];
  for (let i = 0; i < urls.length; i++) {
    const item = await fetchSingleUrlReadable(urls[i], webRenderer);
    if (item.ok) {
      summary.okCount += 1;
    } else {
      summary.failCount += 1;
    }
    items.push(item);
  }
  summary.block = buildWebContextBlock(items);
  return summary;
}

// ============================================================
// ★ 0.292.0：联网搜索（FC 工具 search_web 数据源）——抓 Bing 结果页解析前 N 条
//   零新增 API Key（用户零配置）；后续可升级专业搜索 API（博查/腾讯混元搜索，独立迭代）
// ============================================================

// 搜索结果条目
export interface SearchHit {
  title: string;
  url: string;
  snippet: string;
}

// 单轮 search_web 返回条数上限（防 token 爆炸）
export const WEB_MAX_SEARCH_HITS: number = 5;
// FC 工具循环轮数上限（防失控多扣 SP；到上限后不再声明 tools，AI 落笔回答）
export const WEB_MAX_TOOL_ROUNDS: number = 3;

// 纯函数：解析 Bing 结果 HTML（b_algo 条目：第一个链接=标题行链接，首个 <p>=摘要）
export function extractSearchResults(html: string): SearchHit[] {
  const hits: SearchHit[] = [];
  const blocks = html.split('b_algo');
  for (let i = 1; i < blocks.length && hits.length < WEB_MAX_SEARCH_HITS; i++) {
    const seg = blocks[i];
    const linkMatch = seg.match(/<a[^>]+href="(https?:\/\/[^"]+)"[^>]*>([\s\S]*?)<\/a>/i);
    if (linkMatch === null || linkMatch === undefined) {
      continue;
    }
    const url = linkMatch[1];
    const title = squeezeWhitespace(decodeEntities(linkMatch[2].replace(/<[^>]+>/g, ' '))).substring(0, 100);
    if (title.length === 0 || url.length === 0) {
      continue;
    }
    let snippet = '';
    const pMatch = seg.match(/<p[^>]*>([\s\S]*?)<\/p>/i);
    if (pMatch !== null && pMatch !== undefined) {
      snippet = squeezeWhitespace(decodeEntities(pMatch[1].replace(/<[^>]+>/g, ' '))).substring(0, 160);
    }
    hits.push({ title: title, url: url, snippet: snippet });
  }
  return hits;
}

// 搜索结果 → 给模型读的文本块
export function formatSearchResults(hits: SearchHit[]): string {
  if (hits.length === 0) {
    return '（搜索没有返回结果，可换关键词重试或基于已有知识回答并说明未能联网核实）';
  }
  const parts: string[] = [];
  for (let i = 0; i < hits.length; i++) {
    const h = hits[i];
    parts.push(`${i + 1}. ${h.title}\n   链接：${h.url}${h.snippet.length > 0 ? `\n   摘要：${h.snippet}` : ''}`);
  }
  return parts.join('\n');
}

// search_web 执行体：GET Bing 结果页 → 解析条目（失败 reject 中文 Error，上层写进 tool 结果防模型瞎编）
export function searchWeb(query: string): Promise<SearchHit[]> {
  return new Promise<SearchHit[]>((resolve, reject) => {
    const req = http.createHttp();
    const searchUrl = `https://www.bing.com/search?q=${encodeURIComponent(query)}&setlang=zh-hans&count=10`;
    req.request(searchUrl, {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8'
      },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 8000,
      readTimeout: 12000,
      usingCache: false
    }).then((resp: http.HttpResponse) => {
      req.destroy();
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        reject(new Error(`搜索服务不可用（HTTP ${resp.responseCode}）`));
        return;
      }
      const html = typeof resp.result === 'string' ? resp.result : '';
      if (html.length === 0) {
        reject(new Error('搜索服务返回空内容'));
        return;
      }
      resolve(extractSearchResults(html));
    }).catch((err: BusinessError) => {
      req.destroy();
      const msg = `${err.message}`;
      if (msg.indexOf('timeout') >= 0 || err.code === 2300028) {
        reject(new Error('搜索请求超时'));
      } else {
        reject(new Error(`搜索失败（${msg.substring(0, 40)}）`));
      }
    });
  });
}
