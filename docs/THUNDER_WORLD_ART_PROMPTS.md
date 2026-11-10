# 鸣雷城世界美术生成记录

全部图像通过内置图像生成工具制作。生产图放入 godot/assets/content_v290。背景为八张独立宽屏图，敌人、容器、物品分别保存为一张透明图集并由原生 AtlasTexture 读取。实际成品、尺寸、透明格式、体积和校验值见 world-art-manifest.json。使用纯文字委托生成，参考已有游戏的绘画风格要求。

## 背景共同要求

Use case: stylized-concept. Production landscape background for a painterly anime fantasy turn-based RPG, 16:9 horizontal, matching detailed high fantasy Japanese RPG environment art. Setting is Ming Lei City, an inland mountain city of ivory weathered stone, warm brass electrical machinery, deep navy/violet storm clouds, soft teal and warm amber lighting. Atmospheric rich detail with clear readable values on a phone. Lower third a wide clear stone floor battle apron, camera eye level and broad perspective. No people or monsters, no modern technology, no letters, no UI, no border, no watermark.

thunder_gate: the rainstorm outer gate of Ming Lei City, an inland mountain city of weathered ivory stone and warm brass lightning conductors. Painterly richly detailed anime environment with clean readable values and natural materials, blue-violet storm sky, violet lightning high in distance, teal lamps and warm amber sheltered windows. A monumental closed city gate, stone bridge, brass weather vanes, rain-wet old caravan unloading station at left. Keep entire lower third a broad clear cobbled battle apron for character sprites, horizon mid-height. Express tense but hopeful rescue adventure. Buildings old high-fantasy architecture. Final horizontal background, full bleed.

rain_street: A rain-soaked old city avenue, tall limestone homes and covered balconies, teal street lamps, brass lightning conduits spanning roofs, distant sealed tower behind clouds. Streams along stone drains, glowing windows suggest refuge. Mood concerned but hopeful.

storm_market: A sheltered abandoned covered market during a storm, canvas awnings tied securely above sturdy market stalls, dry cargo crates at sides, violet lightning far beyond a stone arch. Warm brass lamps, subdued teal banners, clear wide plaza. Quiet signs of hurried evacuation.

ward_clinic: An ancient city clinic sanctuary. Ivory stone arcade courtyard with golden protective wards suspended between brass rods, teal medical textiles, potted herbs, folded blankets and wooden medicine cabinets at sides. Warm lamplight shelters the courtyard from blue-violet rain beyond. Caring and restful.

sealed_station: A closed magical freight station in old city architecture, two brass rails and giant locked stone-and-brass gate at back, silent cargo platforms and old winches, overhead conductor coils glow faint violet. Wide wet stone apron in foreground, eerie malfunction with readable details.

observatory: A high mountain city observatory terrace at the edge of a lightning storm. Enormous brass armillary sphere and pointed lightning rods, a view across old city rooftops. Stone balustrade at rear, wide open stone terrace foreground, teal lens light and distant violet lightning. Dramatic but bright readable.

sunken_tower: An ancient circular tower chamber deep beneath the city, half-buried ivory stone foundations, enormous brass conductor arches rising from shallow water at edges, broken old machinery and faint violet runes without readable text. Wide dry stone platform for battle at lower third. Teal crystals and amber maintenance lamps reveal deep perspective.

rift_core: The immense inner chamber of an ancient tower beneath a storm-struck city. A floating bright violet dimensional rift held by tall brass conductor pylons at rear, concentric weathered stone rings, broken lightning conduits, blue and violet energy against warm gold architecture. Wide clear stone dais across lower third for the climactic boss battle. No boss or creatures.

## 地下场景修订

对 sunken_tower 与 rift_core 的初次结果进行逐张检查后，使用已生成图作为编辑目标，保留构图与装置，改成封闭地下大厅。最终编辑提示如下。

