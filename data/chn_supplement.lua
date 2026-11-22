locale "zh_hans"

-- Supplementary entries for strings fixed by this addon's code (hooks and
-- superloads). The generated data/locales/zh_hans.lua must not be edited by
-- hand, so they live here. I18N:t() also writes every entry into the "nil"
-- fallback table, so shared English words get addon-only keys ("...##...")
-- and are looked up explicitly by the code instead of overriding other tags.

--section "birth"
-- Orcs campaign fallback locked_desc (tome-orcs data/birth/worlds.lua).
t("Once freed, twice shy.", "一朝获释，再难轻信。", "_t")
-- World names shown as "Campaign:" in the save description (Game:getSaveDescription).
t("Orcs", "余烬怒火", "birth descriptor name")
t("Infinite", "无尽地下城", "birth descriptor name")
t("Arena", "竞技场", "birth descriptor name")

--section "auto-explore"
-- Stop reasons returned without _t by engine/interface/PlayerRun.lua runCheck.
t("terrain changed ahead", "前方地形变化", "_t")
t("terrain ahead blocks", "前方被地形阻挡", "_t")
t("terrain change on left side", "左侧地形变化", "_t")
t("terrain change on right side", "右侧地形变化", "_t")

--section "hotkey page tutorial"
-- mod/class/Player.lua hotkeyPageTutorial, shown through Dialog:simpleLongPopup.
t("Hotkeys Bar Swapping", "快捷栏翻页", "_t")
t([[You have pressed a key to switch your hotkeys for the first time.
By default the keys to switch are #{bold}#Page.Up#{normal}# and #{bold}#Page.Down#{normal}#.
It can also be switched by using the mouse wheel when the mouse is over the hotkeys.
So do not panic if you do not see your hotkeys anymore, just swap back and they will be there.]], [[你第一次按下了切换快捷栏页面的按键。
默认的切换键是 #{bold}#Page.Up#{normal}# 和 #{bold}#Page.Down#{normal}#。
鼠标悬停在快捷栏上时，也可以用滚轮切换。
如果快捷键突然不见了，不必惊慌，切换回原来的页面就能看到它们。]], "_t")

--section "key binding groups"
-- engine/dialogs/KeyBinder.lua shows group:capitalize() untranslated.
t("Debug##keybind_group", "调试", "_t")
t("Interface##keybind_group", "界面", "_t")
t("Party##keybind_group", "队伍", "_t")
t("User chat##keybind_group", "用户聊天", "_t")
t("Microtransactions - cosmetic##keybind_group", "微交易 - 外观", "_t")

--section "use talents"
-- mod/dialogs/UseTalents.lua; "Active" is shared with other dialogs.
t("Active##use_talents", "可用", "_t")
t("H.Key %d", "快捷键 %d", "tformat")
t("LeftClick", "左键", "_t")
t("MiddleClick", "中键", "_t")

--section "actors"
-- Quick-reply chat nodes get a bare "[leave]" answer (engine/Chat.lua addChat).
-- The mod-tome locale already has _t"[leave]"; hooks/load.lua looks it up.
-- Effect type typo of DOZING (timed_effects/other.lua, type = "otber"), shown
-- through _t(e.type) in the effect tooltip header.
t("otber", "其他", "_t")
-- RIME_WRAITH subtype (timed_effects/magical.lua), shown with tag "effect subtype".
t("parasitic", "寄生", "effect subtype")
-- BEAR_TRAP long_desc pushes a bare "pinned" (timed_effects/physical.lua).
t("pinned##bear_trap", "定身", "_t")
-- Embers PRESSURE_SUIT long_desc returns a plain literal without _t.
t("When hit the suit's motors displace you quickly, ignoring the blow.", "受到攻击时，战服的马达会迅速将你移开，使你避开这次打击。", "_t")
-- Only for creature tooltips and the PREDATOR effect's prey subtypes.
t("light##creature_subtype", "光", "_t")
-- Vault random boss title word-order fixes (mod-tome/data/maps/vaults/renegade-*.lua):
-- Put the title before #rng# so Chinese personal names do not run into trailing nouns/adjectives.
t("#rng# the Flame Terror", "烈焰灾星#rng#", "_t")
t("#rng# the Frozen Terror", "寒冰灾星#rng#", "_t")
t("#rng# the Storm Terror", "风暴灾星#rng#", "_t")
t("#rng# the Caustic Terror", "蚀毒灾星#rng#", "_t")
t("#rng# the Tortured Mass", "受难肉团#rng#", "_t")
t("Tortured Mass #rng#", "受难肉团#rng#", "_t")
t("#rng# the Invoker", "祈唤者#rng#", "_t")

