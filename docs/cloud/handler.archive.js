// ============================================================
// track-events 云函数 — 接收 Pad 埋点批次写入 Cloud DB events 表
// 部署：①函数 zip（本文件 + package.json + agc-credential.json 根目录平铺）
//       ②依赖层 cloud-server-deps（node_modules——层目录 /dcache/layer 是
//         函数目录 /dcache/layer/func 的上一级，Node 向上查找命中）
// 凭证：AGC 控制台 → 项目设置 �� Server SDK 页签 → 认证凭据下载
//       （agc-apiclient-xxx.json，含 client_secret ——绝不入 git/外传）
// API 真相（cloud-server@1.0.5 d.ts 实查）：CloudDBZoneGenericObject 在 database-service/request/
//   下（build(类型名)+addFieldValue(字段,值,isPrimaryKey)——plain object 路径不标记主键，
//   服务端报 3037003 input data does not contain the primary key field，必须用此路径）
// ============================================================
const { cloud, Region, CloudDBZoneGenericObject } = require('@hw-agconnect/cloud-server');
// 项目级凭证初始化（__dirname=云函数运行目录 /dcache/layer/func）
const inst = cloud.createInstance(__dirname + '/agc-credential.json', 'trackEvents', Region.REGION_CN);

async function myHandler(event, context, callback, logger) {
  logger.info('TE start');
  try {
    // 1. 解析参数——多形态兼容：
    //   ① event.events 是字符串（客户端 callFunction params: JSON.stringify）
    //   ② event.events 是数组（测试面板直贴纯 JSON——零转义，粘贴不吃反斜杠）
    //   ③ event.body 内嵌（HTTP 网关形态） ④ event 本身是串
    let raw = null;
    let directList = null;
    try {
      if (event && typeof event === 'object') {
        if (typeof event.events === 'string') {
          raw = event.events;
        } else if (Array.isArray(event.events)) {
          directList = event.events;
        } else if (event.body) {
          const body = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
          if (body && typeof body.events === 'string') {
            raw = body.events;
          } else if (body && Array.isArray(body.events)) {
            directList = body.events;
          }
        }
      } else if (typeof event === 'string') {
        const parsed = JSON.parse(event);
        if (typeof parsed.events === 'string') {
          raw = parsed.events;
        } else if (Array.isArray(parsed.events)) {
          directList = parsed.events;
        }
      }
    } catch (e) {
      logger.warn('TE parse outer fail: ' + e.message);
    }
    if (!raw && !directList) {
      logger.warn('TE no events param, event=' + JSON.stringify(event).slice(0, 200));
      callback({ code: 1, msg: 'no events' });
      return;
    }
    // 2. 解析事件数组
    let list = [];
    if (directList) {
      list = directList;
    } else {
      try {
        list = JSON.parse(raw);
      } catch (e) {
        logger.error('TE parse fail: ' + e.message);
        callback({ code: 2, msg: 'bad events json' });
        return;
      }
    }
    if (!Array.isArray(list) || list.length === 0) {
      callback({ code: 0, msg: 'empty', n: 0 });
      return;
    }
    logger.info('TE parsed n=' + list.length);
    // 3. 写 Cloud DB（存储区 default；e+t 复合主键显式标记——upsert 幂等，客户端重试重发不产生重复行）
    const db = inst.database({ zoneName: 'default' });
    const coll = db.collection('events');
    const records = list.map(function (ev) {
      const obj = CloudDBZoneGenericObject.build('events');
      obj.addFieldValue('e', String(ev && ev.e ? ev.e : ''), true);
      obj.addFieldValue('p', String(ev && ev.p ? ev.p : ''));
      obj.addFieldValue('t', Number(ev && ev.t ? ev.t : Date.now()), true);
      return obj;
    });
    const n = await coll.upsert(records);
    logger.info('TE wrote n=' + n);
    callback({ code: 0, msg: 'ok', n: n });
  } catch (e) {
    logger.error('TE error: ' + (e && e.message ? e.message : String(e)));
    callback({ code: 3, msg: 'db error', err: e && e.message ? e.message : String(e) });
  }
}

exports.myHandler = myHandler;
