import { ArrowRight, Smartphone, Zap } from 'lucide-react';
import screenshot from '../assets/screenshot.png';
import { links, pages } from '../data/links';
import Code from './Code';

const Hero = () => (
  <header className="app-section pt-6">
    <div className="section-panel grid items-center gap-10 md:grid-cols-[1.05fr_1fr] md:p-10">
      <div className="space-y-6">
        <span className="eyebrow">
          <Zap size={13} className="text-[var(--accent-ink)]" /> Hot reload in under a second
        </span>
        <h1 className="text-[clamp(2.4rem,5.5vw,4rem)] font-extrabold leading-[1.04] tracking-tight text-[var(--text)]">
          Your Flutter app,{' '}
          <span className="bg-[linear-gradient(transparent_62%,var(--accent)_62%,var(--accent)_92%,transparent_92%)] dark:bg-none dark:text-[var(--accent)]">
            on your phone
          </span>
          , over Wi-Fi.
        </h1>
        <p className="section-copy max-w-xl text-[17px]">
          RR Pocket runs the Flutter project you&apos;re working on, on your Android phone, straight from your
          computer. No Android SDK, no Gradle build, no adb: just the Flutter SDK you already have, and{' '}
          <Code>flutter run -d pocket</Code>.
        </p>
        <div className="flex flex-wrap gap-2.5">
          <a href={links.play} className="tool-button">
            <Smartphone size={17} /> Get it on Google Play
          </a>
          <a href={pages.docs} className="ghost-button">
            Read the docs <ArrowRight size={16} />
          </a>
        </div>
        <p className="text-[13px] text-[var(--text-muted)]">Android 7.0 or later. No ads, no account. Like Expo Go, for Flutter.</p>
      </div>
      <div className="relative">
        <img
          src={screenshot}
          width="1080"
          height="1200"
          alt="RR Pocket's home screen in light and dark: the phone's address, pairing code and certificate, ready for pocket pair."
          className="mx-auto w-full max-w-[520px] rounded-[28px] shadow-[0_30px_70px_-30px_rgba(28,31,35,0.55)]"
        />
        <div className="tail-bands mx-auto mt-5 w-2/3 max-w-[340px]" aria-hidden="true" />
      </div>
    </div>
  </header>
);

export default Hero;
