#!/usr/bin/env python3
"""Render the Markdown productivity reference as a compact four-page PDF."""

from __future__ import annotations

import argparse
import datetime as dt
import re
from dataclasses import dataclass, field
from pathlib import Path

from reportlab.lib.colors import Color, HexColor
from reportlab.lib.pagesizes import letter
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfgen.canvas import Canvas


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "docs" / "productivity-cheatsheet.md"
DEFAULT_OUTPUT = ROOT / "output" / "pdf" / "strix-productivity-cheatsheet.pdf"

INK = HexColor("#14213D")
PAPER = HexColor("#F5F7FA")
CARD = HexColor("#FFFFFF")
MUTED = HexColor("#607089")
LINE = HexColor("#DDE4EC")
TEAL = HexColor("#0B8F87")
AMBER = HexColor("#E0922E")
VIOLET = HexColor("#7758B3")
CORAL = HexColor("#D75A4A")
BLUE = HexColor("#3478C5")

STATUS_COLORS = {
    "READY": TEAL,
    "FIRST RUN": AMBER,
    "OPTIONAL": VIOLET,
    "SAFETY": CORAL,
}


@dataclass
class Item:
    key: str
    text: str


@dataclass
class Card:
    title: str
    status: str
    column: int
    items: list[Item] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


@dataclass
class Page:
    title: str
    subtitle: str = ""
    cards: list[Card] = field(default_factory=list)


def parse_source(path: Path) -> list[Page]:
    pages: list[Page] = []
    page: Page | None = None
    card: Card | None = None
    column = 0
    item_re = re.compile(r"^- \*\*(.+?)\*\* - (.+)$")

    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line:
            continue
        if line == "<!-- column -->":
            column = 1
            card = None
        elif line.startswith("# "):
            page = Page(line[2:].strip())
            pages.append(page)
            card = None
            column = 0
        elif line.startswith("> "):
            if page is None:
                raise ValueError("subtitle before page title")
            page.subtitle = line[2:].strip().replace("`", "")
        elif line.startswith("## "):
            if page is None:
                raise ValueError("card before page title")
            heading = line[3:].strip()
            title, separator, status = heading.rpartition(" | ")
            if not separator or status not in STATUS_COLORS:
                raise ValueError(f"card heading needs a known status: {line}")
            card = Card(title=title.replace("`", ""), status=status, column=column)
            page.cards.append(card)
        elif line.startswith("- "):
            if card is None:
                raise ValueError(f"item outside card: {line}")
            match = item_re.match(line)
            if not match:
                raise ValueError(f"item must use '- **key** - text': {line}")
            card.items.append(Item(match.group(1).replace("`", ""), match.group(2).replace("`", "")))
        else:
            if card is None:
                raise ValueError(f"note outside card: {line}")
            card.notes.append(line.replace("`", ""))

    if len(pages) != 4:
        raise ValueError(f"expected exactly four pages, found {len(pages)}")
    for page_number, parsed_page in enumerate(pages, 1):
        columns = {card.column for card in parsed_page.cards}
        if columns != {0, 1}:
            raise ValueError(f"page {page_number} must have cards in both columns")
    return pages


def wrap(text: str, font: str, size: float, width: float) -> list[str]:
    words = text.split()
    if not words:
        return [""]
    lines: list[str] = []
    current = words[0]
    for word in words[1:]:
        candidate = f"{current} {word}"
        if stringWidth(candidate, font, size) <= width:
            current = candidate
        else:
            lines.append(current)
            current = word
    lines.append(current)
    return lines


def card_height(card: Card, width: float) -> float:
    body_width = width - 24
    height = 35
    for item in card.items:
        key_width = min(stringWidth(item.key, "Helvetica-Bold", 7.3) + 14, body_width * 0.46)
        text_width = body_width - key_width - 8
        lines = wrap(item.text, "Helvetica", 7.45, text_width)
        height += max(18, len(lines) * 9.2 + 5)
    for note in card.notes:
        height += len(wrap(note, "Helvetica-Oblique", 7.2, body_width)) * 9 + 7
    return height + 6


def rounded_badge(canvas: Canvas, x: float, y: float, text: str, color: Color) -> None:
    width = stringWidth(text, "Helvetica-Bold", 6.3) + 13
    canvas.setFillColor(color)
    canvas.roundRect(x, y - 1, width, 13, 6.5, fill=1, stroke=0)
    canvas.setFillColor(CARD)
    canvas.setFont("Helvetica-Bold", 6.3)
    canvas.drawCentredString(x + width / 2, y + 3.1, text)


