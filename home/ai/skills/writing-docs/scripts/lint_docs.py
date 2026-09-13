#!/usr/bin/env python3
"""Static linter for documents written by the writing-docs skill.

Purpose: enforce the rules in references/style.md and references/mermaid.md
mechanically so verification does not rely on reading alone.
Invariants: standard library only; one stable code per rule; exit 1 on any error.
Usage: lint_docs.py <file>... [--type TYPE] [--root DIR]
"""
from __future__ import annotations

import argparse
import os
import re
import sys
import urllib.parse
from dataclasses import dataclass, field

TYPES = {
    "readme-project": 150,
    "readme-folder": 80,
    "how-to": 200,
    "explanation": 200,
    "reference": 300,
    "requirements": 300,
    "index": 120,
    "adr": 80,
    "glossary": None,
}
GUIDE_TYPES = {"how-to", "reference", "explanation", "index", "requirements"}
MERMAID_TYPES = {"PERSON", "TEAM", "UI", "API", "AGENT", "TOOL", "SERVICE", "SYSTEM", "DATA", "DATABASE"}

BANNED_WORDS = [
    "just", "simply", "easy", "easily", "trivial", "straightforward", "painless",
    "obviously", "of course", "delve", "leverage", "utilize", "seamless",
    "seamlessly", "robust", "comprehensive", "cutting-edge", "powerful",
    "innovative", "streamline", "empower", "crucially", "importantly", "notably",
    "essentially", "basically", "actually", "in order to", "note that",
    "it should be noted", "please note", "it's worth noting", "in today's",
]
META_PHRASES = [
    r"this (section|document|guide|file|readme) (used to|previously|formerly|once)",
    r"what was (one|a) \d+-node",
    r"replaces? what was",
    r"kept for link stability",
    r"this corpus now calls",
    r"became (two|three|four|five) diagrams",
    r"used to carry",
]
SMALL_WORDS = {
    "a", "an", "the", "and", "but", "or", "nor", "for", "so", "yet", "at", "by",
    "from", "in", "into", "of", "on", "onto", "to", "with", "via", "as", "per",
    "versus", "vs", "up", "down", "over", "under",
}

SENTENCE_MAX = 30
PARAGRAPH_MAX = 4
RUN_MAX = 6
CELL_MAX = 20
BULLET_MAX = 30
LIST_MAX = 7
H2_MAX = 10
TOC_LINES = 100
TOC_H2 = 5
DUP_WINDOW = 12


@dataclass
class Finding:
    path: str
    line: int
    code: str
    message: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}: {self.code} {self.message}"


@dataclass
class Doc:
    path: str
    lines: list[str]
    doc_type: str | None = None
    findings: list[Finding] = field(default_factory=list)
    prose_shingles: dict[str, int] = field(default_factory=dict)

    def add(self, line: int, code: str, message: str) -> None:
        self.findings.append(Finding(self.path, line, code, message))


# ---------- helpers ----------

def slugify(heading: str) -> str:
    text = re.sub(r"`([^`]*)`", r"\1", heading).strip().lower()
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def strip_inline_code(text: str) -> str:
    return re.sub(r"`[^`]*`", "CODE", text)


def link_text_only(text: str) -> str:
    return re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)


def word_count(text: str) -> int:
    text = link_text_only(strip_inline_code(text))
    return len([w for w in re.split(r"\s+", text.strip()) if w])


def sentences(text: str) -> list[str]:
    text = link_text_only(strip_inline_code(text))
    text = re.sub(r"\b(e\.g|i\.e|vs|etc)\.", r"\1", text)
    parts = re.split(r"(?<=[.!?])\s+(?=[A-Z\[`(])", text.strip())
    return [p for p in parts if p]


def heading_level(line: str) -> int:
    m = re.match(r"^(#{1,6})\s+\S", line)
    return len(m.group(1)) if m else 0


