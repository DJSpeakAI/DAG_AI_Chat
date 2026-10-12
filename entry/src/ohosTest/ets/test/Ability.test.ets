import { describe, it, expect, beforeEach, afterEach } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { bundleManager } from '@kit.AbilityKit';

export default function abilityTest() {
  describe('DAGAI_ArkUITest', () => {
    beforeEach(() => {
    })
    afterEach(() => {
    })
    it('app_context_ready', 0, () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      expect(delegator !== null && delegator !== undefined).assertTrue();
    })
    it('bundle_versioncode_valid', 0, async (done: Function) => {
      const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      expect(info.name).assertEqual('com.dagaichat.app');
      expect(info.versionCode).assertLarger(0);
      done();
    })
  })
}