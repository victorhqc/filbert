# Provider glyphs

This directory contains the vector inputs for the provider glyphs described by
(ui 14 AC2). The generated PNGs are committed to each provider's `Resources`
directory so the app only needs to load them at runtime.

Run the generator from the repository root:

```sh
swift scripts/generate-provider-glyphs.swift
```

The generator writes a 24-pixel image and a 48-pixel `@2x` image for every
current provider. It uses only files in this repository and overwrites only the
declared outputs.

## Sources

- `claude-code.svg` is the Claude glyph from Simple Icons 16.21.0. Simple Icons
  is distributed under CC0 1.0, but its trademark disclaimer still applies.
  Source: <https://github.com/simple-icons/simple-icons>
- `deepseek.svg` is the DeepSeek glyph from Simple Icons 16.21.0. Simple Icons
  is distributed under CC0 1.0, but its trademark disclaimer still applies.
  Source: <https://github.com/simple-icons/simple-icons>
- `openai-codex.svg` is an original code-bracket glyph. It does not reproduce
  the OpenAI Blossom or wordmark.
- `zai.svg` is an original geometric `Z` glyph. It does not reproduce z.ai's
  official logo or wordmark.

The Simple Icons license and trademark disclaimer are available at:

- <https://github.com/simple-icons/simple-icons/blob/16.21.0/LICENSE.md>
- <https://github.com/simple-icons/simple-icons/blob/16.21.0/DISCLAIMER.md>

