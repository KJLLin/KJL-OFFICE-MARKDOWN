/**
 * KJL-OFFICE — 遥测已停用。
 *
 * 本文件替换上游的 app/src/lib/telemetry.ts。
 * 上游实现会把匿名事件 POST 到 solomd.app/api/track；改装版不保留任何上报行为。
 * 对外 API 保持原状（`track(event, props)`），因此所有调用点无需改动。
 */

export type EventProps = Record<string, string | number | boolean>;

/** 空实现：不读取设置、不生成 anon id、不发任何网络请求。 */
export function track(_event: string, _props?: EventProps): void {
  /* intentionally empty */
}
