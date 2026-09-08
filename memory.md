# memory.md — 项目实现备忘录

> 目的：记录本项目所有实现方式。新会话先读本文件，避免重复探索代码。
> **每次改完代码必须顺手更新本文件**（变更点 + 行号区间 + 版本号）。
> 最后更新：v1.4.0 课件文件功能。

## 一、项目概览
- 纯静态 PWA 课程表/日历提醒应用，**无后端**，部署 GitHub Pages：https://deliciouskfc.github.io/calendar-reminder/
- git push main → 自动上线。后台任务由 GitHub Actions 承担（提醒推送、APK 构建）
- 电脑端 = index.html，手机端 = mobile.html（两页完全独立、各自内联 JS/CSS，改功能需同步改两处）
- 浏览器数据存 localStorage，**不跨设备同步**；schedule.json 是给提醒脚本用的仓库端副本（手动维护，与网页不联动）

## 二、文件清单
| 文件 | 作用 |
|---|---|
| index.html | 电脑端单页（月历 + 事件列表 + 校历） |
| mobile.html | 手机端单页（月历 + 周课表 + 加退课 + 拖拽 + 底部弹窗） |
| sw.js | Service Worker，`CACHE = 'calendar-vN'`，**每次发版 +1**，自动删旧缓存 |
| version.json | `{version, versionCode, downloadUrl, updateLog, forceUpdate}`，应用内检查更新 |
| check.py | 服务端提醒脚本：读 schedule.json，30 分钟内开始的课程/事件 → WxPusher 微信推送 |
| schedule.json | 提醒脚本用课表副本（手动维护，与网页 localStorage 不联动） |
| .github/workflows/notify.yml | cron `*/10 * * * *` 跑 check.py（注意 Actions 免费版有几分钟延迟） |
| .github/workflows/build-apk.yml | 构建 APK（app-release-signed.apk） |
| manifest.json, icon-192/512.png, crest.png, twa-config.json | PWA/图标资源 |
| memory.md | 本备忘录 |

## 三、数据模型（两页一致）
- localStorage key：`'calendar_events_v5'`（STORAGE_KEY），结构 `{ events: [], courses: [] }`
- 载入失败/为空 → 回退 `DEFAULT_EVENTS` / `DEFAULT_COURSES`（mobile.html 1135-1145 附近）
- **course 字段**：`id, name, weekday(1=周一..7=周日), start, end, location, type('Lecture'/'Tutorial'), instructor, crn, url(课件链接)`
- **event 字段**：`id, title, date(YYYY-MM-DD), start, end, type('exam'|'event'), location, remind(提前分钟), url`
- 工具函数（mobile.html ~1252）：`pad, dateKey, uuid, escapeHtml, timeToMinutes`
- **课件文件存储（IndexedDB，仅 mobile.html）**：库 `calendar_files_v1`（版本 1）、store `files`（keyPath 'id'）
  - 记录：`{id, courseId, name, type, size, blob(Blob 原样存), addedAt}`
  - helper（mobile.html ~1350）：`openFileDB / fileDb(mode,fn) / dbAddFiles / dbGetAllFiles / dbDeleteFile`
  - `saveData()` 末尾调用 `pruneOrphanFiles()` 自动清理已退课程的无主附件
  - 弹窗 `#fileOverlay`（底部 sheet，复用 .modal-overlay/.modal）：`openFileSheet(course)` → 列表（图标按扩展名着色）+ 打开（createObjectURL 新标签）+ 删除；`navigator.storage.persist()` 申请持久化配额，`storage.estimate()` 显示用量；单文件上限 100MB
  - 课表角标：`renderSchedule()` 末尾调 `decorateAttachmentBadges()`，给有课件的课程块加 `.cc-file-badge`（📄N）；`attachCountsDirty` 脏标记控制重查

