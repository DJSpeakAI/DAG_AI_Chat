import { describe, it, expect } from '@ohos/hypium';
import { detectWebUrls, extractReadableText, buildWebContextBlock, WEB_MAX_URLS, WEB_MAX_CONTENT_CHARS,
  WebFetchItem } from '../../../main/ets/utils/WebFetchUtil';

// ★ 0.286.0：AI 读网页一期纯函数断言（project_rule §12.13 测试覆盖军令——
//   新功能必须带测试项；抓取链 fetchWebPageText 涉真网络不进单测，此处只断言纯函数三件）
export default function webFetchTest() {
  describe('DAGAI_WebFetchTest', () => {
    // ---- URL 检测：提取 / 去重 / 上限 / 尾字符回退 ----
    it('detect_single_url', 0, () => {
      const urls = detectWebUrls('帮我看看 https://example.com/a?x=1 这篇文章');
      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertEqual('https://example.com/a?x=1');
    })
    it('detect_dedup_and_cap', 0, () => {
      const urls = detectWebUrls('https://a.com https://a.com http://b.com https://c.com https://d.com');
      expect(urls.length).assertEqual(WEB_MAX_URLS);
      expect(urls[0]).assertEqual('https://a.com');
      expect(urls[1]).assertEqual('http://b.com');
    })
    it('detect_trailing_punct_trim', 0, () => {
      const urls = detectWebUrls('参见（https://example.com/page）。');
      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertEqual('https://example.com/page');
    })
    it('detect_none', 0, () => {
      expect(detectWebUrls('普通消息没有链接').length).assertEqual(0);
      expect(detectWebUrls('ftp://example.com 不是 http').length).assertEqual(0);
    })

    // ---- 正文抽取：块剥离 / 标签去除 / 实体解码 / 标题 ----
    it('extract_strips_script_style', 0, () => {
      const page = extractReadableText('<html><head><title>测试页</title><style>.a{color:red}</style>' +
        '<script>var x = "should be removed";</script></head><body><p>正文第一段</p><p>正文第二段</p></body></html>');
      expect(page.title).assertEqual('测试页');
      expect(page.text.indexOf('should be removed') === -1).assertTrue();
      expect(page.text.indexOf('color:red') === -1).assertTrue();
      expect(page.text.indexOf('正文第一段') >= 0).assertTrue();
      expect(page.text.indexOf('正文第二段') >= 0).assertTrue();
    })
    it('extract_decodes_entities_and_breaks_lines', 0, () => {
      const page = extractReadableText('<p>A &amp; B</p><div>C&lt;D</div><br>E&nbsp;F');
      expect(page.text.indexOf('A & B') >= 0).assertTrue();
      expect(page.text.indexOf('C<D') >= 0).assertTrue();
      expect(page.text.indexOf('E F') >= 0).assertTrue();
      const lines = page.text.split('\n');
      expect(lines.length).assertEqual(3);
    })
    it('extract_truncates_long_text', 0, () => {
      const long: string[] = [];
      for (let i = 0; i < 2000; i++) {
        long.push('这是一段很长的网页正文内容用于测试截断逻辑');
      }
      const page = extractReadableText(`<p>${long.join('')}</p>`);
      expect(page.text.length <= WEB_MAX_CONTENT_CHARS + 20).assertTrue(); // 截断+尾注余量
      expect(page.text.indexOf('已截断') >= 0).assertTrue();
    })

    // ---- 注入块拼装：成功正文 / 失败原因 ----
    it('block_lists_ok_and_fail', 0, () => {
      const items: WebFetchItem[] = [
        { url: 'https://a.com', ok: true, content: '标题：A\n正文：内容甲' },
        { url: 'https://b.com', ok: false, content: '网页读取超时' }
      ];
      const block = buildWebContextBlock(items);
      expect(block.indexOf('https://a.com') >= 0).assertTrue();
      expect(block.indexOf('内容甲') >= 0).assertTrue();
      expect(block.indexOf('https://b.com') >= 0).assertTrue();
      expect(block.indexOf('网页读取超时') >= 0).assertTrue();
      expect(block.indexOf('【网页内容结束】') >= 0).assertTrue();
    })
    it('block_empty_items', 0, () => {
      expect(buildWebContextBlock([])).assertEqual('');
    })
  })
}
