const fs = require('fs');
const p = '/storage/Users/currentUser/project/DAG_AI_Chat/entry/src/main/ets/components/ChatPage.ets';
const raw = fs.readFileSync(p, 'utf8');
const NL = raw.includes('\r\n') ? '\r\n' : '\n';
const L = (s) => s.split('\n').join(NL);
const oldStr = L(`      this.imageViewerVisible = false; // 图片预览（0.120）
      return true;
    }
    }
    if (this.wordFolderPickerVisible) {`);
const newStr = L(`      this.imageViewerVisible = false; // 图片预览（0.120）
      return true;
    }
    if (this.wordFolderPickerVisible) {`);
const c = raw.split(oldStr).length - 1;
if (c !== 1) { console.error('MATCH=' + c + ' 中止'); process.exit(1); }
fs.writeFileSync(p, raw.replace(oldStr, newStr));
console.log('OK 孤立括号已删');