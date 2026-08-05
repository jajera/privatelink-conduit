# Diagrams

Published diagrams are **theme-aware SVG** includes under `_includes/diagrams/`.
They use CSS classes (`.diagram-node`, `.diagram-text`, …) so light/dark mode
updates without a page reload.

## Regenerate

```bash
python3 docs/scripts/generate-diagrams.py
```

## Edit in draw.io

1. Open [diagrams.net](https://app.diagrams.net/)
2. **File → Import from → Device** and choose an SVG from `_includes/diagrams/`
3. Save the editable source as `docs/diagrams/<name>.drawio` if you want a checked-in draw.io file
4. Prefer updating `docs/scripts/generate-diagrams.py` and regenerating when the layout is simple — keeps light/dark CSS classes intact

## Files

| Include | Used on |
|---------|---------|
| `topology.svg` | Architecture |
| `provider-tiers.svg` | Architecture |
| `request-path.svg` | How PrivateLink works |
| `sg-chain.svg` | How PrivateLink works |
| `cross-region-flow.svg` | Cross-Region |
| `debug-order.svg` | Troubleshooting |
| `landing-workaround.svg` | Alternatives and limits |
