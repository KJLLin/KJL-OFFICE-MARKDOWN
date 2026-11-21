/**
 * KJL-OFFICE 构建开关。
 *
 * 两个开关互相独立，都只开/关入口，功能与文案代码一律保留。
 *   · KJL_SUPPORT_PROMPTS —— 打赏 / 赞助（支持者徽章、打赏卡片、关于页「支持开发者」「帮忙推广」、赞助者名单）
 *   · KJL_STAR_PROMPT     —— 若干天后一次性弹出的 GitHub Star 邀请（指向本仓库）
 *   · KJL_TELEMETRY_NOTICE —— 首启的「是否关闭匿名使用统计」提示条（本项目已彻底不发统计，故默认关闭）
 */
export const KJL_SUPPORT_PROMPTS = false;
export const KJL_STAR_PROMPT = true;
export const KJL_TELEMETRY_NOTICE = false;
