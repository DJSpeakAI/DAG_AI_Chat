import { describe, it, expect } from '@ohos/hypium';
import { PlanFrame, PlanHook, sanitizePlan, mergeSectionHooks, planFrameJson, planToneLine, stripAnchorMarks, parseBlockMd } from '../../../main/ets/utils/MdInline';

// ★ 0.290.0 司枢模式 2.0：框架先行两段式单元断言（任务书 WP2 §3.3/§七.7 / project_rule §12.13）
// 覆盖：sanitizePlan 防弹衣（围栏抠取/字段修补/越界钳位/bait 定末节/幻觉拦截/空兜底节）/
//   mergeSectionHooks（节尾插入/越界钳位/无节并文末/同位去重/progress 绝迹/管线兼容）/
//   planFrameJson/planToneLine 序列化；导出过滤无残留延续断言
export default function hookMergeTest() {
  describe('DAGAI_HookMergeTest', () => {
    // ---- sanitizePlan：合法框架直通 + 修补 ----
    it('plan_valid_frame_parsed', 0, () => {
      const raw = '{"lengthTier":"medium","targetChars":800,"reason":"单一概念",'
        + '"sections":[{"title":"一句话先懂","points":["大白话定义"],"depth":"plain"},'
        + '{"title":"类比展开","points":["站姿比喻","代码里谁在监听"],"depth":"deep"}],'
        + '"hooks":[{"afterSection":1,"type":"digest","text":"响应式=看到你走近，我换一套站姿"},'
        + '{"afterSection":2,"type":"quiz","text":"依赖数组空与非空，监听时机差在哪？"}],'
        + '"tone":{"voice":"senior","encourage":"low","analogy":"more"}}';
      const frame = sanitizePlan(raw);
      expect(frame !== null).assertTrue();
      expect(frame!.lengthTier).assertEqual('medium');
      expect(frame!.targetChars).assertEqual(800);
      expect(frame!.sections.length).assertEqual(2);
      expect(frame!.hooks.length).assertEqual(2);
      expect(frame!.hooks[0].type).assertEqual('digest');
    })
    it('plan_fence_noise_extracted', 0, () => {
      // 模型加废话/markdown 围栏也能抠出 JSON 对象
      const raw = '好的，框架如下：\n```json\n{"lengthTier":"brief","targetChars":250,"sections":[{"title":"直答","points":["结论"],"depth":"plain"}],"hooks":[]}\n```\n请查收';
      const frame = sanitizePlan(raw);
      expect(frame !== null).assertTrue();
      expect(frame!.lengthTier).assertEqual('brief');
    })
    it('plan_invalid_tier_clamped_medium', 0, () => {
      // lengthTier 不认识 → 钳 medium（任务书 §3.3.2）
      const raw = '{"lengthTier":"huge","targetChars":300,"sections":[{"title":"a","points":["x"],"depth":"deep"}],"hooks":[]}';
      const frame = sanitizePlan(raw);
      expect(frame !== null).assertTrue();
      expect(frame!.lengthTier).assertEqual('medium');
    })
    it('plan_garbage_returns_null', 0, () => {
      // 解析失败 → null（调用侧重试/降级）
      expect(sanitizePlan('模型彻底跑偏，没有任何对象')).assertNull();
      expect(sanitizePlan('')).assertNull();
      expect(sanitizePlan('[]{不是对象}')).assertNull();
    })
    it('plan_empty_sections_default_stuffed', 0, () => {
      // sections 空 → 塞默认节（§3.3.2）
      const raw = '{"lengthTier":"medium","targetChars":600,"sections":[],"hooks":[]}';
      const frame = sanitizePlan(raw);
      expect(frame !== null).assertTrue();
      expect(frame!.sections.length).assertEqual(1);
      expect(frame!.sections[0].title).assertEqual('解答');
    })
    it('plan_hook_after_section_clamped', 0, () => {
      // hooks.afterSection 越界 → 钳制到最后一节（§3.3.2）
      const raw = '{"lengthTier":"medium","targetChars":700,"sections":[{"title":"一","points":["a"],"depth":"deep"},'
        + '{"title":"二","points":["b"],"depth":"deep"}],"hooks":[{"afterSection":99,"type":"breath","text":"钳位"}]}';
      const frame = sanitizePlan(raw);
      expect(frame !== null).assertTrue();
      expect(frame!.hooks[0].afterSection).assertEqual(2);
    })
    it('plan_hook_invalid_type_dropped', 0, () => {
      // hooks.type 非四枚举（含 progress）→ 丢弃该条（WP4：progress 绝迹）
      const raw = '{"lengthTier":"long","targetChars":1600,"sections":[{"title":"一","points":["a1","a2","a3"],"depth":"deep"},'
        + '{"title":"二","points":["b1","b2","b3"],"depth":"deep"}],'
        + '"hooks":[{"afterSection":1,"type":"progress","text":"到这里了"},{"afterSection":1,"type":"link","text":"联想"},'
        + '{"afterSection":1,"type":"digest","text":"合法"}]}';
      const frame = sanitizePlan(raw);
      expect(frame !== null).assertTrue();
      expect(frame!.hooks.length).assertEqual(1);
      expect(frame!.hooks[0].type).assertEqual('digest');
    })
    it('plan_bait_kept_last_fixed_final_section', 0, () => {
      // bait 保留最后一条且固定最后一节（§3.3.2）
      const raw = '{"lengthTier":"long","targetChars":1600,"sections":[{"title":"一","points":["a1","a2"]},{"title":"二","points":["b1","b2"]},{"title":"三","points":["c1","c2"]}],'
        + '"hooks":[{"afterSection":1,"type":"bait","text":"引子甲"},{"afterSection":2,"type":"bait","text":"引子乙"}]}';
      const frame = sanitizePlan(raw);
      expect(frame !== null).assertTrue();
      let baitCount = 0;
      for (let i = 0; i < frame!.hooks.length; i++) {
        if (frame!.hooks[i].type === 'bait') {
          baitCount++;
          expect(frame!.hooks[i].text).assertEqual('引子乙');
          expect(frame!.hooks[i].afterSection).assertEqual(3);
        }
      }
      expect(baitCount).assertEqual(1);
    })
    it('plan_hallucination_intercepted', 0, () => {
      // ★ Q6 幻觉拦截：targetChars≥1500 但 points 合计 <30 字 → 判框架废 → null
      const raw = '{"lengthTier":"long","targetChars":2000,"reason":"深度",'
        + '"sections":[{"title":"一","points":["展开"]},{"title":"二","points":["细讲"]},{"title":"三","points":["收尾"]]}],'
        + '"hooks":[]}'; // points 合计 6 字撑不起 2000 字
      expect(sanitizePlan(raw)).assertNull();
    })
    it('plan_tone_fields_defaulted', 0, () => {
      // tone 各字段非法 → 默认（senior/low/less）
      const raw = '{"lengthTier":"brief","targetChars":250,"sections":[{"title":"a","points":["x"]}],"hooks":[],"tone":{"voice":"alien","encourage":"mid","analogy":"same"}}';
      const frame = sanitizePlan(raw);
      expect(frame !== null).assertTrue();
      expect(frame!.voice).assertEqual('senior');
      expect(frame!.encourage).assertEqual('low');
      expect(frame!.analogy).assertEqual('less');
    })
    // ---- mergeSectionHooks：节尾插入与钳位 ----
    it('merge_hook_inserted_after_section', 0, () => {
      const content = '## 一、概念\n\n第一节的正文内容。\n\n## 二、展开\n\n第二节的正文内容，讲得更深一些。\n\n## 三、收尾\n\n结尾段。';
      const h = new PlanHook();
      h.afterSection = 1;
      h.type = 'digest';
      h.text = '简单说：这一节讲了结构';
      const merged = mergeSectionHooks([h], content);
      expect(merged !== content).assertTrue();
      expect(merged.indexOf('[[anchor:digest|简单说：这一节讲了结构]]') >= 0).assertTrue();
      // 标记必须出现在第一节末（第二节标题前）
      expect(merged.indexOf('[[anchor:digest') < merged.indexOf('## 二、展开')).assertTrue();
      expect(merged.indexOf('[[anchor:digest') > merged.indexOf('第一节的正文内容')).assertTrue();
    })
    it('merge_out_of_range_clamped_to_last_section', 0, () => {
      const content = '## 一\n\n内容一。\n\n## 二\n\n内容二。';
      const h = new PlanHook();
      h.afterSection = 99;
      h.type = 'bait';
      h.text = '文末引子';
      const merged = mergeSectionHooks([h], content);
      expect(merged.indexOf('[[anchor:bait|文末引子]]') > merged.indexOf('内容二')).assertTrue();
    })
    it('merge_no_sections_hooks_to_doc_end', 0, () => {
      // 无 ## 节（brief 直给）→ 钩子并到文末
      const content = '直接给结论：今天是周四。\n\n补一句背景说明。';
      const h = new PlanHook();
      h.afterSection = 1;
      h.type = 'quiz';
      h.text = '你知道周几吗';
      const merged = mergeSectionHooks([h], content);
      expect(merged.indexOf('[[anchor:quiz|你知道周几吗]]') > merged.indexOf('补一句背景说明')).assertTrue();
    })
    it('merge_same_position_deduped', 0, () => {
      // 同位去重（保留首条）
      const content = '## 一\n\n内容。\n\n## 二\n\n内容二。';
      const h1 = new PlanHook();
      h1.afterSection = 1;
      h1.type = 'digest';
      h1.text = '首条';
      const h2 = new PlanHook();
      h2.afterSection = 1;
      h2.type = 'breath';
      h2.text = '次条';
      const merged = mergeSectionHooks([h1, h2], content);
      expect(merged.indexOf('首条') >= 0).assertTrue();
      expect(merged.indexOf('次条')).assertEqual(-1);
    })
    it('merge_invalid_type_skipped_empty_untouched', 0, () => {
      // 非法类型跳过；空钩子数组原文返回
      const content = '## 一\n\n内容。';
      const h = new PlanHook();
      h.afterSection = 1;
      h.type = 'progress'; // 已砍类型
      h.text = '到这里了';
      expect(mergeSectionHooks([h], content)).assertEqual(content);
      expect(mergeSectionHooks([], content)).assertEqual(content);
    })
    it('merge_h3_not_section_boundary', 0, () => {
      // ### 不是节边界（## 才算）——钩子仍落在所属 ## 节末
      const content = '## 一、总\n\n开头段。\n\n### 1.1 细分\n\n细分内容。\n\n## 二\n\n内容二。';
      const h = new PlanHook();
      h.afterSection = 1;
      h.type = 'breath';
      h.text = '喘口气';
      const merged = mergeSectionHooks([h], content);
      expect(merged.indexOf('[[anchor:breath|喘口气]]') > merged.indexOf('细分内容')).assertTrue();
      expect(merged.indexOf('[[anchor:breath|喘口气]]') < merged.indexOf('## 二')).assertTrue();
    })
    // ---- 序列化 ----
    it('plan_frame_json_compact', 0, () => {
      const frame = new PlanFrame();
      const s = frame.sections[0];
      s.title = '解答';
      s.points.push('要点');
      const json = planFrameJson(frame);
      expect(json.indexOf('"title":"解答"') >= 0).assertTrue();
      expect(json.indexOf('lengthTier')).assertEqual(-1); // 执笔只需要 sections
    })
    it('plan_tone_line_contains_mapping', 0, () => {
      const frame = new PlanFrame();
      frame.voice = 'coach';
      frame.encourage = 'high';
      frame.analogy = 'more';
      const line = planToneLine(frame);
      expect(line.indexOf('教练') >= 0).assertTrue();
      expect(line.indexOf('多肯定') >= 0).assertTrue();
      expect(line.indexOf('类比先行') >= 0).assertTrue();
    })
    // ---- 导出/复制过滤：钩子标记零残留（延续 0.269 协议） ----
    it('hook_strip_marks_for_export', 0, () => {
      const content = '第一段。\n\n[[anchor:breath|喘口气]]\n\n第二段。\n\n[[anchor:bait|延伸一下]]';
      const stripped = stripAnchorMarks(content, false);
      expect(stripped.indexOf('[[anchor:')).assertEqual(-1);
      expect(stripped.indexOf('喘口气')).assertEqual(-1);
      expect(stripped.indexOf('第二段') >= 0).assertTrue();
    })
    // ---- 与既有渲染管线兼容：合成产物可被 parseBlockMd 解析为锚点块 ----
    it('hook_merged_content_parses_as_anchor_blocks', 0, () => {
      const content = '## 一、开篇\n\n正文段落。\n\n## 二、展开\n\n更多正文。';
      const h = new PlanHook();
      h.afterSection = 1;
      h.type = 'digest';
      h.text = '管线兼容';
      const merged = mergeSectionHooks([h], content);
      const blocks = parseBlockMd(merged.split('\n'));
      let anchorCount = 0;
      for (let i = 0; i < blocks.length; i++) {
        if (blocks[i].kind === 'anchor') {
          anchorCount++;
          expect(blocks[i].anchorType).assertEqual('digest');
        }
      }
      expect(anchorCount).assertEqual(1);
    })
  })
}
