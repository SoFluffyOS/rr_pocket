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

## 1. Found on the network

The phone advertises a DNS-SD service while RR Pocket runs:

- type `_rrpocket._tcp`, port: the control port (8100);
- instance name: the phone's model, such as `Pixel 7` (Android may add
  ` (2)` when two phones share a name);
- TXT records: `v=1`, `model=<model>`, `flutter=<Flutter version>`.

The computer browses for `_rrpocket._tcp.local` for about 3 seconds, then
asks the phone it picked:

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

`computer` is shown as given, cut to 64 characters. The computer waits up to
70 seconds for the answer.

## 2. A QR code on the computer

The computer listens on a random port on all its interfaces and shows a QR
code holding:

```
rrpocket://pair?v=1&hosts=192.168.1.5,10.0.0.3&port=53123&token=<token>&name=<computer>
```

- `hosts`: the computer's site-local IPv4 addresses, best first.
- `token`: 128 random bits, base64url without padding; good for one
  pairing, and only while the code is shown.
- `name`: the computer's name, URL-encoded.

The phone scans it with Google's code scanner (Play services), or, where
Play services can't provide one, its own scanner (`qr_code_scanner_plus`).
The same URI opens RR Pocket from the phone's camera app. Either way the
phone asks first: "Pair with Simon's MacBook Pro?". A QR code anyone could
have shown must not send the pairing code without that tap.

Then the phone tries each host in turn, 5 seconds each:

```
POST http://<host>:<port>/pair
{"token": "<token>", "name": "Pixel 7", "address": "192.168.1.20",
 "port": 8100, "code": "H79GN4XS"}
```

| Status | Body | When |
| --- | --- | --- |
| 200 | `{"computer": "Simon's MacBook Pro"}` | paired: the computer reached the phone's `/hello` with the code |
| 403 | `{"error": "…"}` | wrong or used token |
| 502 | `{"error": "the computer could not reach the phone at …"}` | the computer can't reach the phone; try another network |

The computer stops listening after the first pairing, when the user closes
the QR code, or after 5 minutes.

## 3. Typed

Unchanged: `pocket pair <address> <code>`, or the address and code typed
into Lumide.

## Where each route lives

| | Phone (`app/`) | Computer (`desktop/`) |
| --- | --- | --- |
| Found on the network | NSD registration, `POST /pair`, the Allow prompt | mDNS browse, the request |
| QR code | the scanners, the deep link, the Allow prompt, the post | the listener, the QR in the terminal and in a Lumide panel |
| Typed | the address and code on the home screen | `pocket pair <address> <code>`, Lumide's input boxes |