--section "objects"
-- Shield add_name (data/general/objects/shields.lua); the attribute parts
-- already use a full-width comma.
t(" (#ARMOR#, #SHIELD#)", " (#ARMOR#，#SHIELD#)", "entity add_name")
-- "all" in item property lines only (Object:getTextualDesc).
t("all##item_property", "全部", "_t")
-- "Damage against" lines show actor types through _t(type); "living" is
-- shared with the entity keyword 生命, so items use 活物 (cf. unliving 非活物).
t("living##item_property", "活物", "_t")
-- Keyword separator of Object:getShortName (equipment doll labels).
t(", ##short_name", "、", "_t")

--section "talents"
-- Embers Bloodstream (tome-orcs data/talents/steam/sawmaiming.lua): addon-only
-- key formatted by hooks/dynamic_desc_fixes.lua with the multiplier that
-- action really applies (getDamage). The upstream English key keeps its own
-- translation and argument contract (getDamageInc) in the generated locale.
t([[You "gently" slam your saws into the wounds of a creature, dealing %d%% weapon damage and deepening the wounds.
		If the attack hits, the target was already bleeding before the attack and is still bleeding after it, that bleeding effect's duration is increased by %d turns and its damage becomes %d%% of its current value (this may be done only once per bleeding effect).
		When this happens a gush of blood is projected in a narrow cone of radius 4, dealing %0.2f physical damage to all creatures.
		The power and damage improves with your Steampower.
		#{italic}#The marvels of technology, now at the service of true butchery!#{normal}###chn-mod bloodstream actual multiplier]], [[你“轻柔”地将链锯猛砸进目标的伤口，造成 %d%% 武器伤害并加深伤口。
		若命中已在流血的目标，其流血效果持续时间延长 %d 回合，伤害变为原来的 %d%% （每个流血效果只能强化一次）。
		效果触发时，血流将喷射而出，对半径 4 的窄锥形范围内所有生物造成 %0.2f 物理伤害。
		效果强度和伤害受蒸汽强度加成。
		#{italic}#科技的奇迹，如今为真正的屠戮效力！#{normal}#]], "tformat")

--section "chn options"
-- hooks/chn_options.lua: Game Options "Localization" tab and random boss / artifact Chinese naming toggles.
t("Localization", "汉化", "_t")
t("#GOLD##{bold}#Chinese random boss names#WHITE##{normal}#", "#GOLD##{bold}#随机怪物中文命名#WHITE##{normal}#", "_t")
t([[Generate culturally-grouped Chinese names for random rare and epic bosses in Simplified Chinese mode.
Default is enabled. Only takes effect when the game language is Simplified Chinese.
When disabled, existing and newly generated random bosses immediately revert to their original names. Re-enabling restores their Chinese names (previously written combat log lines are not retroactively changed).#WHITE#]], [[在简体中文模式下，为随机生成的稀有与史诗怪物生成按种族文化分组的中文名称。
默认开启，仅当游戏语言为简体中文时生效。
关闭后，新生成及当前存档中已生成的随机怪物均会立即回退为原版名称；再次开启时可恢复其中文名称（已写入的历史战斗日志不会追溯更改）。#WHITE#]], "_t")
t("#GOLD##{bold}#Chinese random artifact names#WHITE##{normal}#", "#GOLD##{bold}#随机神器中文命名#WHITE##{normal}#", "_t")
t([[Generate thematic Chinese names for identified random artifacts in Simplified Chinese mode.
Default is enabled. Only takes effect when the game language is Simplified Chinese.
When disabled, all random artifacts immediately display their original names. Re-enabling immediately restores their Chinese names.#WHITE#]], [[在简体中文模式下，为已鉴定的随机神器生成契合材质与元素主题的中文名称。
默认开启，仅当游戏语言为简体中文时生效。
关闭后，所有随机神器将立即显示原版名称；再次开启时立即恢复中文名称。#WHITE#]], "_t")