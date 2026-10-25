import { links, pages } from '../data/links';
import RaccoonMark from './RaccoonMark';

const columns = [
  {
    title: 'RR Pocket',
    items: [
      { label: 'Get it on Google Play', href: links.play },
      { label: 'Docs', href: pages.docs },
      { label: 'Privacy policy', href: pages.privacy },
    ],
  },
  {
    title: 'Developers',
    items: [
      { label: 'rr_pocket on pub.dev', href: links.pub },
      { label: 'Source on GitHub', href: links.github },
      { label: 'Report an issue', href: links.issues },
    ],
  },
  {
    title: 'SoFluffy',
    items: [
      { label: links.supportEmail, href: `mailto:${links.supportEmail}` },
      { label: 'Lumide IDE', href: links.lumide },
      { label: "SoFluffy's blog", href: links.sofluffy },
    ],
  },
];

const Footer = () => (
  <footer className="mt-10 w-full overflow-hidden border-t border-[var(--divider)]">
    <div className="mx-auto grid max-w-6xl gap-8 px-4 pt-12 sm:grid-cols-2 md:grid-cols-4">
      <div className="space-y-3">
        <span className="text-[15px] font-extrabold text-[var(--text)]">RR Pocket</span>
        <p className="max-w-[220px] text-[13px] leading-relaxed text-[var(--text-muted)]">
          Your Flutter project on your Android phone, over Wi-Fi. Raccoon Runtime, in your pocket.
        </p>
      </div>
      {columns.map((column) => (
        <div key={column.title} className="space-y-3">
          <h2 className="text-[11px] font-extrabold uppercase tracking-wider text-[var(--text-muted)]">{column.title}</h2>
          <ul className="space-y-2 text-[13px]">
            {column.items.map((item) => (
              <li key={item.label}>
                <a href={item.href} className="text-[var(--text-soft)] transition-colors duration-75 hover:text-[var(--accent-ink)]">
                  {item.label}
                </a>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </div>
    <div className="relative mx-auto mt-6 flex max-w-6xl justify-center px-4">
      <RaccoonMark className="-mb-16 size-56 text-[var(--text)] opacity-[0.16] dark:opacity-[0.1]" />
    </div>
    <div className="relative bg-[var(--app-bg)]">
      <div className="tail-bands rounded-none" />
      <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-4 text-[12px] text-[var(--text-muted)]">
        <span>&copy; 2026 SoFluffy</span>
        <button
          onClick={() => window.scrollTo({ top: 0, behavior: 'smooth' })}
          className="font-bold text-[var(--text-soft)] transition-colors hover:text-[var(--text)]"
        >
          Back to top ↑
        </button>
      </div>
    </div>
  </footer>
);

export default Footer;
