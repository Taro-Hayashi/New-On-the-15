#!/usr/bin/env python3
"""Generate a led-positions property from a KiCad board.

The lighting module measures distance between LEDs, so it needs their real
positions in the same units and origin as the shield's zmk,physical-layout:
100 per key unit, x to the right and y down from the layout's top left corner.

Order follows the SK6812 data chain read from the netlist rather than the
reference designators. The two disagree on boards whose rows are wired
alternately right to left, which is what the x15 does.

Anchoring: one switch whose layout position is known ties the two coordinate
spaces together. Take the key's entry from the shield's -layouts.dtsi and pass
its centre - for a 1u key at <100 100 125 25>, that is 175 75.

    tools/gen_led_positions.py \\
        --pcb kicad-private/x15_panelize/x15_2.kicad_pcb \\
        --net kicad-private/x15_panelize/x15_2.net \\
        --anchor SW1 --anchor-centre 175 75
"""

import argparse
import re
import sys

FOOTPRINT = "(footprint "
LED_REF = re.compile(r"LED\d+")


def sexpr_blocks(text, opener):
    """Yield each balanced s-expression that starts with opener."""
    for match in re.finditer(re.escape(opener), text):
        start, depth, i = match.start(), 0, match.start()
        while True:
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        yield text[start:i + 1]


def placements(pcb_path):
    """Map every footprint's reference designator to its (x, y) in mm."""
    found = {}
    with open(pcb_path, errors="ignore") as handle:
        text = handle.read()
    for block in sexpr_blocks(text, FOOTPRINT):
        ref = re.search(r'\(property "Reference" "([^"]+)"', block)
        at = re.search(r"\(at ([-\d.]+) ([-\d.]+)", block)
        if ref and at:
            found[ref.group(1)] = (float(at.group(1)), float(at.group(2)))
    return found


def chain(net_path):
    """Return the LED references in data-chain order, following DOUT to DIN."""
    with open(net_path, errors="ignore") as handle:
        text = handle.read()

    links = {}
    for _, body in re.findall(
            r'\(net\s+\(code "\d+"\)\s+\(name "([^"]+)"\)(.*?)\n\t\t\)', text, re.S):
        pads = re.findall(
            r'\(node\s+\(ref "([^"]+)"\)\s+\(pin "[^"]+"\)\s+\(pinfunction "([^"]*)"\)',
            body)
        leds = [(ref, function.upper()) for ref, function in pads
                if LED_REF.fullmatch(ref)]
        if len(leds) != 2:
            continue
        source = [led for led in leds if "OUT" in led[1]]
        sink = [led for led in leds if "IN" in led[1] and "OUT" not in led[1]]
        if source and sink:
            links[source[0][0]] = sink[0][0]

    heads = [ref for ref in links if ref not in set(links.values())]
    if len(heads) != 1:
        raise SystemExit(f"expected one chain head, found {sorted(heads)}")

    order = heads
    while order[-1] in links:
        order.append(links[order[-1]])
    return order


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pcb", required=True)
    parser.add_argument("--net", required=True)
    parser.add_argument("--anchor", required=True,
                        help="reference of a switch whose layout centre is known")
    parser.add_argument("--anchor-centre", required=True, nargs=2, type=int,
                        metavar=("X", "Y"),
                        help="that switch's centre in layout units")
    parser.add_argument("--pitch", type=float, default=19.0,
                        help="key pitch in mm, one key unit (default: 19.0)")
    parser.add_argument("--per-line", type=int, default=5,
                        help="LEDs per output line (default: 5)")
    args = parser.parse_args()

    found = placements(args.pcb)
    if args.anchor not in found:
        raise SystemExit(f"{args.anchor} is not on this board")

    anchor_x, anchor_y = found[args.anchor]
    layout_x, layout_y = args.anchor_centre
    scale = 100.0 / args.pitch

    order = chain(args.net)
    missing = [ref for ref in order if ref not in found]
    if missing:
        raise SystemExit(f"no placement for {', '.join(missing)}")

    points = [(round((found[ref][0] - anchor_x) * scale + layout_x),
               round((found[ref][1] - anchor_y) * scale + layout_y))
              for ref in order]

    print(f"    /* {len(points)} LEDs in data-chain order: {order[0]} first. */")
    print("    led-positions = <")
    for start in range(0, len(points), args.per_line):
        row = points[start:start + args.per_line]
        refs = " ".join(order[start:start + args.per_line])
        print("        " + " ".join(f"{x:5d} {y:4d}" for x, y in row) + f"   /* {refs} */")
    print("    >;")


if __name__ == "__main__":
    sys.exit(main())
