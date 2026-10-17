import abilityTest from './Ability.test';
import mdInlineTest from './MdInline.test';
import siyiPointTest from './SiyiPoint.test'; // ★ 0.248.7：SP 实扣链路纯函数断言

export default function testsuite() {
  abilityTest();
  mdInlineTest();
  siyiPointTest();
}