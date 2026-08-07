# LucidRead 1.0.0 版本交付与记忆沉淀文档

本文档记录 LucidRead / 简声 iOS 1.0.0 阶段的核心产出、技术决策、踩坑结论与后续开发红线。后续任何开发、重构、提审或修复都必须先阅读本文件，并以这里沉淀的约束为准。

## 核心功能产出

本阶段完成了一个面向盲人和视弱群体的极简无障碍阅读器，并已以 `1.0.0` 版本提交 App Store Connect。核心目标是降低小说阅读与听书的操作复杂度，同时把 VoiceOver、TTS、本地导入和网站传书作为一等功能。

主要业务逻辑与页面如下：

- 书架首页：支持品牌栏、帮助入口、刷新网站传书、继续阅读、三列“我的书籍”布局、书名两行保留、阅读进度展示、长按/VoiceOver 自定义操作重命名与删除。
  - `PureVoice/Features/Library/LibraryView.swift`
  - `PureVoice/Features/Library/LibraryViewModel.swift`
  - `PureVoice/Features/Library/BookRow.swift`
  - `PureVoice/Features/Library/ContinueReadingSection.swift`
  - `PureVoice/Features/Library/LibraryNavigationBarStyle.swift`

- 阅读页：基于 Readium 展示 EPUB，支持上下滚动与左右分页语义、阅读主题、阅读字号、控制层浮层、章节选择、朗读位置跟随、听书模式下降低 VoiceOver 正文干扰。
  - `PureVoice/Features/Reader/ReaderView.swift`
  - `PureVoice/Features/Reader/ReaderViewModel.swift`
  - `PureVoice/Features/Reader/EPUBNavigatorController.swift`
  - `PureVoice/Features/Reader/ReadiumContainer.swift`
  - `PureVoice/Features/Reader/ReaderToolbar.swift`
  - `PureVoice/Features/Reader/PublicationService.swift`

- 听书功能：支持本地 TTS、语速调节、设备已下载语音库枚举、后台音频、锁屏远程控制、上一章/下一章、Magic Tap 与 VoiceOver 手势、朗读进度持久化。
  - `PureVoice/Features/Speech/ReadiumSpeechService.swift`
  - `PureVoice/Features/Speech/ListeningView.swift`
  - `PureVoice/Features/Speech/ListeningViewModel.swift`
  - `PureVoice/Features/Speech/SpeechService.swift`
  - `PureVoice/Features/Speech/SpeechSessionCoordinator.swift`
  - `PureVoice/Features/Speech/RemoteCommandController.swift`
  - `PureVoice/Features/Speech/MiniPlayerView.swift`

- 本地导入：支持 TXT、EPUB；支持从系统“打开方式”进入 LucidRead 后导入；TXT 支持编码识别、智能分章、转换为规范 EPUB 后进入统一阅读链路。
  - `PureVoice/Features/Import/ImportView.swift`
  - `PureVoice/Features/Import/ImportCoordinator.swift`
  - `PureVoice/Features/Import/ImportPipelineConverter.swift`
  - `PureVoice/Features/Import/ExternalDocumentImporter.swift`
  - `PureVoice/Features/Import/DocumentPicker.swift`
  - `PureVoice/Features/Import/BookFormatDetector.swift`
  - `PureVoice/Features/Import/TXT/TXTDecoder.swift`
  - `PureVoice/Features/Import/TXT/ChapterParser.swift`
  - `PureVoice/Features/Import/TXT/EPUBBuilder.swift`

- 网站传书：App 固定生成长期有效传书码；网页上传 TXT/EPUB 后，App 在书架刷新即可接收；上传文件保留 72 小时；支持 Supabase 存储、验证、下载、清理任务与服务端福利授权预留。
  - `PureVoice/Features/WebTransfer/TransferIdentityStore.swift`
  - `PureVoice/Features/WebTransfer/WebTransferClient.swift`
  - `PureVoice/Features/WebTransfer/WebTransferView.swift`
  - `PureVoice/Features/WebTransfer/WebTransferViewModel.swift`
  - `supabase/functions/transfer/index.ts`
  - `supabase/functions/transfer-web/index.html`
  - `supabase/functions/transfer-cleanup/index.ts`
  - `supabase/migrations/20260722082037_create_web_transfer.sql`
  - `supabase/migrations/20260722122352_web_transfer_limits.sql`
  - `supabase/migrations/20260730094814_server_grant_entitlements.sql`

