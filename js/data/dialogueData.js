// 剧情对话数据 —— 关卡战前/战后脚本
// 新增关卡/章节：直接在此添加配置即可
// 脚本 key 格式: "stageId_timing"，timing = 'pre' | 'post'
// 每条目: { speaker, text, portrait, element?, speakerName?, giftHook? }
//   speaker: 'narrator'=旁白; 其它为角色 id（用于解析名称与元素着色）
//   portrait: 立绘标识，对应 CharacterData[id].image；null 则隐藏立绘区
//   element: 'fire'|'water'|'thunder'|'wind' 用于说话人名称着色
//   speakerName: 覆盖显示名称（默认取 CharacterData[id].name）
//   giftHook: true 表示播放到此条目时触发赠送回调
window.GG = window.GG || {};
window.GG.DialogueData = {

    // ============================================================
    //  第一章：流火荒原 —— 赠送角色：焰龙·卡尔迪（1-4 战后）
    // ============================================================

    // 1-1 荒野入口 · 战前
    'ch1_1_pre': [
        { speaker: 'narrator', text: '流火荒原——一片被远古战火灼烧千年的大地，至今仍回荡着龙族的怒吼。', portrait: null },
        { speaker: 'narrator', text: '冒险者孤身踏入荒原入口，干裂的风裹挟着灰烬扑面而来。', portrait: null },
        { speaker: 'traveler', text: '这就是传说中的流火荒原……空气里都是硫磺的味道。', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'narrator', text: '远处的灌木丛传来低沉的嚎叫——野狼群已经发现了入侵者。', portrait: null },
    ],

    // 1-1 荒野入口 · 战后
    'ch1_1_post': [
        { speaker: 'traveler', text: '不过是几只荒原狼，还算好对付。', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'narrator', text: '击退了野狼后，旅行者望向荒原深处，隐约可见升腾的火光。', portrait: null },
        { speaker: 'traveler', text: '那个方向……有什么东西在燃烧。去看看。', portrait: null, element: 'wind', speakerName: '旅行者' },
    ],

    // 1-2 哥布林营地 · 战前
    'ch1_2_pre': [
        { speaker: 'narrator', text: '荒原的中段，一排破旧的帐篷和火堆映入眼帘。', portrait: null },
        { speaker: 'traveler', text: '哥布林营地……它们好像在驱赶什么东西。', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'narrator', text: '几只哥布林正围着一匹受伤的荒原狼，似乎在试图驯服它。', portrait: null },
        { speaker: 'traveler', text: '这些哥布林和荒原狼居然混在一起了……不能让它们壮大起来。', portrait: null, element: 'wind', speakerName: '旅行者' },
    ],

    // 1-2 哥布林营地 · 战后
    'ch1_2_post': [
        { speaker: 'narrator', text: '营地被清理干净后，旅行者在残骸中发现了一枚烧焦的铭牌。', portrait: null },
        { speaker: 'traveler', text: '这铭牌上刻着……龙纹？难道有龙裔在这片荒原上活动？', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'narrator', text: '铭牌的背面用古语刻着一行字——"炎脉不灭"。', portrait: null },
        { speaker: 'traveler', text: '前方那片烈火森林……也许答案就在那里。', portrait: null, element: 'wind', speakerName: '旅行者' },
    ],

    // 1-3 烈火森林 · 战前（卡尔迪初登场！）
    'ch1_3_pre': [
        { speaker: 'narrator', text: '烈火森林——树木本身就在燃烧，却从未化为灰烬，仿佛时间在此凝固。', portrait: null },
        { speaker: 'narrator', text: '炽热的气浪令空气扭曲，每一口呼吸都像在吞咽火焰。', portrait: null },
        { speaker: 'traveler', text: '这地方……普通人根本无法踏入。', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'narrator', text: '忽然，一道火柱从林间冲天而起，伴随着震耳欲聋的龙吼！', portrait: null },
        { speaker: 'kaldi', text: '哈哈哈！又有火精灵送上门来了！', portrait: 'kaldi', element: 'fire' },
        { speaker: 'narrator', text: '烈焰之中，一个身影缓缓走出——灼红的鳞甲，燃烧的双瞳。', portrait: null },
        { speaker: 'traveler', text: '你是……龙裔？', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'kaldi', text: '不错！焰龙·卡尔迪，炎脉山脉最后的龙裔战士。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'kaldi', text: '这片森林里的火焰精灵最近闹得很凶，正愁没人帮我收拾它们。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'kaldi', text: '你看起来还算能打，一起上吧！', portrait: 'kaldi', element: 'fire' },
    ],

    // 1-3 烈火森林 · 战后
    'ch1_3_post': [
        { speaker: 'kaldi', text: '干得漂亮！你比我想象的要强不少。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'traveler', text: '你一个人住在这种地方？', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'kaldi', text: '这片荒原是我的领地——更准确地说，是炎王霸占了我的领地。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'kaldi', text: '那头炎王从地下钻出来，占据了炎脉深处，我一直在寻找击退它的方法。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'traveler', text: '炎王……听起来很危险。', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'kaldi', text: '危险？哈哈！危险才值得去战斗！前面就是岩石峡谷，那里的石巨人是炎王的守门人。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'kaldi', text: '击败它们，就能打开通往炎王领地的大门。跟我来！', portrait: 'kaldi', element: 'fire' },
    ],

    // 1-4 岩石峡谷(精英) · 战前
    'ch1_4_pre': [
        { speaker: 'narrator', text: '岩石峡谷——两侧峭壁如刀削般耸立，地面布满裂痕，炽热的岩浆在深处流淌。', portrait: null },
        { speaker: 'kaldi', text: '我能感觉到……石巨人的震动就在前方。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'traveler', text: '你确定我们要挑战它们？', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'kaldi', text: '我体内流淌着远古火龙的血脉，这些石头家伙算什么？', portrait: 'kaldi', element: 'fire' },
        { speaker: 'kaldi', text: '不过……还是小心为上。石巨人的防御可不是闹着玩的，我们配合着来。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'traveler', text: '好，我掩护你的侧翼。', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'kaldi', text: '爽快！那就——上吧！', portrait: 'kaldi', element: 'fire' },
    ],

    // 1-4 岩石峡谷(精英) · 战后 —— ★赠送卡尔迪★
    'ch1_4_post': [
        { speaker: 'narrator', text: '巨大的石巨人轰然倒下，峡谷中回荡着碎石滚落的声响。', portrait: null },
        { speaker: 'kaldi', text: '哈哈哈！痛快！这些石头家伙也不过如此！', portrait: 'kaldi', element: 'fire' },
        { speaker: 'traveler', text: '你的火焰……真的很强。', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'kaldi', text: '你也不错，比我遇到的多数冒险者都可靠。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'narrator', text: '卡尔迪沉默了片刻，看向峡谷深处——那是通往炎王领地的方向。', portrait: null },
        { speaker: 'kaldi', text: '说实话……我一个人对抗炎王，没有十足的把握。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'kaldi', text: '但如果是你的话——也许我们可以并肩作战。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'kaldi', text: '旅行者，从现在起，我焰龙·卡尔迪愿与你同行！', portrait: 'kaldi', element: 'fire' },
        // ★ 赠送钩子：在此触发卡尔迪赠送
        { speaker: 'narrator', text: '烈焰与意志共鸣——焰龙·卡尔迪加入了你的队伍！', portrait: 'kaldi', giftHook: true },
        { speaker: 'kaldi', text: '走吧！炎王的领地就在前方，是时候夺回属于龙裔的荣耀了！', portrait: 'kaldi', element: 'fire' },
    ],

    // 1-5 炎王的领地(BOSS) · 战前
    'ch1_5_pre': [
        { speaker: 'narrator', text: '炎脉深处，灼热的气息令人窒息，整片大地都在颤抖。', portrait: null },
        { speaker: 'kaldi', text: '就在那里——炎王的王座。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'narrator', text: '巨大的身影从熔岩中浮现，炎王睁开赤红的双眼，怒视着入侵者。', portrait: null },
        { speaker: 'kaldi', text: '炎王！千年来你霸占了龙族的炎脉，今天——该归还了！', portrait: 'kaldi', element: 'fire' },
        { speaker: 'traveler', text: '我们一起上！', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'kaldi', text: '烈焰不灭，我亦永恒！上啊——！', portrait: 'kaldi', element: 'fire' },
    ],

    // 1-5 炎王的领地(BOSS) · 战后
    'ch1_5_post': [
        { speaker: 'narrator', text: '炎王的咆哮渐渐消散，它的身躯化为漫天的火星飘散在空中。', portrait: null },
        { speaker: 'kaldi', text: '终于……炎脉回归了龙族。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'traveler', text: '荒原的火势好像在减弱。', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'kaldi', text: '炎王消逝后，这片荒原终将恢复平静。不过……', portrait: 'kaldi', element: 'fire' },
        { speaker: 'kaldi', text: '我感受到了来自北方的异样气息——冰原那边，似乎有更大的危机在酝酿。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'traveler', text: '北方的冰霜雪原？', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'kaldi', text: '嗯，风暴女巫的势力在扩张，那股寒意连我这龙裔都能感觉到。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'kaldi', text: '走吧，旅行者。我们的冒险才刚刚开始！', portrait: 'kaldi', element: 'fire' },
    ],

    // ============================================================
    //  第二章：冰霜雪原 —— 赠送角色：霜语·艾拉（2-4 战后）
    // ============================================================

    // 2-1 冰封平原 · 战前
    'ch2_1_pre': [
        { speaker: 'narrator', text: '冰霜雪原——极北之地，暴风雪掩盖了一切，连时间都被冻结。', portrait: null },
        { speaker: 'traveler', text: '好冷……这种温度，普通人根本撑不了多久。', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'kaldi', text: '呵，这点寒气？在我眼里跟秋天的微风差不多。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'traveler', text: '……你身上可是在冒火。', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'kaldi', text: '那倒也是。不过小心点，前面有冰狼群的气息。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'narrator', text: '风雪中，数双幽蓝的眼睛亮起——冰狼群已经包围了过来。', portrait: null },
    ],

    // 2-1 冰封平原 · 战后
    'ch2_1_post': [
        { speaker: 'kaldi', text: '这些冰狼比荒原的野狼难对付多了——它们的皮甲硬得像石头。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'traveler', text: '但我注意到它们在刻意朝一个方向驱赶我们。', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'narrator', text: '旅行者拨开冰面的积雪，发现雪下埋着古老的符文路标，指向山脉深处。', portrait: null },
        { speaker: 'traveler', text: '这条路标……像是某种引导。有人在山中设下了局。', portrait: null, element: 'wind', speakerName: '旅行者' },
    ],

    // 2-2 雷鹰巢穴 · 战前
    'ch2_2_pre': [
        { speaker: 'narrator', text: '陡峭的冰崖之上，电光在云层中穿梭，雷鹰巢穴赫然矗立。', portrait: null },
        { speaker: 'kaldi', text: '雷鹰——风暴女巫最忠诚的斥候。它们在这里筑巢，说明女巫的老巢不远了。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'traveler', text: '女巫为什么要用雷鹰监视这片雪原？', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'kaldi', text: '为了囚禁某个重要的人——我隐约听到过传闻。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'kaldi', text: '先解决这些雷鹰，别让它们回去报信！', portrait: 'kaldi', element: 'fire' },
    ],

    // 2-2 雷鹰巢穴 · 战后
    'ch2_2_post': [
        { speaker: 'narrator', text: '雷鹰坠落冰崖，羽毛在雷电中燃烧殆尽。', portrait: null },
        { speaker: 'traveler', text: '在巢穴深处发现了一张地图……这是女巫的祭坛方位！', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'kaldi', text: '让我看看……黑暗要塞、女巫祭坛……都在这条路线的尽头。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'narrator', text: '地图边缘有人用冰蓝色的墨水潦草写下了一行字——', portrait: null },
        { speaker: 'narrator', text: '"救救我……祭坛之下……冰霜正在吞噬一切。"', portrait: null },
        { speaker: 'traveler', text: '这是求救信号！我们必须加快速度！', portrait: null, element: 'wind', speakerName: '旅行者' },
    ],

    // 2-3 黑暗要塞 · 战前
    'ch2_3_pre': [
        { speaker: 'narrator', text: '黑暗要塞——冰与铁铸成的监狱，沉重的铁门上刻满了封印符文。', portrait: null },
        { speaker: 'traveler', text: '这里关押着很多人……但大多数牢房已经空了。', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'narrator', text: '要塞深处传来微弱的声音，像是有人在低声吟唱。', portrait: null },
        { speaker: 'traveler', text: '你听到了吗？那个声音……', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'narrator', text: '冰霜骑士挡在了前进的道路上——它们是女巫的狱卒，绝不轻易放行。', portrait: null },
        { speaker: 'kaldi', text: '让开！不管谁挡路——我都要过去！', portrait: 'kaldi', element: 'fire' },
    ],

    // 2-3 黑暗要塞 · 战后
    'ch2_3_post': [
        { speaker: 'narrator', text: '冰霜骑士化为了碎冰，沉重的铁门轰然开启。', portrait: null },
        { speaker: 'narrator', text: '要塞最深处，一道冰蓝色的光芒从祭坛方向传来，伴随着更清晰的吟唱声。', portrait: null },
        { speaker: 'traveler', text: '那个声音越来越清楚了……是一个女声，她在念治愈的咒文。', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'kaldi', text: '冰原圣女……如果传闻是真的，那她就是风暴女巫最忌惮的存在。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'kaldi', text: '女巫囚禁她，是因为害怕她的治愈之力瓦解一切黑暗诅咒。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'traveler', text: '我们一定要救出她！祭坛就在前方！', portrait: null, element: 'wind', speakerName: '旅行者' },
    ],

    // 2-4 女巫的祭坛(精英) · 战前（艾拉首次登场！）
    'ch2_4_pre': [
        { speaker: 'narrator', text: '女巫的祭坛——巨大的冰晶从地面拔起，中央被黑暗魔力笼罩。', portrait: null },
        { speaker: 'narrator', text: '冰柱之中，一个身影若隐若现——银白的长发，冰蓝色的光芒环绕全身。', portrait: null },
        { speaker: 'ayla', text: '……有人来了吗？求你们……快离开这里……', portrait: 'ayla', element: 'water' },
        { speaker: 'traveler', text: '你被囚禁了？我们是来救你的！', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'ayla', text: '不行……女巫在祭坛周围布下了黑暗守卫，你们会……', portrait: 'ayla', element: 'water' },
        { speaker: 'kaldi', text: '让女巫的守卫来吧！我正愁火没地方发！', portrait: 'kaldi', element: 'fire' },
        { speaker: 'ayla', text: '你们……真的要为我冒险？', portrait: 'ayla', element: 'water' },
        { speaker: 'traveler', text: '放心，我们一定把你救出来！', portrait: null, element: 'wind', speakerName: '旅行者' },
    ],

    // 2-4 女巫的祭坛(精英) · 战后 —— ★赠送艾拉★
    'ch2_4_post': [
        { speaker: 'narrator', text: '黑暗骑士与雷鹰在烈焰与勇气的面前彻底溃败。', portrait: null },
        { speaker: 'narrator', text: '冰晶上的封印出现裂痕，银白色的身影缓缓走了出来。', portrait: null },
        { speaker: 'ayla', text: '你们……真的做到了。我以为……再也不会有人来救我了。', portrait: 'ayla', element: 'water' },
        { speaker: 'traveler', text: '你还好吗？', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'ayla', text: '我没事……只是被女巫封印太久，力量有些虚弱。', portrait: 'ayla', element: 'water' },
        { speaker: 'ayla', text: '我叫艾拉——冰原圣女，原本守护着北境的生灵。', portrait: 'ayla', element: 'water' },
        { speaker: 'kaldi', text: '风暴女巫为什么囚禁你？', portrait: 'kaldi', element: 'fire' },
        { speaker: 'ayla', text: '因为我的治愈之力……是唯一能对抗女巫黑暗诅咒的力量。', portrait: 'ayla', element: 'water' },
        { speaker: 'ayla', text: '她害怕我，所以将我封印在冰晶之中。但我不会因此退缩。', portrait: 'ayla', element: 'water' },
        { speaker: 'ayla', text: '你们救了我的命，我愿意用我的力量回报你们。', portrait: 'ayla', element: 'water' },
        { speaker: 'ayla', text: '从今以后，我霜语·艾拉愿与你们同行！', portrait: 'ayla', element: 'water' },
        // ★ 赠送钩子：在此触发艾拉赠送
        { speaker: 'narrator', text: '冰霜与温柔交织——霜语·艾拉加入了你的队伍！', portrait: 'ayla', giftHook: true },
        { speaker: 'ayla', text: '风暴女巫就在前方……这一次，我不再是独自面对了。', portrait: 'ayla', element: 'water' },
    ],

    // 2-5 风暴女巫(BOSS) · 战前
    'ch2_5_pre': [
        { speaker: 'narrator', text: '暴风雪的中心——风暴女巫悬浮在冰晶之巅，黑暗魔力如漩涡般翻涌。', portrait: null },
        { speaker: 'narrator', text: '她的声音如寒冰刺骨，回荡在整个雪原。', portrait: null },
        { speaker: 'narrator', text: '"愚蠢的蝼蚁……竟敢放走我的囚徒。"', portrait: null },
        { speaker: 'ayla', text: '女巫，你的暴政到此为止了。', portrait: 'ayla', element: 'water' },
        { speaker: 'kaldi', text: '哼，说再多大话也没用——吃我一拳！', portrait: 'kaldi', element: 'fire' },
        { speaker: 'traveler', text: '三人合力，一定能击败她！', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'ayla', text: '我会用治愈之力守护你们，不要害怕！', portrait: 'ayla', element: 'water' },
    ],

    // 2-5 风暴女巫(BOSS) · 战后
    'ch2_5_post': [
        { speaker: 'narrator', text: '风暴女巫的身影在暴风雪中消散，她的黑暗魔力如黑烟般被净化。', portrait: null },
        { speaker: 'narrator', text: '笼罩冰霜雪原千年的暴风雪，终于渐渐平息。', portrait: null },
        { speaker: 'ayla', text: '北境……终于恢复平静了。', portrait: 'ayla', element: 'water' },
        { speaker: 'kaldi', text: '嘿，配合得不错嘛！火焰和冰霜一起上，什么敌人都挡不住。', portrait: 'kaldi', element: 'fire' },
        { speaker: 'ayla', text: '谢谢你，旅行者。如果不是你，我也许永远困在那冰晶之中。', portrait: 'ayla', element: 'water' },
        { speaker: 'traveler', text: '是我们一起做到的。', portrait: null, element: 'wind', speakerName: '旅行者' },
        { speaker: 'ayla', text: '冰冻，有时是最温柔的救赎。而我找到了比冰更温暖的东西——你们的信任。', portrait: 'ayla', element: 'water' },
        { speaker: 'kaldi', text: '好啦好啦，别煽情了！前方还有更多冒险在等着我们呢！', portrait: 'kaldi', element: 'fire' },
        { speaker: 'narrator', text: '火与冰的羁绊在此铸就——旅行者的故事，才刚刚开始……', portrait: null },
    ],

    // ========== 未来章节扩展预留 ==========
    // 直接添加新的 'chX_Y_timing' 键到此对象即可
};