def is_title_case(title: str) -> bool:
    title = re.sub(r"`[^`]*`", "", title)
    title = re.sub(r"^ADR \d+:\s*", "", title)
    title = re.sub(r"^Flow \w+:\s*", "", title)
    words = [w for w in re.split(r"\s+", title.strip()) if w]
    for i, word in enumerate(words):
        bare = word.strip("()\"'“”:,.;!?")
        if not bare or not re.match(r"^[A-Za-z]", bare):
            continue
        if not re.match(r"^[A-Za-z][a-z]*(['’][a-z]+)?$|^[A-Z][A-Z0-9]+$|^[A-Za-z][a-zA-Z0-9]*[-/][A-Za-z0-9-]+$", bare):
            continue
        is_edge = i == 0 or i == len(words) - 1
        if bare.lower() in SMALL_WORDS and not is_edge:
            if bare[0].isupper():
                return False
            continue
        if bare[0].islower():
            return False
    return True


# ---------- segmentation ----------

@dataclass
class Block:
    kind: str  # fence, table, list, para, heading, blank, html
    start: int
    lines: list[str]
    lang: str = ""


def segment(lines: list[str]) -> list[Block]:
    blocks: list[Block] = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        m = re.match(r"^(\s*)(`{3,}|~{3,})\s*(\S*)", line)
        if m:
            fence = m.group(2)
            lang = m.group(3)
            start = i
            i += 1
            while i < n and not re.match(rf"^\s*{re.escape(fence[0])}{{{len(fence)},}}\s*$", lines[i]):
                i += 1
            blocks.append(Block("fence", start, lines[start:i + 1], lang))
            i += 1
            continue
        if line.strip().startswith("<!--"):
            start = i
            while i < n and "-->" not in lines[i]:
                i += 1
            blocks.append(Block("html", start, lines[start:i + 1]))
            i += 1
            continue
        if not line.strip():
            blocks.append(Block("blank", i, [line]))
            i += 1
            continue
        if heading_level(line):
            blocks.append(Block("heading", i, [line]))
            i += 1
            continue
        if line.lstrip().startswith("|"):
            start = i
            while i < n and lines[i].lstrip().startswith("|"):
                i += 1
            blocks.append(Block("table", start, lines[start:i]))
            continue
        if re.match(r"^\s*([-*+]|\d+\.)\s+", line):
            start = i
            while i < n and lines[i].strip() and not heading_level(lines[i]) and not lines[i].lstrip().startswith("|") and not re.match(r"^\s*(`{3,}|~{3,})", lines[i]):
                i += 1
            blocks.append(Block("list", start, lines[start:i]))
            continue
        start = i
        while i < n and lines[i].strip() and not heading_level(lines[i]) and not lines[i].lstrip().startswith("|") and not re.match(r"^\s*(`{3,}|~{3,}|[-*+]\s|\d+\.\s|<!--)", lines[i]):
            i += 1
        blocks.append(Block("para", start, lines[start:i]))
    return blocks


# ---------- checks ----------

def check_header(doc: Doc, blocks: list[Block], forced_type: str | None) -> None:
    first = blocks[0] if blocks else None
    if not first or first.kind != "html":
        doc.add(1, "HDR", "file must open with a <!-- Purpose: ... Type: ... --> header comment")
        doc.doc_type = forced_type
        return
    body = [l.strip() for l in first.lines[1:-1] if l.strip()]
    shape_ok = len(body) == 2 and body[0].startswith("Purpose:") and body[1].startswith("Type:")
    if not shape_ok:
        doc.add(1, "HDR", "header comment must hold exactly a Purpose: line and a Type: line")
    declared = None
    for l in body:
        if l.startswith("Type:"):
            declared = l.split(":", 1)[1].strip()
    if declared and declared not in TYPES:
        doc.add(1, "HDR", f"unknown Type '{declared}'; expected one of {', '.join(TYPES)}")
        declared = None
    doc.doc_type = forced_type or declared
    if not doc.doc_type and shape_ok:
        doc.add(1, "HDR", "Type missing; pass --type or add a Type: line")


