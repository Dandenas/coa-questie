"""World position (map, x, y) -> (zone areaId, map %x, map %y), from the client's WorldMapArea.dbc.

Questie stores spawns per top-level zone in the zone's world-map percentages. A point can sit inside
several zone rectangles (they overlap at borders); the zone where it is furthest inside wins.
"""
import glob, os, struct, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from mpq import MPQ

DATA = os.path.join(os.environ.get("COA_CLIENT", r"D:\COA Client"), "Data")  # set COA_CLIENT to your client folder


def read_dbc(name):
    found = None
    for p in sorted(glob.glob(os.path.join(DATA, "*.MPQ")) + glob.glob(os.path.join(DATA, "*.mpq")), key=str.lower):
        try:
            d = MPQ(p).read("DBFilesClient\\" + name)
        except Exception:
            d = None
        if d:
            found = d
    magic, n, nf, rs, ss = struct.unpack_from("<4s4I", found, 0)
    strings = found[20 + n * rs:]
    rows = []
    for i in range(n):
        raw = found[20 + i * rs:20 + (i + 1) * rs]
        rows.append((struct.unpack_from("<%di" % nf, raw), struct.unpack_from("<%df" % nf, raw), strings))
    return rows


def text(strings, off):
    return strings[off:strings.find(b"\0", off)].decode("utf-8", "replace")


class Zones:
    def __init__(self):
        self.area_parent, self.area_name = {}, {}
        for ints, _, s in read_dbc("AreaTable.dbc"):
            self.area_parent[ints[0]] = ints[2]
            self.area_name[ints[0]] = text(s, ints[11])
        self.rects = {}  # map -> [(areaId, left, right, top, bottom)]
        for ints, fl, s in read_dbc("WorldMapArea.dbc"):
            wid, mapid, area = ints[0], ints[1], ints[2]
            left, right, top, bottom = fl[4:8]
            if area == 0 or left == right or top == bottom:
                continue
            if self.area_parent.get(area, 0) != 0:
                continue  # sub-zones/caves: Questie keys spawns by the top-level zone
            self.rects.setdefault(mapid, []).append((area, left, right, top, bottom))

    def locate(self, mapid, wx, wy):
        best, best_score = None, None
        for area, left, right, top, bottom in self.rects.get(mapid, ()):
            if not (right <= wy <= left and bottom <= wx <= top):
                continue
            px = (left - wy) / (left - right)
            py = (top - wx) / (top - bottom)
            score = min(px, 1 - px, py, 1 - py)  # how far inside, as a fraction of the map
            if best_score is None or score > best_score:
                best, best_score = (area, round(px * 100, 2), round(py * 100, 2)), score
        return best
