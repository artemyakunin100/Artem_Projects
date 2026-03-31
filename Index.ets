import media from '@ohos.multimedia.media'
import common from '@ohos.app.ability.common'

@Entry
@Component
struct Metronome {

  @State bpm: number = 120
  @State isPlaying: boolean = false
  @State currentBeat: number = 0
  @State beatsPerMeasure: number = 4
  private intervalId: number = -1
  private avPlayer: media.AVPlayer | null = null

  async aboutToAppear() {
    const context = getContext(this) as common.UIAbilityContext
    this.avPlayer = await media.createAVPlayer()
    const fileDescriptor = await context.resourceManager.getRawFd('freesound_community-metronome-85688.mp3')
    this.avPlayer.fdSrc = fileDescriptor
    // When playback finishes, seek back to start so it's ready for next tick
    this.avPlayer.on('stateChange', (state: string) => {
      if (state === 'completed' && this.avPlayer) {
        this.avPlayer.seek(0)
      }
    })
    await this.avPlayer.prepare()
  }

  playBeep() {
    if (this.avPlayer) {
      this.avPlayer.play()
    }
  }

  startStop() {
    if (this.isPlaying) {
      clearInterval(this.intervalId)
      this.isPlaying = false
      this.currentBeat = 0
    } else {
      this.isPlaying = true
      const interval = Math.round(60000 / this.bpm)
      this.intervalId = setInterval(() => {
        this.currentBeat = (this.currentBeat + 1) % this.beatsPerMeasure
        this.playBeep()
      }, interval)
    }
  }

  changeBpm(newBpm: number) {
    this.bpm = newBpm
    if (this.isPlaying) {
      clearInterval(this.intervalId)
      const interval = Math.round(60000 / this.bpm)
      this.intervalId = setInterval(() => {
        this.currentBeat = (this.currentBeat + 1) % this.beatsPerMeasure
        this.playBeep()
      }, interval)
    }
  }

  changeTimeSignature(beats: number) {
    this.beatsPerMeasure = beats
    this.currentBeat = 0
  }

  build() {
    Column({ space: 32 }) {

      Text('Metronome')
        .fontSize(36)
        .fontWeight(FontWeight.Bold)
        .fontColor('#212121')

      Text(`${this.bpm} BPM`)
        .fontSize(48)
        .fontWeight(FontWeight.Bold)
        .fontColor('#E53935')

      Row({ space: 12 }) {
        ForEach([0,1,2,3,4,5,6,7].slice(0, this.beatsPerMeasure), (i: number) => {
          Column()
            .width(32)
            .height(32)
            .borderRadius(16)
            .backgroundColor(this.isPlaying && this.currentBeat === i ? '#E53935' : '#E0E0E0')
        }, (i: number) => i.toString())
      }

      Column({ space: 8 }) {
        Text('Tempo')
          .fontSize(14)
          .fontColor('#9E9E9E')
        Slider({
          value: this.bpm,
          min: 40,
          max: 240,
          step: 1,
          style: SliderStyle.OutSet
        })
          .width(300)
          .trackColor('#E0E0E0')
          .selectedColor('#E53935')
          .onChange((value: number) => {
            this.changeBpm(Math.round(value))
          })
      }

      Column({ space: 8 }) {
        Text('Time Signature')
          .fontSize(14)
          .fontColor('#9E9E9E')
        Row({ space: 12 }) {
          ForEach([2, 3, 4, 6], (beats: number) => {
            Button(`${beats}/4`)
              .width(64)
              .height(40)
              .fontSize(14)
              .borderRadius(20)
              .backgroundColor(this.beatsPerMeasure === beats ? '#E53935' : '#F5F5F5')
              .fontColor(this.beatsPerMeasure === beats ? Color.White : '#212121')
              .onClick(() => this.changeTimeSignature(beats))
          }, (beats: number) => beats.toString())
        }
      }

      Button(this.isPlaying ? 'Stop' : 'Start')
        .width(160)
        .height(56)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .borderRadius(28)
        .backgroundColor(this.isPlaying ? '#212121' : '#E53935')
        .fontColor(Color.White)
        .onClick(() => this.startStop())

    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.White)
  }
}