def check_title(doc: Doc, blocks: list[Block]) -> None:
    h1s = [b for b in blocks if b.kind == "heading" and heading_level(b.lines[0]) == 1]
    if len(h1s) != 1:
        doc.add(1, "TTL", f"expected exactly one H1, found {len(h1s)}")
        return
    idx = blocks.index(h1s[0])
    following = [b for b in blocks[idx + 1:] if b.kind != "blank"]
    nxt = following[0] if following else None
    t = doc.doc_type
    if t in ("readme-project", "readme-folder"):
        if not nxt or nxt.kind != "para":
            doc.add(h1s[0].start + 1, "TTL", "a README puts its one-line description directly under the H1")
        elif t == "readme-project":
            text = " ".join(l.strip() for l in nxt.lines)
            if len(nxt.lines) > 2 or len(text) > 120:
                doc.add(nxt.start + 1, "TTL", "project one-liner must be one sentence under 120 characters")
    elif t in GUIDE_TYPES:
        if not nxt or nxt.kind != "para" or not nxt.lines[0].startswith("Audience:"):
            doc.add(h1s[0].start + 1, "TTL", "a guide puts one 'Audience:' line directly under the H1")


def h2_headings(blocks: list[Block]) -> list[Block]:
    return [b for b in blocks if b.kind == "heading" and heading_level(b.lines[0]) == 2]


def check_headings(doc: Doc, blocks: list[Block]) -> None:
    headings = [b for b in blocks if b.kind == "heading"]
    for i, b in enumerate(headings):
        title = re.sub(r"^#+\s+", "", b.lines[0]).strip()
        if not is_title_case(title):
            doc.add(b.start + 1, "HCASE", f"heading is not Title Case: '{title}'")
    for i, b in enumerate(blocks):
        if b.kind != "heading":
            continue
        rest = [x for x in blocks[i + 1:] if x.kind != "blank"]
        if not rest or (rest[0].kind == "heading" and heading_level(rest[0].lines[0]) <= heading_level(b.lines[0])):
            doc.add(b.start + 1, "EMPTY", "heading has no content before the next heading")
    h2s = h2_headings(blocks)
    if len(h2s) > H2_MAX:
        doc.add(h2s[H2_MAX].start + 1, "H2N", f"more than {H2_MAX} H2 sections; split the file")


def check_toc(doc: Doc, blocks: list[Block]) -> None:
    h2s = h2_headings(blocks)
    titles = [re.sub(r"^#+\s+", "", b.lines[0]).strip() for b in h2s]
    toc_idx = next((i for i, t in enumerate(titles) if t.lower() == "table of contents"), None)
    needs = (len(doc.lines) > TOC_LINES or len(h2s) > TOC_H2) and len(h2s) >= 3 and doc.doc_type != "adr"
    if doc.doc_type == "adr" and toc_idx is not None:
        doc.add(h2s[toc_idx].start + 1, "TOC", "an ADR never has a table of contents")
        return
    if needs and toc_idx is None:
        doc.add(1, "TOC", f"file exceeds {TOC_LINES} lines or {TOC_H2} H2 sections and needs a Table of Contents")
        return
    if not needs and toc_idx is not None:
        doc.add(h2s[toc_idx].start + 1, "TOC", "file is under the threshold; remove the Table of Contents")
        return
    if toc_idx is None:
        return
    toc_block = blocks[blocks.index(h2s[toc_idx]) + 1:]
    toc_list = next((b for b in toc_block if b.kind == "list"), None)
    if not toc_list:
        doc.add(h2s[toc_idx].start + 1, "TOC", "Table of Contents has no list")
        return
    anchors = re.findall(r"\]\(#([^)]+)\)", "\n".join(toc_list.lines))
    expected = [slugify(t) for i, t in enumerate(titles) if i != toc_idx]
    if anchors != expected:
        doc.add(toc_list.start + 1, "TOC", f"Table of Contents entries must match the H2 headings in order: expected {expected}")


def check_cap(doc: Doc) -> None:
    if doc.doc_type is None:
        widest = max(c for c in TYPES.values() if c)
        if len(doc.lines) > widest:
            doc.add(widest + 1, "CAP", f"{len(doc.lines)} lines exceeds even the widest cap ({widest}); declare a Type and split by topic")
        return
    cap = TYPES.get(doc.doc_type)
    if cap and len(doc.lines) > cap:
        doc.add(cap + 1, "CAP", f"{len(doc.lines)} lines exceeds the {cap}-line cap for type '{doc.doc_type}'; split by topic")


