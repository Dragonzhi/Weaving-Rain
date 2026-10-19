extends "res://docs/demo-delivery/render-drafts.gd"
## Publicity typography over unmodified official-map viewport captures.
func run() -> void:
    root.size=Vector2i(1920,1080)
    root.content_scale_size=Vector2i(1920,1080)
    heading.font_names=PackedStringArray(["SimSun","Microsoft YaHei"])
    body.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])
    for card in [
        ["mountain","借山成云","把湿空气迎向山坡，让雨落在需要它的地方。"],
        ["tools","留风聚云","留下风带，收拢水汽，组织下一场雨。"],
        ["storm","海上借雨","从外围引导雨带，在田地与水库之间作取舍。"]
    ]:
        var page := Control.new()
        picture(page,OUT+card[0]+"-source.png",Vector2.ZERO,Vector2(1920,1080))
        words(page,card[1],Vector2(108,166),58,paper,true)
        words(page,card[2],Vector2(112,249),23,paper)
        words(page,"风织雨  /  Weaving Rain",Vector2(112,1004),20,paper)
        words(page,"ZLOONG · 智龙  /  开发 Demo · 实机画面",Vector2(1430,1004),18,paper)
        await save_page(page,card[0]+"-gameplay.png")
    print("DEMO GAMEPLAY CARDS: three 1920x1080 pages saved")
    quit()
