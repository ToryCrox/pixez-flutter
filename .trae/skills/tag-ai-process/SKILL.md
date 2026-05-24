---
name: tag-ai-process
description: 从数据库读取高频未处理标签，AI 分析并生成导入 JSON
---

# 标签智能处理 Skill

从 `downloaded_tags` 表读取高频未分类标签，先用本地脚本压缩上下文和做确定性判断，再让 AI 只处理少数需要语义确认的标签，最后生成 `tag_updates.json` 供 App 导入。

目标：
- 准确：数据库读取、作品别名归并、主标签选择、结果校验都交给脚本
- 省 token：分析阶段只读 `build\ai_tag_batch.json` 和 `build\bangumi_lookup.json`
- 可追溯：联网只在必要时使用，通过本地脚本封装 Bangumi 公开 OpenAPI，结论必须能映射回数据库原始标签
- 保守：不确定就少写，不为了覆盖率硬猜

## 前置条件

- 仓库根目录：`E:\Workspace\flutter\pixez_flutter`
- 默认数据库：`E:\Pictures\pixez_downloads\download.db`
- 数据库中已有 `downloaded_tags` 表，需要先在 App 中执行「同步标签」
- 生成和校验脚本位于 `.agent\skills\tag-ai-process\scripts`

## 总体流程

1. 运行预处理脚本生成 `build\ai_tag_batch.json`
2. 运行 Bangumi 查询脚本生成 `build\bangumi_lookup.json`
3. 只读取 `build\ai_tag_batch.json` 和 `build\bangumi_lookup.json` 进行分析
4. 先落地高置信 `deterministic_suggestion`
5. 只对 `needs_ai = true` 的标签做补判
6. 写入 `build\tag_updates.json`
7. 运行校验脚本，失败则修正后重跑

分析阶段不要手动读取整库或临时写 SQL。数据库存在性、父标签合法性、重复项和无效更新由校验脚本检查。

## 1. 生成 AI 批次文件

```powershell
dart run .agent/skills/tag-ai-process/scripts/prepare_tag_ai_context.dart --db "E:\Pictures\pixez_downloads\download.db" --limit 50 --out "build\ai_tag_batch.json"
```

脚本会完成：
- 读取前 50 条高频未分类标签
- 读取作品标签和 `バーチャルYouTuber`
- 按 `referenced_tag_id` 归并作品别名并选出主标签
- 为每条待处理标签生成 `signals`
- 对高置信情况生成 `deterministic_suggestion`
- 标记 `needs_ai` 和 `ai_focus`

输出文件：`build\ai_tag_batch.json`

## 2. 生成 Bangumi 查询文件

不要让 AI 手写 HTTP 请求；使用封装脚本查询公开 OpenAPI：

```powershell
dart run .agent/skills/tag-ai-process/scripts/bangumi_lookup.dart --input "build\ai_tag_batch.json" --out "build\bangumi_lookup.json"
```

脚本会完成：
- 只为 `needs_ai = true` 且 `ai_focus` 需要译名、归属或分类判断的标签查询
- 跳过明显通用、元数据、特征标签
- 调用 Bangumi 公开 OpenAPI，不需要 Bangumi 个人令牌
- 查询作品、角色和角色关联作品
- 将响应压缩为 AI 需要的字段
- 写入并复用 `build\bangumi_lookup.cache.json`

单独调试：

```powershell
dart run .agent/skills/tag-ai-process/scripts/bangumi_lookup.dart subject "ちょびっツ"
dart run .agent/skills/tag-ai-process/scripts/bangumi_lookup.dart character "神尾観鈴"
```

常用限制参数：

```powershell
dart run .agent/skills/tag-ai-process/scripts/bangumi_lookup.dart --input "build\ai_tag_batch.json" --out "build\bangumi_lookup.json" --limit 5 --character-limit 1 --batch-limit 20
```

输出文件：
- `build\bangumi_lookup.json`
- `build\bangumi_lookup.cache.json`

## 3. 阅读压缩文件

只读取这些文件：
- `build\ai_tag_batch.json`
- `build\bangumi_lookup.json`

`ai_tag_batch.json` 优先使用这些字段：
- `pending_tags`
- `signals`
- `deterministic_suggestion`
- `needs_ai`
- `ai_focus`
- `resolved_parent_reference`