## 四、校历逻辑（mobile.html ~1158-1250）
- 常量表：`SEMESTERS`（含 type:'independent' 独立探索期）、`EXAM_PERIODS`、`HOLIDAYS`、`MAKEUP_DAYS`（{date, weekdayAs: 补课按周几上}）
- `getDateInfo(d)` → `{semester, week, holiday, makeup, exam, independent}`；`hasSchool(d)` = 额外判断假期/考试期/探索期
- 周次计算：学期起始日回溯到当周周一，`Math.round(周一差/7天)+1`
- 补课日：日历视图把 `makeup.weekdayAs` 对应星期的课程渲染到补课日列

## 五、渲染与交互（mobile.html，行号约值，改动后更新）
- 视图渲染：`renderCalendar / renderEventsList / renderSchedule / renderLegend`；课程块 `renderCourseBlock(1626)`（超出生课时间窗 TT_START/END_MIN 直接不渲染）
- 课表课程块点击 → `showPopupCourseMenu`（**async**，会查 IndexedDB 统计课件数，菜单含 📎课件文件(N) / 🔗课件链接 / ✏️编辑 / 🗑删除，data-act='files' → openFileSheet）；事件块 → `showPopupEventMenu`
  - popup 菜单 = `#popupMenu` 容器 innerHTML 重建，`.pm-item` + `data-act` 委托；`positionPopup` 定位在点击处
  - document click/scroll/resize 自动 `hidePopup()`（2119-2121）
- 编辑弹窗 `openModal(event, course)(1735)`：`editingId/editingKind` 区分类型，closeModal(1803)；遮罩点击关闭(2238)
- 加课表单：星期**多选 chips**（周一~周日），选多天生成多门同名课（v1.3.2）
- 拖拽换位：`startCourseDrag(1829)`，拖前快照进 `undoStack`（可多次撤销），拖到占用格互换 weekday/start/end
- 提醒：`updateReminderStatus(2147)`、`checkReminders` 每 15s(2364)、`new Notification`（需页面前台 + 权限；iOS 需 PWA 添加到主屏）
- 电脑端差异：日历视图**不显示课程标签**（只显示考试/事件），课程管理在课表/退课列表

## 六、发版流程（每次新功能必做）
1. 改代码（功能通常两页都要同步）
2. 两页各自改：`APP_VERSION` / `APP_VERSION_CODE` / `CHANGELOG` 数组头部加新条目
3. sw.js：`CACHE = 'calendar-v(N+1)'`
4. version.json：version / versionCode / updateLog
5. git commit + push（push 即上线，无需其他操作）

## 七、服务端提醒
- check.py：`load_schedule()` 读 schedule.json → `find_upcoming()` 找 30 分钟内开始的项 → `push()` 走 WxPusher（SPT：env `WXPUSHER_SPT`，默认含 SPT）
- 校历判断与前端一致（is_holiday / is_exam_period / get_school_day）

## 八、已踩坑/教训
- 浏览器 Notification 齐后台标签页会暂停定时器 → 提醒主要靠 WxPusher 服务端推送兜底
- iOS Safari 必须以 PWA"添加到主屏幕"才能收到网页通知
- GitHub Actions 免费版 cron 有几分钟延迟，测试课程开始时间要留余量
- 学校邮箱（CUHK-SZ）集成不可行：租户禁止第一方应用 OAuth 同意（AADSTS65002），用户也无权注册 Azure 应用；网易邮箱无公开 API。**邮箱功能已在 e1c602f 整体移除，勿再实现**
- 拖拽结束后 350ms 内忽略 click（justDraggedAt），防止拖完误开弹窗

## 九、版本历史
- v1.0.0 (09-07)：首版
- v1.1.0/v1.1.1 (09-07)：课程数据修正 / 图标修复
- v1.2.0 (09-08)：拖拽换位、一键退/加课、更新日志
- v1.3.0~v1.3.2 (09-08)：加课表单化、拖拽撤销、星期多选
- v1.4.0（邮箱，已回退删除）
- v1.4.0 (09-08)：**课程关联本地课件文件**（手机端 IndexedDB，见"三、数据模型"）— 复用了回退前的版本号
- 当前版本：v1.4.0 / versionCode 8 / sw cache calendar-v8
