import { useMemo } from 'react';
import Layout from './Layout';
import useActiveSection from './useActiveSection';

// A long page with its contents beside it: the docs and the privacy policy.
const DocLayout = ({ current, title, lead, sections, children }) => {
  const ids = useMemo(() => sections.map((section) => section.id), [sections]);
  const active = useActiveSection(ids);

  return (
    <Layout current={current}>
      <div className="mx-auto grid max-w-6xl gap-6 px-4 pb-8 pt-8 md:grid-cols-[13rem_minmax(0,1fr)] md:gap-12 md:pt-12">
        <nav aria-label="On this page" className="md:sticky md:top-20 md:self-start">
          <p className="mb-2 text-[11px] font-extrabold uppercase tracking-wider text-[var(--text-muted)]">On this page</p>
          <ol className="flex flex-wrap gap-1.5 md:block md:space-y-0.5">
            {sections.map((section) => (
              <li key={section.id}>
                <a
                  href={`#${section.id}`}
                  className={`block squircle-item px-2.5 py-1 text-[13.5px] font-bold transition-colors duration-75 max-md:border max-md:border-[var(--divider)] ${
                    active === section.id
                      ? 'bg-[var(--accent-soft)] text-[var(--text)]'
                      : 'text-[var(--text-muted)] hover:text-[var(--text)]'
                  }`}
                >
                  {section.title}
                </a>
              </li>
            ))}
          </ol>
        </nav>
        <main className="min-w-0 max-w-3xl">
          <h1 className="text-[clamp(2rem,4.5vw,2.8rem)] font-extrabold leading-tight tracking-tight text-[var(--text)]">{title}</h1>
          <p className="mt-3 text-[17px] leading-relaxed text-[var(--text-muted)]">{lead}</p>
          <div className="tail-bands mt-6 w-32" aria-hidden="true" />
          <article className="prose-rr">{children}</article>
        </main>
      </div>
    </Layout>
  );
};

export default DocLayout;
