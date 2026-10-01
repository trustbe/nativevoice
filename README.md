# NativeVoice

Hold a key, speak, let go. The text appears where your cursor is.

NativeVoice is a macOS dictation app for the languages the big tools treat as
an afterthought. Dictation on a Mac is excellent if you speak English and
patchy to absent if you do not — macOS offers an offline model, automatic
punctuation and continuous listening for `en-US` alone, and the well-known
third-party apps advertise "100+ languages" while quietly listing Polish,
Russian and Ukrainian but not Czech.

This one treats those languages as the point rather than the long tail. It
speaks 36:

- Belarusian, Bosnian, Bulgarian, Catalan, Croatian, Czech
- Danish, Dutch, English, Estonian, Finnish, French
- Galician, German, Greek, Hungarian, Icelandic, Indonesian
- Italian, Japanese, Kannada, Latvian, Macedonian, Malay
- Malayalam, Norwegian, Polish, Portuguese, Romanian, Russian
- Slovak, Spanish, Swedish, Turkish, Ukrainian, Vietnamese

If a language is missing it is because ElevenLabs does not transcribe it yet,
not because it was skipped. Anything on this list gets the same behaviour as
any other — there is no first-class language here.

## An API key of your own

NativeVoice sends your audio to [ElevenLabs](https://elevenlabs.io) for
transcription and needs your own ElevenLabs API key to work. ElevenLabs
bills by usage, so what you dictate is what you pay for — there is no
subscription bundled into the app. The key is stored in the macOS Keychain,
never anywhere else.

## Installation

Requires macOS 13 or later. Universal: Apple silicon and Intel.

1. Download the `.dmg` from the [releases page](https://github.com/trustbe/nativevoice/releases).
2. Open it and drag **NativeVoice** into **Applications**.
3. Open NativeVoice from Applications. It needs **two** permissions in
   System Settings, and macOS will not ask you for the first one — the app's
   own menu tells you which it is waiting for:

   - **Input Monitoring** — lets NativeVoice notice when you hold the
     trigger key. Without it, nothing happens when you hold the key down.
     **Quit and reopen the app after granting it**; macOS hands the permission
     only to a freshly started process, so nothing changes until you do.
   - **Accessibility** — lets NativeVoice paste the finished transcript into
     whatever you were typing into. Without it, NativeVoice still transcribes
     your speech, but nothing appears where you were typing: it pastes
     silently into nothing.

   Granting only one of the two is the most common way to end up confused —
   the app looks like it is working but nothing lands on the page.

4. Enter your ElevenLabs API key when NativeVoice asks for it (also reachable
   any time from the menu bar icon).

## Using it

Hold the right ⌘ key, speak, and release it. NativeVoice transcribes what you
said and pastes it wherever your cursor is.

## Custom vocabulary

Names, brands, and technical terms that don't exist in a general-purpose
language model are the single biggest source of transcription mistakes —
fixing this with a vocabulary file helps more than any setting in the app.
Edit the list from the menu bar ("Edit vocabulary…"), or directly at:

```
~/.config/nativevoice/vocabulary.txt
```

One term per line; lines starting with `#` are comments.

## Building from source

```
./Scripts/build-app.sh 0.1.0 1
```

This produces a universal (Intel + Apple Silicon) `.app` bundle at
`.build/app/NativeVoice.app`. Run `./Scripts/test.sh` to run the test suite
first.

## License

MIT. See [LICENSE](LICENSE).
