"""Minimal read-only MPQ reader (formats v0/v1, zlib/bzip2 sectors) for pulling
single files such as DBFilesClient\\WorldMapArea.dbc out of WoW 3.3.5 archives."""
import struct, zlib, bz2, sys, os

def _crypt_table():
    table = [0] * 0x500
    seed = 0x00100001
    for i in range(0x100):
        idx = i
        for _ in range(5):
            seed = (seed * 125 + 3) % 0x2AAAAB
            t1 = (seed & 0xFFFF) << 16
            seed = (seed * 125 + 3) % 0x2AAAAB
            t2 = seed & 0xFFFF
            table[idx] = t1 | t2
            idx += 0x100
    return table

CRYPT = _crypt_table()

def hash_string(s, htype):
    seed1, seed2 = 0x7FED7FED, 0xEEEEEEEE
    for ch in s.upper().replace('/', '\\'):
        c = ord(ch)
        seed1 = (CRYPT[(htype << 8) + c] ^ (seed1 + seed2)) & 0xFFFFFFFF
        seed2 = (c + seed1 + seed2 + (seed2 << 5) + 3) & 0xFFFFFFFF
    return seed1

def decrypt(data, key):
    out = bytearray()
    seed = 0xEEEEEEEE
    n = len(data) // 4
    vals = struct.unpack('<%dI' % n, data[:n * 4])
    for v in vals:
        seed = (seed + CRYPT[0x400 + (key & 0xFF)]) & 0xFFFFFFFF
        d = (v ^ ((key + seed) & 0xFFFFFFFF)) & 0xFFFFFFFF
        key = (((~key << 0x15) + 0x11111111) | (key >> 0x0B)) & 0xFFFFFFFF
        seed = (d + seed + (seed << 5) + 3) & 0xFFFFFFFF
        out += struct.pack('<I', d)
    return bytes(out) + data[n * 4:]

class MPQ:
    def __init__(self, path):
        self.path = path
        self.f = open(path, 'rb')
        off = 0
        while True:
            self.f.seek(off)
            magic = self.f.read(4)
            if magic == b'MPQ\x1a':
                break
            if magic == b'MPQ\x1b':
                self.f.read(4)
                off += struct.unpack('<I', self.f.read(4))[0]
                continue
            off += 0x200
            if off > 0x1000000:
                raise ValueError('no MPQ header')
        self.base = off
        self.f.seek(off)
        hdr = self.f.read(44)
        (_, hsize, _, fmt, shift, hpos, bpos, hcount, bcount) = struct.unpack('<4sIIHHIIII', hdr[:32])
        hi_h = hi_b = 0
        if fmt >= 1 and len(hdr) >= 44:
            _, hi_h, hi_b = struct.unpack('<QHH', hdr[32:44])
        self.sector = 512 << shift
        self.f.seek(off + hpos + (hi_h << 32))
        ht = decrypt(self.f.read(hcount * 16), hash_string('(hash table)', 3))
        self.hashes = [struct.unpack_from('<IIHHI', ht, i * 16) for i in range(hcount)]
        self.f.seek(off + bpos + (hi_b << 32))
        bt = decrypt(self.f.read(bcount * 16), hash_string('(block table)', 3))
        self.blocks = [struct.unpack_from('<IIII', bt, i * 16) for i in range(bcount)]

    def find(self, name):
        a, b = hash_string(name, 1), hash_string(name, 2)
        n = len(self.hashes)
        i = hash_string(name, 0) % n
        for _ in range(n):
            na, nb, loc, plat, bi = self.hashes[i]
            if bi == 0xFFFFFFFF:
                return None
            if na == a and nb == b and bi != 0xFFFFFFFE:
                return self.blocks[bi]
            i = (i + 1) % n
        return None

    def read(self, name):
        blk = self.find(name)
        if not blk:
            return None
        pos, csize, fsize, flags = blk
        if not flags & 0x80000000:
            return None
        if flags & 0x00000100:
            raise NotImplementedError('imploded file')
        key = None
        if flags & 0x00010000:
            key = hash_string(name.replace('/', '\\').split('\\')[-1], 3)
            if flags & 0x00020000:
                key = ((key + pos) ^ fsize) & 0xFFFFFFFF
        self.f.seek(self.base + pos)
        raw = self.f.read(csize)
        if flags & 0x01000000:  # single unit
            data = decrypt(raw, key) if key is not None else raw
            return self._decomp(data, fsize) if (flags & 0x200 and csize < fsize) else data
        nsec = (fsize + self.sector - 1) // self.sector
        otab = raw[:(nsec + 1) * 4]
        if key is not None:
            otab = decrypt(otab, (key - 1) & 0xFFFFFFFF)
        offs = struct.unpack('<%dI' % (nsec + 1), otab)
        out = bytearray()
        for s in range(nsec):
            chunk = raw[offs[s]:offs[s + 1]]
            if key is not None:
                chunk = decrypt(chunk, (key + s) & 0xFFFFFFFF)
            want = min(self.sector, fsize - s * self.sector)
            if flags & 0x200 and len(chunk) < want:
                chunk = self._decomp(chunk, want)
            out += chunk
        return bytes(out)

    @staticmethod
    def _decomp(data, want):
        mask, body = data[0], data[1:]
        if mask == 0x02:
            return zlib.decompress(body)
        if mask == 0x10:
            return bz2.decompress(body)
        raise NotImplementedError('compression mask 0x%02x' % mask)

if __name__ == '__main__':
    name = sys.argv[1]
    for path in sys.argv[2:]:
        try:
            m = MPQ(path)
            blk = m.find(name)
            if blk:
                print('%s: found, size=%d flags=0x%08x' % (os.path.basename(path), blk[2], blk[3]))
        except Exception as e:
            print('%s: error %s' % (os.path.basename(path), e))