def check_fences(doc: Doc, blocks: list[Block]) -> None:
    for b in blocks:
        if b.kind == "fence" and not b.lang:
            doc.add(b.start + 1, "FENCE", "code fence has no language tag")


def check_density(doc: Doc, blocks: list[Block]) -> None:
    for b in blocks:
        if b.kind == "para":
            if len(b.lines) > RUN_MAX:
                doc.add(b.start + 1, "RUN", f"prose run of {len(b.lines)} lines exceeds {RUN_MAX}; break it with a list, table, or diagram")
            text = " ".join(l.strip() for l in b.lines)
            if b.lines[0].startswith("Audience:"):
                continue
            sents = sentences(text)
            if len(sents) > PARAGRAPH_MAX:
                doc.add(b.start + 1, "PARA", f"paragraph has {len(sents)} sentences; cap is {PARAGRAPH_MAX}")
            for s in sents:
                wc = word_count(s)
                if wc > SENTENCE_MAX:
                    doc.add(b.start + 1, "SENT", f"sentence of {wc} words exceeds {SENTENCE_MAX}: '{s[:60]}...'")
        elif b.kind == "table":
            for j, row in enumerate(b.lines):
                if re.match(r"^\s*\|[\s:\-|]+\|\s*$", row):
                    continue
                cells = [c.strip() for c in row.strip().strip("|").split("|")]
                for c in cells:
                    wc = word_count(c)
                    if wc > CELL_MAX:
                        doc.add(b.start + j + 1, "CELL", f"table cell of {wc} words exceeds {CELL_MAX}: '{c[:50]}...'")
        elif b.kind == "list":
            items: list[tuple[int, str, int]] = []  # (line, text, indent)
            for j, l in enumerate(b.lines):
                m = re.match(r"^(\s*)([-*+]|\d+\.)\s+(.*)", l)
                if m:
                    items.append((b.start + j, m.group(3), len(m.group(1))))
                elif items:
                    ln, txt, ind = items[-1]
                    items[-1] = (ln, txt + " " + l.strip(), ind)
            top = [it for it in items if it[2] == 0]
            if len(top) > LIST_MAX and doc.doc_type != "index":
                doc.add(top[LIST_MAX][0] + 1, "LIST", f"list has {len(top)} items; cap is {LIST_MAX}, use a table or split")
            for ln, txt, _ in items:
                wc = word_count(txt)
                if wc > BULLET_MAX:
                    doc.add(ln + 1, "BUL", f"bullet of {wc} words exceeds {BULLET_MAX}; use a sub-bullet")
                for s in sentences(txt):
                    wc = word_count(s)
                    if wc > SENTENCE_MAX:
                        doc.add(ln + 1, "SENT", f"sentence of {wc} words exceeds {SENTENCE_MAX}")


def check_words(doc: Doc, blocks: list[Block]) -> None:
    banned = [(w, re.compile(r"(?<![\w-])" + re.escape(w) + r"(?![\w-])", re.I)) for w in BANNED_WORDS]
    metas = [re.compile(p, re.I) for p in META_PHRASES]
    for b in blocks:
        if b.kind in ("fence", "html", "blank"):
            continue
        for j, raw in enumerate(b.lines):
            text = strip_inline_code(raw)
            for w, rx in banned:
                if rx.search(text):
                    doc.add(b.start + j + 1, "WORD", f"banned word '{w}'; delete it")
            for rx in metas:
                if rx.search(text):
                    doc.add(b.start + j + 1, "META", "meta-commentary about the document itself; describe the current state instead")


