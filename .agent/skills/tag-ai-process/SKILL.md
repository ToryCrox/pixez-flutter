---
name: tag-ai-process
description: 从数据库读取高频未处理标签，AI 分析并生成导入 JSON
---

# 标签智能处理 Skill

每次从 `downloaded_tags` 表读取 50 条插画数量最多且未分类的标签，交由 AI 分析后生成 `tag_updates.json` 供 App 导入。

## 前置条件

- 数据库路径：`E:\Pictures\pixez_downloads\download.db`
- 数据库中已有 `downloaded_tags` 表（需要先在 App 中执行「同步标签」）

## 执行步骤

### 1. 读取待处理标签

// turbo
执行以下 SQL 查询未分类（`category = 0`）的标签，按 `count` 降序排列，取前 50 条：

```powershell
sqlite3 "E:\Pictures\pixez_downloads\download.db" ".mode json" "SELECT id, name, translated_name, custom_translated_name, category, count, parent_id, referenced_tag_id FROM downloaded_tags WHERE category = 0 AND count > 0 ORDER BY count DESC LIMIT 50" > e:\Workspace\flutter\pixez_flutter\build\pending_tags.json
```

### 2. AI 分析标签

对查询结果中的每个标签，根据以下规则进行分析：

**信息导出规则（必做）**：
为了提取归属并彻底杜绝重复查询数据库，在开始分析标签前，**必须执行以下命令**导出当前的标签上下文数据（包含未分类、作品分类及数量统计）：
```powershell
sqlite3 "E:\Pictures\pixez_downloads\download.db" ".mode json" "SELECT name, translated_name, custom_translated_name, category, count FROM downloaded_tags WHERE category IN (0, 1) ORDER BY count DESC" > e:\Workspace\flutter\pixez_flutter\build\tag_context.json
```
将此导出的 JSON 文件内容作为本地上下文库，唯一且直接地用于判断 `parent_name` 是否存在，以及匹配最高级的同义主标签。

**分类规则**（`category` 值）：
- `1` = 作品（动漫/游戏/漫画作品名，如 `Fate/Grand_Order`、`原神`）
- `2` = 角色（角色名，如 `セイバー`、`Saber`）
- `6` = 特点（身体特征/服装/姿势，如 `おっぱい`、`黒タイツ`）
- `4` = 通用（通用描述，如 `1girl`、`solo`）
- `5` = 元数据（图片本身的属性，如 `highres`、`absurdres`、`commentary`）
- `0` = 无法判断时保持未分类

**翻译规则**：
- **核心要求**：翻译内容必须**符合市面上公认的官方翻译或权威渠道译名**。对于 ACG（动漫/游戏/小说）相关的标签，应优先采用官方代理、维基百科（萌娘百科/维基百科）或网络上广泛流传的标准译名。
- **实时同步**：如果对译名不确定，应主动通过 `search_web` 查询网络上的最新翻译，确保与主流用法同步。
- **中文标签**：
  - 如果 `translated_name` 为空 → 不需要额外翻译（标签本身就是中文）
  - 如果 `translated_name` 不为空但不是中文 → 需要提供中文翻译，或者 `custom_translated_name` 直接设为标签的 `name`（因为 name 本身就是中文）
- **日文标签** → 提供标准的中文翻译。若为作品或角色名，必须使用官方/常用译名。
- **英文标签** → 如果有常用中文名则提供（如 `maid` → `女仆`），否则保留英文。

**归属规则**：
- **核心原则**：分析归属时，**必须直接读取 `e:\Workspace\flutter\pixez_flutter\build\tag_context.json` 文件进行查找匹配，绝对不要再使用 SQL 重复查询数据库**。
- 角色标签名中包含 `（作品名）` 或 `(作品名)` → 在 `tag_context.json` 中查找该作品，设置 `parent_name` 为匹配到的 **`name` 字段值**。
- 角色标签名中没有包含作品名 → 使用 `search_web` 工具确认角色所属作品，然后在 `tag_context.json` 中查找对应的作品，获取其 **`name` 字段值**。
- **重要**：同一个作品可能有多个同义 tag（如 `fgo` 和 `Fate/Grand_Order`），`parent_name` 应指向在 `tag_context.json` 文件中 `count` 最高或名称最完整的主标签的 `name` 字段。
- **父标签必须在 `tag_context.json` 中存在**：赋给 `parent_name` 的值必须是对应标签在 JSON 里的原始名（`name` 字段），**严禁使用翻译名**。
- 如果不确定归属，或者在 `tag_context.json` 中无法匹配到该作品项，可留空 `parent_name`。

**额外归属规则**：
以下为自定义归属映射，优先于默认归属规则：
- 隶属于 **彩虹社（にじさんじ / Nijisanji）** 的角色 → `parent_name` 设为 `バーチャルYouTuber`
- 隶属于 **Hololive** 的角色 → `parent_name` 设为 `バーチャルYouTuber`
- 其他虚拟主播（VTuber）→ `parent_name` 设为 `バーチャルYouTuber`

### 3. 生成结果 JSON

将分析结果写入项目 `build` 目录下的 `tag_updates.json`（路径：`e:\Workspace\flutter\pixez_flutter\build\tag_updates.json`）：

```json
{
  "version": 1,
  "updates": [
    {
      "name": "原始标签名（必须与数据库 name 字段字形、字符完全一致，严禁转换繁简或修改日文汉字）",
      "category": 2,
      "custom_translated_name": "中文翻译（推荐使用简体中文，null 表示不更改）",
      "parent_name": "父标签的原名（对应 tag_context.json 中的 `name` 字段，null 表示不设置，必须在上下文库中存在，严禁使用翻译名）",
      "reason": "分析理由（仅供预览显示）"
    }
  ]
}
```

### 4. 完成提示

告知用户 JSON 已生成，可在 App 标签管理页中使用「导入标签数据」功能加载。

## 注意事项

- **字符一致性（核心）**：JSON 中的 `name` 字段是查找记录的唯一标识。**绝对禁止**将数据库中的繁体字、日文汉字自动转换为简体中文。例如数据库中是 `鳴潮`，`name` 必须写 `鳴潮` 而不是 `鸣潮`。
- 每次只处理 50 条，重复调用此 Skill 可继续处理余下标签
- 已分类的标签（`category != 0`）不会被查询到，自动跳过
- 如标签含义不确定，`category` 保持 `0`（未分类），`custom_translated_name` 设为 `null`
- `reason` 字段帮助用户在 App 中预览时理解建议依据
- 归属不确定时宁可不填，不要猜测
- 父标签必须能在 tag_context.json 中查找到，否则切勿猜测并查询数据库，应直接不设置归属
