// ============================================================
// FaceModeStore.ets — ★ 0.224.0 卡面模式全局单通道
// ============================================================
// 用户拍板（2026-10-12）：卡面模式不按库分开、不让用户两头选——一个 mode 全局生效，
// 卡片复习页 / 司忆区两处（聊天下方+屏幕圈选提炼弹窗）/ 桌面卡片全部跟随；
// 全局设置与复习页 ⚙ 两入口同一 @ObservedV2 实例即时同步。
// 独立中性文件（原居 ReviewPage——0.224.0 桌面卡片跟随需 WidgetHostBridge 读取，
// 反向 import 组件文件会成环，按 0.165.2 提供者注入同族纪律外提）。
// 卡片进程禁止 import 本文件（@ObservedV2 在卡片进程崩——0.204.1 铁律；
// 卡片侧一律经 WidgetState.face 快照注入）。
// ============================================================

import { PersistenceV2 } from '@kit.ArkUI';

// 'single'=单面（题面+内容全显，评分按钮直接可按）；'double'=正反两面（先题面，点击翻面后评分）
// ★ 0.209.0 原两库分治字段保留休眠（Schema 铁律：字段只追加不删除，旧落盘兼容）
@ObservedV2
export class FaceModeStore {
  @Trace wordFace: string = 'single';      // （0.224.0 起休眠——历史字段）
  @Trace knowledgeFace: string = 'single'; // （0.224.0 起休眠）
  @Trace mode: string = 'single';          // ★ 0.224.0 统一通道：'single' | 'double'（唯一真相源）
}

export function connectFaceMode(): FaceModeStore {
  // ★ 0.224.0-fix：全新 key v2——0.185 铁律实证复发（更深层形态）：根类新字段挂旧 key
  //   不入持久化 track 集——实测 Pad 上 mode 置 double 后重启回 single、persistent_storage
  //   文件 mtime 纹丝不动（@Trace 内存刷新正常但零写盘）。旧 v1 两库分治字段就此休眠
  //   （不迁移：用户个人偏好单面，双面用户重拨一次即可——代价最小语义最清）。
  return PersistenceV2.connect(FaceModeStore, 'review-face-mode-v2', () => new FaceModeStore()) as FaceModeStore;
}