def check_links(doc: Doc, blocks: list[Block], root: str, heading_cache: dict[str, list[str]]) -> None:
    base = os.path.dirname(os.path.abspath(doc.path))
    for b in blocks:
        if b.kind in ("fence", "html"):
            continue
        for j, raw in enumerate(b.lines):
            line_no = b.start + j + 1
            text = strip_inline_code(raw)
            for m in re.finditer(r"(?<!!)\[([^\]]*)\]\(([^)\s]+)\)", text):
                label, target = m.group(1), m.group(2)
                if label.strip().lower() in ("here", "click here", "link", "this"):
                    doc.add(line_no, "LINK", f"link text '{label}' says nothing; name the target")
                if re.match(r"https?://", target):
                    if re.search(r"github\.com/[^/]+/[^/]+/(blob|tree)/", target):
                        doc.add(line_no, "LINK", "absolute GitHub URL into a repo; use a relative path")
                    continue
                if target.startswith("mailto:"):
                    continue
                path_part, _, anchor = target.partition("#")
                path_part = urllib.parse.unquote(path_part)
                if path_part:
                    full = os.path.normpath(os.path.join(base, path_part))
                    if not os.path.exists(full):
                        doc.add(line_no, "LINK", f"relative link does not resolve: {target}")
                        continue
                else:
                    full = os.path.abspath(doc.path)
                if anchor:
                    if os.path.isdir(full):
                        doc.add(line_no, "LINK", f"anchor on a directory link: {target}")
                        continue
                    slugs = heading_cache.get(full)
                    if slugs is None:
                        try:
                            with open(full, encoding="utf-8") as fh:
                                slugs = collect_slugs(fh.read().splitlines())
                        except OSError:
                            slugs = []
                        heading_cache[full] = slugs
                    if anchor.lower() not in slugs:
                        doc.add(line_no, "LINK", f"anchor '#{anchor}' matches no heading in {os.path.relpath(full, root)}")
            for m in re.finditer(r"(?<![(<`\[])https?://\S+", text):
                doc.add(line_no, "LINK", f"bare URL '{m.group(0)[:40]}'; give it link text")


def collect_slugs(lines: list[str]) -> list[str]:
    seen: dict[str, int] = {}
    out: list[str] = []
    in_fence = False
    for l in lines:
        if re.match(r"^\s*(`{3,}|~{3,})", l):
            in_fence = not in_fence
            continue
        if in_fence or not heading_level(l):
            continue
        s = slugify(re.sub(r"^#+\s+", "", l))
        if s in seen:
            seen[s] += 1
            s = f"{s}-{seen[s]}"
        else:
            seen[s] = 0
        out.append(s)
    return out


def check_mermaid(doc: Doc, blocks: list[Block]) -> None:
    for i, b in enumerate(blocks):
        if b.kind != "fence" or b.lang != "mermaid":
            continue
        line_no = b.start + 1
        body = [l for l in b.lines[1:-1] if l.strip() and not l.strip().startswith("%%")]
        if not body:
            doc.add(line_no, "MMD", "empty diagram")
            continue
        head = body[0].strip()
        titles: list[str] = []
        if head == "flowchart TD":
            titles = check_flowchart(doc, line_no, body[1:])
        elif head == "sequenceDiagram":
            titles = check_sequence(doc, line_no, body[1:])
        else:
            doc.add(line_no, "MMD", f"diagram must start with 'flowchart TD' or 'sequenceDiagram', found '{head}'")
            continue
        if any("click " in l for l in body):
            doc.add(line_no, "MMD", "click directives are not allowed; the Node table carries the links")
        before = [x for x in blocks[:i] if x.kind != "blank"]
        if not before or before[-1].kind != "para":
            doc.add(line_no, "MMD", "a diagram is preceded by one lead sentence")
        after = [x for x in blocks[i + 1:] if x.kind != "blank"]
        if after and after[0].kind == "list" and re.match(r"^\s*\d+\.", after[0].lines[0]):
            after = after[1:]
        if not after or after[0].kind != "table" or not re.match(r"^\|\s*Node\s*\|\s*Source\s*\|", after[0].lines[0]):
            doc.add(line_no, "MMD", "a diagram is followed by an optional numbered list and then a '| Node | Source |' table")
            continue
        rows = [r for r in after[0].lines[2:]]
        listed = [r.strip().strip("|").split("|")[0].strip() for r in rows]
        listed = [re.sub(r"`", "", x) for x in listed]
        for t in titles:
            if t not in listed:
                doc.add(after[0].start + 1, "MMD", f"node '{t}' is missing from the Node table")


