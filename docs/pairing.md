# Pairing

How a computer gets the phone's address and pairing code. Three routes,
tried in this order; each later one is the fallback for the one before.

1. **Found on the network.** The computer finds the phone by mDNS and asks
   it to pair; the user taps Allow on the phone. Nothing to type or scan.
   Needs multicast on the Wi-Fi, which some networks block.
2. **A QR code on the computer.** The computer shows a QR code; the phone
   scans it and sends its address and code to the computer. Needs the
   phone to reach the computer.
3. **Typed.** The user types the address and code the phone shows:
   `pocket pair <address> <code>`. Always works when the computer can reach
   the phone.

Whatever the route, the computer then checks the code with `GET /hello`
before it saves the pairing, as it always has.

## TLS and the certificate

The phone's servers speak only TLS, with a certificate RR Pocket makes
once and signs itself (P-256, kept with the app's data like the code). A
computer trusts it by its fingerprint, the SHA-256 of the certificate in
lowercase hex, which it saves with the pairing (`device.json`,
`fingerprint`) and checks on every connection; no certificate authority
counts. Each route learns the fingerprint its own way:

| Route | How the computer learns the fingerprint | Who could get in the way |
| --- | --- | --- |
| QR code | from the phone, signed with the QR code's token | nobody: the token only crossed the screen to the camera |
| Found on the network | the certificate that answers `POST /pair` | someone already in the middle of the Wi-Fi at that moment; the phone's question shows the address that asked |
| Typed | the certificate that answers the first `GET /hello` | the same, at that moment |

The code itself never crosses the network in the clear on any route.

On the two routes that trust the first certificate, the computer then
prints the fingerprint's first 8 hex digits (`2DC9 1E21`), and RR Pocket
shows the same under its code. If they differ, something else on the Wi-Fi
answered first, for example a device announcing itself as RR Pocket:
forget it (`pocket forget`) and pair by QR code. 32 bits are enough to
catch a device that merely answered first, not one that made certificates
until one matched the start; against that, pair by QR code.

## 1. Found on the network

The phone advertises a DNS-SD service while RR Pocket runs:

- type `_rrpocket._tcp`, port: the control port (8100);
- instance name: the phone's model, such as `Pixel 7` (Android may add
  ` (2)` when two phones share a name);
- TXT records: `v=1`, `model=<model>`, `flutter=<Flutter version>`.

The computer browses for `_rrpocket._tcp.local` for about 3 seconds, then
asks the phone it picked, over TLS, trusting the certificate that answers
and pinning it:

```
POST /pair          (no Authorization header)
{"computer": "Simon's MacBook Pro"}
```

The phone asks on its own screen: "Pair with Simon's MacBook Pro?"
(Allow / Don't allow), and holds the request open until the user answers,
at most 60 seconds:

| Status | Body | When |
| --- | --- | --- |
| 200 | `{"code": "H79GN4XS"}` | the user allowed it |
| 403 | `{"error": "pairing refused on the phone"}` | the user refused |
| 408 | `{"error": "no answer on the phone"}` | 60 seconds passed |
| 409 | `{"error": "…"}` | another request is waiting, or a project is running (RR Pocket's own screen is not showing) |
| 429 | `{"error": "…"}` | the phone said no, or nobody answered, in the last 30 seconds |

The question shows the address the request came from, so a name alone
can't pass for someone's computer, and someone in the middle shows up as
an address that isn't the computer's.

`computer` is shown as given, cut to 64 characters. The computer waits up to
70 seconds for the answer.

## 2. A QR code on the computer

The computer listens, plain HTTP, on a random port on all its interfaces
and shows a QR code holding:

```
rrpocket://pair?v=1&hosts=192.168.1.5,10.0.0.3&port=53123&token=<token>&name=<computer>
```

- `hosts`: the computer's site-local IPv4 addresses, best first. The phone
  posts only to private (10/8, 172.16/12, 192.168/16) or link-local
  (169.254/16) addresses: any page or app can open a link, and a pairing
  must not reach beyond the network, nor another app on the phone.
- `token`: 128 random bits, base64url without padding; good for one
  pairing, and only while the code is shown. It never crosses the network
  in the clear.
- `name`: the computer's name, URL-encoded.

The phone scans it with Google's code scanner (Play services), or, where
Play services can't provide one, its own scanner (`qr_code_scanner_plus`).
The same URI opens RR Pocket from the phone's camera app. Either way the
phone asks first: "Pair with Simon's MacBook Pro?". A QR code anyone could
have shown must not send the pairing code without that tap.

Once the user allows it, the phone keeps the token for 2 minutes, for one
use, and tries each host in turn: 5 seconds to connect, then up to 20 to
answer. It sends where it is and its certificate's fingerprint, not its
code, with `proof` = HMAC-SHA256 of the fingerprint keyed with the token
(lowercase hex):

```
POST http://<host>:<port>/pair
{"name": "Pixel 7", "address": "192.168.1.20", "port": 8100,
 "fingerprint": "2dc91e21…", "proof": "5bdcc146…"}
```

The computer checks the proof: only a phone that saw the QR code can make
it, and it vouches for that fingerprint. It then asks that phone for the
code, over TLS pinned to the fingerprint, showing the token (up to 10
seconds), and checks the code with `/hello` (up to 10 more):

```
POST https://<address>:<port>/pair     (no Authorization header)
{"token": "<token>"}
→ 200 {"code": "H79GN4XS"}   once, while the token is kept
→ 403 {"error": "…"}         another token, used, or expired
```

Then it answers the phone's post:

| Status | Body | When |
| --- | --- | --- |
| 200 | `{"computer": "Simon's MacBook Pro"}` | paired: the computer got the code and reached the phone's `/hello` with it |
| 403 | `{"error": "…"}` | the proof is not for this QR code's token, or it was used |
| 502 | `{"error": "the computer could not reach the phone at …"}` | the computer can't reach the phone, or a phone with that certificate; try another network |

The computer stops listening after the first pairing, when the user closes
the QR code, or after 5 minutes.

## 3. Typed

`pocket pair <address> <code>`, or the address and code typed into Lumide.
The computer pins the certificate that answers the first `GET /hello`.

## Where each route lives

| | Phone (`app/`) | Computer (`desktop/`) |
| --- | --- | --- |
| Found on the network | NSD registration, `POST /pair`, the Allow prompt | mDNS browse, the request |
| QR code | the scanners, the deep link, the Allow prompt, the post | the listener, the QR in the terminal and in a Lumide panel |
| Typed | the address and code on the home screen | `pocket pair <address> <code>`, Lumide's input boxes |
