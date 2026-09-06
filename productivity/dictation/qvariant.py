import re, struct

def unescape(s):
    """Qt QSettings escaping -> raw bytes."""
    out = bytearray(); i = 0
    simple = {'0':0,'a':7,'b':8,'f':12,'n':10,'r':13,'t':9,'v':11,'\\':92,'"':34,"'":39}
    while i < len(s):
        c = s[i]
        if c == '\\' and i+1 < len(s):
            n = s[i+1]
            if n == 'x':
                j = i+2; h = ''
                while j < len(s) and len(h) < 2 and s[j] in '0123456789abcdefABCDEF':
                    h += s[j]; j += 1
                out.append(int(h,16)); i = j; continue
            if n in simple:
                out.append(simple[n]); i += 2; continue
            out.append(ord(n)); i += 2; continue
        out.append(ord(c)); i += 1
    return bytes(out)

def rd_u32(b,o): return struct.unpack('>I', b[o:o+4])[0], o+4

def parse(b):
    """QVariant blob -> python list."""
    o = 0
    t,o = rd_u32(b,o)              # type 9 = QVariantList
    n,o = rd_u32(b,o)              # element count
    items = []
    for _ in range(n):
        et,o = rd_u32(b,o)
        if et == 2:                # int
            v,o = rd_u32(b,o); items.append(('int', v))
        elif et == 3:              # uint
            v,o = rd_u32(b,o); items.append(('uint', v))
        elif et == 10:             # QString
            ln,o = rd_u32(b,o)
            if ln == 0xFFFFFFFF:
                items.append(('str', None))
            else:
                items.append(('str', b[o:o+ln].decode('utf-16-be'))); o += ln
        else:
            items.append(('?%d' % et, None)); break
    return items

def wr_u32(v): return struct.pack('>I', v)

def build(target, rtype, desc, pattern, repl, lang, name):
    """python fields -> QVariant blob bytes (mirrors what the GUI writes)."""
    out = bytearray()
    out += wr_u32(9); out += wr_u32(7)          # QVariantList, 7 elements
    out += wr_u32(3) + wr_u32(target)           # uint  target flags
    out += wr_u32(2) + wr_u32(rtype)            # int   rule type
    for s in (desc, pattern, repl, lang, name):
        out += wr_u32(10)                        # QString
        if s is None:
            out += b'\xff\xff\xff\xff'
        else:
            e = s.encode('utf-16-be'); out += wr_u32(len(e)) + e
    return bytes(out)

def escape(b):
    """raw bytes -> Qt QSettings escaped text."""
    named = {0:'\\0', 7:'\\a', 8:'\\b', 12:'\\f', 10:'\\n', 13:'\\r', 9:'\\t', 11:'\\v'}
    out = []
    for by in b:
        if by in named: out.append(named[by])
        elif by == 0x5c: out.append('\\\\')
        elif by == 0x22: out.append('\\"')
        elif by in (0x28, 0x29, 0x2c, 0x3b, 0x3d, 0x5b, 0x5d):
            out.append('\\x%x' % by)      # ( ) , ; = [ ] terminate the value for QSettings
        elif 0x20 <= by <= 0x7e: out.append(chr(by))
        else: out.append('\\x%x' % by)
    return ''.join(out)

def split_blobs(val):
    """Find every @Variant(...) payload, honouring escaped parens."""
    out = []; i = 0
    while True:
        k = val.find("@Variant(", i)
        if k < 0: break
        j = k + len("@Variant("); depth = 1
        while j < len(val) and depth:
            if val[j] == '\\': j += 2; continue
            if val[j] == '(': depth += 1
            elif val[j] == ')': depth -= 1
            j += 1
        out.append(val[k+len("@Variant("): j-1]); i = j
    return out
