/**
 * KJL-OFFICE 构建开关。
 *
 * 两个开关互相独立，都只开/关入口，功能与文案代码一律保留。
 *   · KJL_SUPPORT_PROMPTS —— 打赏 / 赞助（支持者徽章、打赏卡片、关于页「支持开发者」「帮忙推广」、赞助者名单）
 *   · KJL_STAR_PROMPT     —— 若干天后一次性弹出的 GitHub Star 邀请（指向本仓库）
 *   · KJL_TELEMETRY_NOTICE —— 首启的「是否关闭匿名使用统计」提示条（本项目已彻底不发统计，故默认关闭）
 *   · KJL_TELEMETRY_SETTINGS —— 设置页「发送匿名使用数据」复选框（默认隐藏）
 *   · KJL_UPDATE_SETTINGS —— 设置页「自动检查更新」一项与帮助菜单的检查更新入口（默认隐藏；本构建不发版到上游更新源）
 */
export const KJL_SUPPORT_PROMPTS = false;
export const KJL_STAR_PROMPT = true;
export const KJL_TELEMETRY_NOTICE = false;
export const KJL_TELEMETRY_SETTINGS = false;
export const KJL_UPDATE_SETTINGS = false;
