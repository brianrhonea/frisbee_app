"""Minimal docx -> Markdown converter (stdlib only).
Usage: python -I docx2md.py <in.docx> <out.md> <assets_dir> <assets_rel_prefix>
Handles Title/Heading1-6, ListBullet/numPr lists, tables, bold/italic, line breaks, images."""
import sys, zipfile, re, os
import xml.etree.ElementTree as ET

W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
R = '{http://schemas.openxmlformats.org/officeDocument/2006/relationships}'
A = '{http://schemas.openxmlformats.org/drawingml/2006/main}'
PR = '{http://schemas.openxmlformats.org/package/2006/relationships}'

src, out, assets, rel_prefix = sys.argv[1:5]
z = zipfile.ZipFile(src)
doc = ET.fromstring(z.read('word/document.xml'))
rels = {}
try:
    for r in ET.fromstring(z.read('word/_rels/document.xml.rels')):
        rels[r.get('Id')] = r.get('Target')
except KeyError:
    pass
base = os.path.splitext(os.path.basename(src))[0]
img_count = 0


def esc(t, in_table):
    t = t.replace('\\', '\\\\').replace('<', '&lt;').replace('>', '&gt;').replace('&lt;br&gt;', '<br>')
    if in_table:
        t = t.replace('|', '\\|')
    return t


def run_text(p, in_table=False):
    global img_count
    parts = []
    for r in p.iter():
        if r.tag != W + 'r':
            continue
        rpr = r.find(W + 'rPr')
        bold = rpr is not None and rpr.find(W + 'b') is not None and rpr.find(W + 'b').get(W + 'val') not in ('0', 'false')
        ital = rpr is not None and rpr.find(W + 'i') is not None and rpr.find(W + 'i').get(W + 'val') not in ('0', 'false')
        txt = ''
        for ch in r:
            if ch.tag == W + 't':
                txt += ch.text or ''
            elif ch.tag == W + 'tab':
                txt += ' '
            elif ch.tag in (W + 'br', W + 'cr'):
                txt += '<br>' if in_table else '  \n'
            elif ch.tag == W + 'drawing':
                for blip in ch.iter(A + 'blip'):
                    rid = blip.get(R + 'embed')
                    tgt = rels.get(rid)
                    if tgt:
                        img_count += 1
                        data = z.read('word/' + tgt.lstrip('/').replace('word/', '', 1))
                        ext = os.path.splitext(tgt)[1]
                        name = f'{base}_image{img_count}{ext}'
                        os.makedirs(assets, exist_ok=True)
                        with open(os.path.join(assets, name), 'wb') as fh:
                            fh.write(data)
                        txt += f'![{base} image {img_count}]({rel_prefix}/{name})'
        if not txt:
            continue
        txt = esc(txt, in_table) if '![' not in txt else txt
        parts.append((txt, bold, ital))
    # merge adjacent runs with same formatting
    merged = []
    for t, b, i in parts:
        if merged and merged[-1][1] == b and merged[-1][2] == i:
            merged[-1][0] += t
        else:
            merged.append([t, b, i])
    s = ''
    for t, b, i in merged:
        if (b or i) and t.strip() and '![' not in t:
            lead = t[:len(t) - len(t.lstrip())]
            trail = t[len(t.rstrip()):]
            core = t.strip()
            mark = ('**' if b else '') + ('*' if i else '')
            s += f'{lead}{mark}{core}{mark[::-1]}{trail}'
        else:
            s += t
    return s


def style(p):
    ppr = p.find(W + 'pPr')
    if ppr is None:
        return '', False
    ps = ppr.find(W + 'pStyle')
    num = ppr.find(W + 'numPr') is not None
    return (ps.get(W + 'val') if ps is not None else ''), num


lines = []
for el in doc.find(W + 'body'):
    if el.tag == W + 'p':
        st, num = style(el)
        t = run_text(el).strip()
        if not t:
            continue
        if st == 'Title':
            lines.append(f'# {t}')
        elif st.startswith('Heading') and st[7:].isdigit():
            lvl = min(int(st[7:]) + 1, 6)
            lines.append('#' * lvl + ' ' + t.replace('**', ''))
        elif st.startswith('ListBullet') or st == 'ListParagraph' or num:
            lines.append(f'- {t}')
            continue_list = True
        else:
            lines.append(t)
        lines.append('')
    elif el.tag == W + 'tbl':
        rows = []
        trs = el.findall(W + 'tr')
        def all_bold(tr):
            runs = [r for r in tr.iter(W + 'r') if ''.join(t.text or '' for t in r.iter(W + 't')).strip()]
            if not runs:
                return False
            for r in runs:
                rpr = r.find(W + 'rPr')
                b = rpr.find(W + 'b') if rpr is not None else None
                if b is None or b.get(W + 'val') in ('0', 'false'):
                    return False
            return True
        has_header = bool(trs) and all_bold(trs[0])
        if trs and not has_header:
            first = [''.join(t.text or '' for t in tc.iter(W + 't')).strip() for tc in trs[0].findall(W + 'tc')]
            has_header = all(c and len(c) <= 40 and not c.endswith('.') for c in first)
        for tr in trs:
            cells = []
            for tc in tr.findall(W + 'tc'):
                ps = [run_text(p, True).strip() for p in tc.findall(W + 'p')]
                cells.append('<br>'.join(x for x in ps if x))
            rows.append(cells)
        if not rows:
            continue
        n = max(len(r) for r in rows)
        rows = [r + [''] * (n - len(r)) for r in rows]
        if has_header:
            lines.append('| ' + ' | '.join(c.replace('**', '') for c in rows[0]) + ' |')
            body = rows[1:]
        else:
            lines.append('|' + ' |' * n)
            body = rows
        lines.append('|' + '---|' * n)
        for r in body:
            lines.append('| ' + ' | '.join(r) + ' |')
        lines.append('')

# collapse blank lines between consecutive bullets
text = '\n'.join(lines)
text = re.sub(r'(\n- [^\n]*)\n\n(?=- )', r'\1\n', text)
text = re.sub(r'(\n- [^\n]*)\n\n(?=- )', r'\1\n', text)
header = f'<!-- Converted from {os.path.basename(src)}; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->\n\n'
with open(out, 'w', encoding='utf-8', newline='\n') as fh:
    fh.write(header + text.strip() + '\n')
print(out, len(text), 'chars', img_count, 'images')