`bangumi_lookup.json` 优先使用这些字段：
- `results[].tag_name`
- `results[].queries.subject.matches`
- `results[].queries.character.matches`
- `results[].queries.character.matches[].detail.infobox`
- `results[].queries.character.matches[].subjects`
- `stats`

处理规则：
- `deterministic_suggestion` 是可直接采用的高置信建议。如果它会产生实际变更，应写入 `updates`
- `needs_ai = false` 表示不要继续推理或联网，但不代表不能采用 `deterministic_suggestion`
- `needs_ai = true` 时，只补充 `ai_focus` 要求的事项
- `resolved_parent_reference` 只用于确认父标签信息，不能替代 `parent_name`
- `bangumi_lookup.json` 只作为证据，不能直接把 Bangumi `name` 或 `name_cn` 写入 `parent_name`
- 如果 `ai_focus` 为空，不要额外扩展分类、翻译或归属

## 4. 分类规则

`category` 值：
- `1` = 作品，动漫、游戏、漫画等作品名，例如 `Fate/Grand_Order`、`原神`
- `2` = 角色，角色名或虚拟主播个人名，例如 `セイバー`、`Saber`
- `6` = 特点，身体特征、服装、姿势、表情，例如 `おっぱい`、`黒タイツ`
- `4` = 通用，人数、构图、背景等通用描述，例如 `1girl`、`solo`
- `5` = 元数据，图片本身属性或 Pixiv 状态，例如 `highres`、`commentary`
- `0` = 无法可靠判断时保持未分类

优先级：
1. 明显元数据词设为 `5`
2. 明显人数、构图、背景等通用标签设为 `4`
3. 明显外观、服装、姿势、表情等特征设为 `6`
4. 命中已有作品别名设为 `1`
5. 角色名含 `（作品名）` 或 `(作品名)` 且父标签已解析，设为 `2` 并填写父标签
6. 其余项由 AI 谨慎补判，不确定就保持 `0` 或不写入

不要把创作者名、声优名、社团名误归为角色。Pixiv 标签里出现真人或组织时，除非能确定它在当前标签体系中作为作品或 VTuber 父类使用，否则保持未分类。

## 5. 翻译规则

目标是必要时补充，非必要不覆盖：
- 标签本身已经是自然中文时，通常不填写 `custom_translated_name`
- 已有 `translated_name` 或 `custom_translated_name` 且中文正确时，不重复改写
- 只有需要补足官方译名、修正错误翻译、或把日文/英文转成稳定中文名时，才填写 `custom_translated_name`
- 普通特征词用简洁常用中文，不写解释句
- 作品名、角色名优先使用官方中文名，其次使用 Bangumi `name_cn` 或社区稳定译名
- 不要为了“看起来更中文”改写已经广泛使用的原文标题或英文缩写
- 无法确认标准中文名时，宁可不填

## 6. 归属规则

只对角色类标签尝试填写 `parent_name`：
- 如果脚本给出 `resolved_parent_name`，优先直接使用
- `parent_name` 必须是数据库中真实存在的原始 `name`
- 严禁使用翻译名、Bangumi `name_cn` 或自行翻译的作品名作为 `parent_name`
- 如果归属能查到但数据库没有对应父标签，先留空，不要新造父标签名
- 如果归属不确定，留空

特殊映射：
- 隶属于彩虹社、Hololive 或其他 VTuber 企划/个人势的角色，若数据库存在 `バーチャルYouTuber`，`parent_name` 设为 `バーチャルYouTuber`
- VTuber 的团体名本身通常不是角色；个人名才按角色处理

## 7. Bangumi OpenAPI 工具

默认不联网。只有满足以下任一条件时，才运行 `bangumi_lookup.dart`：
- `ai_focus` 包含 `确认中文译名`
- `ai_focus` 包含 `确认所属作品`
- 同一标签存在多个常见译名，需要核实官方或主流用法

禁止联网：
- `needs_ai = false`
- 明显通用、元数据或特征标签
- 仅需字面翻译即可解决的普通词
- 为了补全背景故事、设定、角色关系而搜索

