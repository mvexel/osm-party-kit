# osmlogo — project scope

A party kit: anyone can bake a kit for their own party and host a mapping
party — one room, one laptop on a hotspot, one evening. Two audiences:
the host who sets it up (party.json, nouns.yaml, lang/, build.sh) and the
guests who scan a QR and play. The evening is the unit of ambition —
MVP forever.

- Bias to subtraction. Every new feature needs a justification at one of
  two levels: host setup or the party night itself. If neither, push back.
- Guest-side friction is the cardinal sin: joining must be scan → play,
  nothing mandatory in between.
- Deliberately dumb architecture, keep it that way: no build step for the
  frontend, no framework, no accounts, stdlib-only server, one-file
  frontend (web/index.html + scribbles.js), append-only JSONL as the
  entire sync protocol.
