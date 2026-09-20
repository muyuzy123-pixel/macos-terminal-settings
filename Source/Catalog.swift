import Foundation

enum PreferenceCatalog {
    static func search(_ searchText: String, resources: LocalizationResources = .main) -> [PreferenceItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            let displayFields = [item.title, item.detail, item.source.detailLabel,
                                 item.category.title, item.evidence.title] +
                [item.source.systemSettings?.path, item.stability.note].compactMap { $0 }
            return [AppLanguage.simplifiedChinese, .english].contains { language in
                displayFields.contains {
                    $0.rendered(language: language, resources: resources).localizedCaseInsensitiveContains(query)
                }
            } || item.allAddresses.contains {
                $0.domain.localizedCaseInsensitiveContains(query) || $0.key.localizedCaseInsensitiveContains(query)
            }
        }
    }

    private static let global = "NSGlobalDomain"
    private static let expandedCompatibility = PreferenceCompatibility(
        minimumMajorVersion: 14,
        verifiedMajorVersion: 26,
        verifiedMinorVersion: 6,
        verifiedPatchVersion: 2,
        verifiedOSVersion: "macOS 26.6.2",
        verifiedDate: "2026-09-12"
    )
    private static let tahoeCompatibility = PreferenceCompatibility(
        minimumMajorVersion: 26,
        verifiedMajorVersion: 26,
        verifiedMinorVersion: 6,
        verifiedPatchVersion: 2,
        verifiedOSVersion: "macOS 26.6.2",
        verifiedDate: "2026-09-12"
    )
    private static let advancedCompatibility = PreferenceCompatibility(
        minimumMajorVersion: 14,
        verifiedMajorVersion: 26,
        verifiedMinorVersion: 6,
        verifiedPatchVersion: 2,
        verifiedOSVersion: "macOS 26.6.2",
        verifiedDate: "2026-09-12"
    )
    private static let dockAnimationEvidence = PreferenceEvidence(
        title: L("macOS Defaults：Dock 自动隐藏动画浮点键"),
        url: "https://macos-defaults.com/dock/autohide-time-modifier.html"
    )
    private static let dockScrollEvidence = PreferenceEvidence(
        title: L("macOS Defaults：Scroll to Exposé app"),
        url: "https://macos-defaults.com/dock/scroll-to-open.html"
    )
    private static let appsGestureEvidence = PreferenceEvidence(
        title: L("Apple 支持：使用 Multi-Touch 手势显示应用程序"),
        url: "https://support.apple.com/102482"
    )
    private static let legacyLaunchpadGestureEvidence = PreferenceEvidence(
        title: L("Mathias dotfiles：旧 Launchpad 手势键"),
        url: "https://github.com/mathiasbynens/dotfiles/blob/main/.macos"
    )
    private static let appSwitcherEvidence = PreferenceEvidence(
        title: L("Tahoe 多显示器验证与当前 Dock 键"),
        url: "https://gist.github.com/jthodge/c4ba15a78fb29671dfa072fe279355f0"
    )
    private static let dockPinningEvidence = PreferenceEvidence(
        title: L("macOS Dock pinning 参考与当前 Dock 键"),
        url: "https://gist.github.com/maxfenton/c5a316f4254d27b18cf3"
    )
    private static let minimizeEffectEvidence = PreferenceEvidence(
        title: L("macOS Defaults：Minimize animation effect"),
        url: "https://macos-defaults.com/dock/mineffect.html"
    )
    private static let finderAnimationEvidence = PreferenceEvidence(
        title: L("2026 macOS 动画偏好清单与当前 Finder 键"),
        url: "https://gist.github.com/m0zgen/085f42ada013efbcb59f43fc47b46d99"
    )
    private static let quickLookTextEvidence = PreferenceEvidence(
        title: L("历史 macOS 配置：QLEnableTextSelection"),
        url: "https://gist.github.com/adamseadub/363803dec06e7371260c0d4d40523590"
    )
    private static let legacyTrackpadEvidence = PreferenceEvidence(
        title: L("macOS 11.3 私有触控板后端：threeFingerDoubleTap"),
        url: "https://github.com/cmsj/ApplePrivateHeaders/blob/7d0c0200eeb7c3e326fafd4bbd7b6786f8000730/macOS/11.3/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/Versions/A/PreferencePanesSupport/MTTGestureBackEnd.h"
    )
    private static let windowDragEvidence = PreferenceEvidence(
        title: L("AeroSpace：macOS 窗口拖动提示"),
        url: "https://github.com/nikitabobko/AeroSpace"
    )
    private static let tooltipEvidence = PreferenceEvidence(
        title: L("2026 macOS 工具提示延迟清单"),
        url: "https://gist.github.com/m0zgen/085f42ada013efbcb59f43fc47b46d99"
    )
    private static let menuBarSpacingEvidence = PreferenceEvidence(
        title: L("SaneBar：可逆菜单栏图标间距"),
        url: "https://github.com/sane-apps/SaneBar"
    )
    private static let networkStoreEvidence = PreferenceEvidence(
        title: L("Apple 支持：调整 SMB 浏览行为"),
        url: "https://support.apple.com/102064"
    )
    private static let usbStoreEvidence = PreferenceEvidence(
        title: L("macOS 26 Tahoe Hardening Guide"),
        url: "https://github.com/ernw/hardening/blob/master/operating_system/osx/26/Hardening_Guide-macOS_26_Tahoe_1.0.md"
    )
    private static let pmsetEvidence = PreferenceEvidence(
        title: L("Apple pmset(8) 系统手册"),
        url: nil
    )
    private static let desktopDockSettingsEvidence = PreferenceEvidence(
        title: L("Apple 支持：桌面与程序坞设置"),
        url: "https://support.apple.com/guide/mac-help/change-desktop-dock-settings-mchlp1119/26/mac/26"
    )
    private static let keyboardSettingsEvidence = PreferenceEvidence(
        title: L("Apple 支持：键盘设置"),
        url: "https://support.apple.com/guide/mac-help/change-keyboard-settings-on-mac-kbdm162/mac"
    )
    private static let dockSizesEvidence = PreferenceEvidence(
        title: L("Apple 设备管理：Dock 尺寸定义"),
        url: "https://developer.apple.com/documentation/devicemanagement/dock"
    )
    private static let screensaverIdleEvidence = PreferenceEvidence(
        title: L("Apple 设备管理：用户屏幕保护程序闲置时间"),
        url: "https://developer.apple.com/documentation/devicemanagement/screensaveruser"
    )
    private static let dockSizesEnhancement = PreferenceSource(
        exposure: .systemSettingsEnhancement,
        enhancementKind: .exactValue,
        systemSettings: SystemSettingsReference(
            coverage: .extended,
            pathSegments: [L("系统设置"), L("桌面与程序坞"), L("大小与放大")],
            verifiedOSVersion: "macOS 26.6.2",
            note: L("系统设置提供尺寸滑块，本项显示精确点数并支持整数输入。")
        ),
        note: L("Apple 设备管理定义给出 16–128 的范围；这不等同于承诺普通应用直接写入偏好的可见效果。")
    )
    private static let screensaverIdleEnhancement = PreferenceSource(
        exposure: .systemSettingsEnhancement,
        enhancementKind: .exactValue,
        systemSettings: SystemSettingsReference(
            coverage: .extended,
            pathSegments: [L("系统设置"), L("墙纸"), L("屏幕保护程序")],
            verifiedOSVersion: "macOS 26.6.2",
            note: L("系统设置提供固定时间，本项在受控范围内提供精确秒数及独立的“永不”选项。")
        ),
        note: L("数值采用当前主机偏好；设备管理定义证明单位与 0 的语义，实际行为仍需单独验证。")
    )
    private static let dockLaunchAnimationMirror = PreferenceSource(
        exposure: .systemSettingsMirror,
        enhancementKind: nil,
        systemSettings: SystemSettingsReference(
            coverage: .exact,
            pathSegments: [L("系统设置"), L("桌面与程序坞")],
            verifiedOSVersion: "macOS 26.6.1",
            note: L("与“打开应用程序时显示动画”使用同一布尔能力。")
        ),
        note: L("本项保留为现有目录的系统设置镜像，不作为批量复制系统设置的先例。")
    )
    private static let legacyLaunchpadGestureMirror = PreferenceSource(
        exposure: .systemSettingsMirror,
        enhancementKind: nil,
        systemSettings: SystemSettingsReference(
            coverage: .related,
            pathSegments: [L("系统设置"), L("触控板"), L("更多手势")],
            verifiedOSVersion: "macOS 26.6.1",
            note: L("这是旧版 Launchpad 手势的历史相关入口；Tahoe 当前图形开关与可见效果均不能证明仍由此键控制。")
        ),
        note: L("仅按历史能力保留为镜像分类，不宣称与 Tahoe 当前“应用程序”手势开关等价；继续标记实验性与不稳定。")
    )
    private static let dockMinimizeEffectEnhancement = PreferenceSource(
        exposure: .systemSettingsEnhancement,
        enhancementKind: .extraOption,
        systemSettings: SystemSettingsReference(
            coverage: .extended,
            pathSegments: [L("系统设置"), L("桌面与程序坞"), L("窗口最小化效果")],
            verifiedOSVersion: "macOS 26.6.1",
            note: L("系统设置提供常规效果，本项增加未列出的历史枚举。")
        ),
        note: L("额外枚举不代表 Apple 公开支持。")
    )
    private static let keyboardRepeatEnhancement = PreferenceSource(
        exposure: .systemSettingsEnhancement,
        enhancementKind: .exactValue,
        systemSettings: SystemSettingsReference(
            coverage: .extended,
            pathSegments: [L("系统设置"), L("键盘")],
            verifiedOSVersion: "macOS 26.6.1",
            note: L("系统设置提供两个滑块，本项显示整数系统刻度并开放受控的更快范围。")
        ),
        note: L("数值继续称为系统刻度，不换算成固定毫秒数。")
    )

    static let items: [PreferenceItem] = [
        PreferenceItem(
            id: "dock.iconSizes",
            category: .dock,
            title: L("精确调整程序坞图标尺寸"),
            detail: L("分别设置普通尺寸与放大尺寸，以 1 点为步进；放大尺寸不能小于普通尺寸。"),
            symbol: "square.resize",
            control: .numeric(NumericPreference(
                detail: L("两项尺寸成组应用；关闭系统放大功能时，放大尺寸会预存，在放大功能开启后生效。"),
                parameters: [
                    NumericPreferenceParameter(
                        id: "tileSize",
                        title: L("普通尺寸"),
                        detail: L("控制程序坞图标的普通尺寸；应用预设为 48 点，不代表系统默认值。"),
                        address: PreferenceAddress(domain: "com.apple.dock", key: "tilesize"),
                        range: 16...128,
                        step: 1,
                        presetValue: 48,
                        storage: .float,
                        unit: L("点"),
                        precision: 0,
                        readingPolicy: .integerOrFloat
                    ),
                    NumericPreferenceParameter(
                        id: "largeSize",
                        title: L("放大尺寸"),
                        detail: L("控制启用系统放大功能后的尺寸；应用预设为 64 点，不代表系统默认值。"),
                        address: PreferenceAddress(domain: "com.apple.dock", key: "largesize"),
                        range: 16...128,
                        step: 1,
                        presetValue: 64,
                        storage: .float,
                        unit: L("点"),
                        precision: 0,
                        readingPolicy: .integerOrFloat
                    )
                ],
                constraints: [
                    .ordered(
                        lowerParameterID: "tileSize",
                        upperParameterID: "largeSize",
                        message: L("放大尺寸不能小于普通尺寸")
                    )
                ],
                initializesDraftsFromCurrentValue: true
            )),
            restartProcesses: ["Dock"],
            effectHint: L("程序坞会自动重启；放大尺寸仅在系统放大功能开启时可见"),
            caution: .compatibility,
            stability: .unstable(
                L("macOS 26.6.2 的本机只读检查可读到尺寸值；本轮验证只覆盖隔离写入契约与当前值读取，尚未验证真实 Dock 的可见效果、中间值回显或持久性。放大开关及尺寸锁定标记仅读取。")
            ),
            compatibility: expandedCompatibility,
            evidence: dockSizesEvidence,
            source: dockSizesEnhancement,
            recovery: .restoreBaseline,
            contextAddresses: [
                PreferenceAddress(domain: "com.apple.dock", key: "magnification"),
                PreferenceAddress(domain: "com.apple.dock", key: "size-immutable"),
                PreferenceAddress(domain: "com.apple.dock", key: "magsize-immutable")
            ],
            lockingContextAddresses: [
                PreferenceAddress(domain: "com.apple.dock", key: "size-immutable"),
                PreferenceAddress(domain: "com.apple.dock", key: "magsize-immutable")
            ]
        ),
        PreferenceItem(
            id: "dock.instantReveal",
            category: .dock,
            title: L("调整隐藏程序坞显示延迟"),
            detail: L("控制光标触碰屏幕边缘后的等待时间；安全预设为立即显示，仅在自动隐藏程序坞时有作用。"),
            symbol: "bolt.fill",
            control: toggle(
                domain: "com.apple.dock", key: "autohide-delay", enabled: .float(0)
            ),
            restartProcesses: ["Dock"],
            effectHint: L("程序坞会自动重启"),
            caution: .none,
            compatibility: expandedCompatibility,
            customization: PreferenceCustomization(
                detail: L("在自动隐藏已开启时调整光标触碰屏幕边缘后的等待时间；范围限制为已核对的非负值。"),
                parameters: [
                    NumericPreferenceParameter(
                        id: "delay",
                        title: L("显示延迟"),
                        detail: L("0 秒为立即显示；较大的值会延后程序坞出现。"),
                        address: PreferenceAddress(
                            domain: "com.apple.dock",
                            key: "autohide-delay"
                        ),
                        range: 0...2,
                        step: 0.001,
                        presetValue: 0,
                        storage: .float,
                        unit: L("秒"),
                        precision: 3
                    )
                ]
            )
        ),
        PreferenceItem(
            id: "dock.fastAnimation",
            category: .dock,
            title: L("尝试缩短自动隐藏程序坞动画"),
            detail: L("把“autohide-time-modifier”写为安全预设 0.18；仅在程序坞自动隐藏已开启时可能改变展开与收起动画。"),
            symbol: "hare.fill",
            control: toggle(
                domain: "com.apple.dock",
                key: "autohide-time-modifier",
                enabled: .float(0.18)
            ),
            restartProcesses: ["Dock"],
            effectHint: L("程序坞会自动重启"),
            caution: .compatibility,
            stability: .unstable(
                L("macOS 26.6.1 的 Dock 仍以浮点数读取此键，缺省读取基准为 1，并在内部乘以固定常量；但网上资料把它分别解释为时长、倍率或速度。应用提供 0.000–2.000 的受限实验滑块，0.18 为安全预设；该数值不是秒，可见动画与数值的精确比例及方向仍未确认。")
            ),
            compatibility: expandedCompatibility,
            evidence: dockAnimationEvidence,
            customization: PreferenceCustomization(
                detail: L("在 0.000–2.000 的可逆范围内调整 Dock 动画计算系数；这不是秒数，1.000 是缺省读取基准，实际效果仍属于实验性。"),
                parameters: [
                    NumericPreferenceParameter(
                        id: "modifier",
                        title: L("动画时间系数"),
                        detail: L("数值越小通常越短，但不保证与可见时长线性对应。"),
                        address: PreferenceAddress(
                            domain: "com.apple.dock",
                            key: "autohide-time-modifier"
                        ),
                        range: 0...2,
                        step: 0.001,
                        presetValue: 0.18,
                        storage: .float,
                        unit: L(""),
                        precision: 3
                    )
                ]
            )
        ),
        PreferenceItem(
            id: "dock.scrollExpose",
            category: .dock,
            title: L("滚动图标显示 App 窗口"),
            detail: L("在程序坞图标上向上滚动时显示该 App 的所有窗口，也可用相同手势展开堆栈；滚动方向受系统设置影响。"),
            symbol: "arrow.up.circle.fill",
            control: toggle(
                domain: "com.apple.dock", key: "scroll-to-open", enabled: .bool(true)
            ),
            restartProcesses: ["Dock"],
            effectHint: L("程序坞会自动重启"),
            caution: .compatibility,
            stability: .unstable(
                L("macOS 26.6.1 的 Dock 主二进制未再检出“scroll-to-open”明文；写入地址、布尔类型和删除恢复路径仍明确，但它可能已迁入私有组件、只保留兼容读取，也可能被忽略。即使仍被读取，触发结果也取决于滚动设备、系统滚动方向以及图标类型。")
            ),
            compatibility: expandedCompatibility,
            evidence: dockScrollEvidence
        ),
        PreferenceItem(
            id: "dock.disableAppsPinchGesture",
            category: .dock,
            title: L("关闭捏合显示应用程序"),
            detail: L("在 macOS Tahoe 中停用拇指与三指向内捏合显示“应用程序”的手势；不会关闭向外张开的“显示桌面”。仅在系统多指捏合手势已启用时有作用。"),
            symbol: "hand.pinch",
            control: toggle(
                domain: "com.apple.dock",
                key: "showSpotlightGestureEnabled",
                enabled: .bool(false)
            ),
            restartProcesses: ["Dock"],
            effectHint: L("程序坞会自动重启"),
            caution: .compatibility,
            stability: .unstable(
                L("Dock 26.6.1 以布尔值读取“showSpotlightGestureEnabled”，缺省为开启；但本轮没有对实体触控板执行捏合回归。触控板总手势开关、硬件能力或后续系统更新都可能让写入成功但动作不变。")
            ),
            compatibility: tahoeCompatibility,
            evidence: appsGestureEvidence
        ),
        PreferenceItem(
            id: "dock.disableLegacyLaunchpadPinchGesture",
            category: .dock,
            title: L("尝试关闭旧版 Launchpad 捏合手势"),
            detail: L("把旧“showLaunchpadGestureEnabled”门控写为 false；它与 Tahoe 当前“应用程序”手势使用的门控相互独立。"),
            symbol: "hand.pinch.fill",
            control: toggle(
                domain: "com.apple.dock",
                key: "showLaunchpadGestureEnabled",
                enabled: .bool(false)
            ),
            restartProcesses: ["Dock"],
            effectHint: L("程序坞会自动重启"),
            caution: .compatibility,
            stability: .unstable(
                L("Dock 26.6.1 仍包含该键、布尔属性和兼容 Launchpad 代码，但 Tahoe 当前“应用程序”动作另读“showSpotlightGestureEnabled”。此旧门控可能只影响兼容分支，也可能没有任何可见效果；需要控制当前动作时应使用相邻的新门控。")
            ),
            compatibility: tahoeCompatibility,
            evidence: legacyLaunchpadGestureEvidence,
            source: legacyLaunchpadGestureMirror,
            recovery: .restoreBaseline
        ),
        PreferenceItem(
            id: "dock.noLaunchAnimation",
            category: .dock,
            title: L("关闭 App 启动弹跳动画"),
            detail: L("从程序坞打开 App 时不再显示图标弹跳；部分现代 App 可能忽略此偏好。"),
            symbol: "arrow.up.and.down.square",
            control: .toggle(TogglePreference(
                readAddress: PreferenceAddress(
                    domain: "com.apple.dock",
                    key: "launchanim"
                ),
                enabledValue: .bool(false),
                enableMutations: [
                    .write("com.apple.dock", "launchanim", .bool(false))
                ],
                disableMutations: [
                    .write("com.apple.dock", "launchanim", .bool(true))
                ]
            )),
            restartProcesses: ["Dock"],
            effectHint: L("程序坞会自动重启"),
            caution: .compatibility,
            stability: .unstable(
                L("该键只约束 Dock 自己管理的启动弹跳；现代 App 的启动呈现、恢复窗口或自定义图标动画可能绕过它，所以不同 App 的可见结果可能不一致。")
            ),
            evidence: desktopDockSettingsEvidence,
            source: dockLaunchAnimationMirror,
            recovery: .restoreBaseline
        ),
        PreferenceItem(
            id: "dock.activeOnly",
            category: .dock,
            title: L("仅显示正在运行的 App"),
            detail: L("程序坞只保留当前已打开的 App，固定但未运行的图标暂时隐藏。"),
            symbol: "app.badge.checkmark",
            control: toggle(
                domain: "com.apple.dock", key: "static-only", enabled: .bool(true)
            ),
            restartProcesses: ["Dock"],
            effectHint: L("程序坞会自动重启"),
            caution: .interaction
        ),
        PreferenceItem(
            id: "dock.allDisplaySwitcher",
            category: .dock,
            title: L("在所有显示器显示 App 切换器"),
            detail: L("按 ⌘Tab 时让 App 切换器同时出现在每台显示器上，便于多显示器工作区快速定位。"),
            symbol: "display.2",
            control: toggle(
                domain: "com.apple.dock", key: "appswitcher-all-displays", enabled: .bool(true)
            ),
            restartProcesses: ["Dock"],
            effectHint: L("程序坞会自动重启"),
            caution: .none,
            compatibility: expandedCompatibility,
            evidence: appSwitcherEvidence
        ),
        PreferenceItem(
            id: "dock.dimHidden",
            category: .dock,
            title: L("淡化已隐藏 App 的图标"),
            detail: L("使用 ⌘H 隐藏 App 后，将其程序坞图标显示为半透明。"),
            symbol: "circle.lefthalf.filled",
            control: toggle(
                domain: "com.apple.dock", key: "showhidden", enabled: .bool(true)
            ),
            restartProcesses: ["Dock"],
            effectHint: L("程序坞会自动重启"),
            caution: .compatibility,
            stability: .unstable(
                L("macOS 26.6.1 的 Dock 主二进制未检出“showhidden”明文；布尔写入与删除恢复路径仍明确，但该键可能已迁入私有组件、只保留兼容读取，也可能被忽略。即使仍有效，它也只应影响通过 ⌘H 隐藏的 App 图标。")
            ),
            compatibility: expandedCompatibility
        ),
        PreferenceItem(
            id: "dock.singleApp",
            category: .dock,
            title: L("启用单 App 模式"),
            detail: L("从程序坞切换 App 时自动隐藏其他 App，减少桌面干扰。"),
            symbol: "rectangle.on.rectangle.slash",
            control: toggle(
                domain: "com.apple.dock", key: "single-app", enabled: .bool(true)
            ),
            restartProcesses: ["Dock"],
            effectHint: L("程序坞会自动重启"),
            caution: .compatibility,
            stability: .unstable(
                L("macOS 26.6.1 的 Dock 主二进制未检出“single-app”明文；布尔写入与删除恢复路径仍明确，但该键可能只存在于兼容分支或已被忽略。若仍生效，从 Dock 切换 App 会自动隐藏其他 App，可能打断当前多窗口工作流。")
            ),
            compatibility: expandedCompatibility
        ),
        PreferenceItem(
            id: "dock.pinning",
            category: .dock,
            title: L("程序坞对齐位置"),
            detail: L("在屏幕边缘的起始端、中央或末端对齐程序坞；具体方向会随程序坞所在边缘变化。"),
            symbol: "align.horizontal.center",
            control: .choice(ChoicePreference(
                address: PreferenceAddress(domain: "com.apple.dock", key: "pinning"),
                options: [
                    ChoiceOption(id: "system", title: L("系统默认"), value: nil),
                    ChoiceOption(id: "start", title: L("起始端"), value: .string("start")),
                    ChoiceOption(id: "middle", title: L("居中"), value: .string("middle")),
                    ChoiceOption(id: "end", title: L("末端"), value: .string("end"))
                ]
            )),
            restartProcesses: ["Dock"],
            effectHint: L("程序坞会自动重启"),
            caution: .none,
            compatibility: expandedCompatibility,
            evidence: dockPinningEvidence
        ),
        PreferenceItem(
            id: "dock.suckEffect",
            category: .dock,
            title: L("隐藏的窗口最小化效果"),
            detail: L("启用系统设置未列出的“挤压（Suck）”最小化动画；可单独采用 Apple 默认，或恢复本应用接管前的原始选择。"),
            symbol: "arrow.down.right.and.arrow.up.left",
            control: .choice(ChoicePreference(
                address: PreferenceAddress(domain: "com.apple.dock", key: "mineffect"),
                options: [
                    ChoiceOption(id: "system", title: L("Apple 默认（删除显式值）"), value: nil),
                    ChoiceOption(id: "suck", title: L("挤压"), value: .string("suck"))
                ]
            )),
            restartProcesses: ["Dock"],
            effectHint: L("程序坞会自动重启"),
            caution: .compatibility,
            stability: .unstable(
                L("“suck”是未公开的历史动画枚举。Dock 可能因系统版本、减少动态效果或动画实现变化而回退到其他效果，偏好值成功读回并不保证实际采用该动画。")
            ),
            compatibility: expandedCompatibility,
            evidence: minimizeEffectEvidence,
            source: dockMinimizeEffectEnhancement,
            recovery: .restoreBaseline
        ),

        PreferenceItem(
            id: "finder.posixTitle",
            category: .finder,
            title: L("在窗口标题中显示完整路径"),
            detail: L("让访达标题栏显示当前文件夹的 POSIX 路径，而不仅是文件夹名称。"),
            symbol: "point.topleft.down.to.point.bottomright.curvepath",
            control: toggle(
                domain: "com.apple.finder", key: "_FXShowPosixPathInTitle", enabled: .bool(true)
            ),
            restartProcesses: ["Finder"],
            effectHint: L("访达会自动重启"),
            caution: .none
        ),
        PreferenceItem(
            id: "finder.quitMenu",
            category: .finder,
            title: L("显示“退出访达”菜单"),
            detail: L("在访达菜单中加入退出项；退出后桌面图标也会暂时消失。"),
            symbol: "rectangle.portrait.and.arrow.right",
            control: toggle(
                domain: "com.apple.finder", key: "QuitMenuItem", enabled: .bool(true)
            ),
            restartProcesses: ["Finder"],
            effectHint: L("访达会自动重启"),
            caution: .interaction
        ),
        PreferenceItem(
            id: "finder.noAnimations",
            category: .finder,
            title: L("减少访达界面动画"),
            detail: L("关闭打开窗口和“显示简介”等部分访达动画；新版界面可能只响应其中一部分。"),
            symbol: "rectangle.stack.badge.minus",
            control: toggle(
                domain: "com.apple.finder", key: "DisableAllAnimations", enabled: .bool(true)
            ),
            restartProcesses: ["Finder"],
            effectHint: L("访达会自动重启"),
            caution: .compatibility,
            stability: .unstable(
                L("该总开关仍可在 macOS 26.6.1 的 Finder 中检出；窗口、信息面板和现代 SwiftUI 界面不一定共用同一动画实现，因此可能只减少部分动画。")
            ),
            compatibility: expandedCompatibility,
            evidence: finderAnimationEvidence
        ),
        PreferenceItem(
            id: "finder.quickLookTextSelection",
            category: .finder,
            title: L("尝试启用 Quick Look 文本选择"),
            detail: L("写入旧版 Finder 的“QLEnableTextSelection”布尔键，尝试在按空格打开的 Quick Look 预览中选择文字。"),
            symbol: "text.cursor",
            control: toggle(
                domain: "com.apple.finder",
                key: "QLEnableTextSelection",
                enabled: .bool(true)
            ),
            restartProcesses: ["Finder"],
            effectHint: L("访达会自动重启"),
            caution: .compatibility,
            stability: .unstable(
                L("本机 Finder 与 Quick Look 26.6.1 二进制中未检出该键名，现代预览也可能按文件类型自行决定文字是否可选。因此此项很可能被忽略，或与系统本来就支持的选择行为没有可见差异；这里只保证布尔写入与删除恢复。")
            ),
            compatibility: expandedCompatibility,
            evidence: quickLookTextEvidence
        ),
        PreferenceItem(
            id: "finder.noNetworkDSStore",
            category: .finder,
            title: L("不在网络磁盘写入 .DS_Store"),
            detail: L("减少 SMB、NAS 等网络位置中的访达元数据文件；只影响之后访问的目录。"),
            symbol: "network",
            control: toggle(
                domain: "com.apple.desktopservices", key: "DSDontWriteNetworkStores", enabled: .bool(true)
            ),
            restartProcesses: [],
            effectHint: L("重新登录后完整生效"),
            caution: .none,
            compatibility: expandedCompatibility,
            evidence: networkStoreEvidence
        ),
        PreferenceItem(
            id: "finder.noUSBDSStore",
            category: .finder,
            title: L("不在可移动磁盘写入 .DS_Store"),
            detail: L("减少 U 盘和移动硬盘中的访达元数据文件；不会删除已有文件。"),
            symbol: "externaldrive",
            control: toggle(
                domain: "com.apple.desktopservices", key: "DSDontWriteUSBStores", enabled: .bool(true)
            ),
            restartProcesses: [],
            effectHint: L("重新登录后完整生效"),
            caution: .none,
            compatibility: expandedCompatibility,
            evidence: usbStoreEvidence
        ),

        PreferenceItem(
            id: "screenshots.noShadow",
            category: .screenshots,
            title: L("移除窗口截屏阴影"),
            detail: L("使用 ⌘⇧4 后按空格截取窗口时，不再添加透明阴影边缘。"),
            symbol: "square.dashed",
            control: toggle(
                domain: "com.apple.screencapture", key: "disable-shadow", enabled: .bool(true)
            ),
            restartProcesses: [],
            effectHint: L("下次截屏生效"),
            caution: .none
        ),
        PreferenceItem(
            id: "screenshots.format",
            category: .screenshots,
            title: L("截屏文件格式"),
            detail: L("更改系统截屏保存格式。JPEG 更小但有损；PNG 适合界面与文字。"),
            symbol: "photo.badge.arrow.down",
            control: .choice(ChoicePreference(
                address: PreferenceAddress(domain: "com.apple.screencapture", key: "type"),
                options: [
                    ChoiceOption(id: "system", title: L("系统默认"), value: nil),
                    ChoiceOption(id: "png", title: L("PNG"), value: .string("png")),
                    ChoiceOption(id: "jpg", title: L("JPEG"), value: .string("jpg")),
                    ChoiceOption(id: "pdf", title: L("PDF"), value: .string("pdf")),
                    ChoiceOption(id: "tiff", title: L("TIFF"), value: .string("tiff"))
                ]
            )),
            restartProcesses: [],
            effectHint: L("下次截屏生效"),
            caution: .none
        ),
        PreferenceItem(
            id: "screenshots.noDate",
            category: .screenshots,
            title: L("文件名不包含日期"),
            detail: L("生成更短的截屏文件名；系统仍会自动添加序号以避免重名。"),
            symbol: "calendar.badge.minus",
            control: toggle(
                domain: "com.apple.screencapture", key: "include-date", enabled: .bool(false)
            ),
            restartProcesses: [],
            effectHint: L("下次截屏生效"),
            caution: .none
        ),
        PreferenceItem(
            id: "screenshots.name",
            category: .screenshots,
            title: L("截屏文件名前缀"),
            detail: L("设置文件名开头的文字；留空并应用可恢复系统默认名称。"),
            symbol: "textformat",
            control: .text(TextPreference(
                address: PreferenceAddress(domain: "com.apple.screencapture", key: "name"),
                placeholder: L("系统默认")
            )),
            restartProcesses: [],
            effectHint: L("下次截屏生效"),
            caution: .none
        ),

        PreferenceItem(
            id: "trackpad.legacyThreeFingerDoubleTap",
            category: .trackpad,
            title: L("尝试启用遗留三指双击动作"),
            detail: L("向内建触控板与 Bluetooth 触控板偏好域写入历史值 2；旧系统曾保留三指双击后端，但未公开其稳定动作语义。"),
            symbol: "hand.tap.fill",
            control: .toggle(TogglePreference(
                readAddress: PreferenceAddress(
                    domain: "com.apple.AppleMultitouchTrackpad",
                    key: "TrackpadThreeFingerDoubleTapGesture"
                ),
                enabledValue: .integer(2),
                enableMutations: [
                    .write(
                        "com.apple.AppleMultitouchTrackpad",
                        "TrackpadThreeFingerDoubleTapGesture",
                        .integer(2)
                    ),
                    .write(
                        "com.apple.driver.AppleBluetoothMultitouch.trackpad",
                        "TrackpadThreeFingerDoubleTapGesture",
                        .integer(2)
                    )
                ],
                disableMutations: [
                    .delete(
                        "com.apple.AppleMultitouchTrackpad",
                        "TrackpadThreeFingerDoubleTapGesture"
                    ),
                    .delete(
                        "com.apple.driver.AppleBluetoothMultitouch.trackpad",
                        "TrackpadThreeFingerDoubleTapGesture"
                    )
                ]
            )),
            restartProcesses: [],
            effectHint: L("重新登录、重连触控板或重启后再验证"),
            caution: .compatibility,
            stability: .unstable(
                L("macOS 26.6.1 的触控板诊断资源仍可观察到“threeFingerDoubleTap”语义字段，但尚未确认当前两个用户偏好域到该后端字段的映射，也未确认整数 2 所代表的动作。写入可能完全无效，可能被系统覆盖，也可能与第三方手势工具冲突。")
            ),
            compatibility: expandedCompatibility,
            evidence: legacyTrackpadEvidence
        ),

        PreferenceItem(
            id: "keyboard.keyRepeat",
            category: .keyboard,
            title: L("长按字母时连续输入"),
            detail: L("关闭重音字符弹窗，让长按字母键像方向键一样连续重复。"),
            symbol: "repeat",
            control: toggle(
                domain: global, key: "ApplePressAndHoldEnabled", enabled: .bool(false)
            ),
            restartProcesses: [],
            effectHint: L("重新打开相关 App 后生效"),
            caution: .interaction
        ),
        PreferenceItem(
            id: "keyboard.ultraFast",
            category: .keyboard,
            title: L("调整按键重复速度"),
            detail: L("常用预设使用比系统设置滑块更快的速度（KeyRepeat 1，InitialKeyRepeat 10），也可在受控范围内放慢。"),
            symbol: "speedometer",
            control: .numeric(NumericPreference(
                detail: L("分别控制按住按键后的首次等待和持续重复间隔；使用系统刻度，越小越快，不换算为固定毫秒数。"),
                parameters: [
                    NumericPreferenceParameter(
                        id: "repeatInterval",
                        title: L("重复间隔"),
                        detail: L("限制为 1–10 系统刻度；越小，按住按键后的重复越快。"),
                        address: PreferenceAddress(domain: global, key: "KeyRepeat"),
                        range: 1...10,
                        step: 1,
                        presetValue: 1,
                        storage: .integer,
                        unit: L("刻度"),
                        precision: 0
                    ),
                    NumericPreferenceParameter(
                        id: "initialDelay",
                        title: L("首次重复等待"),
                        detail: L("限制为 10–60 系统刻度；越小，首次重复等待越短，过短可能增加误输入。"),
                        address: PreferenceAddress(domain: global, key: "InitialKeyRepeat"),
                        range: 10...60,
                        step: 1,
                        presetValue: 10,
                        storage: .integer,
                        unit: L("刻度"),
                        precision: 0
                    )
                ]
            )),
            restartProcesses: [],
            effectHint: L("重新登录后完整生效"),
            caution: .interaction,
            compatibility: expandedCompatibility,
            evidence: keyboardSettingsEvidence,
            source: keyboardRepeatEnhancement,
            recovery: .restoreBaseline
        ),

        PreferenceItem(
            id: "windows.expandedSave",
            category: .windows,
            title: L("默认展开保存对话框"),
            detail: L("保存新文件时直接显示完整文件浏览器，而不是紧凑面板。"),
            symbol: "rectangle.expand.vertical",
            control: compoundToggle(
                readDomain: global,
                readKey: "NSNavPanelExpandedStateForSaveMode",
                enabledValue: .bool(true),
                writes: [
                    .write(global, "NSNavPanelExpandedStateForSaveMode", .bool(true)),
                    .write(global, "NSNavPanelExpandedStateForSaveMode2", .bool(true))
                ]
            ),
            restartProcesses: [],
            effectHint: L("重新打开相关 App 后生效"),
            caution: .none
        ),
        PreferenceItem(
            id: "windows.expandedPrint",
            category: .windows,
            title: L("默认展开打印对话框"),
            detail: L("打印时直接显示预览、纸张与详细选项。"),
            symbol: "printer.fill.and.paper.fill",
            control: compoundToggle(
                readDomain: global,
                readKey: "PMPrintingExpandedStateForPrint",
                enabledValue: .bool(true),
                writes: [
                    .write(global, "PMPrintingExpandedStateForPrint", .bool(true)),
                    .write(global, "PMPrintingExpandedStateForPrint2", .bool(true))
                ]
            ),
            restartProcesses: [],
            effectHint: L("重新打开相关 App 后生效"),
            caution: .none
        ),
        PreferenceItem(
            id: "windows.localDocuments",
            category: .windows,
            title: L("新文稿优先保存在本机"),
            detail: L("支持该偏好的 App 在首次保存时优先使用本机，而不是 iCloud。"),
            symbol: "internaldrive",
            control: toggle(
                domain: global, key: "NSDocumentSaveNewDocumentsToCloud", enabled: .bool(false)
            ),
            restartProcesses: [],
            effectHint: L("重新打开相关 App 后生效"),
            caution: .compatibility,
            stability: .unstable(
                L("这是 AppKit 的全局建议偏好；使用独立文稿框架、沙盒内自有设置或非 AppKit 界面的 App 可能忽略它，因此不同 App 的首次保存位置可能不一致。")
            )
        ),
        PreferenceItem(
            id: "windows.noAnimations",
            category: .windows,
            title: L("减少窗口打开动画"),
            detail: L("关闭部分 App 的窗口展开动画；并非所有现代 App 都遵循此偏好。"),
            symbol: "sparkles.rectangle.stack",
            control: toggle(
                domain: global, key: "NSAutomaticWindowAnimationsEnabled", enabled: .bool(false)
            ),
            restartProcesses: [],
            effectHint: L("重新打开相关 App 后生效"),
            caution: .compatibility,
            stability: .unstable(
                L("该键只影响仍读取 AppKit 全局动画偏好的窗口路径；SwiftUI、Catalyst、网页容器或自绘窗口可能不响应，减少效果可能因 App 而异。")
            )
        ),
        PreferenceItem(
            id: "windows.dragAnywhere",
            category: .windows,
            title: L("按住修饰键从任意位置拖动窗口"),
            detail: L("按住 Control+Command 后，可从窗口内容区域拖动窗口；仅对遵循 AppKit 行为的 App 生效。"),
            symbol: "hand.point.up.left.fill",
            control: toggle(
                domain: global, key: "NSWindowShouldDragOnGesture", enabled: .bool(true)
            ),
            restartProcesses: [],
            effectHint: L("重新打开相关 App 后生效"),
            caution: .interaction,
            compatibility: expandedCompatibility,
            evidence: windowDragEvidence
        ),
        PreferenceItem(
            id: "windows.tooltipDelay",
            category: .windows,
            title: L("工具提示出现延迟"),
            detail: L("缩短鼠标悬停后提示气泡的等待时间；仅影响读取此 AppKit 偏好的 App。"),
            symbol: "text.bubble.fill",
            control: .choice(ChoicePreference(
                address: PreferenceAddress(domain: global, key: "NSInitialToolTipDelay"),
                options: [
                    ChoiceOption(id: "system", title: L("系统默认"), value: nil),
                    ChoiceOption(id: "fast", title: L("\(0.1) 秒"), value: .integer(100)),
                    ChoiceOption(id: "balanced", title: L("\(0.3) 秒"), value: .integer(300)),
                    ChoiceOption(id: "moderate", title: L("\(0.5) 秒"), value: .integer(500))
                ]
            )),
            restartProcesses: [],
            effectHint: L("重新打开相关 App 后生效"),
            caution: .compatibility,
            stability: .unstable(
                L("“NSInitialToolTipDelay”的整数毫秒值可写入并读回，但现代 App 可能使用 SwiftUI、自绘提示或自己的计时器而忽略它。界面数值表示写入值，不是所有 App 的保证延迟。")
            ),
            compatibility: expandedCompatibility,
            evidence: tooltipEvidence,
            customization: PreferenceCustomization(
                detail: L("在 AppKit 可识别的范围内精细调整悬停等待时间；现代 App 可能忽略此偏好。"),
                parameters: [
                    NumericPreferenceParameter(
                        id: "delay",
                        title: L("提示延迟"),
                        detail: L("0 秒为立即显示；以 0.001 秒（1 毫秒）为步进，最长 2 秒。"),
                        address: PreferenceAddress(
                            domain: global,
                            key: "NSInitialToolTipDelay"
                        ),
                        range: 0...2,
                        step: 0.001,
                        presetValue: 0.3,
                        storage: .integer,
                        storageScale: 1_000,
                        unit: L("秒"),
                        precision: 3
                    )
                ]
            )
        ),
        PreferenceItem(
            id: "windows.noAutoTermination",
            category: .windows,
            title: L("禁用 App 自动终止"),
            detail: L("阻止支持该机制的空闲 App 被系统静默终止；可能增加内存占用。"),
            symbol: "memorychip",
            control: toggle(
                domain: global, key: "NSDisableAutomaticTermination", enabled: .bool(true)
            ),
            restartProcesses: [],
            effectHint: L("重新打开相关 App 后生效"),
            caution: .interaction
        ),

        PreferenceItem(
            id: "system.screensaverIdle",
            category: .system,
            title: L("精确设置屏幕保护程序闲置时间"),
            detail: L("以 1 秒为步进设置 1–3600 秒的闲置等待时间，也可单独选择“永不”；不改变锁屏密码要求或显示器睡眠时间。"),
            symbol: "display",
            control: .numeric(NumericPreference(
                detail: L("选择预设、计时或“永不”仅修改草稿，点击应用才写入当前 Mac 的屏幕保护程序偏好。"),
                parameters: [
                    NumericPreferenceParameter(
                        id: "idleTime",
                        title: L("闲置等待时间"),
                        detail: L("有限时间为 1–3600 秒；“永不”写入整数 0。应用预设为 5 分钟，不代表系统默认值。"),
                        address: PreferenceAddress(
                            domain: "com.apple.screensaver",
                            key: "idleTime",
                            hostScope: .currentHost
                        ),
                        range: 1...3600,
                        step: 1,
                        presetValue: 300,
                        storage: .integer,
                        unit: L("秒"),
                        precision: 0,
                        specialValues: [NumericPreferenceSpecialValue(value: 0, title: L("永不"))],
                        presets: [
                            NumericPreferencePreset(value: 60, title: L("1 分钟")),
                            NumericPreferencePreset(value: 300, title: L("5 分钟")),
                            NumericPreferencePreset(value: 600, title: L("10 分钟")),
                            NumericPreferencePreset(value: 1800, title: L("30 分钟")),
                            NumericPreferencePreset(value: 3600, title: L("60 分钟"))
                        ]
                    )
                ],
                initializesDraftsFromCurrentValue: true
            )),
            restartProcesses: [],
            effectHint: L("由系统后续闲置检测读取；实际生效时间待行为验证"),
            caution: .compatibility,
            stability: .unstable(
                L("macOS 26.6.2 可读取当前主机的 idleTime 整数秒数；本轮未执行真实屏保计时测试，尚未验证任意秒数的可见效果、系统设置回显或持久性。0 表示永不启动屏幕保护程序，不改变锁屏密码策略。")
            ),
            compatibility: expandedCompatibility,
            evidence: screensaverIdleEvidence,
            source: screensaverIdleEnhancement,
            recovery: .restoreBaseline
        ),
        PreferenceItem(
            id: "system.compactMenuBar",
            category: .system,
            title: L("调整菜单栏项目间距"),
            detail: L("安全预设把当前 Mac 的项目内容留白与高亮外扩设为 4，也可在受控范围内调整疏密。"),
            symbol: "menubar.rectangle",
            control: compoundCurrentHostToggle(
                readDomain: global,
                readKey: "NSStatusItemSpacing",
                enabledValue: .integer(4),
                writes: [
                    .writeCurrentHost(global, "NSStatusItemSpacing", .integer(4)),
                    .writeCurrentHost(global, "NSStatusItemSelectionPadding", .integer(4))
                ]
            ),
            restartProcesses: [],
            effectHint: L("重新登录后完整生效"),
            caution: .interaction,
            compatibility: expandedCompatibility,
            evidence: menuBarSpacingEvidence,
            customization: PreferenceCustomization(
                detail: L("分别调整菜单栏项目的内容留白与选中高亮外扩；使用当前主机作用域，并禁止负值。"),
                parameters: [
                    NumericPreferenceParameter(
                        id: "spacing",
                        title: L("项目内容留白"),
                        detail: L("加到每个状态项目内容宽度；0–1 点极紧，过大更容易被刘海遮挡。"),
                        address: PreferenceAddress(
                            domain: global,
                            key: "NSStatusItemSpacing",
                            hostScope: .currentHost
                        ),
                        range: 0...16,
                        step: 1,
                        presetValue: 4,
                        storage: .integer,
                        unit: L("点"),
                        precision: 0
                    ),
                    NumericPreferenceParameter(
                        id: "selectionPadding",
                        title: L("高亮外扩"),
                        detail: L("控制选中背景向两侧扩展的宽度；过大会让相邻高亮区域靠得过近。"),
                        address: PreferenceAddress(
                            domain: global,
                            key: "NSStatusItemSelectionPadding",
                            hostScope: .currentHost
                        ),
                        range: 0...16,
                        step: 1,
                        presetValue: 4,
                        storage: .integer,
                        unit: L("点"),
                        precision: 0
                    )
                ]
            )
        ),
        PreferenceItem(
            id: "system.noTimeMachineOffer",
            category: .system,
            title: L("不询问将新磁盘用于 Time Machine"),
            detail: L("接入新磁盘时不再弹出 Time Machine 备份用途建议。"),
            symbol: "externaldrive.badge.timemachine",
            control: toggle(
                domain: "com.apple.TimeMachine", key: "DoNotOfferNewDisksForBackup", enabled: .bool(true)
            ),
            restartProcesses: [],
            effectHint: L("下次连接新磁盘时生效"),
            caution: .none
        ),
        PreferenceItem(
            id: "system.webkitExtras",
            category: .system,
            title: L("启用 WebKit 开发者附加功能"),
            detail: L("为遵循全局 WebKit 偏好的 App 开启检查元素等开发菜单；Safari 自身设置不受替代。"),
            symbol: "chevron.left.forwardslash.chevron.right",
            control: toggle(
                domain: global, key: "WebKitDeveloperExtras", enabled: .bool(true)
            ),
            restartProcesses: [],
            effectHint: L("重新打开相关 App 后生效"),
            caution: .compatibility,
            stability: .unstable(
                L("该全局键只影响仍采用对应 WebKit/AppKit 偏好桥的宿主；Safari、WKWebView 宿主和使用自有设置的 App 可能分别忽略它，不能据此保证出现检查元素菜单。")
            )
        ),
        PreferenceItem(
            id: "advanced.ttyKeepAwake",
            category: .advanced,
            title: L("活跃终端会话阻止闲置睡眠"),
            detail: L("当本地终端或远程登录的 TTY 会话仍处于活跃状态时，阻止 Mac 因闲置而自动睡眠；可能增加耗电。"),
            symbol: "terminal.fill",
            control: .privilegedToggle(PrivilegedTogglePreference(key: "ttyskeepawake")),
            restartProcesses: [],
            effectHint: L("按此 Mac 现有电源来源立即生效"),
            caution: .privileged,
            compatibility: advancedCompatibility,
            evidence: pmsetEvidence
        ),
        PreferenceItem(
            id: "advanced.proximityWake",
            category: .advanced,
            title: L("附近的受信任设备可唤醒 Mac"),
            detail: L("允许使用同一 iCloud 账户的附近设备触发系统从睡眠中唤醒；只在硬件与系统电源能力支持时可用。"),
            symbol: "wave.3.right.circle.fill",
            control: .privilegedToggle(PrivilegedTogglePreference(key: "proximitywake")),
            restartProcesses: [],
            effectHint: L("按此 Mac 现有电源来源立即生效"),
            caution: .privileged,
            compatibility: advancedCompatibility,
            evidence: pmsetEvidence
        ),
        PreferenceItem(
            id: "advanced.powerSourceWake",
            category: .advanced,
            title: L("电源来源变化时唤醒 Mac"),
            detail: L("接入或断开电源适配器时允许系统从睡眠中唤醒；只在支持该能力的 Mac 上显示为可操作。"),
            symbol: "powerplug.fill",
            control: .privilegedToggle(PrivilegedTogglePreference(key: "acwake")),
            restartProcesses: [],
            effectHint: L("按此 Mac 现有电源来源立即生效"),
            caution: .privileged,
            compatibility: advancedCompatibility,
            evidence: pmsetEvidence
        )
    ]

    static func items(in category: SettingsCategory) -> [PreferenceItem] {
        items.filter { $0.category == category }
    }

    private static func toggle(
        domain: String,
        key: String,
        enabled: PreferenceValue
    ) -> PreferenceControl {
        .toggle(TogglePreference(
            readAddress: PreferenceAddress(domain: domain, key: key),
            enabledValue: enabled,
            enableMutations: [.write(domain, key, enabled)],
            disableMutations: [.delete(domain, key)]
        ))
    }

    private static func compoundToggle(
        readDomain: String,
        readKey: String,
        enabledValue: PreferenceValue,
        writes: [PreferenceMutation]
    ) -> PreferenceControl {
        .toggle(TogglePreference(
            readAddress: PreferenceAddress(domain: readDomain, key: readKey),
            enabledValue: enabledValue,
            enableMutations: writes,
            disableMutations: writes.map { .delete($0.address.domain, $0.address.key) }
        ))
    }

    private static func compoundCurrentHostToggle(
        readDomain: String,
        readKey: String,
        enabledValue: PreferenceValue,
        writes: [PreferenceMutation]
    ) -> PreferenceControl {
        .toggle(TogglePreference(
            readAddress: PreferenceAddress(
                domain: readDomain,
                key: readKey,
                hostScope: .currentHost
            ),
            enabledValue: enabledValue,
            enableMutations: writes,
            disableMutations: writes.map {
                .deleteCurrentHost($0.address.domain, $0.address.key)
            }
        ))
    }
}
