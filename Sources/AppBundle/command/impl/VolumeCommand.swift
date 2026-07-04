import AppKit
import Common

struct VolumeCommand: Command {
    let args: VolumeCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        switch args.action.val {
            case .up:
                SystemVolume.increase(by: 0.0625)
            case .down:
                SystemVolume.decrease(by: 0.0625)
            case .muteToggle:
                SystemVolume.toggleMuted()
            case .muteOn:
                SystemVolume.setMuted(true)
            case .muteOff:
                SystemVolume.setMuted(false)
            case .set(let int):
                SystemVolume.setScalar(Float(int) / 100)
        }
        return true
    }
}
