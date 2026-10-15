import ModelWidgetCore
import SwiftUI

/// Gear-menu items for idle-hide: the threshold picker and the last time it fired.
struct IdleHideMenuItems: View {
    @AppStorage(IdleHidePolicy.defaultsKey) private var idleHideMinutes = IdleHidePolicy.defaultMinutes
    @AppStorage(IdleHideRecord.defaultsKey) private var lastIdleHide: String?

    var body: some View {
        Picker("Hide apps when idle", selection: $idleHideMinutes) {
            ForEach(IdleHidePolicy.pickerChoices(including: idleHideMinutes), id: \.self) { minutes in
                Text(IdleHidePolicy.choiceTitle(minutes)).tag(minutes)
            }
        }
        Text(IdleHideRecord.menuLabel(IdleHideRecord.decode(lastIdleHide), now: Date()))
    }
}
