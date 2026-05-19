#!/usr/bin/env python3
"""Generate locales/messages.json — run when adding new i18n keys."""
import json
from pathlib import Path

def e(zh_hans, zh_hant, en, ja, ko):
    return {"zh-Hans": zh_hans, "zh-Hant": zh_hant, "en": en, "ja": ja, "ko": ko}

S: dict = {}

def add(key, *langs):
    S[key] = e(*langs)

# Import all keys from a module - for maintainability we'll inline in run
# This file is the generator; edit add() calls below.

add("welcome.title",
    "你打算领养这只小猫吗？", "你打算領養這隻小貓嗎？",
    "Ready to adopt this little cat?", "この子猫を迎え入れますか？", "이 고양이를 입양할까요?")
add("welcome.body",
    "每天到了约定时间，它都会住进你的电脑\n为了保证它的睡眠，你就不能使用电脑了哦",
    "每天到了約定時間，牠都會住進你的電腦\n為了保證牠的睡眠，你就不能使用電腦了哦",
    "Every day at the agreed time, it moves into your Mac.\nWhile it sleeps, you can't use the computer.",
    "約束の時間になると、この Mac に入ってきます。\nねこが眠っている間は、パソコンを使えません。",
    "약속한 시간이 되면 Mac 안으로 들어옵니다.\n고양이가 자는 동안에는 컴퓨터를 쓸 수 없어요.")
add("welcome.cta", "好想养", "好想養", "I'd love to", "迎えたい", "키우고 싶어요")
add("config.bedtime.title", "猫猫休眠时间", "貓貓休眠時間", "Cat bedtime", "ねこの就寝時間", "고양이 취침 시간")
add("config.bedtime.hint", "千万不要太晚哦，猫猫也需要一个好睡眠", "千萬不要太晚哦，貓貓也需要一個好睡眠",
    "Not too late — cats need good sleep too", "遅すぎないで。ねこにも質のいい睡眠が必要です", "너무 늦지 마세요. 고양이도 푹 자야 해요")
add("config.wakeup.title", "猫猫起床时间", "貓貓起床時間", "Cat wake-up time", "ねこの起床時間", "고양이 기상 시간")
add("config.wakeup.hint", "到这个时间后，猫猫就会离开，你可以使用电脑", "到這個時間後，貓貓就會離開，你可以使用電腦",
    "After this time the cat leaves and you can use your Mac", "この時間になるとねこは去り、Mac を使えます", "이 시간이 되면 고양이가 떠나고 Mac을 쓸 수 있어요")
add("config.days.title", "猫猫周几可以来", "貓貓週幾可以來", "Which days can the cat visit?", "ねこが来られる曜日", "고양이가 올 요일")
add("config.confirm", "确认", "確認", "Continue", "確認", "확인")
add("agreement.title", "领养协议签署", "領養協議簽署", "Adoption agreement", "迎え入れ同意", "입양 동의")
add("agreement.subtitle", "请仔细阅读并签字确认", "請仔細閱讀並簽字確認", "Please read carefully and sign", "よく読んで署名してください", "잘 읽고 서명해 주세요")
add("agreement.sleep", "猫猫睡觉", "貓貓睡覺", "Bedtime", "就寝", "취침")
add("agreement.leave", "猫猫离开", "貓貓離開", "Wake-up", "起床", "기상")
add("agreement.days", "来睡日子", "來睡日子", "Visit days", "来る曜日", "방문 요일")
add("agreement.reminder", "睡前提醒", "睡前提醒", "Wind-down reminder", "就寝前リマインダー", "취침 전 알림")
add("agreement.reminder_value", "%d 分钟", "%d 分鐘", "%d min", "%d 分", "%d분")
add("agreement.pledge_prompt", "请键入「%@」完成领养协议", "請鍵入「%@」完成領養協議",
    "Type “%@” to complete the agreement", "「%@」と入力して同意を完了", "「%@」을(를) 입력해 동의를 완료하세요")
add("agreement.pledge_placeholder", "在此键入上面的句子", "在此鍵入上面的句子", "Type the sentence above", "上の文をここに入力", "위 문장을 입력하세요")
add("agreement.confirm", "确认领养", "確認領養", "Confirm adoption", "迎え入れを確定", "입양 확정")
add("agreement.confirmed", "已确认！", "已確認！", "Confirmed!", "確認しました！", "확인했어요!")
add("agreement.wrong_final", "未正确输入，想好了再来哦～", "未正確輸入，想好了再來哦～",
    "Incorrect text. Come back when you're ready.", "入力が違います。準備ができたらまたどうぞ", "입력이 맞지 않아요. 준비되면 다시 와 주세요")
