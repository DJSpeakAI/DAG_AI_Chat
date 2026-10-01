// 从 Sourcegraph 结果提取目标文件的 commit hash + 完整匹配行
const fs = require('fs');
const F = 'C:/Users/Administrator/.local/share/.codeartsdoer/tool-output/tool_0f8edfef7001K8QDi35gShm1W0';
const s = fs.readFileSync(F, 'utf8');
const dataLines = s.split('\n').filter(l => l.startsWith('data: ') && !l.includes('"done"'));
let entries = [];
for (const l of dataLines) {
  try {
    const arr = JSON.parse(l.slice(6));
    if (Array.isArray(arr)) entries = entries.concat(arr);
  } catch (e) {}
}

// 目标文件
const targets = [
  ['labring/aiproxy', 'core/relay/adaptor/doubaoaudio/constants.go'],
  ['JiaCheng2004/Polaris', 'internal/provider/bytedance/voice.go'],
  ['xixihhhh/clipforge', 'src/lib/tts-presets.ts'],
  ['sumarilkkxx/Mora', 'src/lib/tts-presets.ts'],
  ['calesthio/OpenMontage', 'tools/audio/doubao_tts.py'],
  ['justlovemaki/Podcast-Generator', 'server/podcast_generator.py'],
  ['justlovemaki/Podcast-Generator', 'server/main.py'],
  ['CCCpan/ai-api-integration', 'docs/modalities/audio.md'],
  ['oomol-lab/open-connector', 'src/providers/fusion-api/operations.ts'],
  ['EvovexAI/EvoFlow', 'backend/packages/harness/evoflow/plans/volc_agent_plan_models.py'],
];

for (const [repo, path] of targets) {
  const hits = entries.filter(e => (e.repository || '').includes(repo) && (e.path || '') === path);
  if (hits.length === 0) { console.log('[未命中] ' + repo + ' :: ' + path); continue; }
  const e = hits[0];
  console.log('=== ' + repo + ' :: ' + path + ' ===');
  console.log('commit: ' + (e.commit || '无'));
  const content = (e.lineMatches || []).map(m => (m.line || '').trim());
  console.log('匹配行 (' + content.length + '):');
  content.slice(0, 15).forEach(c => console.log('  ' + c));
  console.log('');
}
