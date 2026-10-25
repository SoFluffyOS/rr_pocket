import DocLayout from '../components/DocLayout';
import { links } from '../data/links';

// The same text as store/privacy-policy.md: change both together.
const sections = [
  { id: 'collects', title: 'What it collects' },
  { id: 'keeps', title: 'What it keeps' },
  { id: 'network', title: 'Your network' },
  { id: 'camera', title: 'The camera' },
  { id: 'your-app', title: 'The app you run' },
  { id: 'children', title: 'Children' },
  { id: 'contact', title: 'Contact' },
];

const PrivacyPage = () => (
  <DocLayout
    current="privacy"
    title="Privacy policy"
    lead="Last updated 25 October 2026. RR Pocket is a tool for Flutter developers: it runs, on your phone, the app you are developing on your computer."
    sections={sections}
  >
    <h2 id="collects">What RR Pocket collects: nothing</h2>
    <p>It has no accounts, no analytics, no ads and no servers. It sends nothing over the internet.</p>

    <h2 id="keeps">What it keeps on your phone</h2>
    <p>
      A pairing code and a certificate, made when you first open it, which your computer uses to connect. They stay on the
      phone until you clear the app&apos;s data or uninstall it.
    </p>

    <h2 id="network">Your network</h2>
    <p>
      RR Pocket listens on your local network for the computer you paired, and announces itself there so your computer can
      find it. A computer that asks to pair gets the pairing code only if you tap Allow on the phone. The paired computer
      sends the app you are developing, and RR Pocket runs it. Everything between them is encrypted (TLS), and your computer
      talks only to the phone it paired with. Only pair computers you trust.
    </p>

    <h2 id="camera">The camera, for pairing</h2>
    <p>
      When you tap Scan QR code, RR Pocket reads the QR code your computer shows. On phones with Google Play services,
      Google&apos;s code scanner does the scanning and gives RR Pocket only the code&apos;s text; it needs no camera
      permission. Elsewhere RR Pocket scans itself and asks for the camera first. Nothing is recorded or kept.
    </p>

    <h2 id="your-app">The app you run in it</h2>
    <p>
      Camera, microphone, location, notifications and biometrics are available to the app you are developing, and Android
      asks you before that app uses them. What that app does with them is up to you, its developer; RR Pocket doesn&apos;t
      see or keep any of it.
    </p>

    <h2 id="children">Children</h2>
    <p>RR Pocket is for developers and not directed at children.</p>

    <h2 id="contact">Contact</h2>
    <p>
      SoFluffy, <a className="link" href={`mailto:${links.supportEmail}`}>{links.supportEmail}</a>.
    </p>
  </DocLayout>
);

export default PrivacyPage;