NODE_RX = re.compile(r'(\w+)\s*(\[\(|\[/|\[|\(\(|\(|\{)\s*"([^"]*)"')
NODE_DEF_RX = re.compile(r'(\w+)\s*(?:\[\(|\[/|\[|\(\(|\(|\{)\s*"[^"]*"\s*(?:\)\]|/\]|\]|\)\)|\)|\})')
ARROW = r'(?:(?:-->|==>|-\.->|---)\s*(?:\|\s*"([^"]*)"\s*\|)?|-\.\s*"([^"]*)"\s*\.->|--\s*"([^"]*)"\s*-->|==\s*"([^"]*)"\s*==>)'
EDGE_RX = re.compile(r'(\w+)\s*' + ARROW + r'\s*(?=(\w+))')


def check_flowchart(doc: Doc, line_no: int, body: list[str]) -> list[str]:
    nodes: dict[str, str] = {}
    edges: list[tuple[str, str]] = []
    for l in body:
        s = l.strip()
        if s.startswith("subgraph"):
            if not re.match(r'^subgraph\s+\w+\["[^"]+"\]', s):
                doc.add(line_no, "MMD", f"subgraph needs an id and a quoted label: '{s}'")
            continue
        if s in ("end",) or s.startswith("direction"):
            if s.startswith("direction"):
                doc.add(line_no, "MMD", "direction overrides are not allowed; the diagram is TD")
            continue
        for m in NODE_RX.finditer(s):
            ident, label = m.group(1), m.group(3)
            lm = re.match(r"^(.+)<br/>\[([A-Z, ]+)\]$", label)
            if not lm:
                doc.add(line_no, "MMD", f"node label must be 'Title<br/>[TYPE]': '{label}'")
                nodes[ident] = label
                continue
            title, typ = lm.group(1).strip(), lm.group(2).strip()
            if typ not in MERMAID_TYPES:
                doc.add(line_no, "MMD", f"unknown TYPE '{typ}' in node '{title}'")
            if re.match(r"^\d+[a-z]?\.\s", title):
                doc.add(line_no, "MMD", f"node title carries a number: '{title}'; numbers belong on edges")
            if len(title.split()) > 4:
                doc.add(line_no, "MMD", f"node title longer than three or four words: '{title}'")
            nodes[ident] = title
        stripped = NODE_DEF_RX.sub(r"\1", s)
        for em in EDGE_RX.finditer(stripped):
            src, dst = em.group(1), em.group(6)
            label = next((g for g in em.groups()[1:5] if g is not None), None)
            edges.append((src, dst))
            if label is None:
                doc.add(line_no, "MMD", f"edge {src} -> {dst} has no label")
            else:
                words = re.sub(r"^\d+\.\s*", "", label).split()
                if len(words) > 4:
                    doc.add(line_no, "MMD", f"edge label longer than four words: '{label}'")
    count = len(nodes)
    if count < 4:
        doc.add(line_no, "MMD", f"only {count} nodes; write a sentence instead of a diagram")
    if count > 12:
        doc.add(line_no, "MMD", f"{count} nodes exceeds the cap of 12; split the diagram")
    if nodes and edges:
        adj: dict[str, set[str]] = {n: set() for n in nodes}
        for a, c in edges:
            adj.setdefault(a, set()).add(c)
            adj.setdefault(c, set()).add(a)
        seen: set[str] = set()
        stack = [next(iter(nodes))]
        while stack:
            n = stack.pop()
            if n in seen:
                continue
            seen.add(n)
            stack.extend(adj.get(n, ()))
        if not set(nodes) <= seen:
            doc.add(line_no, "MMD", "diagram holds more than one disconnected graph; split it")
    return list(nodes.values())