- 设置页：支持中英文应用语言、应用字体小/中/大/极大、阅读偏好、深色/浅色/护眼主题、订阅入口、隐私条款、服务条款、版本号与检查更新入口。
  - `PureVoice/Features/Settings/SettingsView.swift`
  - `PureVoice/Features/Settings/ReaderPreferences.swift`
  - `PureVoice/Features/Settings/PreferencesStore.swift`
  - `PureVoice/Core/Models/AppVersionInfo.swift`
  - `PureVoice/Core/Models/LegalDocument.swift`

- 订阅与付费墙：新设备 3 天免费；到期后在进入阅读或听书播放时拦截；支持月订阅、年订阅 7 天试用、永久买断、恢复购买；预留服务端 `lifetime-free` 福利授权。
  - `PureVoice/Features/Purchases/PaywallView.swift`
  - `PureVoice/Features/Purchases/StoreKitPurchaseManager.swift`
  - `PureVoice/Features/Purchases/PurchaseAccessStore.swift`
  - `PureVoiceTests/PurchaseAccessStoreTests.swift`

- 内置审核书籍与资源：为审核准备默认内置书籍；品牌图标、深色图标、帮助图标、刷新图标、导入/网络/复制 SVG 均已接入资产目录。
  - `PureVoice/App/BundledBookInstaller.swift`
  - `PureVoice/Resources/BundledBooks/pg79182-images-3.epub`
  - `PureVoice/Resources/Assets.xcassets/BrandLogo.imageset/`
  - `PureVoice/Resources/Assets.xcassets/BrandLogoDark.imageset/`
  - `PureVoice/Resources/Assets.xcassets/HelpAction.imageset/`
  - `PureVoice/Resources/Assets.xcassets/RefreshAction.imageset/`

## 架构与技术决策

技术栈与模块原则：

- 客户端使用 SwiftUI + Swift Concurrency + Core Data + Readium + AVFoundation / AVSpeechSynthesizer 体系。
- EPUB 与阅读导航统一走 Readium；TXT 通过本地转换为 EPUB 后进入同一阅读链路，不再维护两套阅读器。
- 数据持久化以 `BookRepository` 抽象为边界，Core Data 为生产实现，测试使用内存或 recording fake。
- 文件持久化通过 `BookFileStore` 管理。App 更新后不能依赖旧 bundle/container 绝对路径，必须通过可迁移、可重定位路径恢复书籍文件。
- App 依赖统一从 `AppDependencies` 注入，避免页面直接 new 复杂服务。
- 书籍导入、阅读、听书、设置、传书、订阅分模块拆分，目录以 `PureVoice/Features/<Feature>` 为边界。
- UI 需要同时服务普通视觉用户与 VoiceOver 用户。极简指的是功能路径极简，不代表视觉设计粗糙。
- 服务端使用 Supabase Edge Functions + Postgres + Storage + Cron；GitHub Pages/静态页作为传书网页入口方案之一。
- StoreKit 作为订阅底层方案；当前保留将来接入 RevenueCat 的可能，但客户端不能被 RevenueCat 强绑定。

绝对不能推翻的历史决策：