`bangumi_lookup.dart` 封装这些 Bangumi 公开 OpenAPI，不使用 `bangumi` CLI：
- OpenAPI 文档：`https://github.com/bangumi/api/tree/master/open-api`
- API Base URL：`https://api.bgm.tv`
- 公开搜索接口可用于只读查询，不要求 Bangumi 个人令牌
- 非浏览器请求必须设置 `User-Agent`，但不要包含本项目仓库地址、用户名或本地路径
- 作品查询使用 `POST /v0/search/subjects?limit=5`
- 角色查询使用 `POST /v0/search/characters?limit=5`
- 角色关联作品使用 `GET /v0/characters/{character_id}/subjects`
- Bangumi 条目类型：`1` 书籍、`2` 动画、`3` 音乐、`4` 游戏、`6` 三次元。处理作品标签时通常只考虑 `1`、`2`、`4`

Bangumi OpenAPI 结果采信规则：
- 作品译名优先看 `name_cn`，为空则不要强行翻译
- 角色译名优先看角色结果的 `name_cn`，并用关联作品交叉确认
- 角色归属必须再映射回数据库已有作品主标签，不能直接把 Bangumi `name` 或 `name_cn` 写进 `parent_name`
- 搜索结果只作为证据。若前 5 个结果没有明确匹配，停止查询并留空
- 同系列或同作品批量标签只查询一次，结论复用到整批
- 不把 API 原始响应、网页摘录或长解释写入 `reason`

如果 Bangumi 搜不到，才考虑其他可靠来源。仍然只确认“标准中文名”和“所属作品”，不要扩展背景信息。

## 8. 生成结果 JSON

写入 `build\tag_updates.json`：

```json
{
  "version": 1,
  "updates": [
    {
      "name": "原始标签名",
      "category": 2,
      "custom_translated_name": "中文翻译",
      "parent_name": "父标签原始 name",
      "reason": "简短理由"
    }
  ]
}
```

字段约束：
- `name` 必须与数据库 `name` 字段完全一致，严禁转换繁简、改写日文汉字或替换符号
- `category` 可省略或设为 `null` 表示不更改；若填写必须是 `0`、`1`、`2`、`4`、`5`、`6`
- `custom_translated_name` 可省略或设为 `null` 表示不更改，不要写空字符串
- `parent_name` 可省略或设为 `null` 表示不更改，填写时必须是数据库已有原始标签名
- `reason` 保持 8 到 20 个中文字符左右

输出约束：
- 只写有实际建议的项
- 高置信 `deterministic_suggestion` 若会改变分类或父标签，应写入
- AI 只补充 `ai_focus` 要求的字段
- 无法得出可靠变更的标签不写入 `updates`
- 不要把推理过程、搜索摘要、API 响应或网页摘录写入 JSON

推荐 `reason`：
- `高频作品标签`
- `角色名含作品括号`
- `命中已有作品别名`
- `服装特征词`
- `Pixiv常见元数据`
- `Bangumi译名`
- `Bangumi归属`

## 9. 校验结果 JSON

```powershell
dart run .agent/skills/tag-ai-process/scripts/validate_tag_updates.dart --db "E:\Pictures\pixez_downloads\download.db" --input "build\tag_updates.json" --report "build\tag_updates.validation.json"
```

校验脚本会检查：
- `name` 是否存在
- `parent_name` 是否存在
- `parent_name` 是否是主标签
- `category` 是否合法
- 是否重复
- `reason` 是否过长
- 是否存在不会产生实际效果的无效更新

如果校验失败：
1. 读取 `build\tag_updates.validation.json`
2. 修正 `build\tag_updates.json`
3. 重新运行校验脚本

可选严格校验：

```powershell
dart run .agent/skills/tag-ai-process/scripts/validate_tag_updates.dart --db "E:\Pictures\pixez_downloads\download.db" --input "build\tag_updates.json" --report "build\tag_updates.validation.json" --strict
```

## 10. 完成提示

完成后告诉用户这些文件的位置：
- `build\ai_tag_batch.json`
- `build\bangumi_lookup.json`
- `build\tag_updates.json`
- `build\tag_updates.validation.json`

并提示用户可在 App 标签管理页使用「导入标签数据」加载 `tag_updates.json`。

## 核心注意事项

- `name` 和 `parent_name` 都必须保持数据库原始字形
- 父标签只能填数据库存在的原始标签名，不能填中文译名
- 优先信任脚本的高置信建议
- 联网查询只解决 `ai_focus` 指出的具体问题
- Bangumi 结果要谨慎映射回本地数据库，不要直接照抄成父标签
- 不确定时少写，`updates` 少于批次数量是正常结果