add("agreement.wrong_attempts", "输入不正确，还有 %d 次机会", "輸入不正確，還有 %d 次機會",
    "Incorrect. %d attempts left", "入力が違います。あと %d 回", "입력이 틀렸어요. %d번 남았습니다")
add("pledge.required_phrase",
    "我愿意遵守承诺让猫猫好好休息", "我願意遵守承諾讓貓貓好好休息",
    "I promise to let the cat rest well", "約束を守って、ねこをしっかり休ませます", "약속을 지켜 고양이가 푹 쉴 수 있게 하겠습니다")
add("lock_preview.playing", "正在播放锁屏效果预览", "正在播放鎖屏效果預覽", "Playing lock screen preview", "ロック画面プレビューを再生中", "잠금 화면 미리보기 재생 중")
add("dashboard.delay", "推迟", "推遲", "Delay", "延期", "연기")
add("dashboard.sleep_config", "睡眠时间配置", "睡眠時間配置", "Sleep schedule", "睡眠スケジュール", "수면 일정")
add("dashboard.sleep", "睡觉", "睡覺", "Bedtime", "就寝", "취침")
add("dashboard.wakeup", "起床", "起床", "Wake-up", "起床", "기상")
add("dashboard.weekly", "每周哪天来", "每週哪天來", "Weekly visit days", "毎週の訪問日", "매주 방문 요일")
add("dashboard.saved", "已保存！", "已儲存！", "Saved!", "保存しました！", "저장했어요!")
add("dashboard.save", "确认修改", "確認修改", "Save changes", "変更を保存", "변경 저장")
add("days.every_day", "每天", "每天", "Every day", "毎日", "매일")
add("days.weekdays", "周一到周五", "週一到週五", "Mon–Fri", "月〜金", "월–금")
add("days.none", "无", "無", "None", "なし", "없음")
add("days.list_sep", "、", "、", ", ", "、", ", ")

days_data = [
    ("一", "周一", "Mon", "Monday", "月", "月曜", "월", "월요일"),
    ("二", "周二", "Tue", "Tuesday", "火", "火曜", "화", "화요일"),
    ("三", "周三", "Wed", "Wednesday", "水", "水曜", "수", "수요일"),
    ("四", "周四", "Thu", "Thursday", "木", "木曜", "목", "목요일"),
    ("五", "周五", "Fri", "Friday", "金", "金曜", "금", "금요일"),
    ("六", "周六", "Sat", "Saturday", "土", "土曜", "토", "토요일"),
    ("日", "周日", "Sun", "Sunday", "日", "日曜", "일", "일요일"),
]
for i, (zs, zf, es, ef, js, jf, ks, kf) in enumerate(days_data, 1):
    S[f"day.short.{i}"] = e(zs, zs, es, js, ks)
    S[f"day.full.{i}"] = e(zf, zf.replace("周", "週"), ef, jf, kf)

add("delay.title", "⏰ 往后推迟时间", "⏰ 往後推遲時間", "⏰ Delay bedtime", "⏰ 就寝を延期", "⏰ 취침 연기")
add("delay.hint", "有特殊情况，请提前告知猫猫", "有特殊情況，請提前告知貓貓",
    "If something comes up, let the cat know in advance", "事情があるときは、ねこに先に伝えてください", "특별한 일이 있으면 고양이에게 미리 알려 주세요")
add("delay.reason_label", "原因（可选）", "原因（可選）", "Reason (optional)", "理由（任意）", "사유 (선택)")
add("delay.reason_placeholder", "今晚有特殊情况是因为", "今晚有特殊情況是因為", "Why tonight is special…", "今夜は特別な理由が…", "오늘 밤 특별한 이유…")
add("delay.duration_label", "推迟多久", "推遲多久", "Delay by", "どれくらい延期", "얼마나 연기할까요")
add("delay.15min", "15 分钟", "15 分鐘", "15 min", "15 分", "15분")
add("delay.30min", "30 分钟", "30 分鐘", "30 min", "30 分", "30분")
add("delay.custom", "自定义", "自訂", "Custom", "カスタム", "직접 입력")
add("delay.postpone", "推迟", "推遲", "Delay", "延期", "연기")
add("delay.minutes", "分钟", "分鐘", "min", "分", "분")
add("delay.cancel", "取消", "取消", "Cancel", "キャンセル", "취소")
add("delay.submit", "告知猫猫", "告知貓貓", "Tell the cat", "ねこに伝える", "고양이에게 알리기")
add("delay.default_reason", "推迟%d分钟", "推遲%d分鐘", "Delayed %d minutes", "%d 分延期", "%d분 연기")
add("quit.title", "确定要退出 Cat Bedtime 吗？", "確定要退出 Cat Bedtime 嗎？", "Quit Cat Bedtime?", "Cat Bedtime を終了しますか？", "Cat Bedtime를 종료할까요?")
add("quit.message",
    "退出只会关闭设置窗口\n睡眠时间和后台定时任务会继续保留，到点仍会锁屏",
    "退出只會關閉設定視窗\n睡眠時間和背景定時任務會繼續保留，到點仍會鎖屏",
    "Only the settings window closes.\nYour schedule and background tasks keep running — lock screen still activates on time.",
    "設定ウィンドウだけが閉じます。\nスケジュールとバックグラウンド処理は続き、時間になるとロックされます。",
    "설정 창만 닫힙니다.\n일정과 백그라운드 작업은 계속되며, 시간이 되면 잠금 화면이 켜집니다.")
