import Code from './Code';
import CodeBlock from './CodeBlock';

const steps = [
  {
    title: 'Open RR Pocket',
    body: (
      <>Install it from Google Play and open it. It shows the phone&apos;s address, a pairing code and the Flutter version it carries.</>
    ),
  },
  {
    title: 'Pair your computer',
    code: 'dart pub global activate rr_pocket\npocket pair',
    body: <>It finds the phone on your Wi-Fi: tap Allow on the phone. Or scan the QR code it shows.</>,
  },
  {
    title: 'Run any project',
    code: 'pocket pin\nflutter run -d pocket',
    body: (
      <>
        Your app opens inside RR Pocket. <Code>r</Code> hot reloads, <Code>R</Code> hot restarts, <Code>q</Code> quits.
      </>
    ),
  },
];

const Steps = () => (
  <section id="start" className="app-section">
    <div className="section-panel md:px-10">
      <h2 className="section-title">
        Three steps, then just <Code>r</Code>
      </h2>
      <p className="section-copy mt-3 max-w-2xl text-[16px]">
        Pair once. After that, every Flutter project runs on the phone with a stock <Code>flutter run</Code>.
      </p>
      <ol className="mt-8 grid gap-3 md:grid-cols-3">
        {steps.map((step, index) => (
          <li key={step.title} className="squircle-panel flex flex-col p-5">
            <span className="grid size-9 place-items-center rounded-full bg-[var(--accent)] text-[15px] font-extrabold text-[var(--mask)]">
              {index + 1}
            </span>
            <h3 className="mt-4 text-[17px] font-extrabold text-[var(--text)]">{step.title}</h3>
            {step.code && <CodeBlock code={step.code} compact />}
            <p className="mt-1 text-[14.5px] leading-relaxed text-[var(--text-muted)]">{step.body}</p>
          </li>
        ))}
      </ol>
    </div>
  </section>
);

export default Steps;
