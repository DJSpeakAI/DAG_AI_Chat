// FireworksOverlay.ets — ★ 0.254.0 复习完成页烟花层（全屏 Canvas，命令式绘制）
// ★ 0.255.1 两项重构：
//   ①密度翻三倍以上（用户实测评级「最多同屏 1~2 个，至少要五六个」）——
//     并发发射体 4→14 / 粒子上限 440→1400 / 自动间隔 1.3s→0.45s / 自动改双发 → 同屏 6~8 束；
//   ②点击无反应根治（0.254.0 垫底层赌命中穿透，上层 Column 铺满内容区拦截不可靠）——
//     本层移 Stack 顶层 + hitTestBehavior(Transparent)：点空白=放烟花，事件透传下层按钮不遮蔽；
//     拖尾随之改 destination-out 半透明擦除（Canvas 背景保持透明，顶层不遮完成页内容）。
//   ③两阶段表演（用户拍板「先自动放一段时间，放完用户可点击继续放」）：
//     自动高密度 8s → 之后静默等点击；点击任何时候都立即响应（自动+手动可同时存在）。
// 物理算法不变（桌面 123.txt 移植）：发射体底部飞向目标 → 到达爆 55 粒（随机方向·初速
// 65~210vp/s）→ 重力 65 / 指数阻力 exp(-0.6·dt) / 寿命 1.2~1.8s。
const FW_ROCKET_MAX = 14;      // 发射体并发上限（0.255.1：4→14 密度×3）
const FW_PARTICLE_MAX = 1400;  // 粒子上限（0.255.1：440→1400；超限暂缓/减量）
const FW_BURST_COUNT = 55;     // 每束粒子数（123.txt）
const FW_GRAVITY = 65;         // 重力 vp/s²（123.txt）
const FW_DRAG = 0.6;           // 指数阻力系数（123.txt）
const FW_ROCKET_SPEED = 430;   // 发射体飞行速度 vp/s（0.6~0.9s 到达上半屏）
const FW_AUTO_FIRST = 0.2;     // 自动表演首发延迟 s（进完成页即见）
const FW_AUTO_GAP = 0.45;      // 自动表演平均间隔 s（0.255.1：1.3→0.45 密度×3）
const FW_AUTO_DURATION = 8;    // 自动表演时长 s（两阶段：之后静默，等用户点击续放）
const FW_TRAIL_FADE = 0.25;    // destination-out 每帧擦除透明度（拖尾强度，同 123.txt 25%）

// 发射体：从底部出发，携带目标点 tx/ty（123.txt：到达后 burst 并移除）
class FwRocket {
  x: number = 0;
  y: number = 0;
  vx: number = 0;
  vy: number = 0;
  tx: number = 0;
  ty: number = 0;
  hue: number = 0;

  constructor(x: number, y: number, vx: number, vy: number, tx: number, ty: number, hue: number) {
    this.x = x;
    this.y = y;
    this.vx = vx;
    this.vy = vy;
    this.tx = tx;
    this.ty = ty;
    this.hue = hue;
  }
}

// 爆炸粒子：px/py 上一帧位置（画拖尾线段用），maxLife 归一化寿命算透明度
class FwParticle {
  x: number = 0;
  y: number = 0;
  px: number = 0;
  py: number = 0;
  vx: number = 0;
  vy: number = 0;
  hue: number = 0;
  life: number = 0;
  maxLife: number = 0;

  constructor(x: number, y: number, vx: number, vy: number, hue: number, life: number) {
    this.x = x;
    this.y = y;
    this.px = x;
    this.py = y;
    this.vx = vx;
    this.vy = vy;
    this.hue = hue;
    this.life = life;
    this.maxLife = life;
  }
}

// hue(0~360) → rgba 字符串（s=100%；HSL→RGB 标准公式，不依赖 hsla 字符串解析兼容性）
function fwHueColor(hue: number, light: number, alpha: number): string {
  const hp = (((hue % 360) + 360) % 360) / 60;
  const c = 1 - Math.abs(2 * light - 1);
  const xx = c * (1 - Math.abs(hp % 2 - 1));
  let r = 0;
  let g = 0;
  let b = 0;
  if (hp < 1) {
    r = c;
    g = xx;
  } else if (hp < 2) {
    r = xx;
    g = c;
  } else if (hp < 3) {
    g = c;
    b = xx;
  } else if (hp < 4) {
    g = xx;
    b = c;
  } else if (hp < 5) {
    r = xx;
    b = c;
  } else {
    r = c;
    b = xx;
  }
  const m = light - c / 2;
  const to255 = (v: number): number => Math.round((v + m) * 255);
  return `rgba(${to255(r)},${to255(g)},${to255(b)},${alpha.toFixed(3)})`;
}