add("quit.confirm", "退出", "退出", "Quit", "終了", "종료")
add("quit.cancel", "取消", "取消", "Cancel", "キャンセル", "취소")
add("menu.quit", "退出 Cat Bedtime", "退出 Cat Bedtime", "Quit Cat Bedtime", "Cat Bedtime を終了", "Cat Bedtime 종료")
add("lock.quote", "嘘，猫猫睡了，安静", "噓，貓貓睡了，安靜", "Shh — the cat is asleep. Quiet, please.", "しっ、ねこが寝てる。静かに", "쉿, 고양이가 자고 있어요. 조용히")
add("lock.countdown_hours", "还有 %d 小时 %d 分钟醒来", "還有 %d 小時 %d 分鐘醒來", "Wakes in %d h %d min", "あと %d 時間 %d 分で起きる", "%d시간 %d분 후에 일어나요")
add("lock.countdown_minutes", "还有 %d 分钟醒来", "還有 %d 分鐘醒來", "Wakes in %d min", "あと %d 分で起きる", "%d분 후에 일어나요")
add("lock.wakeup_line", "猫猫 %@ 起床 · %@", "貓貓 %@ 起床 · %@", "Cat wakes at %@ · %@", "ねこ %@ 起床 · %@", "고양이 %@ 기상 · %@")
add("lock.missing_asset",
    "缺少猫猫动画素材\n~/.timetosleep/assets/cat-bedtime.mov",
    "缺少貓貓動畫素材\n~/.timetosleep/assets/cat-bedtime.mov",
    "Missing cat animation\n~/.timetosleep/assets/cat-bedtime.mov",
    "ねこのアニメ素材がありません\n~/.timetosleep/assets/cat-bedtime.mov",
    "고양이 애니메이션 없음\n~/.timetosleep/assets/cat-bedtime.mov")
add("lock.esc_hint",
    "异常时连按两下 ESC：重新校验时间，非锁机时段可退出",
    "異常時連按兩下 ESC：重新校驗時間，非鎖機時段可退出",
    "If something's wrong, double-press ESC to re-check time; exit when lock isn't active",
    "異常時は ESC を2回：時刻を再確認。ロック時間外なら終了できます",
    "문제가 있으면 ESC 두 번: 시간 재확인. 잠금 시간이 아니면 종료 가능")
add("notify.winddown.title", "🐾  猫猫开始打哈欠了", "🐾  貓貓開始打哈欠了", "🐾  The cat is getting sleepy", "🐾  ねこがあくびを始めました", "🐾  고양이가 하품하기 시작했어요")
add("notify.winddown.subtitle", "还有 %d 分钟到关灯", "還有 %d 分鐘到關燈", "%d minutes until lights out", "消灯まであと %d 分", "불 끄기까지 %d분")
add("notify.winddown.body", "收尾这一小段就好", "收尾這一小段就好", "Just wrap up this bit", "このあたりを片づけましょう", "이 정도만 마무리해요")
add("notify.winddown.button", "知道啦", "知道啦", "Got it", "わかった", "알겠어요")
add("notify.locksoon.title", "💤  它要去拉灯绳了", "💤  牠要去拉燈繩了", "💤  It's pulling the lamp cord", "💤  消灯のひもを引きに行きます", "💤  불 끄러 가요")
add("notify.locksoon.subtitle", "一分钟后锁屏", "一分鐘後鎖屏", "Lock screen in one minute", "1 分後にロック", "1분 후 잠금")
add("notify.locksoon.body", "手头的按个保存就好，今天到这", "手頭的按個保存就好，今天到這",
    "Save what you're doing — that's enough for today", "手元の作業を保存して、今日はここまで", "하고 있던 건 저장하고, 오늘은 여기까지")
add("notify.locksoon.button", "好", "好", "OK", "OK", "좋아요")

