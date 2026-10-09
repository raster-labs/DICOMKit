#!/usr/bin/env python3
"""Fetch a frozen NEMA DocBook part and dump its tables as tab-separated rows.

Usage:
    python3 Scripts/nema_docbook.py fetch 2026a 6 [--out DIR]
    python3 Scripts/nema_docbook.py subtitle part06.xml
    python3 Scripts/nema_docbook.py tables part06.xml [--grep TEXT]
    python3 Scripts/nema_docbook.py table part06.xml "6-1" [--header] [--caption TEXT]

`fetch` downloads https://dicom.nema.org/medical/dicom/<edition>/source/docbook/partNN/partNN.xml
and prints its subtitle, which must name the edition you asked for.
`tables` lists table labels and captions. `table` prints one table, one row per line,
cells separated by tabs. Cross-references are resolved to their labels (e.g. "TID 301"),
paragraphs within a cell are joined with " | ", whitespace is normalised and zero-width
spaces (U+200B) are removed, so the output can be diffed against values from the code.

This is the extraction step of the verification method in
DICOMCORE_STANDARD_IMPLEMENTATION.md; it works for every part (PS3.3, 3.5, 3.6, 3.16, ...).
"""
import argparse
import os
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET

D = '{http://docbook.org/ns/docbook}'
X = '{http://www.w3.org/XML/1998/namespace}'
URL = 'https://dicom.nema.org/medical/dicom/{edition}/source/docbook/part{part:02d}/part{part:02d}.xml'


def norm(s):
    return re.sub(r'\s+', ' ', s.replace('​', '')).strip()


class Part:
    def __init__(self, path):
        self.root = ET.parse(path).getroot()
        self.labels = {}
        for e in self.root.iter():
            i = e.get(X + 'id')
            if i and e.get('label'):
                self.labels[i] = e.get('label')

    @property
    def subtitle(self):
        sub = self.root.find('.//' + D + 'subtitle')
        return norm(''.join(sub.itertext())) if sub is not None else ''

    def text(self, element):
        def walk(n, out, top):
            if n.tag == D + 'xref':
                out.append(self.labels.get(n.get('linkend'), n.get('linkend')))
            elif n.tag == D + 'olink':
                out.append(f"{n.get('targetdoc')} {n.get('targetptr')}")
            else:
                if n.text:
                    out.append(n.text)
                for c in n:
                    walk(c, out, False)
            if n.tail and not top:
                out.append(n.tail)
        paras = element.findall(D + 'para') or [element]
        parts = []
        for p in paras:
            out = []
            walk(p, out, True)
            if norm(''.join(out)):
                parts.append(norm(''.join(out)))
        return ' | '.join(parts)

    def tables(self):
        for t in self.root.iter(D + 'table'):
            caption = t.find(D + 'caption')
            yield t.get('label') or '', norm(''.join(caption.itertext())) if caption is not None else '', t

    def table(self, label, caption=None):
        label = re.sub(r'^Table ', '', label)
        matches = [(cap, t) for lab, cap, t in self.tables()
                   if lab == label and (caption is None or caption.lower() in cap.lower())]
        if not matches:
            sys.exit(f'no table labelled {label!r}' + (f' with caption {caption!r}' if caption else ''))
        if len(matches) > 1:
            # e.g. a TID has a "Parameters" table and the template table under one label
            print(f'{len(matches)} tables labelled {label!r}: '
                  + '; '.join(repr(c) for c, _ in matches) + '. Using the last; pass --caption to choose.',
                  file=sys.stderr)
        return matches[-1][1]

    def rows(self, table, header=False):
        sections = (['thead'] if header else []) + ['tbody']
        for section in sections:
            for body in table.iter(D + section):
                for tr in body.findall(D + 'tr'):
                    yield [self.text(c) for c in tr if c.tag in (D + 'td', D + 'th')]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = parser.add_subparsers(dest='command', required=True)
    f = sub.add_parser('fetch')
    f.add_argument('edition')
    f.add_argument('part', type=int)
    f.add_argument('--out', default='.')
    s = sub.add_parser('subtitle')
    s.add_argument('xml')
    ts = sub.add_parser('tables')
    ts.add_argument('xml')
    ts.add_argument('--grep', default='')
    t = sub.add_parser('table')
    t.add_argument('xml')
    t.add_argument('label')
    t.add_argument('--header', action='store_true')
    t.add_argument('--caption', help='pick among tables sharing a label by caption text')
    args = parser.parse_args()

    if args.command == 'fetch':
        url = URL.format(edition=args.edition, part=args.part)
        path = os.path.join(args.out, f'part{args.part:02d}_{args.edition}.xml')
        urllib.request.urlretrieve(url, path)
        subtitle = Part(path).subtitle
        print(f'{path}: {subtitle}')
        if args.edition not in subtitle:
            sys.exit(f'subtitle does not name {args.edition}; do not use this copy')
    elif args.command == 'subtitle':
        print(Part(args.xml).subtitle)
    elif args.command == 'tables':
        for label, caption, _ in Part(args.xml).tables():
            if args.grep.lower() in (label + ' ' + caption).lower():
                print(f'{label}\t{caption}')
    else:
        part = Part(args.xml)
        for row in part.rows(part.table(args.label, args.caption), args.header):
            print('\t'.join(row))


if __name__ == '__main__':
    main()
