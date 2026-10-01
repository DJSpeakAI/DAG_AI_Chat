// 从 webfetch 保存的文件中提取 TTS 查证信息（v2：正则容错版）
const fs = require('fs');
const D = 'C:/Users/Administrator/.local/share/.codeartsdoer/tool-output/';

// 1. PyPI volcengine-python-sdk：README(description) 中搜 tts/speech/audio 关键词
try {
  const raw = fs.readFileSync(D + 'tool_0f8ebc786001NhoVIkltEpOy3C', 'utf8');
  const d = JSON.parse(raw);
  const desc = d.info.description || '';
  console.log('README 长度:', desc.length);
  // 找关键词上下文
  ['tts', 'speech', 'audio', '语音'].forEach(kw => {
    const re = new RegExp('.{40}' + kw + '.{60}', 'gi');
    const hits = desc.match(re) || [];
    console.log('\n[' + kw + '] 命中 ' + hits.length + ' 处:');
    hits.slice(0, 4).forEach(h => console.log('  ...' + h.replace(/\n/g, ' ') + '...'));
  });
} catch (e) { console.log('PyPI 解析失败:', e.message); }

console.log('\n=== TalkifyTTS volc 文件（正则提取） ===');
// 2. TalkifyTTS 文件树：正则提取 path（不依赖 JSON 完整性）
try {
  const s = fs.readFileSync(D + 'tool_0f8e8e5f0001koF4yOi8cF0e5u', 'utf8');
  const all = s.match(/"path": "[^"]*"/g) || [];
  console.log('文件树总条目:', all.length);
  const volc = all.filter(p => /volc/i.test(p));
  console.log('volc 相关 (' + volc.length + ' 个):');
  volc.forEach(p => console.log('  ' + p.replace('"path": "', '').replace('"', '')));
} catch (e) { console.log('TalkifyTTS 读取失败:', e.message); }