# CLI keys (abbreviated - full set)
cli_keys = [
    ("cli.not_configured", "还没有领养猫猫。运行 zzz init 开始", "還沒有領養貓貓。執行 zzz init 開始", "No cat adopted yet. Run zzz init to start", "まだねこを迎えていません。zzz init を実行", "아직 고양이를 입양하지 않았어요. zzz init 실행"),
    ("cli.yes", "是", "是", "Yes", "はい", "예"),
    ("cli.no", "否", "否", "No", "いいえ", "아니오"),
    ("cli.eta_hours", "%d 小时 %d 分钟", "%d 小時 %d 分鐘", "%d h %d min", "%d 時間 %d 分", "%d시간 %d분"),
    ("cli.eta_minutes", "%d 分钟", "%d 分鐘", "%d min", "%d 分", "%d분"),
    ("cli.skipped.title", "猫猫今晚不来睡觉了", "貓貓今晚不來睡覺了", "The cat isn't sleeping here tonight", "今夜はねこが来ません", "오늘 밤 고양이는 안 와요"),
    ("cli.skipped.note", "它已经收到你的留言了", "牠已經收到你的留言了", "It got your message", "あなたの伝言は届きました", "당신의 메시지를 받았어요"),
    ("cli.skipped.tomorrow", "明天 %s 再看日程", "明天 %s 再看日程", "Check again tomorrow at %s", "明日 %s にまた確認", "내일 %s에 다시 확인"),
    ("cli.tonight.title", "猫猫今晚 %s 睡觉", "貓貓今晚 %s 睡覺", "Cat sleeps at %s tonight", "今夜のねこの就寝は %s", "오늘 밤 고양이 취침 %s"),
    ("cli.tonight.until", "离猫猫睡觉还有 %s", "離貓貓睡覺還有 %s", "%s until cat bedtime", "就寝まであと %s", "취침까지 %s"),
    ("cli.tonight.remind", "提前 %s 分钟提醒你准备", "提前 %s 分鐘提醒你準備", "Reminder %s min before", "%s 分前にリマインド", "%s분 전에 알림"),
    ("cli.tonight.wakeup", "猫猫早上 %s 走", "貓貓早上 %s 走", "Cat leaves at %s", "ねこは朝 %s に去ります", "고양이는 아침 %s에 떠나요"),
    ("cli.off_day", "猫猫今天不用来睡觉，放松吧", "貓貓今天不用來睡覺，放鬆吧", "No cat visit today — relax", "今日はねこは来ません。のんびりどうぞ", "오늘은 고양이가 안 와요. 편히 쉬세요"),
    ("cli.off_day.hint", "来住日子请查看 zzz config", "來住日子請查看 zzz config", "See visit days: zzz config", "訪問日: zzz config", "방문 요일: zzz config"),
    ("cli.already_asleep", "猫猫今晚已经睡下了", "貓貓今晚已經睡下了", "The cat is already asleep tonight", "今夜のねこはもう寝ています", "오늘 밤 고양이는 이미 잤어요"),
    ("cli.tomorrow", "明天 %s 再来", "明天 %s 再來", "Back tomorrow at %s", "明日 %s にまた", "내일 %s에 다시"),
    ("cli.stats.title", "猫猫记录", "貓貓記錄", "Cat log", "ねこの記録", "고양이 기록"),
    ("cli.stats.total", "总晚数", "總晚數", "Total nights", "合計夜数", "총 밤"),
    ("cli.stats.came", "来过", "來過", "Visited", "来た", "방문"),
    ("cli.stats.skipped", "没来", "沒來", "Skipped", "来なかった", "미방문"),
    ("cli.stats.rate", "来访率", "來訪率", "Visit rate", "来訪率", "방문률"),
    ("cli.config.not_configured", "还没有配置。运行 zzz init", "還沒有設定。執行 zzz init", "Not configured. Run zzz init", "未設定です。zzz init を実行", "설정 없음. zzz init 실행"),
    ("cli.config.header", "当前设置", "目前設定", "Current settings", "現在の設定", "현재 설정"),
    ("cli.config.bedtime", "猫猫睡觉", "貓貓睡覺", "Bedtime", "就寝", "취침"),
    ("cli.config.wakeup", "猫猫离开", "貓貓離開", "Wake-up", "起床", "기상"),
    ("cli.config.days", "猫猫来住的日子", "貓貓來住的日子", "Visit days", "来る曜日", "방문 요일"),
    ("cli.config.winddown", "睡前提醒", "睡前提醒", "Wind-down", "就寝前", "취침 전 알림"),
    ("cli.config.winddown_value", "%s 分钟", "%s 分鐘", "%s min", "%s 分", "%s분"),
    ("cli.config.hint", "修改: zzz config <key> <value>", "修改: zzz config <key> <value>", "Change: zzz config <key> <value>", "変更: zzz config <key> <value>", "변경: zzz config <key> <value>"),
    ("cli.config.keys", "可用 key: bedtime, wakeup, winddown", "可用 key: bedtime, wakeup, winddown", "Keys: bedtime, wakeup, winddown", "キー: bedtime, wakeup, winddown", "키: bedtime, wakeup, winddown"),
    ("cli.error.time_format", "格式错误，请用 HH:MM（如 23:00）", "格式錯誤，請用 HH:MM（如 23:00）", "Invalid format. Use HH:MM (e.g. 23:00)", "形式が違います。HH:MM（例 23:00）", "형식 오류. HH:MM (예: 23:00)"),
    ("cli.success.bedtime", "猫猫睡觉时间已更新为 %s", "貓貓睡覺時間已更新為 %s", "Bedtime updated to %s", "就寝を %s に更新", "취침 시간 %s로 변경"),
    ("cli.success.wakeup", "猫猫离开时间已更新为 %s", "貓貓離開時間已更新為 %s", "Wake-up updated to %s", "起床を %s に更新", "기상 시간 %s로 변경"),
    ("cli.error.winddown_range", "请输入 5-120 之间的分钟数", "請輸入 5-120 之間的分鐘數", "Enter minutes between 5 and 120", "5〜120 の分を入力", "5–120 사이 분을 입력"),
    ("cli.success.winddown", "会提前 %s 分钟提醒你准备让猫猫睡觉", "會提前 %s 分鐘提醒你準備讓貓貓睡覺",
     "You'll be reminded %s min before cat bedtime", "就寝 %s 分前にリマインドします", "취침 %s분 전에 알림"),
    ("cli.error.unknown_key", "未知设置: %s", "未知設定: %s", "Unknown setting: %s", "不明な設定: %s", "알 수 없는 설정: %s"),
    ("cli.error.unknown_keys", "可用: bedtime, wakeup, winddown", "可用: bedtime, wakeup, winddown", "Available: bedtime, wakeup, winddown", "利用可能: bedtime, wakeup, winddown", "사용 가능: bedtime, wakeup, winddown"),
    ("cli.tonight.warn", "今晚不让猫猫来睡觉吗？", "今晚不讓貓貓來睡覺嗎？", "Skip the cat's visit tonight?", "今夜はねこを来させませんか？", "오늘 밤 고양이를 안 부를까요?"),
    ("cli.tonight.ask_reason", "跟猫猫说一声为什么今晚不来？", "跟貓貓說一聲為什麼今晚不來？", "Tell the cat why tonight is off", "今夜来ない理由をねこに伝えて", "오늘 안 오는 이유를 고양이에게"),
    ("cli.tonight.need_reason", "需要跟猫猫说一声才能跳过", "需要跟貓貓說一聲才能跳過", "You need to tell the cat why to skip", "スキップするには理由が必要です", "건너뛰려면 이유를 말해야 해요"),
    ("cli.tonight.skipped", "今晚猫猫不会来睡觉了（原因: %s）", "今晚貓貓不會來睡覺了（原因: %s）", "Cat won't visit tonight (reason: %s)", "今夜は来ません（理由: %s）", "오늘 밤 안 옵니다 (사유: %s)"),
    ("cli.error.tonight_usage", "用法: zzz tonight off", "用法: zzz tonight off", "Usage: zzz tonight off", "使い方: zzz tonight off", "사용법: zzz tonight off"),
    ("cli.error.unknown_action", "未知操作: %s", "未知操作: %s", "Unknown action: %s", "不明な操作: %s", "알 수 없는 작업: %s"),
    ("cli.log.header", "历史记录", "歷史記錄", "History", "履歴", "기록"),
    ("cli.log.empty", "还没有记录", "還沒有記錄", "No records yet", "まだ記録がありません", "기록 없음"),
    ("cli.log.came", "猫猫来过了", "貓貓來過了", "Cat visited", "ねこが来ました", "고양이가 왔어요"),
    ("cli.log.skipped", "猫猫没来", "貓貓沒來", "Cat skipped", "ねこは来ませんでした", "고양이 안 옴"),
    ("cli.error.too_many_args", "参数太多", "參數太多", "Too many arguments", "引数が多すぎます", "인수가 너무 많음"),
    ("cli.error.test_usage", "用法: zzz test [seconds]", "用法: zzz test [seconds]", "Usage: zzz test [seconds]", "使い方: zzz test [seconds]", "사용법: zzz test [seconds]"),
    ("cli.error.test_seconds", "测试秒数需要是 1-120 之间的数字", "測試秒數需要是 1-120 之間的數字", "Seconds must be 1–120", "秒数は 1〜120", "초는 1–120"),
    ("cli.error.overlay_missing", "找不到锁屏程序，请先运行 install.sh", "找不到鎖屏程式，請先執行 install.sh",
     "Lock screen binary not found. Run install.sh", "ロック画面が見つかりません。install.sh を実行", "잠금 화면 없음. install.sh 실행"),
    ("cli.test.running", "测试锁屏覆盖层（%s 秒后自动退出）...", "測試鎖屏覆蓋層（%s 秒後自動退出）...",
     "Testing lock overlay (%s s)…", "ロック画面をテスト（%s 秒）…", "잠금 화면 테스트 (%s초)…"),
    ("cli.test.done", "测试完成", "測試完成", "Test complete", "テスト完了", "테스트 완료"),
    ("cli.uninstall.stats_title", "你和猫猫的日子", "你和貓貓的日子", "Your time with the cat", "あなたとねこの日々", "고양이와 함께한 날"),
    ("cli.uninstall.nights", "相处晚数  %s 晚", "相處晚數  %s 晚", "Nights together  %s", "一緒の夜  %s", "함께한 밤  %s"),
    ("cli.uninstall.visits", "来过次数  %s / %s", "來過次數  %s / %s", "Visits  %s / %s", "来訪  %s / %s", "방문  %s / %s"),
    ("cli.uninstall.streak", "连续来住  %s 晚", "連續來住  %s 晚", "Streak  %s nights", "連続 %s 夜", "연속 %s밤"),
    ("cli.uninstall.confirm_prompt", "确定要卸载吗？请输入：", "確定要解除安裝嗎？請輸入：", "Uninstall? Type:", "アンインストールしますか？入力:", "제거할까요? 입력:"),
    ("cli.uninstall.confirm_phrase", "送走猫猫", "送走貓貓", "goodbye cat", "さようならねこ", "고양이 안녕"),
    ("cli.uninstall.cancelled", "卸载已取消", "解除安裝已取消", "Uninstall cancelled", "キャンセルしました", "제거 취소"),
    ("cli.uninstall.step.schedule", "移除定时任务...", "移除定時任務...", "Removing schedule…", "スケジュールを削除…", "일정 제거 중…"),
    ("cli.uninstall.step.config", "清理配置文件...", "清理設定檔...", "Cleaning config…", "設定を削除…", "설정 정리 중…"),
    ("cli.uninstall.step.command", "移除命令...", "移除命令...", "Removing command…", "コマンドを削除…", "명령 제거 중…"),
    ("cli.uninstall.done", "已完全卸载", "已完全解除安裝", "Fully uninstalled", "アンインストール完了", "완전히 제거됨"),
    ("cli.uninstall.farewell", "猫猫带着行李走了。它会记得你的", "貓貓帶著行李走了。牠會記得你的",
     "The cat packed its bags. It will remember you.", "ねこは荷物を持って去りました。また覚えています", "고양이가 짐을 들고 떠났어요. 당신을 기억할 거예요"),
    ("cli.help.usage", "用法", "用法", "Usage", "使い方", "사용법"),
    ("cli.help.default", "今晚猫猫状态", "今晚貓貓狀態", "Tonight's cat status", "今夜のねこ状態", "오늘 밤 고양이 상태"),
    ("cli.help.init", "领养 / 重新设置", "領養 / 重新設定", "Adopt / reconfigure", "迎え入れ / 再設定", "입양 / 재설정"),
    ("cli.help.status", "猫猫到访记录", "貓貓到訪記錄", "Visit history", "訪問記録", "방문 기록"),
    ("cli.help.config", "查看猫猫日程", "查看貓貓日程", "View schedule", "スケジュール表示", "일정 보기"),
    ("cli.help.config_edit", "修改猫猫日程", "修改貓貓日程", "Edit schedule", "スケジュール変更", "일정 수정"),
    ("cli.help.tonight", "今晚不让猫猫来睡觉", "今晚不讓貓貓來睡覺", "Skip cat tonight", "今夜はねこを休む", "오늘 밤 고양이 쉬기"),
    ("cli.help.log", "猫猫来访历史", "貓貓來訪歷史", "Visit log", "来訪履歴", "방문 기록"),
    ("cli.help.test", "测试锁屏（默认 10 秒）", "測試鎖屏（預設 10 秒）", "Test lock screen (default 10s)", "ロック画面テスト（既定10秒）", "잠금 테스트 (기본 10초)"),
    ("cli.help.uninstall", "卸载", "解除安裝", "Uninstall", "アンインストール", "제거"),
    ("cli.help.help", "显示帮助", "顯示說明", "Show help", "ヘルプ", "도움말"),
    ("cli.error.unknown_command", "未知命令: %s", "未知命令: %s", "Unknown command: %s", "不明なコマンド: %s", "알 수 없는 명령: %s"),
    ("cli.error.not_installed",
     "Error: Cat Bedtime is not properly installed.\nRun install.sh first or check your installation.",
     "Error: Cat Bedtime is not properly installed.\nRun install.sh first or check your installation.",
     "Error: Cat Bedtime is not properly installed.\nRun install.sh first or check your installation.",
     "Error: Cat Bedtime が正しくインストールされていません。\ninstall.sh を実行してください。",
     "Error: Cat Bedtime가 올바르게 설치되지 않았습니다.\ninstall.sh를 실행하세요."),
]
for row in cli_keys:
    add(row[0], *row[1:])

