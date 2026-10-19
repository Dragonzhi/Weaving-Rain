extends "res://docs/demo-delivery/render-drafts.gd"
## Documentation assets only. Original art: built-in image_gen; native typography/size export.
const DIR := "res://docs/demo-delivery/taptap-2026-10-18/"

func art(parent: Node, filename: String, dimensions: Vector2) -> void:
    var texture := TextureRect.new()
    texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
    texture.texture=ImageTexture.create_from_image(Image.load_from_file(DIR+"sources/"+filename))
    texture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
    texture.size=dimensions
    parent.add_child(texture)

func title_line(parent: Node, text: String, font: Font, font_size: int, y: float, height: float) -> void:
    var line := Label.new()
    line.text=text
    line.position=Vector2(0,y)
    line.size=Vector2(1600,height)
    line.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
    line.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
    line.add_theme_font_override("font",font)
    line.add_theme_font_size_override("font_size",font_size)
    line.add_theme_color_override("font_color",Color("f8f8eb"))
    line.add_theme_color_override("font_outline_color",Color(0.13,0.33,0.36,0.20))
    line.add_theme_constant_override("outline_size",2)
    parent.add_child(line)

func export_png(page: Control, dimensions: Vector2i, filename: String, trim: bool = false) -> void:
    var viewport := SubViewport.new()
    viewport.size=dimensions
    viewport.disable_3d=true
    viewport.transparent_bg=true
    viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    viewport.add_child(page)
    await process_frame
    await process_frame
    await RenderingServer.frame_post_draw
    var pixels := viewport.get_texture().get_image()
    assert(pixels.get_size()==dimensions)
    if trim:
        var bounds := pixels.get_used_rect().grow(10).intersection(Rect2i(Vector2i.ZERO,dimensions))
        pixels=pixels.get_region(bounds)
    assert(pixels.save_png(DIR+"upload/"+filename)==OK)
    print(filename," ",pixels.get_size()," bytes=",FileAccess.get_file_as_bytes(DIR+"upload/"+filename).size())
    viewport.queue_free()
    await process_frame

func run() -> void:
    heading.font_names=PackedStringArray(["SimSun","Microsoft YaHei"])
    body.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])
    var logo := Control.new()
    title_line(logo,"风织雨",heading,470,0,540)
    title_line(logo,"W E A V I N G   R A I N",body,78,540,120)
    await export_png(logo,Vector2i(1600,700),"logo-transparent.png",true)
    var logo_size := Vector2(Image.load_from_file(DIR+"upload/logo-transparent.png").get_size())
    for item in [
        ["promo-1920x1080.png",Vector2i(1920,1080),"landscape.png",Vector2(130,104),620.0],
        ["cover-landscape-1840x860.png",Vector2i(1840,860),"landscape.png",Vector2(108,78),560.0],
        ["cover-portrait-1200x1800.png",Vector2i(1200,1800),"portrait.png",Vector2(175,48),850.0],
        ["wallpaper-3840x1240.png",Vector2i(3840,1240),"wallpaper.png",Vector2.ZERO,0.0]
    ]:
        var page := Control.new()
        art(page,item[2],Vector2(item[1]))
        var width: float=item[4]
        if width>0:
            picture(page,DIR+"upload/logo-transparent.png",item[3],Vector2(width,roundf(width*logo_size.y/logo_size.x)))
        await export_png(page,item[1],item[0])
    print("TAPTAP ASSETS: five PNGs exported; no game scene or game configuration loaded")
    quit()