def check_sequence(doc: Doc, line_no: int, body: list[str]) -> list[str]:
    titles: list[str] = []
    messages = 0
    for l in body:
        s = l.strip()
        pm = re.match(r"^(actor|participant)\s+(\w+)(?:\s+as\s+(.+))?$", s)
        if pm:
            kw, ident, label = pm.groups()
            label = label or ident
            lm = re.match(r"^(.+)<br/>\[([A-Z, ]+)\]$", label)
            if not lm:
                doc.add(line_no, "MMD", f"participant label must be 'Title<br/>[TYPE]': '{label}'")
                titles.append(label)
                continue
            title, typ = lm.group(1).strip(), lm.group(2).strip()
            if typ not in MERMAID_TYPES:
                doc.add(line_no, "MMD", f"unknown TYPE '{typ}' in participant '{title}'")
            if re.match(r"^\d+\.\s", title):
                doc.add(line_no, "MMD", f"participant carries an ordinal prefix: '{title}'; number messages, not participants")
            if (typ == "PERSON") != (kw == "actor"):
                doc.add(line_no, "MMD", f"'{title}': PERSON uses 'actor', every other TYPE uses 'participant'")
            titles.append(title)
            continue
        mm = re.match(r"^\w+\s*(-{1,2}>>?|-{1,2}x|-{1,2}\))\s*\w+\s*:\s*(.*)$", s)
        if mm:
            messages += 1
            if not re.match(r"^\d+\.\s", mm.group(2)):
                doc.add(line_no, "MMD", f"sequence message is not numbered: '{mm.group(2)[:40]}'")
    if len(titles) > 7:
        doc.add(line_no, "MMD", f"{len(titles)} participants exceeds the cap of 7; split the flow")
    if messages > 12:
        doc.add(line_no, "MMD", f"{messages} messages exceeds the cap of 12; split the flow by phase")
    return titles


STOPWORDS = set("""a an the and or but of to in on at by for with from as is are be was were
it its this that these those there here not any all each every than then so
into over under without within between must may can will should also only when where
which who whose what how""".split())
NEAR_MIN_WORDS = 8
NEAR_THRESHOLD = 0.4


def stem(word: str) -> str:
    for suffix in ("ing", "ed", "es", "s"):
        if word.endswith(suffix) and len(word) - len(suffix) >= 3:
            return word[: -len(suffix)]
    return word


def content_words(sentence: str) -> frozenset[str]:
    words = re.findall(r"[a-z0-9']+", link_text_only(strip_inline_code(sentence)).lower())
    return frozenset(stem(w) for w in words if w not in STOPWORDS and len(w) > 2)


def collect_sentences(doc: Doc, blocks: list[Block]) -> list[tuple[int, str, frozenset[str]]]:
    out: list[tuple[int, str, frozenset[str]]] = []
    for b in blocks:
        if b.kind == "para":
            units = [" ".join(l.strip() for l in b.lines)]
        elif b.kind == "list":
            units = []
            for l in b.lines:
                m = re.match(r"^\s*([-*+]|\d+\.)\s+(.*)", l)
                if m:
                    units.append(m.group(2))
                elif units:
                    units[-1] += " " + l.strip()
        else:
            continue
        for text in units:
            if text.startswith("Audience:"):
                continue
            for sent in sentences(text):
                words = content_words(sent)
                if len(words) >= NEAR_MIN_WORDS:
                    out.append((b.start + 1, sent, words))
    return out


def check_near_duplicates(docs: list[Doc], sentence_sets: dict[str, list[tuple[int, str, frozenset[str]]]]) -> None:
    reported: set[tuple[str, int, str]] = set()
    for i, a in enumerate(docs):
        for b in docs[i + 1:]:
            for la, sa, wa in sentence_sets[a.path]:
                for lb, sb, wb in sentence_sets[b.path]:
                    inter = len(wa & wb)
                    union = len(wa | wb)
                    if union and inter / union >= NEAR_THRESHOLD:
                        key = (b.path, lb, a.path)
                        if key in reported:
                            continue
                        reported.add(key)
                        b.add(lb, "DUP", f"sentence restates {a.path}:{la} ('{sa[:50]}...'); one fact, one home")