init_keys = [
    ("init.welcome.line1", "每天到了约定时间，", "每天到了約定時間，", "Every day at the agreed time,", "約束の時間になると、", "약속한 시간이 되면,"),
    ("init.welcome.line2", "它都会住进你的电脑", "牠都會住進你的電腦", "it moves into your Mac", "この Mac に入ってきます", "Mac 안으로 들어옵니다"),
    ("init.welcome.line3", "为了保证它的睡眠，", "為了保證牠的睡眠，", "While it sleeps,", "ねこが眠っている間は、", "고양이가 자는 동안"),
    ("init.welcome.line4", "你就不能使用电脑了哦", "你就不能使用電腦了哦", "you can't use the computer", "パソコンを使えません", "컴퓨터를 쓸 수 없어요"),
    ("init.bedtime.prompt", "猫猫几点才能睡觉？", "貓貓幾點才能睡覺？", "What time should the cat sleep?", "ねこは何時に寝ますか？", "고양이는 몇 시에 자나요?"),
    ("init.wakeup.prompt", "猫猫早上几点走？", "貓貓早上幾點走？", "What time does the cat leave?", "ねこは朝何時に去りますか？", "고양이는 아침 몇 시에 가나요?"),
    ("init.days.prompt", "猫猫每周几可以来睡觉？", "貓貓每週幾可以來睡覺？", "Which nights can the cat visit?", "週の何曜日に来られますか？", "매주 어느 날 올 수 있나요?"),
    ("init.days.hint", "其他日子猫猫自己在外面浪", "其他日子貓貓自己在外面浪", "Other nights the cat roams free", "それ以外の夜はねこは自由です", "다른 날은 고양이가 자유롭게 놀아요"),
    ("init.contract.title", "领养协议", "領養協議", "Adoption agreement", "迎え入れ同意", "입양 동의"),
    ("init.contract.sleep", "  猫猫睡觉：%s    猫猫离开：%s", "  貓貓睡覺：%s    貓貓離開：%s", "  Bedtime: %s    Wake-up: %s", "  就寝: %s    起床: %s", "  취침: %s    기상: %s"),
    ("init.contract.days", "  来睡日子：%s", "  來睡日子：%s", "  Visit days: %s", "  来る曜日: %s", "  방문 요일: %s"),
    ("init.contract.remind", "  睡前 %s 分钟和 %s 分钟会提醒你", "  睡前 %s 分鐘和 %s 分鐘會提醒你",
     "  Reminders %s and %s min before bed", "  就寝 %s 分前と %s 分前に通知", "  취침 %s분·%s분 전 알림"),
    ("init.pledge_prompt", "最后一步：请键入下面这句完成领养协议：", "最後一步：請鍵入下面這句完成領養協議：",
     "Last step — type this sentence:", "最後に、この文を入力:", "마지막 — 아래 문장을 입력:"),
    ("init.cancelled", "未正确输入，设置已取消", "未正確輸入，設定已取消", "Incorrect text. Setup cancelled.", "入力が違います。設定を中止しました", "입력 오류. 설정 취소"),
    ("init.retry", "想好了再来：zzz init", "想好了再來：zzz init", "When ready: zzz init", "準備ができたら: zzz init", "준비되면: zzz init"),
    ("init.schedule_ok", "定时任务已激活", "定時任務已啟用", "Schedule activated", "スケジュールを有効化", "일정 활성화됨"),
    ("init.done.title", "领养完成！", "領養完成！", "Adoption complete!", "迎え入れ完了！", "입양 완료!"),
    ("init.done.line1", "猫猫已经记住你家地址了", "貓貓已經記住你家地址了", "The cat knows where you live now", "ねこはあなたの家を覚えました", "고양이가 집 주소를 기억했어요"),
    ("init.done.line2", "今晚 %s，它会住进你的电脑睡觉", "今晚 %s，牠會住進你的電腦睡覺", "Tonight at %s it moves in to sleep", "今夜 %s に Mac で寝ます", "오늘 밤 %s에 Mac에서 잠"),
    ("init.done.line3", "睡前 %s 分钟和 %s 分钟会提醒你", "睡前 %s 分鐘和 %s 分鐘會提醒你",
     "Reminders %s and %s min before bed", "就寝 %s・%s 分前に通知", "취침 %s·%s분 전 알림"),
    ("init.done.hint", "输入 zzz 查看今晚状态", "輸入 zzz 查看今晚狀態", "Run zzz for tonight's status", "zzz で今夜の状態を確認", "zzz 로 오늘 상태 확인"),
]
for row in init_keys:
    add(row[0], *row[1:])

