# 配置字段字典

> 自动生成自 `tables/*.csv` 四行表头，勿手改。来源：docs/12 §1-§4。

## AffixPool

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| affixId | `int` | `c` | 主键 |
| group | `int` | `c` | 词条组（1前缀攻击系2后缀生存系） |
| stat | `string` | `c` | 作用属性键 |
| rollType | `int` | `c` | 1百分比2平面值 |
| min | `float` | `c` | 基准区间下限 |
| max | `float` | `c` | 基准区间上限 |
| weight | `float` | `c` | 抽取权重 |
| qualityMin | `int` | `c` | 最低品质（0白..5红） |
| qualityMax | `int` | `c` | 最高品质 |

## BuffConfig

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| buffId | `int` | `c` | 主键 |
| name | `string` | `c` | 状态名 |
| kind | `int` | `c` | 类型1dot2控制3削弱4标记5增益6护盾 |
| modStat | `string` | `c` | 属性修正1 |
| modPct | `float` | `c` | 比例 |
| modStat2 | `string` | `c` | 属性修正2 |
| modPct2 | `float` | `c` | 比例 |
| dotPct | `float` | `c` | 回合结算比例（dot伤害或再生回复） |
| dotElement | `int` | `c` | dot元素 |
| markElement | `int` | `c` | 标记元素（受该元素伤害加成） |
| markPct | `float` | `c` | 标记加成 |
| ctrlRes | `float` | `c` | 控制抗性 |
| stacks | `int` | `c` | 最大层数 |
| duration | `int` | `c` | 基础持续 |
| captureLinked | `bool` | `c` | 是否捕捉联动（03文档5章） |
| control | `int` | `c` | 控制类型0无1冰冻2眩晕3催眠4麻痹5封技 |

## Building

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| buildingId | `int` | `c` | 主键 |
| name | `string` | `c` | 建筑 |
| maxLevel | `int` | `c` | 最高等级 |
| unlockRealm | `string` | `c` | 解锁境界 |
| effectKind | `enum<BuildingEffect>` | `c` | 效果类型 |
| effectBase | `float` | `c` | 基础值 |
| effectStep | `float` | `c` | 每级增量 |
| upgradeCostKey | `string` | `c` | 消耗货币 |
| upgradeCostBase | `int` | `c` | 基础消耗 |
| upgradeCostStep | `int` | `c` | 每级增量 |

## Crop

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| cropId | `int` | `c` | 主键 |
| name | `string` | `c` | 作物 |
| seedCost | `int` | `c` | 种子价（兽贝） |
| growMin | `int` | `c` | 生长分钟 |
| yieldN | `int` | `c` | 基础产量 |
| outputItemId | `ref<ItemBase>` | `c` | 产物物品 |
| outputCount | `int` | `c` | 产物数量 |
| unlock | `string` | `c` | 解锁境界 |

## DropRule

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| dropId | `int` | `c` | 主键 |
| source | `int` | `c` | 来源（Enums.DropSource） |
| wWhite | `float` | `c` | 白 |
| wGreen | `float` | `c` | 绿 |
| wBlue | `float` | `c` | 蓝 |
| wPurple | `float` | `c` | 紫 |
| wOrange | `float` | `c` | 橙 |
| wRed | `float` | `c` | 红 |
| luckApply | `bool` | `c` | 受幸运值加成 |
| pityQuality | `int` | `c` | 保底品质0无3紫4橙 |
| pityCount | `int` | `c` | 保底次数 |
| equipLvRule | `string` | `c` | 装备等级规则（仅显示兼容） |
| pityUnit | `string` | `c` | 保底计数单位settlement/item |
| equipLvMode | `string` | `c` | 装备等级基准monster_level/nightmare_layer |
| equipLvOffsetMin | `int` | `c` | 等级偏移下限 |
| equipLvOffsetMax | `int` | `c` | 等级偏移上限 |

## EnemyGroup

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| groupId | `int` | `c` | 敌人组 |
| slot | `int` | `c` | 槽位 |
| petId | `ref<PetBase>` | `c` | 灵宠 |
| level | `int` | `c` | 等级 |
| apt | `int` | `c` | 资质（各维统一） |
| strategy | `string` | `c` | 组策略random/focus_weak/focus_squishy/caster_first |

## Enums

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| enumName | `string` | `c` | 枚举名 |
| value | `int` | `c` | 值 |
| label | `string` | `c` | 中文说明 |

## EquipBase

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| equipId | `int` | `c` | 主键 |
| slot | `int` | `c` | 装备部位（1武器2防具3饰品） |
| mainStat | `string` | `c` | 主属性键 |
| baseValue | `float` | `c` | 部位主属性基准（08 §4：基准×(1+等级×EQUIP_MAIN_LV_SCALE)） |
| weight | `float` | `c` | 模板抽取权重 |
| setId | `ref<EquipSet>` | `c` | 所属套装（docs/08 §7；101/201/301→狼魂 102/202/302→雷煞） |

## EquipQuality

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| qualityId | `int` | `c` | 主键（0白1绿2蓝3紫4橙5红） |
| affixMin | `int` | `c` | 词条数下限 |
| affixMax | `int` | `c` | 词条数上限 |
| rareForLuck | `bool` | `c` | 是否受幸运加成 |
| unidentified | `bool` | `c` | 掉落时未鉴定 |
| requiredGroups | `array<int>(2)` | `c` | 必选词条组（0=无；组配额待设计确认 Phase 0 不强制） |

