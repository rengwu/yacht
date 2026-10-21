# Provider marks

The four SVGs are from `@lobehub/icons-static-svg` 1.95.1:
https://cdn.jsdelivr.net/npm/@lobehub/icons-static-svg@1.95.1/icons/

The bundled license is `Sources/Yacht/Resources/Lobe-LICENSE.txt`, from
https://github.com/lobehub/lobe-icons/blob/master/LICENSE.
Provider logos remain their owners' trademarks.

The app loads the checked-in PDF vectors as native template images. No network,
SVG parser, package manager, or conversion tool is needed at build time or runtime.
To regenerate after intentionally changing a source:

```sh
for provider in claude codex kimi grok; do
  rsvg-convert -f pdf -o "Sources/Yacht/Resources/$provider.pdf" \
    "Resources/ProviderMarks/$provider.svg"
done
```
