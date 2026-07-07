# Vocal Warm-Up Coach — v1 Spec (buildable by Opus/Codex without Fable)

## Thesis
Stale incumbents (5-10 yrs unupdated, <4.0 ratings) in a real-demand niche: singers, actors, speakers, worship teams. Differentiator: a real AI coaching voice (ElevenLabs) guiding the routine. Free core + $3.99 one-time or $2.99/mo premium.

## v1 features (ship in a week — nothing more)
1. 3 preset routines (Morning Voice, Pre-Gig, Audition Day): sequenced exercises (lip trills, sirens, 5-note scales, hums), each with duration + guided audio.
2. Pitch reference: on-screen piano C2-C6, tap to sound (local synthesis, no network).
3. Interval timer per exercise with voice cue at transitions.
4. Streak tracker (local only).
5. Settings: voice type (soprano/alto/tenor/bass) shifts scale start notes.

## Architecture
- Flutter (single codebase, Play first). Local-first; zero backend for v1.
- Audio: prebaked ElevenLabs coach clips bundled as assets (record once at build time — near-zero runtime API cost). Pitch tones via oscillator.
- Data model: Routine{id,name,exercises[]}, Exercise{id,name,durationSec,startNote,pattern,audioAsset}, Streak{date,completedRoutineIds} in shared_prefs/sqlite.
- Premium gate: additional routines + alternate coach voices via one-time IAP.

## ElevenLabs plan
Apply for ElevenLabs Startup Grant (12 mo free). Until then: $5 Starter, generate ~40 coaching clips once, cache as assets. Runtime TTS only in a later "custom routine" premium feature.

## ASO (titles the stale incumbents don't own)
- "Vocal Warm Up Coach: Singing Exercises & Pitch"
- keywords: vocal warm up, singing warm up, voice training, pitch practice, audition warm up, worship vocal, speaker voice care
- Screenshots: routine screen + piano + streak. Description leads with "guided by a real coaching voice."

## Build plan (for Opus at effortLevel xhigh)
1. Scaffold Flutter app, nav: Home(routines) / Piano / Streak / Settings.
2. Implement Exercise timer engine + audio asset playback.
3. Piano widget + tone synthesis.
4. Streak persistence.
5. IAP gate (google_play_billing).
6. Lie-detector checklist before publish: app installs clean on a physical device (cite adb log); every routine plays end-to-end (cite run video); no network calls in v1 (cite traffic log); IAP sandbox purchase verified; store listing keywords present in title+description.
