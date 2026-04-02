First attempt to make metronome app

# Changes Log

This document describes the changes made to `entry/src/main/ets/pages/Index.ets` to get `click.mp3` playing reliably on every beat.

## Problem 1 — `click.mp3` did not play

### Original approach: `AVPlayer`

The first version used `media.AVPlayer` from `@ohos.multimedia.media`:

```ts
this.avPlayer = await media.createAVPlayer()
this.avPlayer.on('stateChange', (state: string) => {
  if (state === 'initialized') this.avPlayer.prepare()
  else if (state === 'completed') this.avPlayer.seek(0)
})
this.avPlayer.fdSrc = await context.resourceManager.getRawFd('rawfile/click.mp3')
```

`playBeep()` then called `this.avPlayer.play()` on every `setInterval` tick.

### Why it failed

`AVPlayer` is built for long-form media playback and exposes a strict state machine. Every `play()` triggers an asynchronous chain:

1. `play()` → state goes `prepared` → `playing`
2. clip ends → state goes `completed`
3. the `stateChange` handler calls `seek(0)` → state goes `seeking` → back to `prepared`

A second `play()` call is only valid when the player is in `prepared` or `paused`. At metronome tempos (e.g. 500 ms per beat at 120 BPM) the next tick fires while the player is still in `playing`/`completed`/`seeking`, and that `play()` is silently dropped. The first click after Start could also fail because nothing awaited the transition to `prepared` before the user could press Start.

### Fix: switch to `SoundPool`

`media.SoundPool` (also from `@ohos.multimedia.media`) is designed for short, repeatable sound effects. It loads the clip once into memory and plays via stream IDs without any per-call state machine.

```ts
import media from '@ohos.multimedia.media'
import audio from '@ohos.multimedia.audio'

private soundPool: media.SoundPool | null = null
private soundId: number = -1
private soundReady: boolean = false

async aboutToAppear() {
  const context = getContext(this) as common.UIAbilityContext
  const rendererInfo: audio.AudioRendererInfo = {
    usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
    rendererFlags: 0
  }
  this.soundPool = await media.createSoundPool(4, rendererInfo)
  this.soundPool.on('loadComplete', (loadedId: number) => {
    if (loadedId === this.soundId) this.soundReady = true
  })
  const fd = await context.resourceManager.getRawFd('rawfile/click.mp3')
  this.soundId = await this.soundPool.load(fd.fd, fd.offset, fd.length)
}

playBeep() {
  if (this.soundPool && this.soundReady) {
    this.soundPool.play(this.soundId, {
      loop: 0,
      rate: 1,
      leftVolume: 1,
      rightVolume: 1,
      priority: 1
    })
  }
}
```

Methods used and what they do:

| Call | Purpose |
| --- | --- |
| `media.createSoundPool(maxStreams, audioRendererInfo)` | Creates a pool that can play up to `maxStreams` (4 here) overlapping streams. `audioRendererInfo` tells the system this is `STREAM_USAGE_MUSIC`. |
| `soundPool.on('loadComplete', cb)` | Fires once the asset has been decoded into memory. We flip a `soundReady` flag here so we don't try to play before the load finishes. |
| `resourceManager.getRawFd('rawfile/click.mp3')` | Returns a `{ fd, offset, length }` triple pointing at the asset inside the HAP. |
| `soundPool.load(fd, offset, length)` | Decodes the asset and returns a `soundId` we play later. |
| `soundPool.play(soundId, params)` | Plays an instance of the loaded sound. Each call returns a fresh stream ID and does not block or alter the player's "state" — that's why repeated calls actually fire. `loop: 0` = play once, `rate: 1` = normal speed, volumes 1, `priority: 1`. |
| `soundPool.release()` (in `aboutToDisappear`) | Frees native audio resources when the page is destroyed. The original `AVPlayer` version leaked. |

#### Tried and removed: `parallelPlayFlag`

I initially included `parallelPlayFlag: true` in the `play` parameters so consecutive clicks could overlap if the previous one hadn't finished. The compiler rejected it:

```
'parallelPlayFlag' does not exist in type 'PlayParameters'
```

That field requires API level 12+. Removed it. With 4 stream slots in the pool, consecutive plays already use separate streams, so behavior at metronome tempos is effectively the same. If we later raise `compileSdkVersion` to 12+ we can add the flag back.

## Problem 2 — first beat was silent

After switching to `SoundPool`, the click played from beat 2 onwards but the first beat was silent.

### Cause

`setInterval(cb, ms)` does **not** invoke `cb` at t=0 — it waits one full interval, then calls it. The original `startStop` only scheduled the interval:

```ts
this.intervalId = setInterval(() => {
  this.currentBeat = (this.currentBeat + 1) % this.beatsPerMeasure
  this.playBeep()
}, interval)
```

So pressing Start highlighted beat 0 immediately (because `currentBeat` defaults to 0 and `isPlaying` flipped true), but `playBeep` didn't run until the first interval tick — at which point `currentBeat` had already advanced to 1.

### Fix

Call `playBeep()` once synchronously when Start is pressed, then schedule the interval for subsequent beats:

```ts
this.isPlaying = true
this.currentBeat = 0
this.playBeep()                    // beat 1 — fires immediately
this.intervalId = setInterval(() => {
  this.currentBeat = (this.currentBeat + 1) % this.beatsPerMeasure
  this.playBeep()                  // beats 2..N
}, interval)
```

## Resource cleanup

Added `aboutToDisappear` to clear the interval and release the sound pool when the page is destroyed:

```ts
async aboutToDisappear() {
  if (this.intervalId !== -1) {
    clearInterval(this.intervalId)
    this.intervalId = -1
  }
  if (this.soundPool) {
    await this.soundPool.release()
    this.soundPool = null
  }
}
```

## Summary of files touched

- `entry/src/main/ets/pages/Index.ets` — replaced `AVPlayer` with `SoundPool`, added `loadComplete` gate, added immediate first-beat playback in `startStop`, added `aboutToDisappear` cleanup.
