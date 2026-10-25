import Code from './Code';

const WhyRR = () => (
  <section className="app-section">
    <div className="section-panel bg-[var(--mask)] text-[var(--face)] md:px-10 md:py-9">
      <div className="tail-bands mb-6 w-40" aria-hidden="true" />
      <h2 className="text-[clamp(1.5rem,3vw,2.1rem)] font-extrabold leading-tight">Why &ldquo;RR&rdquo;?</h2>
      <p className="mt-3 max-w-2xl text-[16px] leading-relaxed text-[color-mix(in_srgb,var(--face)_78%,transparent)]">
        Raccoon Runtime, the Flutter runtime underneath. And <Code>r</Code> and <Code>R</Code>: the keys that hot reload and hot
        restart your app.
      </p>
    </div>
  </section>
);

export default WhyRR;
