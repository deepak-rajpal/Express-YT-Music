// Asserts FirstPartyHosts against the hosts Google's sign-in flow really uses, and
// against look-alikes that must NOT be treated as first party.
//   swiftc Sources/FirstPartyHosts.swift Tools/hosttest.swift -o build/hosttest
import Foundation

@main
struct HostTest {
static var failures = 0

static func expect(_ host: String, _ want: Bool) {
    let got = FirstPartyHosts.matches(host)
    if got == want {
        print("  ok    \(host) -> \(got)")
    } else {
        failures += 1
        print("  FAIL  \(host) -> \(got), wanted \(want)")
    }
}

static func main() {
print("first party (must stay in the app)")
for host in [
    "music.youtube.com",
    "www.youtube.com",
    "youtube.com",
    "accounts.google.com",
    "accounts.youtube.com",
    "consent.youtube.com",
    "consent.google.com",
    "myaccount.google.com",
    "ogs.google.com",
    "play.google.com",
    "support.google.com",
    "policies.google.com",
    "google.com",
    "www.google.com",
    "google.co.in",             // country domains appear during sign-in
    "www.google.co.uk",
    "youtube.de",
    "lh3.googleusercontent.com",
    "yt3.ggpht.com",
    "i.ytimg.com",
    "fonts.gstatic.com",
    "rr1---sn-abc.googlevideo.com",
    "content-youtube.googleapis.com",
    "youtu.be",
    "MUSIC.YOUTUBE.COM",        // hosts are case insensitive
    "music.youtube.com.",       // trailing dot is a valid FQDN form
] { expect(host, true) }

print("\nnot first party (must open in the real browser)")
for host in [
    "notgoogle.com",
    "evilgoogle.com",
    "google.com.example.net",   // suffix smuggling
    "youtube.com.attacker.io",
    "my-google.com",
    "googlecom",
    "google",
    "fakeyoutube.com",
    "youtube.evil.com",
    "example.com",
    "spotify.com",
    "genius.com",
    "",
] { expect(host, false) }

print("\n\(failures == 0 ? "PASS" : "FAIL") - \(failures) failure(s)")
exit(failures == 0 ? 0 : 1)
}
}
