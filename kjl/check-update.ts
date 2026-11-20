/**
 * KJL-OFFICE — 更新检查已停用。
 *
 * 本文件替换上游的 app/src/lib/check-update.ts。
 * 上游会访问 solomd.app/api/stats、GitHub Releases、Gitee Releases 三个源，
 * 并在发现新版本时引导下载官方安装包（等于把用户换回官方发行版）。
 * 改装版只保留同名导出，全部改为本地空实现，不产生任何出网请求。
 */
import { getVersion } from '@tauri-apps/api/app';

export interface UpdateResult {
  current: string;
  latest: string | null;
  hasUpdate: boolean;
  url: string;
  error: boolean;
}

export interface UpdateProgressPayload {
  version: string;
  downloaded: number;
  total: number | null;
  percent: number | null;
  source: string;
}

/** 始终 false。 */
export const isMasBuild = (): boolean => false;

/** 不做 Cloudflare trace 探测，直接返回 false。 */
export async function detectVisitorIsChina(): Promise<boolean> {
  return false;
}

/** 永远返回“无更新”，UI 不会弹更新提示。 */
export async function checkForUpdate(): Promise<UpdateResult> {
  const current = await getVersion().catch(() => '0.0.0');
  return { current, latest: null, hasUpdate: false, url: '', error: false };
}

/** 空实现：不打开任何官方页面。 */
export async function openReleaseUrl(_url: string, _version?: string | null): Promise<void> {
  /* intentionally empty */
}

/** 永远返回 false，不会跳转到下载页。 */
export async function downloadAndInstallUpdate(
  _version: string,
  _onProgress?: (p: UpdateProgressPayload) => void,
): Promise<boolean> {
  return false;
}

/** 启动时检查：直接返回 null。 */
export async function checkForUpdateOnStartup(): Promise<UpdateResult | null> {
  return null;
}