ui_keys = [
    ("ui.error.time_parse",
     "没听懂这个时间，试试这些写法：23、23:00、23点、23点半、11pm",
     "沒聽懂這個時間，試試這些寫法：23、23:00、23點、23點半、11pm",
     "Couldn't parse that time. Try: 23, 23:00, 11pm", "時刻が分かりません。23、23:00、11pm など", "시간을 이해하지 못했어요. 23, 23:00, 11pm 등"),
    ("ui.multiselect.hint", "(空格切换, 回车确认)", "(空格切換, Enter確認)", "(space toggle, enter confirm)", "(Spaceで切替、Enterで確定)", "(스페이스 전환, Enter 확인)"),
    ("ui.select.hint", "(↑↓选择, 回车确认)", "(↑↓選擇, Enter確認)", "(↑↓ select, enter confirm)", "(↑↓で選択、Enterで確定)", "(↑↓ 선택, Enter 확인)"),
    ("ui.selected", "已选：%s", "已選：%s", "Selected: %s", "選択: %s", "선택: %s"),
    ("ui.retry", "再试一次（第 %s/%s 次）", "再試一次（第 %s/%s 次）", "Try again (%s/%s)", "再試行 (%s/%s)", "다시 시도 (%s/%s)"),
    ("ui.type_confirm.prompt", "请输入：", "請輸入：", "Type:", "入力:", "입력:"),
    ("ui.type_confirm.mismatch", "输入不匹配，请完整输入上面的确认文字", "輸入不匹配，請完整輸入上面的確認文字",
     "Text doesn't match. Type the full confirmation.", "一致しません。全文を入力してください", "일치하지 않아요. 전체 문장을 입력하세요"),
]
for row in ui_keys:
    add(row[0], *row[1:])

