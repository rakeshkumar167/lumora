// Synthetic ambient input for effects whose pointer/scroll IS the effect.
// Replaces live mouse/scroll with a slow, smooth wandering signal derived
// from performance.now(), so ported CodePen effects self-animate.
const state = {
  // Normalized pointer in [-1, 1] (screen-centered).
  pointer: { x: 0, y: 0 },
  // Normalized pointer in [0, 1] (top-left origin), for pens that expect that.
  pointer01: { x: 0.5, y: 0.5 },
  // Looping progress in [0, 1] for scroll-driven pens.
  progress: 0,
};

function update(nowMs) {
  const t = (nowMs ?? performance.now()) / 1000;
  // Slow Lissajous wander — irrational frequency ratio so it never repeats.
  const x = Math.sin(t * 0.11) * 0.6 + Math.sin(t * 0.037) * 0.3;
  const y = Math.cos(t * 0.09) * 0.6 + Math.cos(t * 0.041) * 0.3;
  state.pointer.x = Math.max(-1, Math.min(1, x));
  state.pointer.y = Math.max(-1, Math.min(1, y));
  state.pointer01.x = state.pointer.x * 0.5 + 0.5;
  state.pointer01.y = state.pointer.y * 0.5 + 0.5;
  // 0→1 ramp over ~24s, then smooth loop.
  const phase = (t / 24) % 1;
  state.progress = 0.5 - 0.5 * Math.cos(phase * Math.PI * 2);
  return state;
}

export const pointer = state.pointer;
export const pointer01 = state.pointer01;
export function getProgress() { return state.progress; }
export { update, state };
export default state;