def draw_card(canvas: Canvas, card: Card, x: float, top: float, width: float) -> float:
    height = card_height(card, width)
    bottom = top - height
    color = STATUS_COLORS[card.status]
    canvas.setFillColor(Color(0, 0, 0, alpha=0.07))
    canvas.roundRect(x + 1.5, bottom - 1.5, width, height, 10, fill=1, stroke=0)
    canvas.setFillColor(CARD)
    canvas.setStrokeColor(LINE)
    canvas.setLineWidth(0.6)
    canvas.roundRect(x, bottom, width, height, 10, fill=1, stroke=1)
    canvas.setFillColor(color)
    canvas.roundRect(x, bottom, 4.5, height, 2.25, fill=1, stroke=0)

    title_y = top - 22
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica-Bold", 10.1)
    canvas.drawString(x + 13, title_y, card.title)
    badge_width = stringWidth(card.status, "Helvetica-Bold", 6.3) + 13
    rounded_badge(canvas, x + width - badge_width - 10, title_y - 2, card.status, color)

    cursor = top - 42
    body_width = width - 24
    for item in card.items:
        key_width = min(stringWidth(item.key, "Helvetica-Bold", 7.3) + 14, body_width * 0.46)
        text_x = x + 13 + key_width + 8
        text_width = body_width - key_width - 8
        lines = wrap(item.text, "Helvetica", 7.45, text_width)
        row_height = max(18, len(lines) * 9.2 + 5)

        canvas.setFillColor(Color(color.red, color.green, color.blue, alpha=0.11))
        canvas.roundRect(x + 13, cursor - 1, key_width, 13.5, 6, fill=1, stroke=0)
        canvas.setFillColor(color)
        canvas.setFont("Helvetica-Bold", 7.3)
        label = item.key
        while stringWidth(label, "Helvetica-Bold", 7.3) > key_width - 9 and len(label) > 4:
            label = label[:-2] + "."
        canvas.drawString(x + 19, cursor + 3, label)

        canvas.setFillColor(INK)
        canvas.setFont("Helvetica", 7.45)
        for index, text_line in enumerate(lines):
            canvas.drawString(text_x, cursor + 4 - index * 9.2, text_line)
        cursor -= row_height

    for note in card.notes:
        canvas.setStrokeColor(LINE)
        canvas.line(x + 13, cursor + 7, x + width - 13, cursor + 7)
        cursor -= 3
        canvas.setFillColor(MUTED)
        canvas.setFont("Helvetica-Oblique", 7.2)
        for text_line in wrap(note, "Helvetica-Oblique", 7.2, body_width):
            canvas.drawString(x + 13, cursor, text_line)
            cursor -= 9
        cursor -= 4
    return bottom


def render(pages: list[Page], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas = Canvas(str(output), pagesize=letter)
    canvas.setTitle("Strix Linux Productivity Cheat Sheet")
    canvas.setAuthor("linux-setup")
    page_width, page_height = letter
    margin = 36
    gap = 14
    column_width = (page_width - 2 * margin - gap) / 2
    accents = [BLUE, VIOLET, TEAL, CORAL]
    build_date = dt.date.today().isoformat()

    for page_index, page in enumerate(pages, 1):
        accent = accents[page_index - 1]
        canvas.setFillColor(PAPER)
        canvas.rect(0, 0, page_width, page_height, fill=1, stroke=0)
        canvas.setFillColor(INK)
        canvas.rect(0, page_height - 96, page_width, 96, fill=1, stroke=0)
        canvas.setFillColor(accent)
        canvas.rect(0, page_height - 96, 9, 96, fill=1, stroke=0)

        canvas.setFillColor(CARD)
        canvas.setFont("Helvetica-Bold", 22)
        canvas.drawString(margin, page_height - 48, page.title)
        canvas.setFillColor(HexColor("#C8D4E6"))
        canvas.setFont("Helvetica", 9)
        canvas.drawString(margin, page_height - 68, page.subtitle)
        canvas.setFont("Helvetica-Bold", 7)
        canvas.drawRightString(page_width - margin, page_height - 28, "LINUX-SETUP / STRIX")

        top = page_height - 112
        bottoms = [top, top]
        for card in page.cards:
            x = margin + card.column * (column_width + gap)
            bottoms[card.column] = draw_card(canvas, card, x, bottoms[card.column], column_width) - 10

        safe_bottom = 37
        if min(bottoms) < safe_bottom:
            raise ValueError(f"page {page_index} content overflows by {safe_bottom - min(bottoms):.1f} points")

        canvas.setStrokeColor(LINE)
        canvas.line(margin, 29, page_width - margin, 29)
        canvas.setFillColor(MUTED)
        canvas.setFont("Helvetica", 6.8)
        canvas.drawString(margin, 17, f"READY / FIRST RUN / OPTIONAL / SAFETY    source: linux-setup    edition {build_date}")
        canvas.setFillColor(accent)
        canvas.circle(page_width - margin - 8, 17.5, 9, fill=1, stroke=0)
        canvas.setFillColor(CARD)
        canvas.setFont("Helvetica-Bold", 7.2)
        canvas.drawCentredString(page_width - margin - 8, 15, str(page_index))
        canvas.showPage()

    canvas.save()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    render(parse_source(args.source), args.output)
    print(args.output)


if __name__ == "__main__":
    main()
