# RR Pocket privacy policy

_2026-10-25. The site's copy (`site/src/pages/PrivacyPage.jsx`, built to
`privacy.html`) is the one to host and give to Google Play; change both
together._

RR Pocket is a tool for Flutter developers: it runs, on your phone, the app
you are developing on your computer.

**What RR Pocket collects: nothing.** It has no accounts, no analytics, no
ads and no servers. It sends nothing over the internet.

**What it keeps on your phone.** A pairing code and a certificate, made
when you first open it, which your computer uses to connect. They stay on
the phone until you clear the app's data or uninstall it.

**Your network.** RR Pocket listens on your local network for the computer
you paired, and announces itself there so your computer can find it. A
computer that asks to pair gets the pairing code only if you tap Allow on
the phone. The paired computer sends the app you are developing, and
RR Pocket runs it. Everything between them is encrypted (TLS), and your
computer talks only to the phone it paired with. Only pair computers you
trust.

**The camera, for pairing.** When you tap Scan QR code, RR Pocket reads the
QR code your computer shows. On phones with Google Play services, Google's
code scanner does the scanning and gives RR Pocket only the code's text; it
needs no camera permission. Elsewhere RR Pocket scans itself and asks for
the camera first. Nothing is recorded or kept.

**The app you run in it.** Camera, microphone, location, notifications and
biometrics are available to the app you are developing, and Android asks
you before that app uses them. What that app does with them is up to you,
its developer; RR Pocket doesn't see or keep any of it.

**Children.** RR Pocket is for developers and not directed at children.

**Contact.** SoFluffy, support@sofluffy.io.
