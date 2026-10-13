# 视觉语言参考图与生成记录

日期：2026-10-13。使用内置 imagegen 生成与修正。用户已认可三张图的UI方向，并指出其中云、地形、水库与田地更有立体感和风味。图片作为共用视觉参考，不是实际运行截图或已经实现的界面；界面代码尚未修改。

1. [完整游玩画面](references/gameplay.png)：小雨滴行、独立池水位、短浮字及紧凑工具栏。
2. [目标状态](references/target-states.png)：水量与安全分开，黄色表示接近过量。
3. [风纹结算](references/result.png)：三枚成果奖章、逐目标结果。

场景绘画现也作为后续立体感提升的方向：云的上下层明暗、岛岸厚度、池岸与水面的高低、田土与植株的层次。具体实现另安排场景美术阶段，不据此修改地图位置、玩法规则或云数据定义。生成图的字体、轮廓、尺寸与配色不是最终绘制规格，实施遵循 DESIGN.md 并在实机核对。原状态图出现了过多装饰及错误黄色文案，已修正；正文只链接修正后的三张图。

## 提示词记录

### visual_gameplay

```text
Use case: ui-mockup. Edit Image 1 into a polished but implementable UI concept screenshot for the Chinese Godot weather game 风织雨. Image 1 is the edit target and establishes the fixed orthographic camera, irregular island, single hill, farm A and reservoir B. Image 2 is a style reference ONLY: smooth silhouettes, a few flat layered cloud color bands, turquoise sea, sage green terrain, cream linework. Keep the scene composition, object locations, playable space and weather silhouette of Image 1; improve only graphic consistency and interface. Landscape 16:9.
The new UI must be VERY COMPACT, with ample unobstructed play area. At top left put a small 风织雨 wordmark, restrained map label, tiny clock 02:18, and small weather reserve bar. A small 菜单 button top right. Bottom center has a narrow cream toolbar with three small distinct outline icons and Chinese text 拨风 / 风带 / 漩涡, and a small 天气提示 control. No huge panels, no decorative game dashboard.
Beside farm A replace the rectangular water card with 'A' followed by EXACTLY FIVE identically sized outlined teardrop water icons: three filled muted cyan, the fourth half filled, fifth empty. Add a small amber warning triangle beside the row. Hovering shows ONE brief floating phrase immediately above it: 雨量已够时，请移云 -- actually use phrase 缺水 to be consistent with the partial row; only exact floating phrase "还差30". The numeric water example is 70/100, 20 per droplet, five total. No checkmark on this incomplete farm. Tiny warm-cream backing only behind the hover words, not a card.
Beside reservoir B show 'B' and a SMALL bowl-shaped outline water gauge filled blue to its brim, plus a small completion checkmark. Floating text 已蓄满. Reservoir never yellow or red because overflow is allowed.
Scene wind is always represented by sparse thin white flowing streaks. Rain lines ONLY visibly fall below cloud base, NEVER over the front/top of clouds. Actual ground rain footprint uses a very faint blue fill and thin contour. Show no arrow clutter. Wind achievement motif, if seen at top, is three small round outline medals each containing three flowing wind lines, NOT stars and NOT spiral vortex symbols.
Fonts readable Chinese sans serif, charcoal blue #354e57 text, cream #f0f5e3, water #7aaebc, soft amber #ddc775. Flat vector-style UI, thin but legible lines, subdued. No characters, no hearts, no glowing magic, no ornamental flourishes. This is a concept mockup, not a claim of implemented game UI.
```

### visual_states

```text
Use case: ui-mockup. Generate a high fidelity landscape visual reference board for the Chinese indie weather game 风织雨, showing compact FARM WATER AND SAFETY UI glyphs placed beside little isometric sage-green farmland patches. One coherent visual system, not alternative art styles. Flat clean vector-like shapes matching smooth layered clouds, pale warm cream background, muted turquoise/gray-blue water, charcoal blue text, soft yellow warning, subdued coral red damage. Professional quiet game UI presentation; small Chinese type, no giant infographic labels. Wide 16:9.
Arrange SIX roomy specimen tiles in two rows of three, each with a tiny stylized farm/island crop context, a compact water droplet row, a separate safety glyph and one SHORT hover-style word. All farm droplets are identical outlined teardrops, filled from bottom upward. Every farm sample except the seedling has FIVE drops (20 units each, target100).
TOP LEFT: label 缺水, 2 blue full drops then one half-full then 2 empty, no completion glyph.
TOP MIDDLE: label 移云, FIVE filled BLUE drops, a small amber warning triangle, clearly water is sufficient yet unsafe; do not put a checkmark.
TOP RIGHT: label 确认安全, FIVE filled muted BLUE drops, a small GOLD circular progress ring 60% complete; do not put a checkmark yet.
BOTTOM LEFT: label 已保住, FIVE filled muted BLUE drops plus small GOLD completion checkmark. NOT stars.
BOTTOM MIDDLE: label 损坏, FIVE filled CORAL RED drops plus RED X / broken glyph. A smaller adjacent swatch caption 蓝 → 黄 → 红 demonstrates water shortage blue, decreasing overflow margin yellow, permanent damage red. Amber color is warning only, not completion. No extra drops beyond five.
BOTTOM RIGHT: label 已蓄满, a separate outlined shallow bowl water gauge filled BLUE, small completion checkmark; one brief hover line 可继续承雨. It is a reservoir, NEVER damage-red.
Near bottom edge a very small seedling specimen 幼苗 shows TWO identical-size blue droplets beside a sprout, explaining lower water requirement by fewer drops, not smaller drops. Use generous white space between specimens, thin 1.5–2px lines in drawing scale, compact faint cream hover text backing only. Keep water graphics, safety graphics and achievement icons separate. Avoid dense text, massive panels, photorealism, gradients on icons, stars, temperature metaphors, fantasy HUD ornament, character mascot. Text must be legible accurate Chinese.
```