## EquipSet

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| equipSetId | `int` | `c` | 主键 |
| name | `string` | `c` | 套装名 |
| element | `int` | `c` | 五行属性 |
| pieces | `int` | `c` | 件数（武器+防具+饰品） |
| bonus2Desc | `string` | `c` | 2件效果描述 |
| bonus2Stat | `string` | `c` | 2件属性修正键 |
| bonus2Pct | `float` | `c` | 2件修正比例 |
| bonus3Desc | `string` | `c` | 3件效果描述 |
| bonus3Stat | `string` | `c` | 3件属性修正键 |
| bonus3Pct | `float` | `c` | 3件修正比例 |

## GlobalConst

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| key | `string` | `c` | 常量键 |
| value | `float` | `c` | 值 |
| desc | `string` | `c` | 说明（变更须记changelog） |

## ItemBase

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| itemId | `int` | `c` | 主键 |
| name | `string` | `c` | 物品名 |
| kind | `enum<ItemKind>` | `c` | 物品类别 |
| storageCategory | `ref<StorageRule>` | `c` | 仓储分类（容量归属） |

## MainQuest

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| questId | `int` | `c` | 主键 |
| chapterId | `int` | `c` | 章节 |
| order | `int` | `c` | 顺序 |
| nodeType | `enum<NodeType>` | `c` | 节点类型 |
| title | `string` | `c` | 标题 |
| goalType | `enum<GoalType>` | `c` | 目标类型 |
| targetId | `int` | `c` | 目标ID |
| count | `int` | `c` | 数量 |
| rewardXiu | `int` | `c` | 修为奖励 |

## Mine

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| mineId | `int` | `c` | 主键 |
| name | `string` | `c` | 矿层 |
| unlockRealm | `string` | `c` | 解锁境界 |
| ironRate | `int` | `c` | 铁矿/时 |
| crystalRate | `int` | `c` | 火晶/时 |
| refinedRate | `int` | `c` | 精铁矿/时 |
| spiritRate | `int` | `c` | 灵晶/时 |
| collapseRisk | `float` | `c` | 塌方风险 |

## PetBase

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| petId | `int` | `c` | 主键1001起 |
| name | `string` | `c` | 名称 |
| element | `int` | `c` | 五行 |
| quality | `int` | `c` | 品质 |
| template | `int` | `c` | 定位模板 |
| offHp | `float` | `c` | HP偏移 |
| offAtk | `float` | `c` | 攻击偏移 |
| offDef | `float` | `c` | 防御偏移 |
| offSpd | `float` | `c` | 速度偏移 |
| offMag | `float` | `c` | 灵力偏移 |
| offRes | `float` | `c` | 抗性偏移 |
| aptitudes | `array<int>(10)` | `c` | 资质范围atkMin;atkMax;defMin;defMax;hpMin;hpMax;spdMin;spdMax;magMin;magMax |
| laborPow | `int` | `c` | 力气 |
| laborDex | `int` | `c` | 灵巧 |
| laborApt | `int` | `c` | 木灵亲和 |
| natures | `array<string>(4)` | `c` | 性格池 |
| breaks | `array<string>(5)` | `c` | 五阶段突破链 |
| captureNote | `string` | `c` | 捕捉说明 |

## PetSkillPool

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| petId | `ref<PetBase>` | `c` | 灵宠 |
| slot | `int` | `c` | 槽位0普攻1主动2主动3绝技 |
| skillId | `ref<SkillConfig>` | `c` | 技能 |
| learnLv | `int` | `c` | 习得等级 |

## Recipe

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| recipeId | `int` | `c` | 主键 |
| station | `enum<Station>` | `c` | 工作台 |
| inputs | `string` | `c` | 输入（itemId:count;分号分隔） |
| outputItemId | `ref<ItemBase>` | `c` | 产物 |
| outputCount | `int` | `c` | 数量 |
| durationMin | `int` | `c` | 耗时分钟 |
| unlockRealm | `string` | `c` | 解锁境界 |

## SeasonWeather

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| seasonId | `int` | `c` | 主键（0春1夏2秋3冬） |
| name | `string` | `c` | 季节名 |
| farmMult | `float` | `c` | 灵田产量系数 |
| mineMult | `float` | `c` | 矿场系数 |
| beastMult | `float` | `c` | 凶兽潮系数 |

## SkillConfig

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| skillId | `int` | `c` | 主键 |
| name | `string` | `c` | 技能名称 |
| element | `int` | `c` | 属性0为无 |
| selector | `string` | `c` | 目标选择器self/ally_all/ally_lowest/enemy_one/enemy_all/enemy_random/enemy_lowest |
| effects | `array<effect>` | `c` | 效果列表格式TYPE\|power\|buffId\|duration\|chance\|hitCount\|onSelf |
| cd | `int` | `c` | 冷却回合 |
| rageGain | `int` | `c` | 怒气获取 |
| learnLv | `int` | `c` | 习得等级 |
| isUlt | `bool` | `c` | 是否绝技 |

## StageConfig

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| stageId | `int` | `c` | 主键 |
| mapId | `int` | `c` | 地图1石岭村2黑风林3赤炎谷4雷鸣泽 |
| order | `int` | `c` | 顺序 |
| name | `string` | `c` | 关卡名 |
| waves | `refs<EnemyGroup>` | `c` | 波次敌人组 |
| dropId | `ref<DropRule>` | `c` | 掉落规则 |
| dropCount | `int` | `c` | 掉落次数 |
| power | `int` | `c` | 推荐战力 |
| captureable | `bool` | `c` | 含可捕捉野怪 |
| boss | `bool` | `c` | 是否Boss关 |

## StorageRule

| 字段 | 类型 | 可见性 | 说明 |
|---|---|---|---|
| categoryId | `int` | `c` | 主键（1矿石2草药3食物4金属锭5建材） |
| baseCap | `int` | `c` | 基础容量（软上限） |
