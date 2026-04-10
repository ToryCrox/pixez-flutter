---
name: tag-ai-process
description: 从数据库读取高频未处理标签，AI 分析并生成导入 JSON
---

# 标签智能处理 Skill

从 `downloaded_tags` 表读取高频未分类标签，先用本地脚本做预处理和校验，再让 AI 只处理真正需要判断的少数项，最后生成 `tag_updates.json` 供 App 导入。

目标：
- 更准确：把查库、别名归并、主标签选择、结果校验交给脚本
- 更快：一次预处理即可得到 AI 需要的压缩上下文
- 更省 token：AI 只看 `ai_tag_batch.json`，不再手动构建大 JSON 索引

## 前置条件

- 数据库路径：`E:\Pictures\pixez_downloads\download.db`
- 数据库中已有 `downloaded_tags` 表（需要先在 App 中执行「同步标签」）
- 在仓库根目录执行命令：`E:\Workspace\flutter\pixez_flutter`

## 执行步骤

### 1. 生成 AI 批次文件

先运行预处理脚本，不要直接把数据库大表喂给 AI：

```powershell
dart run .agent/skills/tag-ai-process/scripts/prepare_tag_ai_context.dart --db "E:\Pictures\pixez_downloads\download.db" --limit 50 --out "build\ai_tag_batch.json"
```

脚本会完成这些确定性工作：
- 读取前 50 条高频未分类标签
- 读取作品标签和 `バーチャルYouTuber`
- 按 `referenced_tag_id` 归并作品别名并选出主标签
- 为每条待处理标签生成 `signals`
- 对高置信度情况生成 `deterministic_suggestion`
- 标记哪些标签 `needs_ai`

生成文件：`build\ai_tag_batch.json`

### 2. 仅基于压缩批次文件分析

分析时只读取 `build\ai_tag_batch.json`，不要再去手动读取整库或重复查 SQL。

优先使用这些字段：
- `pending_tags`
- `signals`
- `deterministic_suggestion`
- `needs_ai`
- `ai_focus`
- `resolved_parent_reference`

分析原则：
- 有 `deterministic_suggestion` 时，优先沿用，除非你有明确证据判断它不对
- `needs_ai = false` 的标签不要继续展开推理
- 只对 `needs_ai = true` 的标签补充分类、翻译、归属
- `ai_focus` 里没有要求的事项，不要额外扩展

### 3. 分类规则

`category` 值：
- `1` = 作品（动漫/游戏/漫画作品名，如 `Fate/Grand_Order`、`原神`）
- `2` = 角色（角色名，如 `セイバー`、`Saber`）
- `6` = 特点（身体特征/服装/姿势，如 `おっぱい`、`黒タイツ`）
- `4` = 通用（通用描述，如 `1girl`、`solo`）
- `5` = 元数据（图片本身的属性，如 `highres`、`absurdres`、`commentary`）
- `0` = 无法判断时保持未分类

高优先级决策顺序：
1. 明显元数据词 → `5`
2. 明显通用人数/构图词 → `4`
3. 明显外观/服装/姿势词 → `6`
4. 已命中已有作品别名 → `1`
5. 角色名含 `（作品名）` / `(作品名)` 且父标签可解析 → `2`
6. 其余项由 AI 谨慎补判，仍不确定就保持 `0`

### 4. 翻译规则

目标是“必要时补充，非必要不覆盖”：
- 如果标签本身已经是自然中文，通常不填写 `custom_translated_name`
- 如果已有 `translated_name` 或 `custom_translated_name` 已是正确中文，不重复改写
- 只有在需要补足官方译名、修正错误翻译、或把日文/英文转为稳定中文名时，才填写 `custom_translated_name`
- 普通特征词优先用简洁常用中文，不写解释句
- 作品名、角色名优先使用官方译名、主流百科词条名或社区最稳定常用译名

### 5. 归属规则

只对角色类标签尝试填写 `parent_name`：
- 如果脚本已经给出 `resolved_parent_name`，优先直接使用
- `parent_name` 必须使用数据库中真实存在的原始 `name`
- 严禁使用翻译名作为 `parent_name`
- 如果归属不确定，宁可留空

额外归属映射，优先于普通归属规则：
- 隶属于 **彩虹社（にじさんじ / Nijisanji）** 的角色 → `parent_name` 设为 `バーチャルYouTuber`
- 隶属于 **Hololive** 的角色 → `parent_name` 设为 `バーチャルYouTuber`
- 其他虚拟主播（VTuber）→ `parent_name` 设为 `バーチャルYouTuber`

### 6. 严格控制联网

默认不联网。只有满足以下任一条件才允许联网查询：
- `ai_focus` 明确要求确认中文译名
- `ai_focus` 明确要求确认所属作品
- 同一标签存在多个常见译名，需要核实官方或主流用法

禁止为以下类型联网：
- `needs_ai = false` 的标签
- 明显通用标签
- 明显元数据标签
- 明显特征标签
- 仅需字面翻译即可解决的普通词

联网时的省 token 规则：
- 同系列只查询一次，结论复用到整批
- 查询目标只聚焦“标准中文名”和“所属作品”
- 不要展开背景故事、设定介绍、角色关系
- 单个标签无法确认时，宁可留空，也不要反复搜索

### 7. 生成结果 JSON

将分析结果写入 `build\tag_updates.json`：

```json
{
  "version": 1,
  "updates": [
    {
      "name": "原始标签名（必须与数据库 name 字段字形、字符完全一致，严禁转换繁简或修改日文汉字）",
      "category": 2,
      "custom_translated_name": "中文翻译（推荐使用简体中文，null 表示不更改）",
      "parent_name": "父标签的原名（必须在数据库中存在，严禁使用翻译名）",
      "reason": "分析理由（仅供预览显示）"
    }
  ]
}
```

输出约束：
- 只写“有实际建议”的项
- 如果某标签无法得出可靠变更，可以不写入 `updates`
- `reason` 保持简短，优先 8 到 20 个中文字符
- 不要把网页摘录、长解释或思维过程写进 JSON

推荐 `reason` 风格：
- `高频作品标签`
- `角色名含作品括号`
- `命中已有作品别名`
- `服装特征词`
- `Pixiv 常见元数据`
- `官方译名`

### 8. 校验结果 JSON

生成完后必须运行校验脚本：

```powershell
dart run .agent/skills/tag-ai-process/scripts/validate_tag_updates.dart --db "E:\Pictures\pixez_downloads\download.db" --input "build\tag_updates.json" --report "build\tag_updates.validation.json"
```

校验脚本会检查：
- `name` 是否在数据库中存在
- `parent_name` 是否存在
- `parent_name` 是否是主标签
- `category` 是否合法
- 是否存在重复项
- `reason` 是否过长
- 是否存在不会产生实际效果的无效更新

如果校验失败，先修正 `build\tag_updates.json`，再继续。

### 9. 完成提示

告知用户以下文件已生成：
- `build\ai_tag_batch.json`
- `build\tag_updates.json`
- `build\tag_updates.validation.json`

然后提示用户可在 App 标签管理页使用「导入标签数据」功能加载 `tag_updates.json`。

## 注意事项

- **字符一致性（核心）**：`name` 字段必须与数据库原值完全一致。绝对禁止繁简转换或修改日文汉字字形
- 优先信任脚本给出的高置信度建议，不要让模型重复做确定性工作
- 分析阶段不要重复执行 SQL 查询
- 不确定时宁可少写，也不要硬猜
- `updates` 少于 50 条是正常的，质量优先于覆盖率
