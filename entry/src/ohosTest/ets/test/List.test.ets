import abilityTest from './Ability.test';
import mdInlineTest from './MdInline.test';
import siyiPointTest from './SiyiPoint.test'; // ★ 0.248.7：SP 实扣链路纯函数断言
import signInTest from './SignIn.test'; // ★ 0.256.0：签到连签递增/里程碑/防重复纯函数断言

export default function testsuite() {
  abilityTest();
  mdInlineTest();
  siyiPointTest();
  signInTest();
}