def collect_shingles(doc: Doc, blocks: list[Block]) -> None:
    for b in blocks:
        if b.kind not in ("para", "list"):
            continue
        for j, raw in enumerate(b.lines):
            text = raw.strip()
            if b.kind == "list":
                text = re.sub(r"^\s*([-*+]|\d+\.)\s+", "", text)
            if text.startswith("Audience:"):
                continue
            text = link_text_only(strip_inline_code(text))
            words = re.findall(r"[a-z0-9']+", text.lower())
            for k in range(0, len(words) - DUP_WINDOW + 1):
                doc.prose_shingles.setdefault(" ".join(words[k:k + DUP_WINDOW]), b.start + j + 1)


def check_duplicates(docs: list[Doc]) -> None:
    owner: dict[str, tuple[Doc, int]] = {}
    reported: set[tuple[str, str]] = set()
    for d in docs:
        for sh, ln in d.prose_shingles.items():
            if sh in owner and owner[sh][0] is not d:
                pair = (owner[sh][0].path, d.path)
                if pair in reported:
                    continue
                reported.add(pair)
                d.add(ln, "DUP", f"12-word run also appears in {owner[sh][0].path}:{owner[sh][1]}; one fact, one home")
            else:
                owner.setdefault(sh, (d, ln))


def guess_type(path: str, root: str) -> str | None:
    p = os.path.abspath(path)
    rel = os.path.relpath(p, root).replace(os.sep, "/")
    name = os.path.basename(p)
    parent = os.path.basename(os.path.dirname(p))
    if re.match(r"^\d{4}-.*\.md$", name) and parent in ("adrs", "adr", "decisions"):
        return "adr"
    if name.lower() == "readme.md":
        if parent == "docs":
            return "index"
        d = os.path.dirname(p)
        markers = ("package.json", "pyproject.toml", "run.sh", ".git", "Cargo.toml", "go.mod")
        if any(os.path.exists(os.path.join(d, m)) for m in markers) or rel == "README.md":
            return "readme-project"
        return "readme-folder"
    if parent == "docs":
        if name == "glossary.md":
            return "glossary"
        if name.startswith("requirements"):
            return "requirements"
    return None


SENTENCE_SETS: dict[str, list[tuple[int, str, frozenset[str]]]] = {}


def lint_file(path: str, root: str, forced: str | None, heading_cache: dict[str, list[str]]) -> Doc:
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    doc = Doc(path, lines)
    blocks = segment(lines)
    check_header(doc, blocks, forced)
    if doc.doc_type is None:
        doc.doc_type = guess_type(path, root)
    check_title(doc, blocks)
    check_headings(doc, blocks)
    check_toc(doc, blocks)
    check_cap(doc)
    check_fences(doc, blocks)
    check_density(doc, blocks)
    check_words(doc, blocks)
    check_links(doc, blocks, root, heading_cache)
    check_mermaid(doc, blocks)
    collect_shingles(doc, blocks)
    SENTENCE_SETS[path] = collect_sentences(doc, blocks)
    return doc


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Lint Markdown docs against the writing-docs house style.")
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--type", choices=sorted(TYPES), help="force the document type instead of reading the header")
    ap.add_argument("--root", default=os.getcwd(), help="repo root used to guess types and report paths")
    ap.add_argument("--no-dup", action="store_true", help="skip the cross-file duplicate check")
    args = ap.parse_args(argv)
    root = os.path.abspath(args.root)
    docs: list[Doc] = []
    cache: dict[str, list[str]] = {}
    for p in args.paths:
        if not os.path.isfile(p):
            print(f"{p}:0: FILE not found", file=sys.stderr)
            return 2
        docs.append(lint_file(p, root, args.type, cache))
    if len(docs) > 1 and not args.no_dup:
        check_duplicates(docs)
        check_near_duplicates(docs, SENTENCE_SETS)
    total = 0
    for d in docs:
        for f in sorted(d.findings, key=lambda x: (x.line, x.code)):
            print(f)
            total += 1
    print(f"{total} finding(s) in {len(docs)} file(s)")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