- 不能把盲人核心操作依赖复杂视觉 UI。Magic Tap、三指滑动、Scrub、自定义操作等 VoiceOver 标准机制是核心体验。
- 不能引入广告、登录注册、信息流、视频、音频平台化等复杂功能。LucidRead 必须保持纯阅读/听书。
- 不能使用 iPhone IMEI、IDFA 或需要额外授权的设备标识。传书 ID 必须是 App 本地生成的随机稳定 ID，不是硬件号。
- 传书码必须长期固定，不应每次打开或每次上传后变化；网页端上传成功后也不能清空本次输入的传书码。
- 网站传书的 Storage 路径必须使用安全 ASCII 结构，例如 `设备ID/上传ID/book.epub`，避免中文文件名、括号、空格等导致 Storage 或 URL 编码问题。上传 ID 保证同设备多次上传不冲突。
- 书架刷新必须能直接接收网站传书，不应要求用户进入导入页才能接收。
- 听书进度与阅读进度必须共享并持久化。暂停、关闭听书、App 进入后台、杀进程前后的恢复逻辑不能回到章节首页。
- 后台朗读必须使用 audio background mode，并正确配置音频会话。开始朗读时不应与其他音乐混播。
- Readium TTS 相关闭包和 delegate 不能继承 MainActor 隔离；Readium 可能在后台 cooperative queue 调用播放引擎。
- 听书章节切换必须跳过目录页、TOC、Contents 等导航资源，不能朗读目录章节名导致卡在目录。
- App Store 版本号当前为 `1.0.0`，本阶段提交 build 为 `2026073004`；后续上传 App Store Connect 必须递增 `CFBundleVersion`。

## 踩坑与未决问题

已解决的隐蔽 Bug：

- 文件大小误判：导入 41.6MB TXT 时被误报超过 250MB，后续导入逻辑需要始终使用真实文件大小而不是错误的中间数据大小。
- EPUB/TXT 分章误识别：部分小说前 1-221 章被识别为“序章”，导致超长章节。已增强章节解析，但分章仍是启发式算法，不可假设所有盗版/精校文本格式统一。
- 上下滚动模式错误：曾经把“滚动”做成横向平滑分页。最终语义必须是“左右分页”和“上下滚动”两种不同阅读模式。
- 阅读主题丢失：分页与滚动切换时曾丢失深色/护眼主题。阅读主题属于阅读偏好，切换布局不能重置。
- 深色模式不一致：系统深色 + 跟随系统时，阅读页曾仍显示浅色。当前规则是系统深色对应深色主题，系统浅色对应护眼主题，除非用户手动选择主题。
- 顶部/底部安全区颜色割裂：深色和护眼模式下，状态栏和底部控制区必须跟随主题，不能突然出现白条。
- 听书进度不同步：听到第 N 句后退出再进入曾回章节首或更早句子。当前必须以朗读 locator/range locator 持久化为准。
- “无法定位到所选章节/无法跟随当前听书位置”频繁弹窗：当正在听 A 书而打开 B 书时，不跟随是正常状态，不能持续弹错误提示。
- Readium TTS Swift 6 崩溃：`ReadiumSpeechService` 为 `@MainActor`，但 `PublicationSpeechSynthesizer.engine` 会在后台队列调用 `engineFactory`。修复为 `nonisolated makeSpeechEngineFactory`，并让 `RateApplyingAVDelegate` 线程安全且非 MainActor。
- 听书时目录页卡住：部分 EPUB 的 reading order 或 TOC 包含目录资源，朗读时会一直读目录名。已通过 `PublicationReadingFilter` 和 `ReadiumSpeechService` 跳过导航资源，但 EPUB 结构复杂，仍需对异常书籍持续加 fixture。
- VoiceOver 焦点碎片化：书架卡片必须合并封面、书名、作者、进度为单一 accessibility focus，否则盲人浏览成本过高。
- 听书时 VoiceOver 与 TTS 双声道冲突：听书模式下正文文本不应被 VoiceOver 当成可读焦点，按钮和控制项仍必须可访问。
- 阅读控制层遮挡：浮层不能把阅读内容向下挤压，否则文字位置变化会破坏阅读/朗读同步。
- App 更新后书籍失效：不能依赖安装包路径或旧容器绝对路径，必须保证导入书籍在 Documents/Application Support 中可恢复。
- Supabase Edge Function 直接返回 HTML 时浏览器显示源码：需要正确 Content-Type；后来传书页改用独立静态部署规避了部分 Edge Function HTML 展示问题。
- Supabase CLI/Docker 部署受本机路径、网络和 TLS 影响不稳定。线上静态页 + Supabase API 是更稳的分离方式。

可能成为技术债的临时兼容方案：

