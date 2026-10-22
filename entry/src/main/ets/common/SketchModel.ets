// ============================================================
// SketchModel.ets — ★ 0.297.0 数学证明画板：结果回传 store
// ============================================================
// 画板页（SketchPage）导出完成 → 写 imageUri（JPEG data URI）→ pop 返回
// ChatPage @Monitor 本 store.imageUri → 挂 pendingImages（走现有 9 格附件流）
// 后消费即清空（imageUri=''），AppStorageV2 应用级不落盘（AnnotationResultStore 同模式）。
// ============================================================

import { AppStorageV2 } from '@kit.ArkUI';

@ObservedV2
export class SketchResultStore {
  @Trace imageUri: string = '';
}

export function connectSketchResult(): SketchResultStore {
  return AppStorageV2.connect(SketchResultStore, 'sketch-result-v1',
    () => new SketchResultStore()) as SketchResultStore;
}
