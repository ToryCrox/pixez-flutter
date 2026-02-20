---
description: 从数据库读取高频未处理标签，AI 分析并生成导入 JSON
---

# 标签智能处理 Skill

每次从 `downloaded_tags` 表读取 20 条插画数量最多且未分类的标签，交由 AI 分析后生成 `tag_updates.json` 供 App 导入。

## 前置条件

- 数据库路径：`E:\Pictures\pixez_downloads\download.db`
- 数据库中已有 `downloaded_tags` 表（需要先在 App 中执行「同步标签」）

## 执行步骤

### 1. 读取待处理标签

// turbo
执行以下 SQL 查询未分类（`category = 0`）的标签，按 `count` 降序排列，取前 20 条：

```powershell
sqlite3 "E:\Pictures\pixez_downloads\download.db" ".mode json" "SELECT id, name, translated_name, custom_translated_name, category, count, parent_id, referenced_tag_id FROM downloaded_tags WHERE category = 0 AND count > 0 ORDER BY count DESC LIMIT 20"
```

### 2. AI 分析标签

对查询结果中的每个标签，根据以下规则进行分析：

**信息导出规则（推荐）**：
为了提高匹配精度并减少重复查询数据库，建议在开始分析前，先导出当前的标签基础信息（特别是未分类和作品分类的标签）：
```powershell
sqlite3 "E:\Pictures\pixez_downloads\download.db" ".mode json" "SELECT name, translated_name, custom_translated_name, category FROM downloaded_tags WHERE category IN (0, 1)"
```
将此信息作为上下文，用于更准确地判断 `parent_name` 是否在库中存在，以及匹配同义主标签。

**分类规则**（`category` 值）：
- `1` = 作品（动漫/游戏/漫画作品名，如 `Fate/Grand_Order`、`原神`）
- `2` = 角色（角色名，如 `セイバー`、`Saber`）
- `6` = 特点（身体特征/服装/姿势，如 `おっぱい`、`黒タイツ`）
- `4` = 通用（通用描述，如 `1girl`、`solo`）
- `5` = 元数据（图片本身的属性，如 `highres`、`absurdres`、`commentary`）
- `0` = 无法判断时保持未分类

**翻译规则**：
- **中文标签**：
  - 如果 `translated_name` 为空 → 不需要额外翻译（标签本身就是中文）
  - 如果 `translated_name` 不为空但不是中文 → 需要提供中文翻译，或者 `custom_translated_name` 直接设为标签的 `name`（因为 name 本身就是中文）
- **日文标签** → 提供中文翻译
- **英文标签** → 如果有常用中文名则提供（如 `maid` → `女仆`），否则保留英文

**归属规则**：
- 角色标签名中包含 `（作品名）` 或 `(作品名)` → 设置 `parent_name` 为该作品名
- 角色标签名中没有包含作品名 → **优先从已导出的标签信息中匹配**，若无匹配再使用 `search_web` 工具确认角色所属作品
- **重要**：作品在数据库中可能有多个同义 tag（如 `fgo` 和 `Fate/Grand_Order`），`parent_name` 应指向**主 tag**（通常是 `count` 最高或名称最完整的那个）
- **父标签必须在数据库表 `downloaded_tags` 中存在**（参考导出的标签信息），如果不存在则不填 `parent_name`
- 如果不确定归属，可留空 `parent_name`

**额外归属规则**：
以下为自定义归属映射，优先于默认归属规则：
- 隶属于 **彩虹社（にじさんじ / Nijisanji）** 的角色 → `parent_name` 设为 `虚拟主播`
- 隶属于 **Hololive** 的角色 → `parent_name` 设为 `虚拟主播`
- 其他虚拟主播（VTuber）→ `parent_name` 设为 `虚拟主播`

### 3. 生成结果 JSON

将分析结果写入项目 `build` 目录下的 `tag_updates.json`（路径：`e:\Workspace\flutter\pixez_flutter\build\tag_updates.json`）：

```json
{
  "version": 1,
  "updates": [
    {
      "name": "原始标签名（必须与数据库 name 完全一致）",
      "category": 2,
      "custom_translated_name": "中文翻译（null 表示不更改）",
      "parent_name": "父标签名（用于归属，null 表示不设置，必须在数据库中存在）",
      "reason": "分析理由（仅供预览显示）"
    }
  ]
}
```

### 4. 完成提示

告知用户 JSON 已生成，可在 App 标签管理页中使用「导入标签数据」功能加载。

## 注意事项

- 每次只处理 20 条，重复调用此 Skill 可继续处理余下标签
- 已分类的标签（`category != 0`）不会被查询到，自动跳过
- 如标签含义不确定，`category` 保持 `0`（未分类），`custom_translated_name` 设为 `null`
- `reason` 字段帮助用户在 App 中预览时理解建议依据
- 归属不确定时宁可不填，不要猜测
- 父标签必须在数据库中存在，否则不设置归属