- 分章规则、目录过滤、导航资源识别仍是启发式，需要沉淀更多真实 EPUB/TXT 样本测试。
- StoreKit 当前保留本地/接口抽象和截图价格兜底，真实产品状态、价格、本地化、试用资格仍依赖 App Store Connect 配置和沙盒验证。
- 服务端 `lifetime-free` 福利授权已有迁移与接口方向，但仍需补齐管理后台、审计、撤销与缓存策略。
- 网站传书当前主要面向家人辅助上传，上传限制、防刷、清理、安全策略要继续强化，测试阶段曾临时放宽每日 3 本限制。
- UI 多语言已覆盖核心文本，但部分异常提示、法律文本、帮助文本仍需逐项审校英文表达。
- Readium 目录过滤目前以标题与 href 特征为主，若 EPUB 把正文错误标为 nav/toc，可能需要更细的内容密度判断。
- App Store Connect 上传流程依赖本机 Xcode 登录与自动签名，CI/CD 尚未固化。

## 下阶段（vX.X+1）开发红线

后续版本开发必须遵守以下红线：

- 不得破坏 `1.0.0` 已提审的产品定位：无广告、无注册、无复杂内容平台，只做本地小说阅读、听书、导入和传书。
- 不得引入需要额外隐私授权的设备唯一标识。传书 ID 必须继续由 `TransferIdentityStore` 生成、长期保存、可复制，但不可频繁变化。
- 不得让网站传书码在上传成功后自动清空；网页端本次会话必须保留传书码。
- 不得把网站传书接收入口藏到导入页。书架刷新必须是主要接收路径。
- 不得绕过 `BookRepository`、`BookFileStore`、`AppDependencies` 直接操作持久化文件或全局单例。
- 不得在阅读和听书之间维护两套进度。任何进度更新必须能回写 `ReadingPosition`，并能被书架、阅读页、听书页共同读取。
- 不得把 Readium/AVFoundation 的后台回调闭包标成或隐式继承 `@MainActor`。所有可能被 Readium 后台调用的 factory/delegate/helper 必须是 `nonisolated` 或明确线程安全。
- 不得把 `RateApplyingAVDelegate` 改回 `@MainActor` 或普通非线程安全状态；这是已验证的崩溃根因。
- 不得用 `synthesizer.previous()` / `synthesizer.next()` 直接实现章节切换。章节切换必须走可读章节导航，跳过目录资源。
- 不得让“听书时打开另一本文档无法跟随位置”弹出错误提示。这属于正常跨书状态，应静默处理。
- 不得让阅读控制层改变正文布局高度或挤压阅读页。浮层必须覆盖显示，显示/隐藏不能造成正文重排。
- 不得让听书 mini player 在停止时占据无意义空白或成为 VoiceOver 焦点。
- 不得让书架图书卡片拆成多个 VoiceOver 焦点。卡片 accessibility label 必须包含书名、作者、进度，双击进入阅读。
- 不得把 VoiceOver 手势替换成自定义冲突手势。优先使用 Magic Tap、accessibilityScroll、accessibilityAction、accessibilityCustomActions、escape/scrub。
- 不得在听书模式下让正文文本继续被 VoiceOver 朗读。听书时正文应避免成为 VoiceOver 文本焦点，控制按钮除外。
- 不得让应用字体设置影响阅读正文字号。应用字体小/中/大/极大只影响非阅读正文 UI；阅读字体由阅读设置独立控制。
- 不得让首次安装默认应用字体不是中等。默认阅读主题需要符合系统主题规则：跟随系统时，系统深色对应深色，系统浅色对应护眼。
- 不得引入未测试的 EPUB/TXT 解析变更。任何分章、目录过滤、阅读定位改动都必须增加 fixture 或单元测试。
- 不得上传重复 `CFBundleVersion` 到 App Store Connect。每次提交 Connect 前必须递增 build number。
- 不得提交未本地构建通过的包。最低验证为 `xcodebuild build -scheme PureVoice -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`；涉及核心逻辑时必须跑对应测试。
- 不得在未说明风险的情况下大规模重构 SwiftUI UI。这个项目的无障碍交互优先级高于视觉微调。
- 不得把 Supabase RLS、Storage 路径、上传有效期、防刷策略随意放宽到生产环境。测试放宽必须有明确回滚点。
