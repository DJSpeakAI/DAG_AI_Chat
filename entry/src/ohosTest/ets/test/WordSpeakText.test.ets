// WordSpeakText.test.ets — ★ 0.288.1 词条播放文本纯函数断言（§12.13 军令：bug 修复须配回归用例）
//   覆盖 bug：中翻英入库词条 word 存中文，点喇叭无声（英文引擎读不了中文，用户实机报障）——
//   speakTextFor 修复口径：word 首字符中文且 explain 非空 → 播英文译文 explain；其余原逻辑（缩略词全称）
import { describe, it, expect } from '@ohos/hypium';
import { WordItem, speakTextFor } from '../../../main/ets/common/WordModel'; // ★ 纯函数直测——测试链零网络依赖（WordSpeaker→ApiClient 重链曾致 hypium +1 失败嫌疑）

export default function wordSpeakTextTest() {
  describe('DAGAI_WordSpeakTextTest', () => {
    it('cn2en_item_speaks_english_explain', 0, () => {
      const item = new WordItem('苹果', '', '/ˈæpl/', 'apple');
      expect(speakTextFor(item)).assertEqual('apple'); // 中翻英词条播英文译文（bug 修复点）
    })
    it('cn_word_without_explain_falls_back', 0, () => {
      const item = new WordItem('苹果', '', '', '');
      expect(speakTextFor(item)).assertEqual('苹果'); // explain 空兜底原 word（不空指针/不返回空串）
    })
    it('en_item_speaks_word', 0, () => {
      const item = new WordItem('operating', '', '/ˈɒpəreɪtɪŋ/', '操作系统');
      expect(speakTextFor(item)).assertEqual('operating'); // 英译中词条原样播单词
    })
    it('abbreviation_speaks_full_name', 0, () => {
      const item = new WordItem('OS', 'operating system', '', '操作系统');
      expect(speakTextFor(item)).assertEqual('operating system'); // 缩略词播全称（0.149 原逻辑不回归）
    })
  })
}