Use case: precise-object-edit. Edit this RPG background to restore its required UNDERGROUND location. Preserve its exact wide 16:9 composition, foreground clear battle floor, brass machinery, ivory stone architecture, lighting quality, painterly anime style and every major subject. Replace ALL visible open sky, outdoor clouds, distant mountain landscapes, outdoor skyline and distant city buildings with deep continuous cavern walls and a heavy arched stone ceiling high overhead. The chamber is buried entirely underneath the city. Show massive stone vaulted supports vanishing into darkness, subtle mineral crystals and damp stone instead of outdoor vistas. Bright enough to read clearly on a phone with teal crystals and warm maintenance lights. Keep no characters, no readable text, no UI.

sunken_tower additional instruction: Keep the central tall ancient tower encased inside this enormous subterranean hall, including shallow water at the edges.

rift_core additional instruction: Keep the large luminous violet dimensional rift and surrounding lightning contained under the underground ceiling. Preserve all floating broken circular architecture around the rift.

## 透明图集共同要求

Use case: stylized-concept. Asset type: production transparent PNG sprite atlas for a painterly anime fantasy RPG, same style as detailed high-fantasy game illustrations with clean edges and soft shading. Palette ivory stone, warm brass, navy, violet lightning and teal light. Every sprite is independent and completely contained in its assigned equal rectangular cell with 12% clear margin all around. True transparent empty background, no floor, no ground shadows outside subjects, no text, no labels, no visible grid lines.

thunder_enemies_atlas: Exactly 5 columns and 2 rows, 10 equal square cells. Landscape ratio 5:2. Reading left to right top row: 1 quadruped wolf-like THUNDER MANE beast with violet electric mane; 2 a small floating CHARGED MAYFLY with translucent violet wings and teal abdomen; 3 brass humanoid STORM PATROL mechanical soldier with spear; 4 floating violet RIFT SHADE with torn ethereal cloak; 5 brass STORM CROSSBOW GUARD automaton. Reading left to right bottom row: 6 BREAKER CAVALIER a bulky armored knight-shaped brass construct with lance, no horse; 7 THUNDER CORE GUARD a sturdy stone-and-brass circular shield automaton; 8 CITY SEALER boss, a towering stone and brass ancient humanoid colossus with a floating violet chest core, clear complete silhouette; 9 CONDUCTION CORE independent floating crystal in a brass circular cage; 10 CITY WARD NODE independent tall stone-and-brass pylon with a teal shielding crystal. All upright combat sprites full body, turned slightly to left, feet or lowest edge aligned near 88% of each cell. No cropped limbs. Boss must remain fully inside its own cell, scaled like the others for later game scaling.

thunder_containers_atlas: Exactly 3 columns and 2 rows, 6 equal square cells. Landscape 3:2. Each cell one large full object viewed three-quarter from slightly above. Reading left to right top row: 1 weathered reinforced sealed city supplies chest with violet seal and brass corner bands; 2 ivory wooden clinic medicine cabinet with folded blue cloth and glass bottles, doors closed; 3 sturdy brass engineer tool cabinet with coil shaped handles and wrench relief. Bottom row: 4 storm memorial stone offering plinth with teal crystal bowl; 5 ancient sealed brass archive cylinder case containing rolled charts, closed; 6 ornate city treasury coffer with deep violet enamel and gold lightning crest. Unique silhouette per container, broad clear forms readable at phone size.

thunder_loot_atlas: Exactly 6 columns and 4 rows, 24 equal square cells. Landscape 3:2. Inventory object sprites, one object per cell, all fully visible with strong distinct silhouette. Read left to right each row. Row 1: a copper wire coil, folded rainproof navy cloth, small ceramic insulator, brass lightning rod cap, violet sealing wax tin, dried silverleaf herb sachet. Row 2: brass contact plates, polished blue storm glass shard, copper induction ring, brass voltage gauge dial, city patrol badge, folded brass survey ruler. Row 3: silver conducting tuning fork, rolled old city electrical blueprint, teal crystal compass, purple protective amulet, gold-framed rotating conductor wheel, clear amber lightning crystal. Row 4: ornate golden city planning scroll case, silver control instrument frame, radiant violet storm heart gem, elaborate ancient lightning instrument, gold city warden crown set with purple crystals, luminous azure boundary crystal. Each exact cell is independent, transparent with no paper panels and no background. Keep safe margins.
