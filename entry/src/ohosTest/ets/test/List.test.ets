import abilityTest from './Ability.test';
import mdInlineTest from './MdInline.test';
import siyiPointTest from './SiyiPoint.test'; // ★ 0.248.7：SP 实扣链路纯函数断言
import signInTest from './SignIn.test'; // ★ 0.256.0：签到连签递增/里程碑/防重复纯函数断言
import memoryEngineTest from './MemoryEngine.test'; // ★ 0.265.0：记忆引擎画像聚合/演变链/埋点滚动/树距离衰减断言
import hookMergeTest from './HookMerge.test'; // ★ 0.269.0：钩子两段式合成器（JSON 兜底/钳位/bait 截断/progress 保底/导出过滤）断言
import aiRerankTest from './AiRerank.test'; // ★ 0.268.0：AI 智慧排序（序号解析容错/未来卡≤1末位/护栏矩阵）断言
import thinkingScoreTest from './ThinkingScore.test'; // ★ 0.271.0：深度思考（计分矩阵/策略矩阵/降级窄门/归一）断言

export default function testsuite() {
  abilityTest();
  mdInlineTest();
  siyiPointTest();
  signInTest();
  memoryEngineTest();
  hookMergeTest();
  aiRerankTest();
  thinkingScoreTest();
}
