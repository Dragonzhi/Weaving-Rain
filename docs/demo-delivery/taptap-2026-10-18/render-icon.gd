extends SceneTree
## Rasterize the platform icon using the same SVG renderer as the game.
func _init() -> void:
    var image := Image.new()
    var svg := FileAccess.get_file_as_string("res://docs/demo-delivery/taptap-2026-10-18/sources/icon-square.svg")
    var error := image.load_svg_from_string(svg)
    if error != OK or image.get_size() != Vector2i(1024, 1024):
        push_error("Icon SVG failed to rasterize at 1024x1024: %s" % error)
        quit(1)
        return
    image.convert(Image.FORMAT_RGB8)
    error = image.save_png("res://docs/demo-delivery/taptap-2026-10-18/upload/icon-square-1024.png")
    if error != OK:
        push_error("Icon PNG failed to save: %s" % error)
        quit(1)
        return
    print("Platform icon: 1024x1024 RGB PNG exported")
    quit()
