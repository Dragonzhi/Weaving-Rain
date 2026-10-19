extends SceneTree
## Documentation-only rasterization/layout; does not load or modify gameplay.
const OUT := "res://docs/demo-delivery/visuals/"
var ink := Color("354e57")
var paper := Color("f0f5e3")
var heading := SystemFont.new()
var body := SystemFont.new()
func _init() -> void:
    call_deferred("run")
func picture(parent: Node, path: String, at: Vector2, dimensions: Vector2) -> void:
    var node := TextureRect.new()
    node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    node.texture = ImageTexture.create_from_image(Image.load_from_file(path))
    node.position = at
    node.size = dimensions
    assert(node.size == dimensions)
    parent.add_child(node)
func words(parent: Node, text: String, at: Vector2, size: int, color: Color, title: bool = false) -> void:
    var node := Label.new()
    node.text = text
    node.position = at
    node.add_theme_font_override("font",heading if title else body)
    node.add_theme_font_size_override("font_size",size)
    node.add_theme_color_override("font_color",color)
    parent.add_child(node)
func save_page(page: Control, filename: String) -> void:
    root.add_child(page)
    await process_frame
    await RenderingServer.frame_post_draw
    var pixels := root.get_texture().get_image()
    assert(pixels.get_size()==Vector2i(1920,1080))
    assert(pixels.save_png(OUT+filename)==OK)
    page.queue_free()
    await process_frame
func run() -> void:
    root.size=Vector2i(1920,1080)
    root.content_scale_size=Vector2i(1920,1080)
    RenderingServer.set_default_clear_color(paper)
    heading.font_names=PackedStringArray(["SimSun","Microsoft YaHei"])
    body.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])
    var svg := FileAccess.get_file_as_string(OUT+"icon-wind-lifts-cloud.svg")
    for size in [32,64,128,256,1024]:
        var image := Image.new()
        assert(image.load_svg_from_string(svg,size/1024.0)==OK)
        assert(image.get_size()==Vector2i(size,size))
        assert(image.save_png(OUT+"icon-%d.png" % size)==OK)
    var sheet := Control.new()
    words(sheet,"A · 风托云",Vector2(96,62),46,ink,true)
    words(sheet,"应用图标草稿  /  缩小尺寸对照",Vector2(99,130),22,Color("607b80"))
    picture(sheet,OUT+"icon-1024.png",Vector2(116,240),Vector2(512,512))
    for entry in [[32,850,330],[64,1020,314],[128,1220,282],[256,1510,218]]:
        var size: int=entry[0]
        picture(sheet,OUT+"icon-%d.png" % size,Vector2(entry[1],entry[2]),Vector2(size,size))
        words(sheet,str(size)+" px",Vector2(entry[1],entry[2]+size+30),20,ink)
    words(sheet,"上扬的风线，托起一朵云。",Vector2(850,650),30,ink,true)
    words(sheet,"青绿海色 · 珍珠白风线 · 灰蓝云底",Vector2(850,710),22,Color("607b80"))
    words(sheet,"ZLOONG · 智龙   /   Weaving Rain",Vector2(99,986),18,Color("607b80"))
    await save_page(sheet,"icon-size-review.png")
    var cover := Control.new()
    picture(cover,OUT+"cover-source-level03.png",Vector2.ZERO,Vector2(1920,1080))
    words(cover,"风 织 雨",Vector2(118,66),110,paper,true)
    words(cover,"W E A V I N G   R A I N",Vector2(126,210),25,paper)
    var rule := ColorRect.new()
    rule.color=Color(paper,0.7)
    rule.position=Vector2(126,267)
    rule.size=Vector2(56,2)
    cover.add_child(rule)
    words(cover,"借山成云，随风送雨。",Vector2(125,287),24,paper)
    words(cover,"ZLOONG · 智龙",Vector2(126,1004),20,paper)
    words(cover,"开发 Demo · 实机画面",Vector2(1580,1004),18,paper)
    await save_page(cover,"cover-sunny-sea-draft.png")
    print("DEMO VISUALS: SVG rasterized at 5 sizes; two 1920x1080 draft pages saved")
    quit()
