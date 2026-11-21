-- Curated, type-independent names for new random artifacts in ToME 1.7.6.
-- Change version when changing selection rules or pools. Saved names stay unchanged.
return {
    version = 1,
    base_names = {
        weapon = {
            longsword = "长剑", greatsword = "巨剑", dagger = "匕首", staff = "法杖",
            waraxe = "战斧", battleaxe = "巨斧", mace = "钉锤", greatmaul = "巨锤",
            longbow = "长弓", sling = "投石索", mindstar = "灵晶",
        },
        armor = {
            shield = "盾牌", cloth = "长袍", light = "轻甲", heavy = "重甲", massive = "板甲",
            cloak = "斗篷", head = "头饰", hands = "手套", feet = "靴子", belt = "腰带",
        },
        jewelry = { ring = "戒指", amulet = "护身符" },
    },
    pools = {
        neutral = {"远行誓约", "旧日回声", "失落铭记", "守夜之约", "归途微光", "黎明前夕",
                   "群星见证", "旧世遗音", "长夜终章", "流年刻印", "未竟之途", "长路余歌",
                   "不眠之誓", "无言见证", "往日余响", "旅人的信物"},
        fire = {"余烬之誓", "熔心", "炉火余歌", "焚星", "灼日回响", "灰烬铭记"},
        cold = {"霜痕", "凛冬回响", "冰原静语", "寒星之约", "北风余响", "封霜"},
        lightning = {"裂空之鸣", "雷云回响", "风暴前奏", "惊雷之誓", "电光余痕", "云间雷语"},
        light = {"晨曦之誓", "破晓回响", "金辉铭记", "曙光余歌", "白昼之约", "远星微光"},
        darkness = {"无光之约", "暮影遗音", "长夜低语", "夜幕回响", "暗星之誓", "幽影刻印"},
    },
}