### visual_result

```text
Use case: ui-mockup. Edit Image 1 to visualize a FINISHED-ROUND interface for 风织雨 using the established game world. Image 1 establishes orthographic island camera, terrain and farm+reservoir. Image 2 provides only smooth flat layered graphic style and palette. Preserve scene geometry and camera; fade scene subtly into a calm backdrop, rain finished, cloud moved offshore, sparse white wind streaks remain. Landscape 16:9.
Create a restrained central warm-cream completion panel, about 38% of image width, not a full-screen dashboard, with thin slate-blue border, slightly rounded corners and no heavy drop shadows. It is an actual plausible game end-screen concept. Small heading 本局完成 at top; then EXACTLY THREE identical circular wind achievement medallions evenly spaced, all activated in soft warm gold. Each medallion has a single thin circular outer rim containing THREE short flowing horizontal wind-line curves -- stylized airflow, NOT star shapes, NOT cyclone spiral icons, NOT coins with currency symbols. Keep medals clean and readable at small scale. Label underneath: 风纹评价 3/3.
Two compact target rows beneath:
A 普通田 — show five same-size blue filled outline teardrops, a little gold checkmark, text 已保住; accurate water value 112/100 and smaller 适量 100–150.
B 蓄水区 — show a small outlined BOWL with blue water at brim, a gold checkmark, text 已蓄满; accurate 250/250 and smaller 满后可继续承雨.
Final small summary 两处目标均已完成. Bottom two native-looking cream/gray-blue buttons 重试 and 下一局. Keep labels exact, readable Chinese sans serif, generous rhythm but compact panel, #354e57 ink, #607b80 secondary text, #7aaebc water, warm muted gold. No stars anywhere, no flashing glitter, no score multiplication, no currency, no extra goals, no new gameplay mechanics. The three wind medals represent the existing three-tier end rating and remain visibly different from tool icons. No giant title. No rain strokes on clouds. This is a visual concept, not an implemented screenshot.
```

### visual_gameplay_fixed

```text
Edit this visual UI concept. Preserve all scene art, clouds, rain, camera, composition, bottom toolbar, reservoir, colors and typography exactly. ONLY correct the farm A state: remove the yellow warning triangle to the right of its five water droplets, because this farm is still short of water. Keep EXACTLY FIVE outlined droplets: three full blue, fourth half-full blue, fifth empty. Keep hovering text 还差30. At the top center change the three wind achievement icons to clearly inactive gray-blue outlines, with no lit gold fill, so an unfinished scene does not show completed awards. Do not add replacement warning icons. Do not change any other part of the image.
```

### visual_states_fixed

```text
Revise Image 1 (edit target), the six-state UI reference board for 风织雨. Image 2 establishes the game's EXACT SIMPLE FLAT STYLE. Keep the six-state board layout, the same water droplet counts, same status ring/check/X, and cream/slate/turquoise/gold/coral palette. Replace the overly ornate countryside dioramas in every specimen with VERY SIMPLE tiny flat isometric farm patches: irregular sage-green turf plinth, plain brown rectangle, at most 3–5 tiny sprout silhouettes; reservoir is a simple oval stone rim with flat cyan water. REMOVE all buildings, waterwheels, trees, countryside landscape, mountain illustrations, fences, fruit orchards and decorative cloud scrolls. Flat vector-like blocks, smooth silhouettes, two or three colors per specimen, no detailed painting or textures.
Text must be corrected and SHORT: top states 缺水 / 移云 / 确认安全, bottom states 已保住 / 损坏 / 已蓄满. Only one concise floating phrase per state, respectively 还差50 / 附近仍有危险 / 正在确认安全 / 当前安全 / 过量损坏 / 可继续承雨. No claims of plant growth limitations or other game rules. Keep two full droplets, one half and two empty for shortage; five full blue for each of danger/confirming/saved; five full coral red for damage; distinct small bowl filled blue for reservoir. Safety ring can say 60%. The seedling specimen at bottom remains simple sprout with EXACTLY TWO same-size blue droplets and caption 幼苗.
Most important correction: the bottom color legend must EXACTLY read 蓝：累计水量    黄：接近过量    红：永久损坏 . YELLOW MEANS APPROACHING EXCESS WATER, NEVER WATER SHORTAGE. Keep equal drop shapes in blue, yellow, red above the respective phrases. Do not include 接近不足 anywhere.
Legible simple Chinese sans serif, ample white space, no large card backing, no gradients on icons, no stars, no new mechanics, no ornate Chinese cultural style. This is a component reference for a minimal procedural-weather game UI.
```
