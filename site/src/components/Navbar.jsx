import { BookOpen, Github, Moon, Shield, Sun } from 'lucide-react';
import { links, pages } from '../data/links';

const navLink =
  'flex h-8 items-center gap-1.5 squircle-item px-2.5 text-[13px] font-bold text-[var(--text-muted)] transition-colors duration-75 hover:bg-[color-mix(in_srgb,var(--text)_6%,transparent)] hover:text-[var(--text)]';

const Navbar = ({ current, isDark, onToggleTheme }) => {
  const item = (page, href, Icon, label) => (
    <a
      href={href}
      aria-current={current === page ? 'page' : undefined}
      className={`${navLink} ${current === page ? 'text-[var(--text)]' : ''}`}
    >
      <Icon size={14} className="hidden sm:block" /> {label}
    </a>
  );

  return (
    <nav className="sticky top-0 z-50 w-full border-b border-[var(--divider)] bg-[color-mix(in_srgb,var(--app-bg)_84%,transparent)] backdrop-blur-md">
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between gap-2 px-4">
        <a href={pages.home} className="flex items-center gap-2.5 transition-opacity hover:opacity-80">
          <img src={`${import.meta.env.BASE_URL}icon.png`} alt="" className="size-8 squircle-item" />
          <span className="hidden text-[16px] font-extrabold tracking-tight text-[var(--text)] min-[400px]:inline">RR Pocket</span>
        </a>
        <div className="flex items-center gap-0.5">
          {item('docs', pages.docs, BookOpen, 'Docs')}
          {item('privacy', pages.privacy, Shield, 'Privacy')}
          <a href={links.github} className={navLink}>
            <Github size={14} className="hidden sm:block" /> GitHub
          </a>
          <button
            onClick={onToggleTheme}
            className="ml-1 grid size-8 place-items-center squircle-item text-[var(--text-muted)] transition-colors duration-75 hover:bg-[color-mix(in_srgb,var(--text)_6%,transparent)] hover:text-[var(--text)]"
            aria-label={isDark ? 'Use the light theme' : 'Use the dark theme'}
          >
            {isDark ? <Sun size={15} /> : <Moon size={15} />}
          </button>
        </div>
      </div>
    </nav>
  );
};

export default Navbar;