install_keys = [
    ("install.title", "安装 Cat Bedtime", "安裝 Cat Bedtime", "Install Cat Bedtime", "Cat Bedtime をインストール", "Cat Bedtime 설치"),
    ("install.step.check", "检查环境...", "檢查環境...", "Checking environment…", "環境を確認…", "환경 확인 중…"),
    ("install.error.macos", "Cat Bedtime 目前只支持 macOS", "Cat Bedtime 目前只支援 macOS", "Cat Bedtime only supports macOS", "Cat Bedtime は macOS のみ対応", "Cat Bedtime는 macOS만 지원"),
    ("install.error.python", "需要 Python 3（macOS 通常自带）", "需要 Python 3（macOS 通常內建）", "Python 3 required (usually preinstalled on macOS)", "Python 3 が必要です", "Python 3 필요"),
    ("install.check_ok", "环境检查通过", "環境檢查通過", "Environment OK", "環境 OK", "환경 확인 완료"),
    ("install.step.dir", "创建安装目录...", "建立安裝目錄...", "Creating install directory…", "インストール先を作成…", "설치 디렉터리 생성…"),
    ("install.step.files", "安装文件...", "安裝檔案...", "Installing files…", "ファイルをインストール…", "파일 설치 중…"),
    ("install.step.link", "创建 zzz 命令...", "建立 zzz 命令...", "Creating zzz command…", "zzz コマンドを作成…", "zzz 명령 생성…"),
    ("install.linked", "已安装到 /usr/local/bin/zzz", "已安裝到 /usr/local/bin/zzz", "Installed to /usr/local/bin/zzz", "/usr/local/bin/zzz にインストール", "/usr/local/bin/zzz에 설치됨"),
    ("install.path_added", "已添加到 PATH（重启终端或 source ~/.zshrc 生效）", "已加入 PATH（重啟終端或 source ~/.zshrc）",
     "Added to PATH (restart terminal or source ~/.zshrc)", "PATH に追加（ターミナル再起動または source ~/.zshrc）", "PATH 추가됨 (터미널 재시작 또는 source ~/.zshrc)"),
    ("install.done.title", "安装完成！", "安裝完成！", "Installation complete!", "インストール完了！", "설치 완료!"),
    ("install.done.next", "即将进入猫猫领养设置...", "即將進入貓貓領養設定...", "Starting cat adoption setup…", "ねこの迎え入れ設定を開始…", "고양이 입양 설정을 시작합니다…"),
]
for row in install_keys:
    add(row[0], *row[1:])

catalog = {"version": 1, "supported": ["zh-Hans", "zh-Hant", "en", "ja", "ko"], "strings": S}
out = Path(__file__).resolve().parent.parent / "locales" / "messages.json"
out.parent.mkdir(parents=True, exist_ok=True)
with out.open("w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)
print(f"Wrote {out} ({len(S)} keys)")
