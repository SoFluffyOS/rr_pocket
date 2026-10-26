import Code from '../components/Code';
import CodeBlock from '../components/CodeBlock';
import DocLayout from '../components/DocLayout';
import PluginChips from '../components/PluginChips';
import Problem from '../components/Problem';
import TableBox from '../components/TableBox';
import { links, pages } from '../data/links';
import { plugins } from '../data/plugins';

const sections = [
  { id: 'requirements', title: 'Requirements' },
  { id: 'install', title: 'Install' },
  { id: 'pair', title: 'Pair' },
  { id: 'run', title: 'Run a project' },
  { id: 'commands', title: 'Commands' },
  { id: 'plugins', title: 'Plugins' },
  { id: 'lumide', title: 'Lumide' },
  { id: 'troubleshooting', title: 'Troubleshooting' },
  { id: 'how', title: 'How it works' },
  { id: 'security', title: 'Security' },
  { id: 'help', title: 'Help' },
];

const commands = [
  [<Code key="c">pocket pair</Code>, <>Pair with the phone and add the <Code>pocket</Code> device to Flutter. Finds the phone on the network, or shows a QR code when it can&apos;t.</>],
  [<Code key="c">pocket pair --qr</Code>, 'Pair by QR code straight away.'],
  [<Code key="c">pocket pair &lt;address&gt; &lt;code&gt;</Code>, 'Pair with the address and code RR Pocket shows.'],
  [<Code key="c">pocket pin</Code>, <>In a project: pin its Android plugins to RR Pocket&apos;s versions in <Code>pubspec_overrides.yaml</Code>, then run <Code>flutter pub get</Code>. A breaking change is left out and named.</>],
  [<Code key="c">pocket pin --all</Code>, 'Pin breaking changes too, once your code is ready for them.'],
  [<Code key="c">pocket doctor</Code>, "Check the setup and the project you're in, and say what to fix."],
  [<Code key="c">pocket forget</Code>, 'Unpair this computer. The phone keeps its code, so pairing again works.'],
];

const lumideCommands = [
  ['RR Pocket: Pair with Phone', 'The phones found on the network, a QR code to scan, or the address and code typed in.'],
  ['RR Pocket: Match Plugin Versions', <><Code key="c">pocket pin</Code> for the open project.</>],
  ['RR Pocket: Show Phone', 'The paired phone, its Flutter version and plugins.'],
  ['RR Pocket: Check Setup', <><Code key="c">pocket doctor</Code>, in the RR Pocket output.</>],
  ['RR Pocket: Forget Phone', 'Unpair, after asking.'],
];