@ComponentV2
export struct FireworksOverlay {
  private ctxSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.ctxSettings);
  private rockets: FwRocket[] = [];
  private particles: FwParticle[] = [];
  private timerId: number = -1;
  private lastMs: number = 0;
  private autoWait: number = FW_AUTO_FIRST;
  private autoElapsed: number = 0;  // 自动表演已放秒数（两阶段闸门）
  private idleFrames: number = 0;   // 全空后持续擦残影帧数（擦净后跳帧省电）
  private canvasW: number = 0;
  private canvasH: number = 0;

  aboutToDisappear(): void {
    this.stopLoop(); // 铁律：定时器销毁必清（离开完成页/页面 pop）
  }

  private startLoop(): void {
    if (this.timerId >= 0 || this.canvasW <= 0 || this.canvasH <= 0) {
      return;
    }
    this.lastMs = Date.now();
    this.timerId = setInterval(() => this.tick(), 16);
  }

  private stopLoop(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private tick(): void {
    const now = Date.now();
    let dt = (now - this.lastMs) / 1000;
    this.lastMs = now;
    if (dt <= 0 || dt > 0.08) {
      dt = 1 / 60; // 123.txt：真实时间差，上限 0.08s 防大步长穿模
    }
    // 两阶段闸门：8s 高密度自动表演，之后静默等点击（点击任何时候都响应）
    if (this.autoElapsed < FW_AUTO_DURATION) {
      this.autoElapsed += dt;
      this.autoWait -= dt;
      if (this.autoWait <= 0) {
        this.autoLaunch();
        this.autoWait = FW_AUTO_GAP * (0.8 + Math.random() * 0.5);
      }
    }
    this.update(dt);
    this.draw();
  }

  /** 手动点击入口：点击处一发 + 邻近随机一发（双发反馈，0.255.1 密度诉求） */
  launchAt(tx: number, ty: number): void {
    this.launchRocket(tx, ty);
    this.launchRocket(tx + (Math.random() - 0.5) * 140, ty + (Math.random() - 0.5) * 110);
  }

  /** 单发发射体；满载/粒子临上限时目标点原地即爆（连点永远有反馈） */
  private launchRocket(tx: number, ty: number): void {
    if (this.canvasW <= 0) {
      return;
    }
    const hue = Math.random() * 360;
    if (this.rockets.length >= FW_ROCKET_MAX || this.particles.length > FW_PARTICLE_MAX - FW_BURST_COUNT) {
      this.burst(tx, ty, hue);
      return;
    }
    const x = this.canvasW * (0.15 + Math.random() * 0.7);
    const y = this.canvasH + 10;
    const ang = Math.atan2(ty - y, tx - x);
    this.rockets.push(new FwRocket(x, y,
      Math.cos(ang) * FW_ROCKET_SPEED, Math.sin(ang) * FW_ROCKET_SPEED, tx, ty, hue));
  }

  /** 自动表演：双发错落（0.255.1 密度×3 核心——间隔 0.45s × 双发 ≈ 同屏 6~8 束） */
  private autoLaunch(): void {
    if (this.canvasW <= 0) {
      return;
    }
    const tx = this.canvasW * (0.1 + Math.random() * 0.8);
    const ty = this.canvasH * (0.12 + Math.random() * 0.33);
    this.launchRocket(tx, ty);
    this.launchRocket(this.canvasW * (0.1 + Math.random() * 0.8), this.canvasH * (0.1 + Math.random() * 0.35));
  }

  /** 目标点爆一圈粒子（123.txt burst：随机方向·初速 65~210·寿命 1.2~1.8） */
  private burst(x: number, y: number, hue: number): void {
    let n = FW_BURST_COUNT;
    if (this.particles.length > FW_PARTICLE_MAX - 30) {
      n = 24; // 接近上限减量（123.txt「暂缓」的柔和版——保留反馈不闷响）
    }
    for (let i = 0; i < n; i++) {
      const ang = Math.random() * Math.PI * 2;
      const spd = 65 + Math.random() * 145;
      const life = 1.2 + Math.random() * 0.6;
      this.particles.push(new FwParticle(x, y, Math.cos(ang) * spd, Math.sin(ang) * spd, hue, life));
    }
  }

  private update(dt: number): void {
    // 发射体推进；到达（剩余距离 < 本帧步长+余量）→ burst 并移除
    const aliveRockets: FwRocket[] = [];
    const step = FW_ROCKET_SPEED * dt + 4;
    for (let i = 0; i < this.rockets.length; i++) {
      const r = this.rockets[i];
      r.x += r.vx * dt;
      r.y += r.vy * dt;
      const dx = r.tx - r.x;
      const dy = r.ty - r.y;
      if (dx * dx + dy * dy <= step * step) {
        this.burst(r.x, r.y, r.hue);
      } else {
        aliveRockets.push(r);
      }
    }
    this.rockets = aliveRockets;
    // 粒子物理（123.txt stepParticle：vx 指数阻力 / vy 只加重力；寿命尽移除）
    const alive: FwParticle[] = [];
    for (let i = 0; i < this.particles.length; i++) {
      const p = this.particles[i];
      p.px = p.x;
      p.py = p.y;
      p.vx *= Math.exp(-FW_DRAG * dt);
      p.vy += FW_GRAVITY * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.life -= dt;
      if (p.life > 0) {
        alive.push(p);
      }
    }
    this.particles = alive;
  }

  private draw(): void {
    if (this.canvasW <= 0 || this.canvasH <= 0) {
      return;
    }
    // 全空且残影已擦净（25 帧 ≈ 0.4s，残 alpha≈0.01% 肉眼不可见）→ 跳帧省电
    if (this.idleFrames >= 25) {
      return;
    }
    const ctx = this.ctx;
    // 透明拖尾（0.255.1 顶层方案）：destination-out 每帧擦掉 25% 已有像素——
    // 拖尾成型且 Canvas 背景保持透明，不遮下层完成页内容（替代 0.254.0 不透明铺底）
    ctx.globalCompositeOperation = 'destination-out';
    ctx.fillStyle = `rgba(0,0,0,${FW_TRAIL_FADE})`;
    ctx.fillRect(0, 0, this.canvasW, this.canvasH);
    ctx.globalCompositeOperation = 'source-over';
    ctx.lineCap = 'round'; // CanvasLineCap 为字符串字面量类型（'butt'|'round'|'square'）非枚举
    // 发射体：彩色短尾 + 白亮头
    for (let i = 0; i < this.rockets.length; i++) {
      const r = this.rockets[i];
      ctx.strokeStyle = fwHueColor(r.hue, 0.75, 0.9);
      ctx.lineWidth = 2.4;
      ctx.beginPath();
      ctx.moveTo(r.x - r.vx * 0.03, r.y - r.vy * 0.03); // 30ms 尾迹
      ctx.lineTo(r.x, r.y);
      ctx.stroke();
      ctx.fillStyle = '#FFFFFF';
      ctx.beginPath();
      ctx.arc(r.x, r.y, 2, 0, Math.PI * 2);
      ctx.fill();
    }
    // 粒子：上一位置→当前位置线段，透明度随寿命衰减（123.txt draw 同款）
    for (let i = 0; i < this.particles.length; i++) {
      const p = this.particles[i];
      const a = Math.min(1, Math.max(0, p.life / p.maxLife));
      ctx.strokeStyle = fwHueColor(p.hue, 0.62, a);
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(p.px, p.py);
      ctx.lineTo(p.x, p.y);
      ctx.stroke();
    }
    if (this.rockets.length === 0 && this.particles.length === 0) {
      this.idleFrames++;
    } else {
      this.idleFrames = 0;
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.startLoop();
      })
      .onAreaChange((_o: Area, n: Area) => {
        this.canvasW = n.width as number;
        this.canvasH = n.height as number;
        this.startLoop(); // 尺寸变化重启循环节拍（分屏/悬浮窗安全）
      })
      .onClick((e: ClickEvent) => {
        this.launchAt(e.x, e.y); // 点击=点击处双发（Transparent 透传下层按钮，不遮蔽）
      })
  }
}
