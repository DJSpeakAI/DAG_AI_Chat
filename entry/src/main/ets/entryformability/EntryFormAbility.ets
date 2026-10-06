// ============================================================
// EntryFormAbility.ets — ★ 0.204.0 桌面卡片 FormExtensionAbility
// ============================================================
// onAddForm：读双队列快照 → formBindingData（卡片初始渲染）
// onFormEvent：卡片内交互（评分/切库）→ processWidgetCommand 自闭环处理
// onSizeChanged：规格变化（2×2/2×4/4×4）→ 记 dimension → 推送刷新排版
// onRemoveForm：卡片删除 → 清 formId
// ============================================================

import { FormExtensionAbility, formBindingData, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import {
  addWidgetFormId,
  removeWidgetFormId,
  setWidgetDimension,
  formBindingDataOf,
  processWidgetCommand,
  pushWidgetState
} from '../utils/WidgetReviewUtil';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = want.parameters?.['ohos.extra.param.key.form_identity'] as string;
    if (formId !== undefined && formId.length > 0) {
      addWidgetFormId(this.context, formId); // 记录卡片 id（推送更新用）
    }
    return formBindingDataOf(this.context); // 双队列快照 → 卡片初始数据
  }

  // ★ 0.204.0：卡片内交互——message 通道（本机桌面 msg 被剥空，实际走 call→EntryAbility Callee；
  //   此回调保留作为 message 通道兼容，若未来系统修复 msg 传递即可用）
  onFormEvent(_formId: string, message: string): void {
    processWidgetCommand(this.context, message);
  }

  // ★ 0.204.3：系统触发卡片更新（残留卡片重挂/定期）——formId 兜底记录 + 推最新快照（自愈第二通道）
  onUpdateForm(formId: string, _wantParams?: Record<string, Object>): void {
    addWidgetFormId(this.context, formId);
    pushWidgetState(this.context);
  }

  // ★ 0.204.3：规格变化（1=1×2 2=2×2 3=2×4 4=4×4）→ 记 dimension + formId 自愈第三通道
  //  （卸载重装后系统不重触发 onAddForm——残留/重加卡片经任何生命周期回调都回记 formId）
  onSizeChanged(formId: string, newDimension: formInfo.FormDimension, _newRect: formInfo.Rect): void {
    addWidgetFormId(this.context, formId);
    setWidgetDimension(this.context, newDimension);
  }

  onRemoveForm(formId: string): void {
    removeWidgetFormId(this.context, formId);
  }

  onCastToNormalForm(_formId: string): void {
    // 保留空实现（当前无临时卡片场景）
  }
}
