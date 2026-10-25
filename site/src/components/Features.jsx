import { AlertTriangle, Bug, Lock, PackageX, Puzzle, Zap } from 'lucide-react';
import { links } from '../data/links';
import Code from './Code';

const features = [
  {
    icon: Zap,
    title: 'Hot reload in under a second',
    body: <>Change your code and press <Code>r</Code>: about half a second on a Pixel 7.</>,
  },
  {
    icon: Bug,
    title: 'Your usual tools',
    body: <>DevTools, breakpoints and your <Code>print</Code> output work as on any other device.</>,
  },
  {
    icon: PackageX,
    title: 'No Android SDK',
    body: <>No Gradle build, no adb, no USB cable. The <Code>pocket</Code> command needs only the Dart SDK, on macOS, Linux and Windows.</>,
  },
  {
    icon: AlertTriangle,
    title: 'Errors you can see',
    body: <>If your app fails as it starts, RR Pocket shows the error instead of a frozen screen.</>,
  },
  {
    icon: Lock,
    title: 'Encrypted and paired',
    body: <>Everything between your computer and the phone goes over TLS, pinned to the phone you paired. RR Pocket collects nothing.</>,
  },
  {
    icon: Puzzle,
    title: 'Built into Lumide',
    body: (
      <>
        The same package is a <a className="link" href={links.lumide}>Lumide</a> plugin: pair from the status bar, then pick RR Pocket in the device list.
      </>
    ),
  },
];

const Features = () => (
  <section id="features" className="app-section">
    <div className="section-panel md:px-10">
      <h2 className="section-title">A real device, without the Android toolchain.</h2>
      <p className="section-copy mt-3 max-w-2xl text-[16px]">
        RR Pocket carries Flutter&apos;s debug engine, so the phone behaves like any device <Code>flutter run</Code> knows.
      </p>
      <div className="mt-8 grid gap-3 md:grid-cols-2 lg:grid-cols-3">
        {features.map((feature) => (
          <div key={feature.title} className="squircle-panel p-5">
            <div className="quiet-icon size-10">
              <feature.icon size={18} />
            </div>
            <h3 className="mt-4 text-[16.5px] font-extrabold text-[var(--text)]">{feature.title}</h3>
            <p className="mt-1.5 text-[14.5px] leading-relaxed text-[var(--text-muted)]">{feature.body}</p>
          </div>
        ))}
      </div>
    </div>
  </section>
);

export default Features;
