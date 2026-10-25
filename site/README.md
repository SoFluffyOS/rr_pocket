# RR Pocket's website

https://rr.sofluffy.io, once hosted. The landing page, the docs and the privacy policy, in React with Vite and
Tailwind, as lumide-landing is. The colours are a raccoon's (`src/index.css`):
ash-grey fur, a near-black mask, a cream face, the tail's bands, and
RR Pocket's amber as the one accent.

```sh
npm install
npm run dev      # http://localhost:5173
npm run lint
npm run build    # static files in dist/: index.html, docs.html, privacy.html
```

`dist/` uses relative paths, so it works at a domain's root or under a path
such as GitHub Pages' `/rr_pocket/`. Each page is its own HTML file; Play
links to `privacy.html`. Nunito is served from the site itself, not Google
Fonts, so visiting it sends nothing to anyone else.

The privacy policy's text is also in `../store/privacy-policy.md`; change
both together. The plugin list (`src/data/plugins.js`) follows
`../app/pubspec.yaml`.
