// 带种子的确定性 RNG（mulberry32）。服务端权威，无需与 GDScript 的流一致，
// 只需自身可复现（回放、测试）。
export class Rng {
  constructor(seed) { this.s = seed >>> 0; }
  next() { // [0,1)
    this.s = (this.s + 0x6D2B79F5) >>> 0;
    let t = this.s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
  randiRange(a, b) { return a + Math.floor(this.next() * (b - a + 1)); } // 双闭
  randf() { return this.next(); }
  state() { return this.s; }
  setState(s) { this.s = s >>> 0; }
}