const DocsPage = () => (
  <DocLayout
    current="docs"
    title="RR Pocket docs"
    lead={
      <>
        RR Pocket runs the Flutter project on your computer on your Android phone, over Wi-Fi, with a stock{' '}
        <Code>flutter run -d pocket</Code>. Two parts work together: the RR Pocket app on the phone, and the{' '}
        <Code>pocket</Code> command on your computer.
      </>
    }
    sections={sections}
  >
    <h2 id="requirements">Requirements</h2>
    <ul>
      <li><strong>A phone</strong> running Android 7.0 or later, with RR Pocket from Google Play.</li>
      <li><strong>A computer</strong> running macOS, Linux or Windows, with the Flutter SDK. No Android SDK, no adb.</li>
      <li>
        <strong>The same Flutter version</strong> RR Pocket was built with. Its home screen shows which. A project&apos;s
        compiled code runs only on the engine its SDK was built for.
      </li>
      <li>
        <strong>One network</strong> for both, where devices can reach each other. Home Wi-Fi works; guest and office
        networks sometimes keep devices apart.
      </li>
    </ul>

    <h2 id="install">Install</h2>
    <p>
      On the phone, install <a className="link" href={links.play}>RR Pocket from Google Play</a> and open it. It shows its
      address, an 8-character pairing code and the start of its certificate.
    </p>
    <p>On the computer, install the <Code>pocket</Code> command:</p>
    <CodeBlock code="dart pub global activate rr_pocket" />
    <p>
      If your shell can&apos;t find <Code>pocket</Code> afterwards, add pub&apos;s bin folder to your <Code>PATH</Code>:{' '}
      <Code>dart pub global activate</Code> prints which folder.
    </p>

    <h2 id="pair">Pair</h2>
    <p>
      Pairing gives your computer the phone&apos;s address and code, and registers the <Code>pocket</Code> device with
      Flutter. You do it once. With RR Pocket open on the phone:
    </p>
    <CodeBlock code="pocket pair" />
    <p>There are three ways to pair. Each is the fallback for the one before.</p>

    <h3>1. Found on the network</h3>
    <p>
      <Code>pocket pair</Code> looks for the phone on your Wi-Fi for a few seconds, then asks it to pair. The phone asks
      &ldquo;Pair with <em>your computer</em>?&rdquo; and shows the address that asked. Tap Allow. Nothing to type or scan.
    </p>

    <h3>2. A QR code</h3>
    <p>
      When the network hides the phone, <Code>pocket pair</Code> shows a QR code instead. Tap <strong>Scan QR code</strong>{' '}
      in RR Pocket, scan it, and allow the pairing. To go straight to the QR code:
    </p>
    <CodeBlock code="pocket pair --qr" />

    <h3>3. Typed</h3>
    <p>With the address and code RR Pocket shows. This works whenever the computer can reach the phone:</p>
    <CodeBlock code="pocket pair 192.168.1.20 H79GN4XS" />

    <h3>Check the certificate</h3>
    <p>
      When the phone was found or typed, <Code>pocket pair</Code> prints the start of the phone&apos;s certificate, such as{' '}
      <Code>2DC9 1E21</Code>. RR Pocket shows the same under its code. If they differ, another device on the network
      answered first: run <Code>pocket forget</Code>, then <Code>pocket pair --qr</Code>. A QR pairing needs no check: the
      phone proves itself with what it scanned.
    </p>

    <h2 id="run">Run a project</h2>
    <p>In your project folder, match its plugin versions to RR Pocket&apos;s once, then run:</p>
    <CodeBlock code={'pocket pin\nflutter run -d pocket'} />
    <p>
      Flutter builds your project and sends it to the phone, and your app opens inside RR Pocket. Everything{' '}
      <Code>flutter run</Code> does works as on any device:
    </p>
    <ul>
      <li><Code>r</Code> hot reloads, <Code>R</Code> hot restarts.</li>
      <li>DevTools, breakpoints and your <Code>print</Code> output.</li>
      <li><Code>q</Code> quits, and the phone is back on RR Pocket&apos;s screen.</li>
    </ul>
    <p>
      Your project needs no <Code>android/</Code> folder. The first launch takes a few seconds, longer for a large app; hot
      reload takes under a second.
    </p>
    <p>Not sure everything is set up? In the project folder:</p>
    <CodeBlock code="pocket doctor" />
    <p>
      It checks the pairing, the phone answering, the Flutter version, the <Code>pocket</Code> device and the project&apos;s
      plugins, and says what to fix for each.
    </p>

    <h2 id="commands">Commands</h2>
    <TableBox head={['Command', 'What it does']} rows={commands} />
    <p>
      Flutter calls <Code>pocket</Code>&apos;s other commands itself during <Code>flutter run</Code>; you don&apos;t need
      them.
    </p>

    <h2 id="plugins">Plugins</h2>
    <p>
      An app built the usual way carries the Android side of each plugin it uses. Under RR Pocket, your project brings only
      its Dart code, so RR Pocket carries the Android side of these {plugins.length} plugins:
    </p>
    <div className="my-4">
      <PluginChips />
    </div>
    <p>
      The two sides must be the same version, so <Code>pocket pin</Code> writes RR Pocket&apos;s versions into your
      project&apos;s <Code>pubspec_overrides.yaml</Code>. <Code>flutter run</Code> stops before sending a project whose
      versions differ, and names them.
    </p>
    <p>
      Plain Dart packages, with no Android code, work as they are. A plugin RR Pocket doesn&apos;t carry gets a warning:
      calls to it throw <Code>MissingPluginException</Code>. Build your app the usual way to try that one.
    </p>

    <h2 id="lumide">Lumide</h2>
    <p>
      The <Code>rr_pocket</Code> package is also a plugin for <a className="link" href={links.lumide}>Lumide</a> (0.24.0 or
      later). Lumide loads it at its next start after <Code>dart pub global activate rr_pocket</Code>, or install it from
      Lumide&apos;s Plugins pane. Then, from the Command Palette or the status bar:
    </p>
    <TableBox head={['Command', 'What it does']} rows={lumideCommands} />
    <p>
      After pairing, pick RR Pocket in the device list and press Run. Lumide and the <Code>pocket</Code> command share one
      pairing, so pairing in either is enough.
    </p>

    <h2 id="troubleshooting">Troubleshooting</h2>
    <p>Start with <Code>pocket doctor</Code> in your project: it names most problems and how to fix them.</p>

    <Problem title={<><Code>pocket pair</Code> doesn&apos;t find the phone</>}>
      <p>
        Some networks block the way devices find each other. <Code>pocket pair</Code> then shows a QR code: scan it with
        RR Pocket. If the phone can&apos;t reach the computer either, type the address and code:{' '}
        <Code>pocket pair &lt;address&gt; &lt;code&gt;</Code>. If nothing works, the network keeps devices apart; try
        another Wi-Fi.
      </p>
    </Problem>
    <Problem title="The Flutter version differs">
      <p>
        <Code>flutter run</Code> stops and says which version RR Pocket needs. Run the project with that version, for
        example with <a className="link" href={links.fvm}>fvm</a>:
      </p>
      <CodeBlock code={'fvm use 3.47.8\nfvm flutter run -d pocket'} />
    </Problem>
    <Problem title="Plugin versions differ">
      <p>
        Run <Code>pocket pin</Code> in the project. If it names a breaking change, update your code for that plugin&apos;s
        new version, then run <Code>pocket pin --all</Code>.
      </p>
    </Problem>
    <Problem title={<Code>MissingPluginException</Code>}>
      <p>Your app calls a plugin RR Pocket doesn&apos;t carry. Build your app the usual way to use that one.</p>
    </Problem>
    <Problem title="The certificate doesn't match">
      <p>Another device answered when you paired. Unpair and pair by QR code, which can&apos;t be answered by anyone else:</p>
      <CodeBlock code={'pocket forget\npocket pair --qr'} />
    </Problem>
    <Problem title="The phone's address changed">
      <p>
        Phones get a new address on another network, and sometimes on the same one. Run <Code>pocket pair</Code> again.
      </p>
    </Problem>
    <Problem title="&ldquo;Too many wrong pairing codes&rdquo;">
      <p>
        After 10 wrong codes from one computer, RR Pocket refuses it for 5 minutes. Wait, then pair again with the code the
        phone shows.
      </p>
    </Problem>
    <Problem title="The app stops at start">
      <p>
        If your app throws as it starts, RR Pocket shows the error on the phone instead of a frozen screen. Fix it and run
        again.
      </p>
    </Problem>
    <Problem title="You cleared RR Pocket's data">
      <p>
        That makes a new pairing code and certificate, so your computer no longer recognizes the phone. Run{' '}
        <Code>pocket forget</Code>, then <Code>pocket pair</Code>.
      </p>
    </Problem>

    <h2 id="how">How it works</h2>
    <p>
      RR Pocket is an Android app that carries Flutter&apos;s debug engine, the one that makes hot reload possible, and the
      Android side of the plugins above.
    </p>
    <ol>
      <li><Code>flutter run -d pocket</Code> builds your project&apos;s debug bundle on the computer, as for any device.</li>
      <li>The <Code>pocket</Code> command, which Flutter calls for this device, sends the bundle to RR Pocket over Wi-Fi.</li>
      <li>RR Pocket restarts into your app, the same way a hot restart does.</li>
      <li>Flutter connects to the app&apos;s debugging service through RR Pocket, for hot reload, DevTools and your logs.</li>
    </ol>

    <h2 id="security">Security</h2>
    <p>RR Pocket runs the code a paired computer sends it, so it guards who can pair:</p>
    <ul>
      <li>
        <strong>Encrypted.</strong> Everything between the computer and the phone goes over TLS. Your computer trusts only
        the certificate of the phone it paired with.
      </li>
      <li>
        <strong>A pairing code on every request.</strong> 8 characters, made on the phone. 10 wrong codes lock that computer
        out for 5 minutes.
      </li>
      <li><strong>You allow each pairing</strong> on the phone, which shows who asked.</li>
      <li>
        <strong>Kept private on the computer.</strong> The pairing is saved in <Code>~/.config/rr_pocket</Code> (
        <Code>%APPDATA%\rr_pocket</Code> on Windows), readable only by you.
      </li>
    </ul>
    <p>
      Pair only computers you trust, on networks you trust. RR Pocket collects nothing; see the{' '}
      <a className="link" href={pages.privacy}>privacy policy</a>.
    </p>

    <h2 id="help">Help</h2>
    <p>
      Found a bug or need help? Open an issue on <a className="link" href={links.issues}>GitHub</a>, or write to{' '}
      <a className="link" href={`mailto:${links.supportEmail}`}>{links.supportEmail}</a>.
    </p>
  </DocLayout>
);

export default DocsPage;
