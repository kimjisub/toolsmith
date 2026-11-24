import os, subprocess, json, pathlib
OUT = pathlib.Path(__file__).resolve().parent
OUT.mkdir(parents=True, exist_ok=True)
LAV, PEACH = '#C7B8FF', '#FFC9A3'

# The Toolsmith mark: a hammer that reads as a T, drawn in a 512 box in one color.
def mark(name, color):
    if name == 'hammer':
        return f'''<path fill="{color}" d="M112 104 L384 104 L436 136 Q448 144 436 152 L384 184 L112 184 Q88 184 88 160 L88 128 Q88 104 112 104 Z"/>
<path fill="{color}" d="M222 176 L290 176 L290 400 Q290 434 256 434 Q222 434 222 400 Z"/>'''
    raise ValueError(name)

NAMES = {'hammer': '망치 T'}

BOX = {'hammer': (88, 104, 448, 434)}

def fitted(name, color, size, centre):
    """The mark scaled so its longer side is `size`, centred on (centre, centre)."""
    x0, y0, x1, y1 = BOX[name]
    k = size / max(x1 - x0, y1 - y0)
    tx = centre - (x0 + x1) / 2 * k
    ty = centre - (y0 + y1) / 2 * k
    return f'<g transform="translate({tx:.1f} {ty:.1f}) scale({k:.4f})">{mark(name, color)}</g>'

def svg(w, h, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>'

def icon(name):
    # macOS 26 app icon grid: 1024 canvas, 824 rounded square at 100, corner about 185.
    return svg(1024, 1024, f'''<defs>
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2E3240"/><stop offset="1" stop-color="#15171E"/></linearGradient>
<linearGradient id="mk" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{LAV}"/><stop offset="1" stop-color="#B3A2FF"/></linearGradient>
</defs>
<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/>
<rect x="101" y="101" width="822" height="822" rx="184" fill="none" stroke="#FFFFFF" stroke-opacity="0.10" stroke-width="2"/>
{fitted(name, LAV, 540, 512)}''')

def render(svgpath, png, w, h=None):
    subprocess.run(['rsvg-convert', '-w', str(w), '-h', str(h or w), '-o', str(png), str(svgpath)], check=True)

sizes = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
for name in NAMES:
    d = OUT / name; d.mkdir(exist_ok=True)
    (d / 'mark.svg').write_text(svg(512, 512, mark(name, '#000000')))
    (d / 'icon.svg').write_text(icon(name))
    # Menu bar template: black on transparent, the mark filling the height with a little air.
    (d / 'menubar.svg').write_text(svg(512, 512, fitted(name, "#000000", 480, 256)))
    sets = d / 'AppIcon.appiconset'; sets.mkdir(exist_ok=True)
    images = []
    for size, scale in sizes:
        fn = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
        render(d / 'icon.svg', sets / fn, size * scale)
        images.append({'filename': fn, 'idiom': 'mac', 'scale': f'{scale}x', 'size': f'{size}x{size}'})
    (sets / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2))
    for pt in (16, 18):
        for scale in (1, 2):
            render(d / 'menubar.svg', d / (f'menubar-{pt}pt' + ('@2x' if scale == 2 else '') + '.png'), pt * scale)

print('ok')
