#!/usr/bin/env python3
"""Generate theme-aware SVG diagram includes for the docs site."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "_includes" / "diagrams"
OUT.mkdir(parents=True, exist_ok=True)


def svg(width, height, body, title):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="100%" role="img" aria-label="{title}">
  <title>{title}</title>
  <defs>
    <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M 0 0 L 10 5 L 0 10 z" class="diagram-arrow-head"/>
    </marker>
  </defs>
{body}
</svg>
'''


def box(x, y, w, h, lines, kind="node"):
    """kind: node | cluster | accent"""
    cls = {"node": "diagram-node", "cluster": "diagram-cluster", "accent": "diagram-accent"}[kind]
    text_cls = "diagram-text"
    rx = 10 if kind != "cluster" else 12
    parts = [f'  <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" class="{cls}"/>']
    if kind == "cluster":
        # Title only — room for nested content below
        parts.append(
            f'  <text x="{x + 14}" y="{y + 22}" class="diagram-label" font-weight="600" font-size="12">{lines[0]}</text>'
        )
        return "\n".join(parts)

    n = len(lines)
    line_h = 15
    block_h = n * line_h
    # Center block; use dominant-baseline so glyphs aren't clipped by the rect
    first_y = y + (h - block_h) / 2 + line_h / 2
    for i, line in enumerate(lines):
        weight = ' font-weight="600"' if i == 0 else ""
        size = 12 if i == 0 else 11
        parts.append(
            f'  <text x="{x + w/2}" y="{first_y + i * line_h}" text-anchor="middle" '
            f'dominant-baseline="middle" class="{text_cls}"{weight} font-size="{size}">{line}</text>'
        )
    return "\n".join(parts)


def arrow(x1, y1, x2, y2, label=None, dashed=False):
    dash = ' stroke-dasharray="5 4"' if dashed else ""
    parts = [
        f'  <line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" class="diagram-line"{dash} marker-end="url(#arrow)"/>'
    ]
    if label:
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        tw = max(72, len(label) * 6.5)
        parts.append(
            f'  <rect x="{mx - tw/2}" y="{my - 11}" width="{tw}" height="20" rx="4" class="diagram-edge-bg"/>'
        )
        parts.append(
            f'  <text x="{mx}" y="{my}" text-anchor="middle" dominant-baseline="middle" '
            f'class="diagram-edge-text" font-size="11">{label}</text>'
        )
    return "\n".join(parts)


# ── 1. Topology ──────────────────────────────────────────────────────────────
topology = []
# Sydney consumer
topology.append(box(20, 16, 360, 118, ["Sydney consumer · ap-southeast-2"], "cluster"))
topology.append(box(40, 48, 110, 64, ["Test EC2"], "node"))
topology.append(box(175, 42, 185, 76, ["VPCE", "config.conduit.internal"], "accent"))
topology.append(arrow(150, 80, 175, 80))

# Melbourne consumer
topology.append(box(20, 154, 360, 130, ["Melbourne consumer · ap-southeast-4"], "cluster"))
topology.append(box(40, 192, 110, 64, ["Test EC2"], "node"))
topology.append(
        box(175, 180, 185, 88, ["VPCE", "config-xr.conduit.internal", "service_region → apse2"], "accent")
    )
topology.append(arrow(150, 224, 175, 224))

# Provider
topology.append(box(420, 70, 440, 180, ["shared-services · Sydney · 10.50.0.0/16"], "cluster"))
topology.append(box(440, 118, 100, 72, ["Endpoint", "service"], "accent"))
topology.append(box(565, 124, 80, 60, ["NLB"], "node"))
topology.append(box(670, 124, 90, 60, ["App EC2"], "node"))
topology.append(box(785, 124, 55, 60, ["RDS"], "node"))
topology.append(arrow(540, 154, 565, 154))
topology.append(arrow(645, 154, 670, 154))
topology.append(arrow(760, 154, 785, 154))

topology.append(arrow(360, 80, 440, 140, "same-Region"))
topology.append(arrow(360, 224, 440, 180, "cross-Region"))

(OUT / "topology.svg").write_text(svg(900, 310, "\n".join(topology), "Lab topology: two consumers to one Sydney provider"))


# ── 2. Provider tiers ────────────────────────────────────────────────────────
tiers = []
tiers.append(box(240, 20, 140, 56, ["Endpoint service"], "accent"))
tiers.append(box(250, 110, 120, 56, ["Internal NLB"], "node"))
tiers.append(box(250, 200, 120, 56, ["App EC2"], "node"))
tiers.append(box(250, 290, 120, 56, ["RDS Postgres"], "node"))
tiers.append(box(40, 200, 120, 56, ["S3 gateway"], "node"))
tiers.append(box(460, 200, 140, 56, ["SSM endpoints"], "node"))
tiers.append(arrow(310, 76, 310, 110))
tiers.append(arrow(310, 166, 310, 200))
tiers.append(arrow(310, 256, 310, 290, "5432"))
tiers.append(arrow(250, 228, 160, 228, dashed=True))
tiers.append(arrow(370, 228, 460, 228, dashed=True))
(OUT / "provider-tiers.svg").write_text(svg(640, 370, "\n".join(tiers), "Provider tiers: endpoint service to NLB to app to RDS"))

# ── 3. Request path (sequence-style) ─────────────────────────────────────────
seq = []
actors = [
    (40, "Client"),
    (160, "VPCE ENI"),
    (280, "EP service"),
    (400, "NLB"),
    (520, "App"),
]
for x, label in actors:
    seq.append(box(x, 20, 100, 44, [label], "node"))
    seq.append(f'  <line x1="{x+50}" y1="64" x2="{x+50}" y2="260" class="diagram-line" stroke-dasharray="3 4"/>')

# messages as horizontal arrows with step numbers
msgs = [
    (90, 90, 210, 90, "1 · TCP :80"),
    (210, 120, 330, 120, "2 · PrivateLink"),
    (330, 150, 450, 150, "3 · forward"),
    (450, 180, 570, 180, "4 · target"),
    (570, 210, 450, 210, "5 · response"),
    (450, 240, 90, 240, "6 · response"),
]
for x1, y1, x2, y2, label in msgs:
    seq.append(arrow(x1, y1, x2, y2, label))
seq.append(
    '  <text x="320" y="290" text-anchor="middle" class="diagram-muted" font-size="12">Provider has no route into the consumer VPC</text>'
)
(OUT / "request-path.svg").write_text(svg(640, 310, "\n".join(seq), "PrivateLink request path from consumer to provider workload"))

# ── 4. SG chain ──────────────────────────────────────────────────────────────
sg = []
sg.append(box(20, 40, 120, 60, ["Test EC2"], "node"))
sg.append(box(180, 40, 140, 60, ["Endpoint SG", ":80"], "accent"))
sg.append(box(360, 40, 140, 60, ["App SG", ":80"], "node"))
sg.append(box(540, 40, 120, 60, ["DB SG", ":5432"], "node"))
sg.append(arrow(140, 70, 180, 70))
sg.append(arrow(320, 70, 360, 70, "PrivateLink"))
sg.append(arrow(500, 70, 540, 70))
(OUT / "sg-chain.svg").write_text(svg(680, 140, "\n".join(sg), "Security group chain across PrivateLink"))

# ── 5. Cross-region flow ─────────────────────────────────────────────────────
xr = []
xr.append(box(200, 20, 200, 50, ["Create endpoint service"], "node"))
xr.append(box(200, 100, 200, 50, ["List supported_regions"], "node"))
xr.append(box(200, 180, 200, 56, ["Consumer Region OK?"], "accent"))
xr.append(box(20, 280, 160, 56, ["NZ → API rejects"], "node"))
xr.append(box(220, 280, 200, 56, ["Melbourne → create", "endpoint + service_region"], "node"))
xr.append(box(220, 370, 200, 50, ["Traffic on AWS backbone"], "accent"))
xr.append(arrow(300, 70, 300, 100))
xr.append(arrow(300, 150, 300, 180))
xr.append(arrow(240, 236, 140, 280, "no"))
xr.append(arrow(300, 236, 300, 280, "yes"))
xr.append(arrow(320, 336, 320, 370))
(OUT / "cross-region-flow.svg").write_text(svg(480, 440, "\n".join(xr), "Cross-Region PrivateLink decision flow"))

# ── 6. Debug order ───────────────────────────────────────────────────────────
dbg = []
steps = [
    (40, "1. Target group healthy?"),
    (120, "2. Endpoint available?"),
    (200, "3. DNS → sandbox IP?"),
    (280, "4. TCP connects?"),
    (360, "5. App responds?"),
]
fixes = [
    (40, "Fix app tier first"),
    (120, "Principals / acceptance"),
    (200, "Zone or alias record"),
    (280, "Endpoint SG ingress"),
    (360, "preserve_client_ip / app SG"),
]
for i, ((y, label), (_, fix)) in enumerate(zip(steps, fixes)):
    dbg.append(box(40, y, 240, 48, [label], "accent" if i == 0 else "node"))
    dbg.append(box(360, y, 220, 48, [fix], "node"))
    dbg.append(arrow(280, y + 24, 360, y + 24, "no"))
    if i < len(steps) - 1:
        dbg.append(arrow(160, y + 48, 160, steps[i + 1][0], "yes"))
(OUT / "debug-order.svg").write_text(svg(600, 430, "\n".join(dbg), "Troubleshooting order for PrivateLink failures"))

# ── 7. Landing workaround ────────────────────────────────────────────────────
land = []
land.append(box(20, 40, 160, 100, ["Consumer · eligible Region"], "cluster"))
land.append(box(40, 70, 120, 50, ["Client → VPCE"], "node"))
land.append(box(220, 40, 200, 100, ["Landing VPC · eligible Region"], "cluster"))
land.append(box(240, 65, 160, 60, ["EP svc → NLB", "→ proxy"], "accent"))
land.append(box(460, 40, 180, 100, ["Workload · ineligible Region"], "cluster"))
land.append(box(480, 70, 140, 50, ["NLB → app"], "node"))
land.append(arrow(160, 95, 240, 95, "same-Region PL"))
land.append(arrow(400, 95, 480, 95, "internal hop"))
(OUT / "landing-workaround.svg").write_text(
    svg(660, 160, "\n".join(land), "Excluded workaround: landing VPC plus internal Region hop")
)

print("Wrote", len(list(OUT.glob("*.svg"))), "SVGs to", OUT)
