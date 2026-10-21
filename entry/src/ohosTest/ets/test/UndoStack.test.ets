import { describe, it, expect } from '@ohos/hypium';
import { UndoStore, UNDO_MAX_ENTRIES } from '../../../main/ets/common/UndoStack';

// ★ 0.287.0：撤销栈纯逻辑断言（project_rule §12.13 测试覆盖军令——push/undo/redo/分支截断/上限裁头/清空）
export default function undoStackTest() {
  describe('DAGAI_UndoStackTest', () => {
    it('undo_redo_basic', 0, () => {
      const s = new UndoStore();
      let v = 0;
      s.push('操作A', (): void => { v = 1; }, (): void => { v = 10; });
      expect(s.canUndo()).assertTrue();
      expect(s.undo()).assertEqual('操作A');
      expect(v).assertEqual(1);
      expect(s.canRedo()).assertTrue();
      expect(s.redo()).assertEqual('操作A');
      expect(v).assertEqual(10);
    })
    it('undo_empty_returns_empty_label', 0, () => {
      const s = new UndoStore();
      expect(s.undo()).assertEqual('');
      expect(s.redo()).assertEqual('');
      expect(s.canUndo()).assertFalse();
      expect(s.canRedo()).assertFalse();
    })
    it('push_truncates_redo_branch', 0, () => {
      const s = new UndoStore();
      let v = 0;
      s.push('一', (): void => { v = 1; }, (): void => { v = -1; });
      s.push('二', (): void => { v = 2; }, (): void => { v = -2; });
      s.undo(); // 撤销「二」——进入已撤销分支
      expect(s.canRedo()).assertTrue();
      s.push('三', (): void => { v = 3; }, (): void => { v = -3; }); // 分支截断：「二」的 redo 永久丢失
      expect(s.canRedo()).assertFalse();
      expect(s.redo()).assertEqual('');
      expect(s.undo()).assertEqual('三');
      expect(s.undo()).assertEqual('一'); // 线性历史只剩 一→三
      expect(s.canUndo()).assertFalse();
    })
    it('max_entries_cap', 0, () => {
      const s = new UndoStore();
      for (let i = 0; i < UNDO_MAX_ENTRIES + 10; i++) {
        s.push(`op${i}`, (): void => {}, (): void => {});
      }
      expect(s.count).assertEqual(UNDO_MAX_ENTRIES);
      // 最旧的 op0 已被裁掉——逐个撤销到头，第一个 label 是 op10
      let first = '';
      while (s.canUndo()) {
        first = s.undo();
      }
      expect(first).assertEqual(`op${UNDO_MAX_ENTRIES + 9}`);
      // 撤空后再撤销无 label
      expect(s.undo()).assertEqual('');
    })
    it('clear_resets_all', 0, () => {
      const s = new UndoStore();
      s.push('x', (): void => {}, (): void => {});
      s.clear();
      expect(s.count).assertEqual(0);
      expect(s.canUndo()).assertFalse();
      expect(s.undo()).assertEqual('');
    })
    it('count_tracks_pointer', 0, () => {
      const s = new UndoStore();
      s.push('a', (): void => {}, (): void => {});
      s.push('b', (): void => {}, (): void => {});
      expect(s.count).assertEqual(2);
      s.undo();
      expect(s.count).assertEqual(1);
      s.undo();
      expect(s.count).assertEqual(0);
      s.redo();
      expect(s.count).assertEqual(1);
    })
  })
}
